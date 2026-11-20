#include "ik_desktop_host.h"

#include <shellapi.h>
#include <shellscalingapi.h>
#include <roapi.h>
#include <systemmediatransportcontrolsinterop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.h>

#include <algorithm>
#include <atomic>
#include <cstdint>
#include <utility>

#include "resource.h"

namespace {
constexpr UINT kTrayMessage = WM_APP + 0x494;
constexpr UINT kMediaMessage = WM_APP + 0x495;
constexpr UINT kTrayId = 0x494B;
constexpr DWORD kStateVersion = 1;
const UINT kTaskbarCreated = RegisterWindowMessageW(L"TaskbarCreated");

struct StoredWindowState {
  DWORD version;
  RECT bounds;
  UINT dpi;
  DWORD maximized;
};

UINT WindowDpi(HWND window) {
  const auto dpi = GetDpiForWindow(window);
  return dpi == 0 ? 96 : dpi;
}

MONITORINFO MonitorInfoFor(RECT bounds) {
  MONITORINFO info{};
  info.cbSize = sizeof(info);
  GetMonitorInfoW(MonitorFromRect(&bounds, MONITOR_DEFAULTTONEAREST), &info);
  return info;
}

BOOL CALLBACK FindIkWindow(HWND window, LPARAM value) {
  if (!GetPropW(window, IkDesktopHost::WindowProperty())) return TRUE;
  *reinterpret_cast<HWND*>(value) = window;
  return FALSE;
}

NOTIFYICONDATAW TrayData(HWND window) {
  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = window;
  data.uID = kTrayId;
  return data;
}
}  // namespace

struct IkDesktopHost::MediaState {
  winrt::Windows::Media::SystemMediaTransportControls controls{nullptr};
  winrt::event_token pressed{};
  std::shared_ptr<std::atomic<bool>> alive =
      std::make_shared<std::atomic<bool>>(true);
  bool runtime_initialized = false;
};

IkSingleInstance::IkSingleInstance(const std::wstring& name) {
  mutex_ = CreateMutexW(nullptr, FALSE, name.c_str());
  const DWORD error = GetLastError();
  primary_ = mutex_ != nullptr && error != ERROR_ALREADY_EXISTS;
}

IkSingleInstance::~IkSingleInstance() {
  if (mutex_) CloseHandle(mutex_);
}

bool IkSingleInstance::WakeExisting() const {
  // 首个进程可能仍在创建 Flutter 宿主，短暂等待独立窗口属性出现。
  for (int attempt = 0; attempt < 80; ++attempt) {
    HWND target = nullptr;
    EnumWindows(FindIkWindow, reinterpret_cast<LPARAM>(&target));
    if (target) {
      DWORD process_id = 0;
      GetWindowThreadProcessId(target, &process_id);
      AllowSetForegroundWindow(process_id);
      return PostMessageW(target, IkDesktopHost::WakeMessage(), 0, 0) != FALSE;
    }
    Sleep(50);
  }
  return false;
}

IkDesktopHost::IkDesktopHost(HWND window,
                             std::function<void(const std::string&)> command,
                             std::function<void()> exit,
                             std::wstring registry_key)
    : window_(window), command_(std::move(command)), exit_(std::move(exit)),
      registry_key_(std::move(registry_key)) {}

IkDesktopHost::~IkDesktopHost() {
  SaveWindowState();
  ReleaseMedia();
  auto data = TrayData(window_);
  if (tray_available_) Shell_NotifyIconW(NIM_DELETE, &data);
  RemovePropW(window_, WindowProperty());
}

const wchar_t* IkDesktopHost::WindowProperty() {
  return L"sun-dove.YueyinMusic.MainWindow";
}

UINT IkDesktopHost::WakeMessage() {
  static const UINT message =
      RegisterWindowMessageW(L"sun-dove.YueyinMusic.ShowWindow");
  return message;
}

void IkDesktopHost::Initialize() {
  if (initialized_) {
    if (!tray_available_) AddTrayIcon();
    if (!media_available()) InitializeMedia();
    return;
  }
  initialized_ = true;
  SetPropW(window_, WindowProperty(), reinterpret_cast<HANDLE>(1));
  RestoreWindowState();
  AddTrayIcon();
  InitializeMedia();
}

void IkDesktopHost::ShowInitial() {
  if (shown_) return;
  ShowWindow(window_, start_maximized_ ? SW_SHOWMAXIMIZED : SW_SHOWNORMAL);
  shown_ = true;
  SaveWindowState();
}

RECT IkDesktopHost::ClampBounds(RECT bounds, const RECT& work, UINT dpi) {
  const LONG work_width = std::max<LONG>(1, work.right - work.left);
  const LONG work_height = std::max<LONG>(1, work.bottom - work.top);
  const LONG min_width = std::min<LONG>(work_width, MulDiv(900, static_cast<int>(dpi), 96));
  const LONG min_height = std::min<LONG>(work_height, MulDiv(600, static_cast<int>(dpi), 96));
  // 64 位差值防止损坏的持久化坐标在相减时溢出。
  const auto requested_width = static_cast<int64_t>(bounds.right) - bounds.left;
  const auto requested_height = static_cast<int64_t>(bounds.bottom) - bounds.top;
  const LONG width = static_cast<LONG>(std::clamp<int64_t>(requested_width, min_width, work_width));
  const LONG height = static_cast<LONG>(std::clamp<int64_t>(requested_height, min_height, work_height));
  const LONG left = std::clamp(bounds.left, work.left, work.right - width);
  const LONG top = std::clamp(bounds.top, work.top, work.bottom - height);
  return RECT{left, top, left + width, top + height};
}

std::optional<IkWindowState> IkDesktopHost::ReadWindowState(
    const std::wstring& key) {
  StoredWindowState stored{};
  DWORD bytes = sizeof(stored);
  const auto result = RegGetValueW(HKEY_CURRENT_USER, key.c_str(), L"Placement",
                                  RRF_RT_REG_BINARY, nullptr, &stored, &bytes);
  if (result != ERROR_SUCCESS || bytes != sizeof(stored) ||
      stored.version != kStateVersion || stored.dpi < 48 || stored.dpi > 768 ||
      stored.maximized > 1) {
    return std::nullopt;
  }
  return IkWindowState{stored.bounds, stored.dpi, stored.maximized != 0};
}

bool IkDesktopHost::WriteWindowState(const std::wstring& key,
                                     const IkWindowState& state) {
  const StoredWindowState stored{kStateVersion, state.bounds, state.dpi,
                                 state.maximized ? 1u : 0u};
  return RegSetKeyValueW(HKEY_CURRENT_USER, key.c_str(), L"Placement", REG_BINARY,
                        &stored, sizeof(stored)) == ERROR_SUCCESS;
}

void IkDesktopHost::RestoreWindowState() {
  auto state = ReadWindowState(registry_key_);
  if (!state) return;
  const auto info = MonitorInfoFor(state->bounds);
  if (info.rcWork.right <= info.rcWork.left) return;
  UINT dpi = WindowDpi(window_);
  UINT dpi_y = dpi;
  GetDpiForMonitor(MonitorFromRect(&state->bounds, MONITOR_DEFAULTTONEAREST),
                   MDT_EFFECTIVE_DPI, &dpi, &dpi_y);
  RECT bounds = ClampBounds(state->bounds, info.rcWork, state->dpi);
  const auto width = std::clamp<int64_t>(
      static_cast<int64_t>(bounds.right) - bounds.left, 1, 32768);
  const auto height = std::clamp<int64_t>(
      static_cast<int64_t>(bounds.bottom) - bounds.top, 1, 32768);
  bounds.right = bounds.left + MulDiv(static_cast<int>(width), static_cast<int>(dpi),
                                     static_cast<int>(state->dpi));
  bounds.bottom = bounds.top + MulDiv(static_cast<int>(height), static_cast<int>(dpi),
                                     static_cast<int>(state->dpi));
  bounds = ClampBounds(bounds, info.rcWork, dpi);
  SetWindowPos(window_, nullptr, bounds.left, bounds.top,
               bounds.right - bounds.left, bounds.bottom - bounds.top,
               SWP_NOACTIVATE | SWP_NOZORDER);
  start_maximized_ = state->maximized;
}

void IkDesktopHost::SaveWindowState() {
  if (!initialized_ || !shown_ || !IsWindow(window_)) return;
  WINDOWPLACEMENT placement{};
  placement.length = sizeof(placement);
  if (!GetWindowPlacement(window_, &placement)) return;
  RECT bounds = placement.rcNormalPosition;
  const auto info = MonitorInfoFor(bounds);
  // WINDOWPLACEMENT 的正常位置是工作区坐标；持久化用屏幕坐标。
  OffsetRect(&bounds, info.rcWork.left - info.rcMonitor.left,
             info.rcWork.top - info.rcMonitor.top);
  const bool maximized = IsZoomed(window_) ||
      (IsIconic(window_) && (placement.flags & WPF_RESTORETOMAXIMIZED) != 0);
  memory_available_ = WriteWindowState(
      registry_key_, IkWindowState{bounds, WindowDpi(window_), maximized});
}

void IkDesktopHost::ShowWindowNow() {
  if (!shown_) ShowInitial();
  if (IsIconic(window_)) ShowWindow(window_, SW_RESTORE);
  else ShowWindow(window_, SW_SHOW);
  SetForegroundWindow(window_);
}

void IkDesktopHost::AddTrayIcon() {
  auto data = TrayData(window_);
  data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP;
  data.uCallbackMessage = kTrayMessage;
  data.hIcon = LoadIconW(GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON));
  if (!data.hIcon) data.hIcon = LoadIconW(nullptr, IDI_APPLICATION);
  wcscpy_s(data.szTip, L"IK Music");
  tray_available_ = Shell_NotifyIconW(NIM_ADD, &data) != FALSE;
  if (tray_available_) {
    data.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIconW(NIM_SETVERSION, &data);
    UpdateTrayIcon();
  }
}

void IkDesktopHost::UpdateTrayIcon() {
  if (!tray_available_) return;
  auto data = TrayData(window_);
  data.uFlags = NIF_TIP;
  const std::wstring tooltip = title_.empty() ? L"IK Music" : L"IK Music · " + title_;
  wcsncpy_s(data.szTip, tooltip.c_str(), _TRUNCATE);
  if (!Shell_NotifyIconW(NIM_MODIFY, &data)) tray_available_ = false;
}

void IkDesktopHost::ShowTrayMenu() {
  HMENU menu = CreatePopupMenu();
  if (!menu) return;
  AppendMenuW(menu, MF_STRING, static_cast<UINT_PTR>(Command::kShow), L"显示 IK Music");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  const UINT flags = MF_STRING | (enabled_ ? MF_ENABLED : MF_GRAYED);
  AppendMenuW(menu, flags, static_cast<UINT_PTR>(Command::kToggle),
              playing_ ? L"暂停" : L"播放");
  AppendMenuW(menu, flags, static_cast<UINT_PTR>(Command::kPrevious), L"上一首");
  AppendMenuW(menu, flags, static_cast<UINT_PTR>(Command::kNext), L"下一首");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, static_cast<UINT_PTR>(Command::kExit), L"退出 IK Music");
  POINT point{};
  GetCursorPos(&point);
  SetForegroundWindow(window_);
  const auto selected = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON,
                                       point.x, point.y, 0, window_, nullptr);
  DestroyMenu(menu);
  PostMessageW(window_, WM_NULL, 0, 0);
  if (selected != 0) DispatchCommand(static_cast<Command>(selected));
}

void IkDesktopHost::DispatchCommand(Command command) {
  if (command == Command::kShow) {
    ShowWindowNow();
    return;
  }
  if (command == Command::kExit) {
    SaveWindowState();
    exit_();
    return;
  }
  if (!enabled_) return;
  switch (command) {
    case Command::kToggle: command_("toggle"); break;
    case Command::kPrevious: command_("previous"); break;
    case Command::kNext: command_("next"); break;
    case Command::kPlay: command_("play"); break;
    case Command::kPause: command_("pause"); break;
    default: break;
  }
}

std::optional<LRESULT> IkDesktopHost::HandleMessage(UINT message, WPARAM wparam,
                                                   LPARAM lparam) {
  if (!initialized_) return std::nullopt;
  if (message == WakeMessage()) {
    ShowWindowNow();
    return 0;
  }
  if (message == kTaskbarCreated) {
    tray_available_ = false;
    AddTrayIcon();
    return 0;
  }
  if (message == kTrayMessage) {
    const UINT event = LOWORD(lparam);
    if (event == WM_CONTEXTMENU || event == WM_RBUTTONUP) ShowTrayMenu();
    else if (event == NIN_SELECT || event == NIN_KEYSELECT || event == WM_LBUTTONDBLCLK) {
      ShowWindowNow();
    }
    return 0;
  }
  if (message == kMediaMessage) {
    DispatchCommand(static_cast<Command>(wparam));
    return 0;
  }
  if (message == WM_GETMINMAXINFO) {
    RECT bounds{};
    GetWindowRect(window_, &bounds);
    const auto info = MonitorInfoFor(bounds);
    auto minimum = ClampBounds(RECT{}, info.rcWork, WindowDpi(window_));
    auto limits = reinterpret_cast<MINMAXINFO*>(lparam);
    limits->ptMinTrackSize.x = minimum.right - minimum.left;
    limits->ptMinTrackSize.y = minimum.bottom - minimum.top;
    return 0;
  }
  if (message == WM_EXITSIZEMOVE || message == WM_CLOSE ||
      message == WM_QUERYENDSESSION ||
      (message == WM_SIZE && wparam != SIZE_MINIMIZED)) {
    SaveWindowState();
  }
  return std::nullopt;
}

void IkDesktopHost::InitializeMedia() {
  media_ = std::make_unique<MediaState>();
  try {
    const HRESULT initialized = RoInitialize(RO_INIT_SINGLETHREADED);
    if (FAILED(initialized) && initialized != RPC_E_CHANGED_MODE) {
      winrt::check_hresult(initialized);
    }
    media_->runtime_initialized = SUCCEEDED(initialized);
    const auto factory = winrt::get_activation_factory<
        winrt::Windows::Media::SystemMediaTransportControls,
        ISystemMediaTransportControlsInterop>();
    winrt::check_hresult(factory->GetForWindow(
        window_, winrt::guid_of<winrt::Windows::Media::SystemMediaTransportControls>(),
        winrt::put_abi(media_->controls)));
    auto controls = media_->controls;
    controls.IsEnabled(false);
    controls.IsPlayEnabled(true);
    controls.IsPauseEnabled(true);
    controls.IsNextEnabled(true);
    controls.IsPreviousEnabled(true);
    const HWND target = window_;
    const auto alive = media_->alive;
    media_->pressed = controls.ButtonPressed([target, alive](
        const auto&, const winrt::Windows::Media::SystemMediaTransportControlsButtonPressedEventArgs& args) {
      if (!alive->load()) return;
      using Button = winrt::Windows::Media::SystemMediaTransportControlsButton;
      Command command;
      switch (args.Button()) {
        case Button::Play: command = Command::kPlay; break;
        case Button::Pause: command = Command::kPause; break;
        case Button::Next: command = Command::kNext; break;
        case Button::Previous: command = Command::kPrevious; break;
        default: return;
      }
      // WinRT 回调不保证在 UI 线程；经 HWND 投递后再调用 Flutter messenger。
      PostMessageW(target, kMediaMessage, static_cast<WPARAM>(command), 0);
    });
    media_error_.clear();
  } catch (const winrt::hresult_error& error) {
    media_error_ = "smtc_unavailable:" + std::to_string(error.code().value);
    ReleaseMedia();
  }
}

bool IkDesktopHost::media_available() const {
  return media_ && media_->controls;
}

void IkDesktopHost::ReleaseMedia() {
  if (!media_) return;
  media_->alive->store(false);
  if (media_->controls) {
    try {
      media_->controls.ButtonPressed(media_->pressed);
      media_->controls.IsEnabled(false);
      media_->controls.DisplayUpdater().ClearAll();
      media_->controls.DisplayUpdater().Update();
    } catch (const winrt::hresult_error&) {
      // 会话已关闭时仍须释放 COM 与回调状态。
    }
    media_->controls = nullptr;
  }
  if (media_->runtime_initialized) RoUninitialize();
  media_.reset();
}

void IkDesktopHost::Update(const std::wstring& title, const std::wstring& artist,
                            bool enabled, bool playing) {
  title_ = title;
  enabled_ = enabled;
  playing_ = playing;
  UpdateTrayIcon();
  if (!media_available()) return;
  try {
    using namespace winrt::Windows::Media;
    auto controls = media_->controls;
    controls.IsEnabled(enabled);
    controls.PlaybackStatus(!enabled ? MediaPlaybackStatus::Closed :
        playing ? MediaPlaybackStatus::Playing : MediaPlaybackStatus::Paused);
    const auto display = controls.DisplayUpdater();
    if (enabled) {
      display.Type(MediaPlaybackType::Music);
      display.MusicProperties().Title(title);
      display.MusicProperties().Artist(artist);
    } else {
      display.ClearAll();
    }
    display.Update();
  } catch (const winrt::hresult_error& error) {
    media_error_ = "smtc_update_failed:" + std::to_string(error.code().value);
    ReleaseMedia();
  }
}

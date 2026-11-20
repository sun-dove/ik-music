#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
#ifdef YUEYIN_BUILD
  desktop_channel_ = std::make_unique<WindowsDesktopChannel>(
      flutter_controller_->engine()->messenger(), GetHandle(), desktop_policy_);
  ik_desktop_channel_ = std::make_unique<IkDesktopChannel>(
      flutter_controller_->engine()->messenger(), GetHandle(), [this]() {
        if (!desktop_channel_->PrepareExit()) {
          desktop_policy_.RequestExit(GetHandle());
        }
      });
#endif
  floating_lyrics_channel_ = std::make_unique<FloatingLyricsChannel>(
      flutter_controller_->engine()->messenger());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
#ifdef YUEYIN_BUILD
    if (ik_desktop_channel_) ik_desktop_channel_->ShowInitial();
#else
    this->Show();
#endif
  });

  flutter_controller_->ForceRedraw();
  return true;
}

void FlutterWindow::OnDestroy() {
#ifdef YUEYIN_BUILD
  ik_desktop_channel_ = nullptr;
  desktop_channel_ = nullptr;
#endif
  if (flutter_controller_) {
    floating_lyrics_channel_ = nullptr;
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
#ifdef YUEYIN_BUILD
  if (ik_desktop_channel_) {
    if (auto result = ik_desktop_channel_->HandleMessage(message, wparam, lparam)) {
      return *result;
    }
  }
  if (desktop_channel_ && message == WM_TIMER && desktop_channel_->HandleTimer(wparam)) return 0;
  if (desktop_channel_ && message == WM_CLOSE &&
      desktop_policy_.NeedsExitPreparation() && desktop_channel_->PrepareExit()) return 0;
  if (auto result = desktop_policy_.HandleMessage(hwnd, message, wparam, lparam)) {
    return *result;
  }
#endif
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

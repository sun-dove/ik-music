#include "ik_desktop_host.h"

#include <systemmediatransportcontrolsinterop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.h>

#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
IkDesktopHost* current_host = nullptr;
LRESULT CALLBACK GateProcedure(HWND window, UINT message, WPARAM wparam,
                               LPARAM lparam) {
  if (current_host) {
    if (auto result = current_host->HandleMessage(message, wparam, lparam)) {
      return *result;
    }
  }
  return DefWindowProcW(window, message, wparam, lparam);
}
void Check(bool passed, const char* name) {
  if (!passed) throw std::runtime_error(name);
  std::cout << "PASS " << name << std::endl;
}
void ActivateForGate(IkDesktopHost& host) {
#ifndef IK_DESKTOP_BASELINE
  host.Initialize();
#endif
}
}  // namespace

int main() {
  const std::wstring registry_key =
      L"Software\\sun-dove\\YueyinMusic\\IkDesktopGate-" +
      std::to_wstring(GetCurrentProcessId());
  HWND window = nullptr;
  try {
    WNDCLASSW cls{};
    cls.lpfnWndProc = GateProcedure;
    cls.hInstance = GetModuleHandleW(nullptr);
    cls.lpszClassName = L"IkDesktopGateWindow";
    Check(RegisterClassW(&cls) != 0, "K07 native window created");
    window = CreateWindowExW(0, cls.lpszClassName, L"ik desktop gate",
                            WS_OVERLAPPEDWINDOW, 30, 40, 1000, 700, nullptr,
                            nullptr, cls.hInstance, nullptr);
    Check(window != nullptr, "K07 HWND exists");
    std::vector<std::string> commands;
    int exits = 0;
    {
      IkDesktopHost host(window, [&](const std::string& command) {
        commands.push_back(command);
      }, [&]() { ++exits; }, registry_key);
      current_host = &host;
      Check(!GetPropW(window, IkDesktopHost::WindowProperty()),
            "K07 old window has no independent identity");
      ActivateForGate(host);
      Check(GetPropW(window, IkDesktopHost::WindowProperty()) != nullptr,
            "K07 activated host identifies only this product");
      host.ShowInitial();
      host.Update(L"测试歌曲", L"测试歌手", false, false);
      host.DispatchCommand(IkDesktopHost::Command::kNext);
      Check(commands.empty(), "K07 empty player rejects media commands");
      host.Update(L"测试歌曲", L"测试歌手", true, false);
      if (host.media_available()) {
        using namespace winrt::Windows::Media;
        SystemMediaTransportControls controls{nullptr};
        const auto factory = winrt::get_activation_factory<
            SystemMediaTransportControls, ISystemMediaTransportControlsInterop>();
        winrt::check_hresult(factory->GetForWindow(window,
            winrt::guid_of<SystemMediaTransportControls>(), winrt::put_abi(controls)));
        Check(controls.IsEnabled() &&
                  controls.PlaybackStatus() == MediaPlaybackStatus::Paused &&
                  controls.DisplayUpdater().MusicProperties().Title() == L"测试歌曲" &&
                  controls.DisplayUpdater().MusicProperties().Artist() == L"测试歌手",
              "K07 actual SMTC session exposes the current song and status");
        host.Update(L"下一首", L"另一歌手", true, true);
        Check(controls.PlaybackStatus() == MediaPlaybackStatus::Playing &&
                  controls.DisplayUpdater().MusicProperties().Title() == L"下一首",
              "K07 actual SMTC session follows playback changes");
      } else {
        Check(!host.media_error().empty(),
              "K07 unavailable media capability has an explicit failure code");
      }
      host.DispatchCommand(IkDesktopHost::Command::kToggle);
      host.DispatchCommand(IkDesktopHost::Command::kPrevious);
      host.DispatchCommand(IkDesktopHost::Command::kNext);
      host.DispatchCommand(IkDesktopHost::Command::kPlay);
      host.DispatchCommand(IkDesktopHost::Command::kPause);
      Check(commands == std::vector<std::string>{"toggle", "previous", "next",
                                               "play", "pause"},
            "K07 native transport uses the one player callback");
      ShowWindow(window, SW_MINIMIZE);
      SendMessageW(window, IkDesktopHost::WakeMessage(), 0, 0);
      Check(IsWindowVisible(window) && !IsIconic(window),
            "K07 second launch and tray can restore the window");
      host.DispatchCommand(IkDesktopHost::Command::kExit);
      Check(exits == 1 && IsWindow(window),
            "K07 exit requests the existing preparation callback");

      for (const UINT dpi : {96u, 120u, 144u}) {
        const RECT work{0, 0, 1920, 1080};
        const RECT small{10, 10, 40, 40};
        const auto rect = IkDesktopHost::ClampBounds(small, work, dpi);
        Check(rect.right - rect.left == MulDiv(900, static_cast<int>(dpi), 96) &&
                  rect.bottom - rect.top == MulDiv(600, static_cast<int>(dpi), 96),
              "K07 minimum dimensions scale with DPI");
        const RECT narrow_work{-800, 10, 0, 510};
        const auto clipped = IkDesktopHost::ClampBounds(small, narrow_work, dpi);
        Check(clipped.left == -800 && clipped.top == 10 &&
                  clipped.right == 0 && clipped.bottom == 510,
              "K07 minimum never exceeds available work area");
      }
      const RECT work{0, 0, 1920, 1080};
      const auto detached = IkDesktopHost::ClampBounds(
          RECT{5000, -800, 6200, 0}, work, 96);
      Check(detached.left >= work.left && detached.top >= work.top &&
                detached.right <= work.right && detached.bottom <= work.bottom,
            "K07 disconnected monitor cannot strand the window");
      const auto invalid = IkDesktopHost::ClampBounds(
          RECT{200, 200, -100, -100}, work, 96);
      Check(invalid.right > invalid.left && invalid.bottom > invalid.top,
            "K07 invalid stored rectangle receives usable dimensions");

      IkWindowState state{RECT{40, 50, 1040, 750}, 120, true};
      Check(IkDesktopHost::WriteWindowState(registry_key, state),
            "K07 isolated placement can be stored");
      const auto restored = IkDesktopHost::ReadWindowState(registry_key);
      Check(restored && EqualRect(&restored->bounds, &state.bounds) &&
                restored->dpi == 120 && restored->maximized,
            "K07 placement and maximized state round trip");
      std::cout << "CAPABILITY tray=" << host.tray_available()
                << " media=" << host.media_available()
                << " media_error=" << host.media_error() << std::endl;

      const auto mutex_name = L"Local\\ik-desktop-gate-" +
                              std::to_wstring(GetCurrentProcessId());
      {
        IkSingleInstance first(mutex_name);
        IkSingleInstance second(mutex_name);
        Check(first.valid() && first.primary() && second.valid() &&
                  !second.primary(),
              "K07 only the first instance becomes primary");
      }
      IkSingleInstance restarted(mutex_name);
      Check(restarted.primary(), "K07 exiting releases single-instance handle");
      host.Update(L"", L"", false, false);
      const auto command_count = commands.size();
      host.DispatchCommand(IkDesktopHost::Command::kToggle);
      Check(commands.size() == command_count,
            "K07 clearing the player disables native transport again");
      current_host = nullptr;
    }
    Check(!GetPropW(window, IkDesktopHost::WindowProperty()),
          "K07 disposal removes window identity");
    DestroyWindow(window);
    window = nullptr;
    UnregisterClassW(cls.lpszClassName, cls.hInstance);
    RegDeleteTreeW(HKEY_CURRENT_USER, registry_key.c_str());
    return 0;
  } catch (const std::exception& error) {
    current_host = nullptr;
    if (window) DestroyWindow(window);
    RegDeleteTreeW(HKEY_CURRENT_USER, registry_key.c_str());
    std::cerr << "FAIL " << error.what() << std::endl;
    return 1;
  }
}

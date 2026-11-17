#include "windows_desktop_policy.h"
#include <iostream>
#include <stdexcept>

namespace {
WindowsDesktopPolicy* current_policy = nullptr;
LRESULT CALLBACK GateProcedure(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  if (current_policy != nullptr) {
    if (auto result = current_policy->HandleMessage(window, message, wparam, lparam)) return *result;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}
HWND CreateGateWindow(WindowsDesktopPolicy& policy) {
  current_policy = &policy;
  HWND window = CreateWindowExW(0, L"YueyinDesktopGate", L"desktop gate",
      WS_OVERLAPPEDWINDOW, 0, 0, 300, 200, nullptr, nullptr, GetModuleHandle(nullptr), nullptr);
  if (window == nullptr) throw std::runtime_error("CreateWindow failed");
  return window;
}
void Check(bool passed, const char* name) {
  if (!passed) throw std::runtime_error(name);
  std::cout << "PASS " << name << std::endl;
}
void ActivateForGate(WindowsDesktopPolicy& policy) {
#ifndef LEYIN_DESKTOP_BASELINE
  policy.Activate();
#endif
}
}
int main() {
  try {
    WNDCLASSW cls{};
    cls.lpfnWndProc = GateProcedure;
    cls.hInstance = GetModuleHandle(nullptr);
    cls.lpszClassName = L"YueyinDesktopGate";
    if (!RegisterClassW(&cls)) throw std::runtime_error("RegisterClass failed");
    {
      WindowsDesktopPolicy policy;
      Check(!policy.HandleMessage(nullptr, WM_CLOSE, 0, 0).has_value(), "W11 legacy path is not intercepted");
      ActivateForGate(policy);
      HWND window = CreateGateWindow(policy);
      SendMessage(window, WM_CLOSE, 0, 0);
      Check(IsWindow(window) && IsIconic(window), "W10 close minimizes without destroying");
      ShowWindow(window, SW_RESTORE);
      SendMessage(window, WM_SYSCOMMAND, SC_CLOSE, 0);
      Check(IsWindow(window) && IsIconic(window), "W10 Alt-F4 system close uses same policy");
      Check(!policy.SetAction("invalid"), "W10 invalid action rejected");
      policy.SetAction("exit");
      SendMessage(window, WM_CLOSE, 0, 0);
      Check(!IsWindow(window), "W10 exit destroys main window");
    }
    {
      WindowsDesktopPolicy policy;
      ActivateForGate(policy);
      HWND window = CreateGateWindow(policy);
      const DWORD before = GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS);
      for (int i = 0; i < 30; ++i) {
        if (ListWindowsFonts(window).empty()) throw std::runtime_error("Font enumeration failed");
      }
      Check(true, "W05 actual font enumeration over all 30 repetitions");
      Check(GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS) <= before + 1, "W05 font enumeration releases GDI handles");
      policy.RequestExit(window);
      MSG message;
      while (PeekMessage(&message, nullptr, 0, 0, PM_REMOVE)) DispatchMessage(&message);
      Check(!IsWindow(window), "W10 independent exit bypasses minimize");
    }
    {
      WindowsDesktopPolicy policy;
      ActivateForGate(policy);
      HWND window = CreateGateWindow(policy);
      Check(SendMessage(window, WM_QUERYENDSESSION, 0, 0) == TRUE, "W10 shutdown accepted");
      SendMessage(window, WM_ENDSESSION, FALSE, 0);
      SendMessage(window, WM_CLOSE, 0, 0);
      Check(IsWindow(window) && IsIconic(window), "W10 cancelled shutdown preserves close policy");
      SendMessage(window, WM_QUERYENDSESSION, 0, 0);
      SendMessage(window, WM_ENDSESSION, TRUE, 0);
      Check(!IsWindow(window), "W10 shutdown does not minimize");
    }
    current_policy = nullptr;
    UnregisterClassW(cls.lpszClassName, cls.hInstance);
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "FAIL " << error.what() << std::endl;
    return 1;
  }
}

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#ifdef YUEYIN_BUILD
#include <shobjidl.h>
#include "ik_desktop_host.h"
#endif

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

#ifdef YUEYIN_BUILD
  IkSingleInstance instance_guard;
  if (!instance_guard.valid()) {
    MessageBoxW(nullptr, L"暂时无法创建 IK Music 的实例锁，请稍后重试。", L"IK Music", MB_OK | MB_ICONERROR);
    return EXIT_FAILURE;
  }
  if (!instance_guard.primary()) {
    if (!instance_guard.WakeExisting()) {
      MessageBoxW(nullptr, L"IK Music 正在启动或退出，请稍后再打开。", L"IK Music", MB_OK | MB_ICONINFORMATION);
    }
    return EXIT_SUCCESS;
  }
#endif

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
#ifdef YUEYIN_BUILD
  ::SetCurrentProcessExplicitAppUserModelID(L"sun-dove.YueyinMusic");
#endif

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1200, 800);
#ifdef YUEYIN_BUILD
  const wchar_t* title = L"IK Music";
#else
  const wchar_t* title = L"Mconnect";
#endif
  if (!window.Create(title, origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetMinimumSize(Win32Window::Size(900, 600));
  window.SetQuitOnClose(true);
  window.SetAskBeforeClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}

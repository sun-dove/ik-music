#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "floating_lyrics_channel.h"
#include "win32_window.h"
#ifdef YUEYIN_BUILD
#include "ik_desktop_channel.h"
#include "windows_desktop_channel.h"
#endif

class FlutterWindow : public Win32Window {
 public:
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  flutter::DartProject project_;
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<FloatingLyricsChannel> floating_lyrics_channel_;
#ifdef YUEYIN_BUILD
  WindowsDesktopPolicy desktop_policy_;
  std::unique_ptr<WindowsDesktopChannel> desktop_channel_;
  std::unique_ptr<IkDesktopChannel> ik_desktop_channel_;
#endif
};

#endif  // RUNNER_FLUTTER_WINDOW_H_

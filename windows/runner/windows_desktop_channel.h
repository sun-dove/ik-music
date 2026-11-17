#ifndef YUEYIN_WINDOWS_DESKTOP_CHANNEL_H_
#define YUEYIN_WINDOWS_DESKTOP_CHANNEL_H_
#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <memory>
#include "windows_desktop_policy.h"

class WindowsDesktopChannel {
 public:
  WindowsDesktopChannel(flutter::BinaryMessenger* messenger, HWND window,
                        WindowsDesktopPolicy& policy);
  ~WindowsDesktopChannel();
  bool PrepareExit();
  bool HandleTimer(WPARAM timer);
 private:
  void BeginExit();
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  HWND window_;
  WindowsDesktopPolicy& policy_;
  bool client_ready_ = false;
  bool preparing_ = false;
  std::shared_ptr<bool> alive_ = std::make_shared<bool>(true);
};
#endif

#ifndef RUNNER_IK_DESKTOP_CHANNEL_H_
#define RUNNER_IK_DESKTOP_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include "ik_desktop_host.h"

class IkDesktopChannel {
 public:
  IkDesktopChannel(flutter::BinaryMessenger* messenger, HWND window,
                   std::function<void()> exit);
  ~IkDesktopChannel();
  void ShowInitial() { host_.ShowInitial(); }
  std::optional<LRESULT> HandleMessage(UINT message, WPARAM wparam,
                                       LPARAM lparam) {
    return host_.HandleMessage(message, wparam, lparam);
  }

 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  IkDesktopHost host_;
};

#endif  // RUNNER_IK_DESKTOP_CHANNEL_H_

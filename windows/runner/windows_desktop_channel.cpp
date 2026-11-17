#include "windows_desktop_channel.h"
#include <flutter/standard_method_codec.h>
#include <flutter/method_result_functions.h>
namespace { constexpr UINT_PTR kExitTimer = 0x595545; }

WindowsDesktopChannel::WindowsDesktopChannel(flutter::BinaryMessenger* messenger,
                                             HWND window,
                                             WindowsDesktopPolicy& policy)
    : window_(window), policy_(policy) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "sun-dove.yueyin/desktop",
      &flutter::StandardMethodCodec::GetInstance());
  policy.Activate();
  channel_->SetMethodCallHandler(
      [this, window, &policy](const auto& call, auto result) {
        if (call.method_name() == "setCloseAction") {
          const auto* args = call.arguments() == nullptr ? nullptr
              : std::get_if<flutter::EncodableMap>(call.arguments());
          const auto found = args == nullptr ? flutter::EncodableMap::const_iterator()
              : args->find(flutter::EncodableValue("action"));
          const auto* action = args == nullptr || found == args->end() ? nullptr
              : std::get_if<std::string>(&found->second);
          if (action == nullptr || !policy.SetAction(*action)) {
            result->Error("invalid_action", "Unsupported close action");
            return;
          }
          client_ready_ = true;
          result->Success(flutter::EncodableValue(flutter::EncodableMap{
              {flutter::EncodableValue("applied"), flutter::EncodableValue(true)},
              {flutter::EncodableValue("action"), flutter::EncodableValue(*action)}}));
        } else if (call.method_name() == "listFonts") {
          flutter::EncodableList fonts;
          for (const auto& family : ListWindowsFonts(window)) {
            const int size = WideCharToMultiByte(CP_UTF8, 0, family.data(),
                static_cast<int>(family.size()), nullptr, 0, nullptr, nullptr);
            std::string encoded(static_cast<size_t>(size), '\0');
            WideCharToMultiByte(CP_UTF8, 0, family.data(),
                static_cast<int>(family.size()), encoded.data(), size, nullptr, nullptr);
            fonts.emplace_back(encoded);
          }
          result->Success(flutter::EncodableValue(fonts));
        } else if (call.method_name() == "exitApplication") {
          result->Success();
          if (!PrepareExit()) policy.RequestExit(window);
        } else {
          result->NotImplemented();
        }
      });
}
WindowsDesktopChannel::~WindowsDesktopChannel() {
  *alive_ = false;
  KillTimer(window_, kExitTimer);
  channel_->SetMethodCallHandler(nullptr);
}

void WindowsDesktopChannel::BeginExit() {
  if (preparing_) return;
  preparing_ = true;
  SetTimer(window_, kExitTimer, 8000, nullptr);
  std::weak_ptr<bool> alive = alive_;
  auto finish = [this, alive]() {
    auto token = alive.lock();
    if (!token || !*token) return;
    KillTimer(window_, kExitTimer);
    policy_.RequestExit(window_);
  };
  channel_->InvokeMethod("prepareExit", nullptr,
      std::make_unique<flutter::MethodResultFunctions<flutter::EncodableValue>>(
        [finish](const flutter::EncodableValue*) { finish(); },
        [finish](const std::string&, const std::string&, const flutter::EncodableValue*) { finish(); },
        [finish]() { finish(); }));
}
bool WindowsDesktopChannel::PrepareExit() {
  if (!client_ready_) return false;
  BeginExit();
  return true;
}
bool WindowsDesktopChannel::HandleTimer(WPARAM timer) {
  if (timer != kExitTimer) return false;
  KillTimer(window_, kExitTimer);
  policy_.RequestExit(window_);
  return true;
}

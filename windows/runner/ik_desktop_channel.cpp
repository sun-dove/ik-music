#include "ik_desktop_channel.h"

#include <flutter/standard_method_codec.h>

#include <utility>

namespace {
std::wstring WideString(const std::string& value) {
  if (value.empty()) return {};
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.data(),
                                      static_cast<int>(value.size()), nullptr, 0);
  if (size <= 0) return {};
  std::wstring wide(static_cast<size_t>(size), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
                      wide.data(), size);
  return wide;
}

template <typename T>
const T* Argument(const flutter::EncodableMap& args, const char* name) {
  const auto found = args.find(flutter::EncodableValue(name));
  return found == args.end() ? nullptr : std::get_if<T>(&found->second);
}
}  // namespace

IkDesktopChannel::IkDesktopChannel(flutter::BinaryMessenger* messenger,
                                     HWND window, std::function<void()> exit)
    : channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "sun-dove.yueyin/ik-desktop",
          &flutter::StandardMethodCodec::GetInstance())),
      host_(window, [this](const std::string& command) {
        channel_->InvokeMethod("command",
            std::make_unique<flutter::EncodableValue>(command));
      }, std::move(exit)) {
  host_.Initialize();
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "initialize") {
      host_.Initialize();
      result->Success(flutter::EncodableValue(true));
    } else if (call.method_name() == "capabilities") {
      result->Success(flutter::EncodableValue(flutter::EncodableMap{
          {flutter::EncodableValue("tray"), flutter::EncodableValue(host_.tray_available())},
          {flutter::EncodableValue("media"), flutter::EncodableValue(host_.media_available())},
          {flutter::EncodableValue("windowMemory"), flutter::EncodableValue(host_.memory_available())},
          {flutter::EncodableValue("mediaError"), flutter::EncodableValue(host_.media_error())}}));
    } else if (call.method_name() == "update") {
      const auto* args = call.arguments() == nullptr ? nullptr :
          std::get_if<flutter::EncodableMap>(call.arguments());
      if (!args) {
        result->Error("invalid_arguments", "Expected playback state map");
        return;
      }
      const auto* title = Argument<std::string>(*args, "title");
      const auto* artist = Argument<std::string>(*args, "artist");
      const auto* enabled = Argument<bool>(*args, "enabled");
      const auto* playing = Argument<bool>(*args, "playing");
      if (!title || !artist || !enabled || !playing) {
        result->Error("invalid_arguments", "Expected title, artist, enabled and playing");
        return;
      }
      host_.Update(WideString(*title), WideString(*artist), *enabled, *playing);
      result->Success();
    } else {
      result->NotImplemented();
    }
  });
}

IkDesktopChannel::~IkDesktopChannel() {
  channel_->SetMethodCallHandler(nullptr);
}

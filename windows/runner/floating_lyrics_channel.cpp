#include "floating_lyrics_channel.h"

#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <cstdint>
#include <string>

#ifdef YUEYIN_BUILD
#include "ik_desktop_host.h"
#endif

namespace {

constexpr char kChannelName[] = "com.mconnect.mconnect/floating_lyrics";

#ifdef YUEYIN_BUILD
BOOL CALLBACK WakeLyricsSettingsWindow(HWND window, LPARAM) {
  DWORD process = 0;
  GetWindowThreadProcessId(window, &process);
  if (process != GetCurrentProcessId() ||
      !GetPropW(window, IkDesktopHost::WindowProperty())) {
    return TRUE;
  }
  PostMessageW(window, IkDesktopHost::WakeMessage(), 0, 0);
  return FALSE;
}
#endif

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return L"";
  }
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, nullptr,
                                       0);
  if (size <= 0) {
    return L"";
  }
  std::wstring result(static_cast<size_t>(size - 1), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, result.data(), size);
  return result;
}

const flutter::EncodableValue* FindValue(const flutter::EncodableMap& map,
                                         const char* key) {
  const auto it = map.find(flutter::EncodableValue(std::string(key)));
  if (it == map.end()) {
    return nullptr;
  }
  return &it->second;
}

std::string GetString(const flutter::EncodableMap& map, const char* key) {
  const auto* value = FindValue(map, key);
  if (value == nullptr || value->IsNull()) {
    return "";
  }
  if (const auto* string_value = std::get_if<std::string>(value)) {
    return *string_value;
  }
  return "";
}

int GetInt(const flutter::EncodableMap& map, const char* key, int fallback) {
  const auto* value = FindValue(map, key);
  if (value == nullptr || value->IsNull()) {
    return fallback;
  }
  if (const auto* int32_value = std::get_if<int32_t>(value)) {
    return *int32_value;
  }
  if (const auto* int64_value = std::get_if<int64_t>(value)) {
    return static_cast<int>(*int64_value);
  }
  if (const auto* double_value = std::get_if<double>(value)) {
    return static_cast<int>(*double_value);
  }
  return fallback;
}

bool GetBool(const flutter::EncodableMap& map, const char* key, bool fallback) {
  const auto* value = FindValue(map, key);
  if (value == nullptr || value->IsNull()) {
    return fallback;
  }
  if (const auto* bool_value = std::get_if<bool>(value)) {
    return *bool_value;
  }
  return fallback;
}

double GetDouble(const flutter::EncodableMap& map,
                 const char* key,
                 double fallback) {
  const auto* value = FindValue(map, key);
  if (value == nullptr || value->IsNull()) {
    return fallback;
  }
  if (const auto* double_value = std::get_if<double>(value)) {
    return *double_value;
  }
  if (const auto* int32_value = std::get_if<int32_t>(value)) {
    return static_cast<double>(*int32_value);
  }
  if (const auto* int64_value = std::get_if<int64_t>(value)) {
    return static_cast<double>(*int64_value);
  }
  return fallback;
}

bool GetColorArgb(const flutter::EncodableMap& map,
                  const char* key,
                  std::uint32_t* argb) {
  const auto* value = FindValue(map, key);
  if (value == nullptr || value->IsNull()) {
    return false;
  }
  if (const auto* int32_value = std::get_if<int32_t>(value)) {
    *argb = static_cast<std::uint32_t>(*int32_value);
    return true;
  }
  if (const auto* int64_value = std::get_if<int64_t>(value)) {
    *argb = static_cast<std::uint32_t>(*int64_value);
    return true;
  }
  if (const auto* double_value = std::get_if<double>(value)) {
    *argb = static_cast<std::uint32_t>(*double_value);
    return true;
  }
  return false;
}

COLORREF GetColor(const flutter::EncodableMap& map,
                  const char* key,
                  COLORREF fallback) {
  std::uint32_t argb = 0;
  if (!GetColorArgb(map, key, &argb)) {
    return fallback;
  }
  return RGB((argb >> 16) & 0xff, (argb >> 8) & 0xff, argb & 0xff);
}

const flutter::EncodableMap* ArgumentsAsMap(
    const flutter::EncodableValue* arguments) {
  if (arguments == nullptr || arguments->IsNull()) {
    return nullptr;
  }
  return std::get_if<flutter::EncodableMap>(arguments);
}

}  // namespace

FloatingLyricsChannel::FloatingLyricsChannel(
    flutter::BinaryMessenger* messenger) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, kChannelName, &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });

  // Set up event callback to send native events back to Flutter
  window_.SetEventCallback([this](const std::string& event) {
    SendEventToFlutter(event);
  });
  compact_window_.SetEventCallback([this](const std::string& event) {
    if (!channel_) return;
    if (event == "windowResized") {
      flutter::EncodableMap args;
      args[flutter::EncodableValue("width")] =
          flutter::EncodableValue(compact_window_.GetWidth());
      args[flutter::EncodableValue("height")] =
          flutter::EncodableValue(compact_window_.GetHeight());
      channel_->InvokeMethod(event,
          std::make_unique<flutter::EncodableValue>(args));
    } else if (event == "lockChanged") {
      channel_->InvokeMethod(event,
          std::make_unique<flutter::EncodableValue>(compact_window_.IsLocked()));
    } else if (event == "previous" || event == "playPause" || event == "next") {
      flutter::EncodableMap args;
      args[flutter::EncodableValue("action")] = flutter::EncodableValue(event);
      channel_->InvokeMethod("controlRequested",
          std::make_unique<flutter::EncodableValue>(args));
    } else if (event == "settingsRequested") {
#ifdef YUEYIN_BUILD
      EnumWindows(WakeLyricsSettingsWindow, 0);
#endif
      channel_->InvokeMethod("settingsRequested", nullptr);
    } else {
      channel_->InvokeMethod(event, nullptr);
    }
  });
}

FloatingLyricsChannel::~FloatingLyricsChannel() = default;

void FloatingLyricsChannel::SendEventToFlutter(const std::string& event) {
  if (!channel_) return;

  if (event == "windowResized") {
    flutter::EncodableMap args;
    args[flutter::EncodableValue("width")] =
        flutter::EncodableValue(window_.GetWidth());
    args[flutter::EncodableValue("height")] =
        flutter::EncodableValue(window_.GetHeight());
    channel_->InvokeMethod(event,
                           std::make_unique<flutter::EncodableValue>(args));
  } else if (event == "lockChanged") {
    channel_->InvokeMethod(
        event,
        std::make_unique<flutter::EncodableValue>(window_.IsLocked()));
  } else {
    channel_->InvokeMethod(event, nullptr);
  }
}

void FloatingLyricsChannel::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();

  if (method == "canDrawOverlays" || method == "openOverlaySettings") {
    result->Success(flutter::EncodableValue(true));
    return;
  }

  if (method == "hide") {
    compact_window_.Hide();
    window_.Hide();
    result->Success(flutter::EncodableValue(true));
    return;
  }

  if (method == "show" || method == "update") {
    const auto* arguments = ArgumentsAsMap(call.arguments());
    if (arguments == nullptr) {
      result->Error("INVALID_ARGUMENTS", "Floating lyrics payload is missing");
      return;
    }

    const auto* presentation = ArgumentsAsMap(
        FindValue(*arguments, "windowsPresentation"));
    if (presentation != nullptr && GetInt(*presentation, "version", 0) == 1 &&
        GetString(*presentation, "style") == "compact") {
      CompactLyricsContent content;
      content.text = Utf8ToWide(GetString(*arguments, "text"));
      content.translation = Utf8ToWide(GetString(*arguments, "translation"));
      content.next_text = Utf8ToWide(GetString(*arguments, "nextText"));
      const auto family = GetString(*presentation, "fontFamily");
      if (!family.empty()) content.font_family = Utf8ToWide(family);
      content.width = GetInt(*arguments, "width", 320);
      content.height = GetInt(*arguments, "height", 92);
      content.font_size = GetDouble(*presentation, "fontSize",
          GetDouble(*arguments, "fontSize", 23));
      GetColorArgb(*arguments, "textColor", &content.text_color);
      GetColorArgb(*arguments, "highlightColor", &content.current_color);
      content.other_color = content.text_color;
      GetColorArgb(*presentation, "currentLineColor", &content.current_color);
      GetColorArgb(*presentation, "otherLineColor", &content.other_color);
      GetColorArgb(*presentation, "backgroundColor", &content.background_color);
      content.shadow_opacity = GetDouble(*presentation, "shadowOpacity",
          GetDouble(*arguments, "shadowOpacity", 0.78));
      content.stroke_width = GetDouble(*arguments, "strokeWidth", 0.7);
      content.highlight_progress = GetDouble(*arguments, "highlightProgress", 0);
      content.highlight_rate = GetDouble(*arguments, "highlightRate", 0);
      content.current_color_explicit =
          GetBool(*presentation, "currentLineColorExplicit", false);
      content.locked = GetBool(*arguments, "isLocked", false);
      content.playing = GetBool(*arguments, "isPlaying", false);
      content.has_song = GetBool(*arguments, "hasSong", false);
      window_.Hide();
      const bool ok = compact_window_.Present(content, method == "show");
      result->Success(flutter::EncodableValue(ok));
      return;
    }
    // 缺省请求明确回到旧窗口，不继承上一次 IK 的呈现选择。
    compact_window_.Hide();

    const std::wstring text = Utf8ToWide(GetString(*arguments, "text"));
    const std::wstring translation =
        Utf8ToWide(GetString(*arguments, "translation"));
    // Drawn under the active pair; previously received and thrown away.
    const std::wstring next_text =
        Utf8ToWide(GetString(*arguments, "nextText"));
    const int width = GetInt(*arguments, "width", 420);
    const int height = GetInt(*arguments, "height", 112);
    const int font_size = GetInt(*arguments, "fontSize", 24);
    const COLORREF text_color =
        GetColor(*arguments, "textColor", RGB(255, 255, 255));
    // Colours the already-sung prefix instead of the hard-coded white pair.
    const COLORREF highlight_color =
        GetColor(*arguments, "highlightColor", RGB(255, 212, 74));
    const double highlight_progress =
        GetDouble(*arguments, "highlightProgress", 0.0);
    const bool locked = GetBool(*arguments, "isLocked", false);

    const bool ok =
        method == "show"
            ? window_.Show(text, translation, width, height, font_size,
                           text_color, locked, next_text, highlight_color,
                           highlight_progress)
            : window_.Update(text, translation, width, height, font_size,
                             text_color, locked, next_text, highlight_color,
                             highlight_progress);
    result->Success(flutter::EncodableValue(ok));
    return;
  }

  result->NotImplemented();
}

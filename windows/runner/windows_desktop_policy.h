#ifndef YUEYIN_WINDOWS_DESKTOP_POLICY_H_
#define YUEYIN_WINDOWS_DESKTOP_POLICY_H_
#include <windows.h>
#include <optional>
#include <set>
#include <string>

// 新通道启用后才接管关闭；Win32Window 的公开接口和旧缺省路径保持。
class WindowsDesktopPolicy {
 public:
  void Activate() { active_ = true; }
  bool NeedsExitPreparation() const { return active_ && !minimize_ && !force_exit_ && !ending_session_; }
  bool SetAction(const std::string& action) {
    if (action != "minimize" && action != "exit") return false;
    minimize_ = action == "minimize";
    return true;
  }
  void RequestExit(HWND window) {
    force_exit_ = true;
    PostMessage(window, WM_CLOSE, 0, 0);
  }
  std::optional<LRESULT> HandleMessage(HWND window, UINT message,
                                     WPARAM wparam, LPARAM) {
    if (!active_) return std::nullopt;
    if (message == WM_QUERYENDSESSION) {
      ending_session_ = true;
      return TRUE;
    }
    if (message == WM_ENDSESSION) {
      ending_session_ = wparam != 0;
      if (ending_session_) DestroyWindow(window);
      return 0;
    }
    if (message != WM_CLOSE) return std::nullopt;
    if (minimize_ && !force_exit_ && !ending_session_) {
      ShowWindow(window, SW_MINIMIZE);
    } else {
      DestroyWindow(window);
    }
    return 0;
  }
 private:
  bool active_ = false;
  bool minimize_ = true;
  bool force_exit_ = false;
  bool ending_session_ = false;
};

inline int CALLBACK CollectWindowsFont(const LOGFONTW* font,
                                      const TEXTMETRICW*, DWORD, LPARAM value) {
  if (font->lfFaceName[0] != L'@') {
    reinterpret_cast<std::set<std::wstring>*>(value)->insert(font->lfFaceName);
  }
  return 1;
}

inline std::set<std::wstring> ListWindowsFonts(HWND window) {
  std::set<std::wstring> families;
  HDC dc = GetDC(window);
  if (dc == nullptr) return families;
  LOGFONTW filter{};
  filter.lfCharSet = DEFAULT_CHARSET;
  EnumFontFamiliesExW(dc, &filter, CollectWindowsFont,
                     reinterpret_cast<LPARAM>(&families), 0);
  ReleaseDC(window, dc);
  return families;
}
#endif

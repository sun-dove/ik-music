#ifndef RUNNER_COMPACT_FLOATING_LYRICS_WINDOW_H_
#define RUNNER_COMPACT_FLOATING_LYRICS_WINDOW_H_

#include <windows.h>

#include <cstdint>
#include <functional>
#include <string>

struct CompactLyricsContent {
  std::wstring text;
  std::wstring translation;
  std::wstring next_text;
  std::wstring font_family = L"Microsoft YaHei UI";
  int width = 320;
  int height = 92;
  double font_size = 23.0;
  std::uint32_t text_color = 0xffffffff;
  std::uint32_t current_color = 0xffffd44a;
  std::uint32_t other_color = 0xffffffff;
  std::uint32_t background_color = 0;
  double shadow_opacity = 0.78;
  double stroke_width = 0.7;
  double highlight_progress = 0;
  double highlight_rate = 0;
  bool current_color_explicit = false;
  bool locked = false;
  bool playing = false;
  bool has_song = false;
};

/// IK 专用逐像素透明窗。旧 FloatingLyricsWindow 的签名和绘制均保留。
class CompactFloatingLyricsWindow {
 public:
  CompactFloatingLyricsWindow();
  ~CompactFloatingLyricsWindow();
  void SetEventCallback(std::function<void(const std::string&)> callback);
  bool Present(const CompactLyricsContent& content, bool explicit_show);
  void Hide();
  int GetWidth() const { return content_.width; }
  int GetHeight() const { return content_.height; }
  bool IsLocked() const { return content_.locked; }
  static LRESULT CALLBACK WndProc(HWND hwnd, UINT message, WPARAM wparam,
                                  LPARAM lparam);

 private:
  HWND window_ = nullptr;
  ULONG_PTR gdiplus_token_ = 0;
  CompactLyricsContent content_;
  std::function<void(const std::string&)> event_callback_;
  POINT body_origin_{};
  POINT drag_origin_{};
  POINT drag_pointer_{};
  SIZE resize_origin_{};
  float scale_ = 1.0f;
  bool positioned_ = false;
  bool visible_ = false;
  bool closed_by_user_ = false;
  bool hovered_ = false;
  bool toolbar_above_ = true;
  bool dragging_ = false;
  bool resizing_ = false;
  int hovered_button_ = -1;
  int pressed_button_ = -1;
  ULONGLONG highlight_anchor_ = 0;
  ULONGLONG line_started_ = 0;
  ULONGLONG paused_at_ = 0;
  ULONGLONG mouse_left_at_ = 0;
  bool needs_motion_ = false;

  static constexpr UINT_PTR kMotionTimer = 1;
  bool EnsureWindow();
  bool Paint();
  void ApplyLock();
  void UpdateTimer();
  void SetHovered(bool hovered);
  void ConstrainBody();
  void Send(const std::string& event);
  bool ToolbarVisible() const;
  RECT BodyRect() const;
  RECT ToolbarRect() const;
  RECT ButtonRect(int index) const;
  int ButtonAt(POINT point) const;
  bool ResizeAt(POINT point) const;
  int Pixels(double value) const;
};

#endif

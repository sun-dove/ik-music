#include "compact_floating_lyrics_window.h"

#include <gdiplus.h>
#include <windowsx.h>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <utility>

namespace {
constexpr wchar_t kCompactClass[] = L"IK_COMPACT_FLOATING_LYRICS_WINDOW";
constexpr int kToolbarHeight = 36;
constexpr int kToolbarGap = 6;
constexpr int kTooltipHeight = 24;
constexpr int kToolbarButtons = 6;

float WindowScale(HWND window) {
  using GetWindowDpi = UINT(WINAPI*)(HWND);
  const auto address = GetProcAddress(GetModuleHandleW(L"user32.dll"),
                                      "GetDpiForWindow");
  GetWindowDpi get_dpi = nullptr;
  static_assert(sizeof(get_dpi) == sizeof(address));
  std::memcpy(&get_dpi, &address, sizeof(get_dpi));
  return get_dpi ? static_cast<float>(get_dpi(window)) / 96.0f : 1.0f;
}

BYTE Alpha(std::uint32_t color) {
  return static_cast<BYTE>((color >> 24) & 0xff);
}

std::uint32_t WithAlpha(std::uint32_t color, BYTE alpha) {
  return (color & 0x00ffffff) | (static_cast<std::uint32_t>(alpha) << 24);
}

void RoundedPath(Gdiplus::GraphicsPath& path, Gdiplus::RectF rect,
                 float radius) {
  const float diameter = std::min(radius * 2, std::min(rect.Width, rect.Height));
  path.AddArc(rect.X, rect.Y, diameter, diameter, 180, 90);
  path.AddArc(rect.GetRight() - diameter, rect.Y, diameter, diameter, 270, 90);
  path.AddArc(rect.GetRight() - diameter, rect.GetBottom() - diameter,
              diameter, diameter, 0, 90);
  path.AddArc(rect.X, rect.GetBottom() - diameter, diameter, diameter, 90, 90);
  path.CloseFigure();
}

Gdiplus::RectF FloatRect(const RECT& value) {
  return Gdiplus::RectF(static_cast<float>(value.left),
                        static_cast<float>(value.top),
                        static_cast<float>(value.right - value.left),
                        static_cast<float>(value.bottom - value.top));
}

void DrawIcon(Gdiplus::Graphics& graphics, RECT bounds, int index,
              bool playing, bool enabled, float scale) {
  const float cx = static_cast<float>(bounds.left + bounds.right) * 0.5f;
  const float cy = static_cast<float>(bounds.top + bounds.bottom) * 0.5f;
  const float r = 6.0f * scale;
  Gdiplus::Color color(static_cast<BYTE>(enabled ? 238 : 86), 244, 248, 247);
  Gdiplus::Pen pen(color, 1.7f * scale);
  pen.SetStartCap(Gdiplus::LineCapRound);
  pen.SetEndCap(Gdiplus::LineCapRound);
  Gdiplus::SolidBrush brush(color);
  if (index == 0 || index == 2) {
    const float direction = index == 0 ? -1.0f : 1.0f;
    Gdiplus::PointF points[] = {
        {cx + direction * r * 0.7f, cy},
        {cx - direction * r * 0.7f, cy - r},
        {cx - direction * r * 0.7f, cy + r}};
    graphics.FillPolygon(&brush, points, 3);
    graphics.DrawLine(&pen, cx + direction * (r + 2 * scale), cy - r,
                       cx + direction * (r + 2 * scale), cy + r);
  } else if (index == 1) {
    if (playing) {
      graphics.FillRectangle(&brush, cx - 5 * scale, cy - r, 3 * scale, 2 * r);
      graphics.FillRectangle(&brush, cx + 2 * scale, cy - r, 3 * scale, 2 * r);
    } else {
      Gdiplus::PointF points[] = {{cx + r, cy}, {cx - r * 0.7f, cy - r},
                                  {cx - r * 0.7f, cy + r}};
      graphics.FillPolygon(&brush, points, 3);
    }
  } else if (index == 3) {
    graphics.DrawArc(&pen, cx - 4 * scale, cy - 7 * scale,
                      8 * scale, 10 * scale, 180, 180);
    Gdiplus::GraphicsPath lock;
    RoundedPath(lock, {cx - 6 * scale, cy - scale, 12 * scale, 9 * scale},
                2 * scale);
    graphics.DrawPath(&pen, &lock);
  } else if (index == 4) {
    graphics.DrawLine(&pen, cx - 5 * scale, cy - 5 * scale,
                       cx + 5 * scale, cy + 5 * scale);
    graphics.DrawLine(&pen, cx + 5 * scale, cy - 5 * scale,
                       cx - 5 * scale, cy + 5 * scale);
  } else {
    Gdiplus::PointF teeth[32];
    for (int i = 0; i < 32; ++i) {
      const float angle = static_cast<float>(i) * 3.14159265f / 16.0f;
      const float radius = (i % 4 < 2 ? 7.0f : 5.3f) * scale;
      teeth[i] = {cx + std::cos(angle) * radius, cy + std::sin(angle) * radius};
    }
    Gdiplus::GraphicsPath gear(Gdiplus::FillModeAlternate);
    gear.AddPolygon(teeth, 32);
    gear.AddEllipse(cx - 2.4f * scale, cy - 2.4f * scale,
                     4.8f * scale, 4.8f * scale);
    graphics.FillPath(&brush, &gear);
  }
}
}  // namespace

CompactFloatingLyricsWindow::CompactFloatingLyricsWindow() = default;

CompactFloatingLyricsWindow::~CompactFloatingLyricsWindow() {
  if (window_) DestroyWindow(window_);
  if (gdiplus_token_) Gdiplus::GdiplusShutdown(gdiplus_token_);
}

void CompactFloatingLyricsWindow::SetEventCallback(
    std::function<void(const std::string&)> callback) {
  event_callback_ = std::move(callback);
}

int CompactFloatingLyricsWindow::Pixels(double value) const {
  return static_cast<int>(std::lround(value * scale_));
}

bool CompactFloatingLyricsWindow::EnsureWindow() {
  if (window_) return true;
  if (!gdiplus_token_) {
    Gdiplus::GdiplusStartupInput input;
    if (Gdiplus::GdiplusStartup(&gdiplus_token_, &input, nullptr) != Gdiplus::Ok) {
      return false;
    }
  }
  WNDCLASSW existing{};
  if (!GetClassInfoW(GetModuleHandle(nullptr), kCompactClass, &existing)) {
    WNDCLASSW definition{};
    definition.lpfnWndProc = WndProc;
    definition.hInstance = GetModuleHandle(nullptr);
    definition.hCursor = LoadCursor(nullptr, IDC_ARROW);
    definition.lpszClassName = kCompactClass;
    if (!RegisterClassW(&definition)) return false;
  }
  window_ = CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
      kCompactClass, L"IK Music 桌面歌词", WS_POPUP, 0, 0, 1, 1,
      nullptr, nullptr, GetModuleHandle(nullptr), this);
  if (!window_) return false;
  scale_ = WindowScale(window_);
  if (scale_ <= 0) scale_ = 1;
  return true;
}

bool CompactFloatingLyricsWindow::Present(const CompactLyricsContent& content,
                                          bool explicit_show) {
  if (closed_by_user_ && !explicit_show) return true;
  if (explicit_show) closed_by_user_ = false;
  const bool changed_line = content.text != content_.text ||
                            content.translation != content_.translation ||
                            content.next_text != content_.next_text;
  const int live_width = content_.width;
  const int live_height = content_.height;
  const bool was_playing = content_.playing;
  const bool was_locked = content_.locked;
  content_ = content;
  if (resizing_) {
    content_.width = live_width;
    content_.height = live_height;
  }
  content_.width = std::clamp(content_.width, 220, 720);
  content_.height = std::clamp(content_.height, 72, 220);
  content_.font_size = std::clamp(content_.font_size, 14.0, 48.0);
  content_.shadow_opacity = std::clamp(content_.shadow_opacity, 0.0, 1.0);
  content_.stroke_width = std::clamp(content_.stroke_width, 0.0, 2.0);
  highlight_anchor_ = GetTickCount64();
  if (changed_line || !line_started_) {
    line_started_ = highlight_anchor_;
    paused_at_ = content_.playing ? 0 : highlight_anchor_;
  } else if (was_playing && !content_.playing) {
    paused_at_ = highlight_anchor_;
  } else if (!was_playing && content_.playing && paused_at_) {
    line_started_ += highlight_anchor_ - paused_at_;
    paused_at_ = 0;
  }
  if (!EnsureWindow()) return false;
  if (!positioned_) {
    RECT work{};
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
    body_origin_.x = work.left + (work.right - work.left - Pixels(content_.width)) / 2;
    body_origin_.y = work.top + Pixels(80);
    positioned_ = true;
  }
  ConstrainBody();
  if (was_locked != content_.locked || !visible_) ApplyLock();
  visible_ = true;
  if (!Paint()) {
    Hide();
    return false;
  }
  ShowWindow(window_, SW_SHOWNOACTIVATE);
  UpdateTimer();
  return true;
}

void CompactFloatingLyricsWindow::Hide() {
  visible_ = false;
  hovered_ = false;
  dragging_ = false;
  resizing_ = false;
  hovered_button_ = -1;
  pressed_button_ = -1;
  if (window_) {
    KillTimer(window_, kMotionTimer);
    if (GetCapture() == window_) ReleaseCapture();
    ShowWindow(window_, SW_HIDE);
  }
}

void CompactFloatingLyricsWindow::Send(const std::string& event) {
  if (event_callback_) event_callback_(event);
}

bool CompactFloatingLyricsWindow::ToolbarVisible() const {
  return !content_.locked && (hovered_ || dragging_ || resizing_);
}

RECT CompactFloatingLyricsWindow::BodyRect() const {
  const int offset = ToolbarVisible() && toolbar_above_
                         ? Pixels(kToolbarHeight + kToolbarGap +
                                  (hovered_button_ >= 0 ? kTooltipHeight : 0))
                         : 0;
  return {0, offset, Pixels(content_.width), offset + Pixels(content_.height)};
}

RECT CompactFloatingLyricsWindow::ToolbarRect() const {
  const int width = Pixels(214);
  const int left = (Pixels(content_.width) - width) / 2;
  const int top = toolbar_above_
                      ? Pixels(hovered_button_ >= 0 ? kTooltipHeight : 0)
                      : Pixels(content_.height + kToolbarGap);
  return {left, top, left + width, top + Pixels(kToolbarHeight)};
}

RECT CompactFloatingLyricsWindow::ButtonRect(int index) const {
  const RECT bar = ToolbarRect();
  // 设置在锁定和关闭之间，原有五项的动作索引保持不变。
  const int slot = index == 5 ? 4 : index == 4 ? 5 : index;
  const int left = bar.left + Pixels(5 + slot * 34);
  return {left, bar.top + Pixels(2), left + Pixels(34), bar.bottom - Pixels(2)};
}

int CompactFloatingLyricsWindow::ButtonAt(POINT point) const {
  if (!ToolbarVisible()) return -1;
  for (int i = 0; i < kToolbarButtons; ++i) {
    const RECT rect = ButtonRect(i);
    if (PtInRect(&rect, point)) return i;
  }
  return -1;
}

bool CompactFloatingLyricsWindow::ResizeAt(POINT point) const {
  if (content_.locked) return false;
  RECT rect = BodyRect();
  rect.left = rect.right - Pixels(18);
  rect.top = rect.bottom - Pixels(18);
  return PtInRect(&rect, point);
}

void CompactFloatingLyricsWindow::ConstrainBody() {
  RECT body{body_origin_.x, body_origin_.y,
             body_origin_.x + Pixels(content_.width),
             body_origin_.y + Pixels(content_.height)};
  MONITORINFO info{sizeof(MONITORINFO)};
  GetMonitorInfoW(MonitorFromRect(&body, MONITOR_DEFAULTTONEAREST), &info);
  body_origin_.x = std::clamp(body_origin_.x, info.rcWork.left,
      std::max(info.rcWork.left, info.rcWork.right - Pixels(content_.width)));
  body_origin_.y = std::clamp(body_origin_.y, info.rcWork.top,
      std::max(info.rcWork.top, info.rcWork.bottom - Pixels(content_.height)));
  toolbar_above_ = body_origin_.y -
                       Pixels(kToolbarHeight + kToolbarGap + kTooltipHeight) >=
                   info.rcWork.top;
}

void CompactFloatingLyricsWindow::ApplyLock() {
  LONG_PTR style = GetWindowLongPtrW(window_, GWL_EXSTYLE);
  if (content_.locked) {
    style |= WS_EX_TRANSPARENT;
    hovered_ = false;
    hovered_button_ = -1;
    pressed_button_ = -1;
    dragging_ = false;
    resizing_ = false;
    if (GetCapture() == window_) ReleaseCapture();
  } else {
    style &= ~static_cast<LONG_PTR>(WS_EX_TRANSPARENT);
  }
  SetWindowLongPtrW(window_, GWL_EXSTYLE, style);
}

void CompactFloatingLyricsWindow::SetHovered(bool hovered) {
  if (content_.locked || hovered_ == hovered) return;
  hovered_ = hovered;
  if (!hovered) hovered_button_ = -1;
  ConstrainBody();
  Paint();
  UpdateTimer();
}

void CompactFloatingLyricsWindow::UpdateTimer() {
  if (!window_) return;
  const bool animate = visible_ &&
      ((!content_.locked) || (content_.playing && needs_motion_));
  if (animate) {
    SetTimer(window_, kMotionTimer, content_.playing && needs_motion_ ? 33 : 100,
             nullptr);
  } else {
    KillTimer(window_, kMotionTimer);
  }
}

bool CompactFloatingLyricsWindow::Paint() {
  if (!window_ || !visible_) return false;
  const bool toolbar = ToolbarVisible();
  const int width = Pixels(content_.width);
  const int height = Pixels(content_.height +
      (toolbar ? kToolbarHeight + kToolbarGap +
                 (hovered_button_ >= 0 ? kTooltipHeight : 0) : 0));
  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = width;
  info.bmiHeader.biHeight = -height;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  HDC screen = GetDC(nullptr);
  HDC memory = CreateCompatibleDC(screen);
  void* bits = nullptr;
  HBITMAP bitmap = CreateDIBSection(screen, &info, DIB_RGB_COLORS, &bits,
                                    nullptr, 0);
  if (!memory || !bitmap || !bits) {
    if (bitmap) DeleteObject(bitmap);
    if (memory) DeleteDC(memory);
    ReleaseDC(nullptr, screen);
    return false;
  }
  const auto previous = SelectObject(memory, bitmap);
  std::memset(bits, 0, static_cast<size_t>(width) * static_cast<size_t>(height) * 4);
  {
    Gdiplus::Bitmap surface(width, height, width * 4, PixelFormat32bppPARGB,
                            static_cast<BYTE*>(bits));
    Gdiplus::Graphics graphics(&surface);
    graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    graphics.SetPixelOffsetMode(Gdiplus::PixelOffsetModeHighQuality);
    graphics.SetCompositingQuality(Gdiplus::CompositingQualityHighQuality);
    const RECT body = BodyRect();
    Gdiplus::GraphicsPath background;
    RoundedPath(background, FloatRect(body), 12 * scale_);
    if (!content_.locked) {
      const BYTE alpha = std::max<BYTE>(Alpha(content_.background_color),
                                        static_cast<BYTE>(toolbar ? 34 : 2));
      Gdiplus::SolidBrush brush(Gdiplus::Color(
          WithAlpha(content_.background_color, alpha)));
      graphics.FillPath(&brush, &background);
    }

    std::wstring primary = content_.text;
    std::wstring secondary = content_.translation.empty()
                                 ? content_.next_text
                                 : content_.translation;
    if (!content_.has_song) {
      primary = L"播放歌曲后显示歌词";
      secondary.clear();
    } else if (primary.empty()) {
      primary = L"暂无歌词";
    }
    const float body_height = static_cast<float>(body.bottom - body.top);
    const float available = body_height - 14 * scale_;
    const float font_size = std::min(
        static_cast<float>(content_.font_size) * scale_, available / 1.45f);
    const float side_size = font_size * 0.76f;
    const float inset = 12 * scale_;
    const float gap = 5 * scale_;
    const float main_height = font_size * 1.45f;
    const float side_height = side_size * 1.4f;
    const bool show_secondary = !secondary.empty() &&
        main_height + gap + side_height <= available;
    const float total = main_height + (show_secondary ? gap + side_height : 0);
    const float top = static_cast<float>(body.top) +
                      std::max(4 * scale_, (body_height - total) * 0.5f);
    const ULONGLONG now = GetTickCount64();
    const ULONGLONG text_clock = content_.playing || !paused_at_ ? now : paused_at_;
    const double progress = std::clamp(content_.highlight_progress +
        (content_.playing ? content_.highlight_rate *
             static_cast<double>(now - highlight_anchor_) : 0.0), 0.0, 1.0);
    needs_motion_ = content_.playing && !content_.current_color_explicit &&
                    content_.highlight_rate > 0 && progress < 1;

    const auto draw_text = [&](const std::wstring& text, Gdiplus::RectF area,
                               float size, std::uint32_t color,
                               bool current) {
      Gdiplus::FontFamily selected(content_.font_family.c_str());
      Gdiplus::FontFamily fallback(L"Microsoft YaHei UI");
      const Gdiplus::FontFamily* family = selected.GetLastStatus() == Gdiplus::Ok
                                            ? &selected : &fallback;
      if (family->GetLastStatus() != Gdiplus::Ok) {
        family = Gdiplus::FontFamily::GenericSansSerif();
      }
      int font_style = current ? Gdiplus::FontStyleBold : Gdiplus::FontStyleRegular;
      if (!family->IsStyleAvailable(font_style)) font_style = Gdiplus::FontStyleRegular;
      Gdiplus::StringFormat format(Gdiplus::StringFormat::GenericTypographic());
      format.SetFormatFlags(format.GetFormatFlags() | Gdiplus::StringFormatFlagsNoWrap);
      Gdiplus::GraphicsPath glyphs;
      glyphs.AddString(text.c_str(), static_cast<INT>(text.size()), family,
                       font_style, size, Gdiplus::PointF(0, 0), &format);
      Gdiplus::RectF bounds;
      glyphs.GetBounds(&bounds);
      if (bounds.Width <= 0 || bounds.Height <= 0) return;
      float offset = 0;
      if (bounds.Width > area.Width) {
        needs_motion_ = needs_motion_ || content_.playing;
        const double elapsed = static_cast<double>(text_clock - line_started_) / 1000.0;
        const float distance = bounds.Width - area.Width;
        const float speed = 24 * scale_;
        const double travel = distance / speed;
        const double phase = std::fmod(elapsed, 2 * travel + 1.8);
        if (phase >= 0.9 && phase < 0.9 + travel) {
          offset = static_cast<float>(phase - 0.9) * speed;
        } else if (phase >= 0.9 + travel && phase < 1.8 + travel) {
          offset = distance;
        } else if (phase >= 1.8 + travel) {
          offset = distance - static_cast<float>(phase - 1.8 - travel) * speed;
        }
      }
      const float origin_x = area.X + std::max(0.0f, (area.Width - bounds.Width) * 0.5f) - offset;
      const float origin_y = area.Y + std::max(0.0f, (area.Height - bounds.Height) * 0.5f);
      Gdiplus::Matrix move;
      move.Translate(origin_x - bounds.X, origin_y - bounds.Y);
      glyphs.Transform(&move);
      const auto saved = graphics.Save();
      graphics.SetClip(area);
      const BYTE shadow_alpha = static_cast<BYTE>(content_.shadow_opacity * 110);
      if (shadow_alpha) {
        Gdiplus::Pen soft(Gdiplus::Color(static_cast<BYTE>(shadow_alpha / 3), 0, 0, 0),
                          5 * scale_);
        soft.SetLineJoin(Gdiplus::LineJoinRound);
        graphics.DrawPath(&soft, &glyphs);
        Gdiplus::Pen edge(Gdiplus::Color(shadow_alpha, 0, 0, 0),
                          static_cast<float>(content_.stroke_width + 0.8) * scale_);
        edge.SetLineJoin(Gdiplus::LineJoinRound);
        graphics.DrawPath(&edge, &glyphs);
      }
      Gdiplus::SolidBrush brush{Gdiplus::Color(color)};
      graphics.FillPath(&brush, &glyphs);
      if (current && !content_.current_color_explicit && progress > 0) {
        graphics.SetClip(Gdiplus::RectF(origin_x, area.Y,
            bounds.Width * static_cast<float>(progress), area.Height),
            Gdiplus::CombineModeIntersect);
        Gdiplus::SolidBrush highlight{Gdiplus::Color(content_.current_color)};
        graphics.FillPath(&highlight, &glyphs);
      }
      graphics.Restore(saved);
    };
    draw_text(primary,
              {inset, top, static_cast<float>(width) - 2 * inset, main_height}, font_size,
              content_.current_color_explicit ? content_.current_color
                                              : content_.text_color,
              true);
    if (show_secondary) {
      draw_text(secondary,
                {inset, top + main_height + gap, static_cast<float>(width) - 2 * inset, side_height},
                side_size, content_.other_color, false);
    }

    if (toolbar) {
      const RECT bar = ToolbarRect();
      // 极轻连接区让鼠标能从正文跨过间距进入工具栏。
      Gdiplus::SolidBrush bridge(Gdiplus::Color(2, 16, 22, 24));
      graphics.FillRectangle(&bridge, Gdiplus::RectF(
          static_cast<float>(bar.left),
          static_cast<float>(toolbar_above_ ? bar.bottom : body.bottom),
          static_cast<float>(bar.right - bar.left),
          static_cast<float>(Pixels(kToolbarGap))));
      Gdiplus::GraphicsPath panel;
      RoundedPath(panel, FloatRect(bar), 10 * scale_);
      Gdiplus::SolidBrush panel_brush(Gdiplus::Color(238, 24, 30, 33));
      graphics.FillPath(&panel_brush, &panel);
      for (int i = 0; i < kToolbarButtons; ++i) {
        const RECT button = ButtonRect(i);
        const bool enabled = i >= 3 || content_.has_song;
        if (hovered_button_ == i && enabled) {
          Gdiplus::GraphicsPath target;
          RoundedPath(target, FloatRect(button), 7 * scale_);
          Gdiplus::SolidBrush glow(i == 4 ? Gdiplus::Color(175, 145, 60, 65)
                                         : Gdiplus::Color(64, 210, 235, 229));
          graphics.FillPath(&glow, &target);
        }
        DrawIcon(graphics, button, i, content_.playing, enabled, scale_);
      }
      if (hovered_button_ >= 0) {
        const wchar_t* title = hovered_button_ == 0 ? L"上一首" :
            hovered_button_ == 1 ? (content_.playing ? L"暂停" : L"播放") :
            hovered_button_ == 2 ? L"下一首" :
            hovered_button_ == 3 ? L"锁定歌词" :
            hovered_button_ == 4 ? L"关闭歌词" : L"桌面歌词设置";
        const float tip_width = (hovered_button_ == 5 ? 112.0f : 90.0f) * scale_;
        Gdiplus::RectF tip((static_cast<float>(width) - tip_width) * 0.5f,
            toolbar_above_ ? 0.0f : static_cast<float>(bar.bottom) + 2 * scale_,
            tip_width, 21 * scale_);
        Gdiplus::GraphicsPath tip_path;
        RoundedPath(tip_path, tip, 6 * scale_);
        graphics.FillPath(&panel_brush, &tip_path);
        Gdiplus::Font font(L"Microsoft YaHei UI", 11 * scale_,
                            Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);
        Gdiplus::StringFormat format;
        format.SetAlignment(Gdiplus::StringAlignmentCenter);
        format.SetLineAlignment(Gdiplus::StringAlignmentCenter);
        Gdiplus::SolidBrush text(Gdiplus::Color(255, 235, 244, 241));
        graphics.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAliasGridFit);
        graphics.DrawString(title, -1, &font, tip, &format, &text);
      }
      Gdiplus::Pen handle(Gdiplus::Color(110, 215, 226, 223), scale_);
      for (int i = 0; i < 2; ++i) {
        const float shift = static_cast<float>(Pixels(5 + i * 5));
        graphics.DrawLine(&handle, static_cast<float>(body.right) - shift - 3 * scale_,
            static_cast<float>(body.bottom) - 4 * scale_,
            static_cast<float>(body.right) - 4 * scale_,
            static_cast<float>(body.bottom) - shift - 3 * scale_);
      }
    }
    graphics.Flush(Gdiplus::FlushIntentionSync);
  }
  POINT destination{body_origin_.x,
      body_origin_.y - (toolbar && toolbar_above_
          ? Pixels(kToolbarHeight + kToolbarGap +
                   (hovered_button_ >= 0 ? kTooltipHeight : 0)) : 0)};
  SIZE dimensions{width, height};
  POINT source{};
  BLENDFUNCTION blend{AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
  const bool result = UpdateLayeredWindow(window_, screen, &destination,
      &dimensions, memory, &source, 0, &blend, ULW_ALPHA) != FALSE;
  SelectObject(memory, previous);
  DeleteObject(bitmap);
  DeleteDC(memory);
  ReleaseDC(nullptr, screen);
  return result;
}

LRESULT CALLBACK CompactFloatingLyricsWindow::WndProc(
    HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  auto* that = reinterpret_cast<CompactFloatingLyricsWindow*>(
      GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    that = static_cast<CompactFloatingLyricsWindow*>(
        reinterpret_cast<CREATESTRUCTW*>(lparam)->lpCreateParams);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(that));
  }
  if (!that) return DefWindowProcW(hwnd, message, wparam, lparam);
  switch (message) {
    case WM_MOUSEACTIVATE:
      return MA_NOACTIVATE;
    case WM_NCHITTEST:
      return that->content_.locked ? HTTRANSPARENT : HTCLIENT;
    case WM_ERASEBKGND:
      return 1;
    case WM_PAINT: {
      PAINTSTRUCT paint{};
      BeginPaint(hwnd, &paint);
      EndPaint(hwnd, &paint);
      return 0;
    }
    case WM_TIMER:
      if (wparam == kMotionTimer && that->visible_) {
        POINT pointer{};
        GetCursorPos(&pointer);
        RECT bounds{};
        GetWindowRect(hwnd, &bounds);
        const bool inside = PtInRect(&bounds, pointer) != FALSE;
        if (!that->content_.locked && !that->dragging_ && !that->resizing_) {
          if (inside) {
            that->mouse_left_at_ = 0;
            that->SetHovered(true);
          } else if (!that->mouse_left_at_) {
            that->mouse_left_at_ = GetTickCount64();
          } else if (GetTickCount64() - that->mouse_left_at_ >= 180) {
            that->SetHovered(false);
          }
        }
        if (that->content_.playing && that->needs_motion_) that->Paint();
        that->UpdateTimer();
        return 0;
      }
      break;
    case WM_MOUSEMOVE: {
      POINT pointer{};
      GetCursorPos(&pointer);
      if (that->dragging_ || that->resizing_) {
        const int dx = pointer.x - that->drag_pointer_.x;
        const int dy = pointer.y - that->drag_pointer_.y;
        if (that->dragging_) {
          that->body_origin_ = {that->drag_origin_.x + dx,
                                 that->drag_origin_.y + dy};
        } else {
          that->content_.width = std::clamp(static_cast<int>(that->resize_origin_.cx) +
              static_cast<int>(static_cast<float>(dx) / that->scale_), 220, 720);
          that->content_.height = std::clamp(static_cast<int>(that->resize_origin_.cy) +
              static_cast<int>(static_cast<float>(dy) / that->scale_), 72, 220);
        }
        that->ConstrainBody();
        that->Paint();
        return 0;
      }
      that->SetHovered(true);
      ScreenToClient(hwnd, &pointer);
      const int button = that->ButtonAt(pointer);
      if (button != that->hovered_button_) {
        that->hovered_button_ = button;
        that->Paint();
      }
      TRACKMOUSEEVENT track{sizeof(TRACKMOUSEEVENT), TME_LEAVE, hwnd, 0};
      TrackMouseEvent(&track);
      return 0;
    }
    case WM_MOUSELEAVE:
      that->mouse_left_at_ = GetTickCount64();
      return 0;
    case WM_SETCURSOR: {
      POINT pointer{};
      GetCursorPos(&pointer);
      ScreenToClient(hwnd, &pointer);
      SetCursor(LoadCursor(nullptr, that->ResizeAt(pointer) ? IDC_SIZENWSE
                       : that->ButtonAt(pointer) >= 0 ? IDC_HAND : IDC_SIZEALL));
      return TRUE;
    }
    case WM_LBUTTONDOWN: {
      if (that->content_.locked) return 0;
      POINT pointer{};
      GetCursorPos(&pointer);
      POINT local = pointer;
      ScreenToClient(hwnd, &local);
      const int button = that->ButtonAt(local);
      if (button >= 0) {
        if (button < 3 && !that->content_.has_song) return 0;
        that->pressed_button_ = button;
      } else {
        that->resizing_ = that->ResizeAt(local);
        that->dragging_ = !that->resizing_;
        that->drag_pointer_ = pointer;
        that->drag_origin_ = that->body_origin_;
        that->resize_origin_ = {that->content_.width, that->content_.height};
      }
      SetCapture(hwnd);
      return 0;
    }
    case WM_LBUTTONUP: {
      POINT point{};
      GetCursorPos(&point);
      ScreenToClient(hwnd, &point);
      const int pressed = that->pressed_button_;
      const bool resized = that->resizing_;
      that->pressed_button_ = -1;
      that->dragging_ = false;
      that->resizing_ = false;
      if (GetCapture() == hwnd) ReleaseCapture();
      if (resized) that->Send("windowResized");
      if (pressed >= 0 && that->ButtonAt(point) == pressed) {
        if (pressed < 3 && that->content_.has_song) {
          that->Send(pressed == 0 ? "previous" : pressed == 1 ? "playPause" : "next");
        } else if (pressed == 3) {
          that->content_.locked = true;
          that->ApplyLock();
          that->Paint();
          that->UpdateTimer();
          that->Send("lockChanged");
        } else if (pressed == 4) {
          that->closed_by_user_ = true;
          that->Hide();
          that->Send("closedByUser");
        } else if (pressed == 5) {
          that->Send("settingsRequested");
        }
      }
      return 0;
    }
    case WM_CAPTURECHANGED:
      that->dragging_ = false;
      that->resizing_ = false;
      that->pressed_button_ = -1;
      return 0;
    case WM_DPICHANGED:
      that->scale_ = static_cast<float>(HIWORD(wparam)) / 96.0f;
      that->ConstrainBody();
      that->Paint();
      return 0;
    case WM_CLOSE:
      that->closed_by_user_ = true;
      that->Hide();
      that->Send("closedByUser");
      return 0;
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

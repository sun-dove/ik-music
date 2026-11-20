#ifndef RUNNER_IK_DESKTOP_HOST_H_
#define RUNNER_IK_DESKTOP_HOST_H_

#include <windows.h>

#include <functional>
#include <memory>
#include <optional>
#include <string>

struct IkWindowState {
  RECT bounds;
  UINT dpi = 96;
  bool maximized = false;
};

// 独立产品的实例身份不依赖显示名或 Flutter 的公共窗口类。
class IkSingleInstance {
 public:
  explicit IkSingleInstance(
      const std::wstring& name = L"Local\\sun-dove.YueyinMusic.Instance");
  ~IkSingleInstance();
  IkSingleInstance(const IkSingleInstance&) = delete;
  IkSingleInstance& operator=(const IkSingleInstance&) = delete;
  bool valid() const { return mutex_ != nullptr; }
  bool primary() const { return primary_; }
  bool WakeExisting() const;

 private:
  HANDLE mutex_ = nullptr;
  bool primary_ = false;
};

// 无 Flutter 依赖，正式原生门与产品使用同一消息处理、窗口及媒体实现。
class IkDesktopHost {
 public:
  enum class Command : UINT {
    kShow = 41001,
    kToggle,
    kPrevious,
    kNext,
    kExit,
    kPlay,
    kPause,
  };

  IkDesktopHost(HWND window, std::function<void(const std::string&)> command,
                std::function<void()> exit,
                std::wstring registry_key =
                    L"Software\\sun-dove\\YueyinMusic\\IkWindow");
  ~IkDesktopHost();
  IkDesktopHost(const IkDesktopHost&) = delete;
  IkDesktopHost& operator=(const IkDesktopHost&) = delete;

  void Initialize();
  void ShowInitial();
  void Update(const std::wstring& title, const std::wstring& artist,
              bool enabled, bool playing);
  void DispatchCommand(Command command);
  std::optional<LRESULT> HandleMessage(UINT message, WPARAM wparam,
                                       LPARAM lparam);
  bool tray_available() const { return tray_available_; }
  bool media_available() const;
  bool memory_available() const { return memory_available_; }
  const std::string& media_error() const { return media_error_; }

  static const wchar_t* WindowProperty();
  static UINT WakeMessage();
  static RECT ClampBounds(RECT bounds, const RECT& work, UINT dpi);
  static std::optional<IkWindowState> ReadWindowState(const std::wstring& key);
  static bool WriteWindowState(const std::wstring& key,
                               const IkWindowState& state);

 private:
  struct MediaState;
  void RestoreWindowState();
  void SaveWindowState();
  void ShowWindowNow();
  void AddTrayIcon();
  void UpdateTrayIcon();
  void ShowTrayMenu();
  void InitializeMedia();
  void ReleaseMedia();

  HWND window_;
  std::function<void(const std::string&)> command_;
  std::function<void()> exit_;
  std::wstring registry_key_;
  std::unique_ptr<MediaState> media_;
  std::string media_error_;
  bool initialized_ = false;
  bool shown_ = false;
  bool start_maximized_ = false;
  bool tray_available_ = false;
  bool memory_available_ = true;
  bool enabled_ = false;
  bool playing_ = false;
  std::wstring title_;
};

#endif  // RUNNER_IK_DESKTOP_HOST_H_

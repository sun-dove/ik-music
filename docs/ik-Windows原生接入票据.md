# ik Windows 原生接入票据

日期：2026-11-20。依据《ik-完整改版实施与验收》K07 及用户“这一版都做完”的确认实施。

## 目标与方案

补齐托盘、单实例唤醒、位置尺寸记忆和系统媒体控制。方案 A 在独立 runner 增加原生宿主及薄 MethodChannel，沿用播放器和退出握手；方案 B 引入通用桌面插件并改公共窗口/播放器模块。采用 A：不新增依赖，不改 Mconnect 路径，原关闭偏好和最长八秒退出等待保持。

## 接口、调用方与回滚

新增 `IkDesktopHost` 管理 HWND、托盘、窗口布局和 SMTC；新增 `IkSingleInstance` 使用稳定的会话内 mutex 与独立窗口 property，第二次启动仅唤醒本产品。位置存到当前用户 `Software\\sun-dove\\YueyinMusic\\IkWindow`，不参与旧 Hive/数据库迁移。

新通道 `sun-dove.yueyin/ik-desktop`：`initialize` 返回通道可用布尔值；`update` 接收 `title/artist/playing/enabled`；`capabilities` 返回 `tray/media/windowMemory` 与失败原因代码；`command` 向 Dart 发送 `play/pause/toggle/previous/next`。托盘退出回调始终走现有 `WindowsDesktopChannel::PrepareExit`，随后 `WindowsDesktopPolicy::RequestExit`。

必须修改的调用点只有 YUEYIN_BUILD 下 `main.cpp`（实例守卫与标题）、`FlutterWindow`（创建、消息与释放、首帧展示）、runner CMake（独立源文件与门）。原公开方法和原默认行为不变。撤销这些独立条件接入即可回滚，新增注册表项无副作用，不删除用户数据。

## 场景与验收门

新增正式 `ik_desktop_gate.cpp`：第二实例不能成为主实例、主实例释放后可重获；特有 HWND 标识只在新宿主启用后存在；托盘/媒体命令使用同一回调、禁用状态不发播放命令；显窗恢复最小化；尺寸按 100/125/150% DPI 计算且不大于工作区；断开的显示器与无效矩形被纠正；注册表往返与最大化标记保持；析构移除窗口标识与系统资源。

`ik_desktop_red_gate` 不激活新宿主，首先在独立窗口标识断言失败，代表旧 runner 的真实缺失行为；`ik_desktop_gate` 走实际新宿主。两个目标均由 Windows runner 编译运行。本机没有已获准的 C++ 工具链，不安装工具绕过限制。

CI 输出托盘与 SMTC 的实际能力。无交互 shell 的 runner 可能不能展示系统托盘/媒体浮窗；确定性命令和错误路径照常验收，不能将 capability=false 说成桌面体验已通过。安装包还需本机实际验证托盘菜单、二次启动、位置恢复、媒体信息与最终退出。

## 当前记录

原生门先建立，随后实现宿主；编译与红绿执行等待现有 Windows runner。已完成宿主、通道、条件编译、首帧恢复、退出回调与标题接入。静态 diff 检查未发现本子任务文件的空白错误；没有声称 C++ 编译成功或系统媒体浮窗已目视验收。

原生绿门在 SMTC 可用时实际读回标题、歌手、暂停与播放状态，失败时必须提供原因代码并打印能力。托盘资源使用同一 EXE 的独立产品图标；Explorer 重启后重新注册。COM/WinRT、按钮订阅、托盘和单实例句柄分别释放。

正式验收门、接入票据属于长期回归交付；门只创建独立临时注册表项并在结束时删除，不读写用户实际窗口偏好。本子任务没有创建临时文件、安装工具或运行后台进程。

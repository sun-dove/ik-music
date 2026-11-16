# 悦音音乐 0.4.0：Windows 使用与构建

本版面向 Windows 10/11 x64，应用程序名为 yueyin_music.exe，使用独立的浅色图标、窗口标题、安装 AppId 和应用数据目录。原 Mconnect 工程与缺省构建保留。最低依赖为 .NET Framework 4.6.2、Visual C++ 2015–2022 x64 运行库和 Microsoft Edge WebView2 Runtime。

## 安装与启动

安装器可选择安装目录，包括 D:/Applications。便携 ZIP 必须完整解压后运行其中的 EXE；不要单独复制 EXE，音频库、Flutter 数据和 data/lx-host 都是运行依赖。“便携”表示免安装，不表示设置写回 EXE 目录；设置仍保存至本用户应用数据目录。Windows 与 Android 不自动同步账号或音源。

设置使用系统应用支持目录下的sun-dove/YueyinMusic，诊断日志也位于该应用目录。不会读取或覆盖用户文档目录中原Mconnect的同名Hive文件；此隔离由独立存储回归门验证。Android继续使用既有目录。

缺少 VC++ 时，安装器会提示先安装运行库。音源宿主或 WebView2 不完整时，应用会显示“Windows音源运行环境未就绪”，应恢复完整发行包或安装 WebView2，再检查音源。

官方运行库下载页：

- [Visual C++ 运行库](https://learn.microsoft.com/cpp/windows/latest-supported-vc-redist)
- [WebView2 Runtime](https://developer.microsoft.com/microsoft-edge/webview2/)
- [.NET Framework 4.8](https://dotnet.microsoft.com/download/dotnet-framework/net48)

## 音源隔离边界

Windows 独立实现原有 LxSandbox 接口。每次初始化或取流都使用新的 WebView2 宿主和专用临时配置；不继承父进程凭据环境，不注册宿主对象，不接入账号页面和 Cookie。宿主移除 chrome 对象，禁用宿主消息、导航、弹窗、下载、权限和外部 URI；CSP、资源拦截和浏览器网络阻断同时生效。第三方脚本的网络请求仍只经 LX 队列交给 Dart 的 HTTPS 公网受控网络层执行。

控制通道只监听随机的本机回环端口，接受一个连接，每条请求验证本次进程独立生成的 256 位随机令牌；令牌不写入文件或日志，并在创建浏览器子进程前从宿主环境中移除。使用长度明确的消息帧，避免 Windows 标准输入管道的缓冲差异。通道没有文件、进程或账号操作接口。

宿主及其浏览器进程加入 Windows Job：单进程内存上限 512 MiB、整组 1 GiB、整组用户态 CPU 时间 30 秒；关闭宿主时结束整组。Dart 另有执行等待上限，死循环可强制终止。创建取消、正常结束和异常结束均清理自己的临时配置，不删除其他浏览器配置。

正式原生门覆盖创建、JSON、异步回调、完整 LX/crypto 资产、fetch/XHR/WebSocket/Worker/iframe/图片绕过网络、死循环终止、重新创建和创建中取消。这些验证使用自造黄金样例；第三方 20 源单独完整检查，见[兼容矩阵](悦音音乐040音源兼容矩阵.md)。解析成功不等于媒体播放成功。

## 可复现构建

需要 Flutter 3.47.5、Visual Studio 的 C++ 桌面开发组件、Windows SDK，以及可选的 Inno Setup 6。本机 C++ 工具链安装曾被自动审批拒绝；这不影响使用已有工具链的 GitHub Windows runner 构建。

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub -j 1
./scripts/build_video_windows.ps1 -FlutterSdk '<Flutter目录>' -DependencyDirectory '<构建缓存目录>'
```

构建脚本先下载固定版本、验证微软数字签名并编译独立宿主，再运行原生门，门通过后才构建 lib/main_video.dart、复制完整依赖和许可证、输出 ZIP；有 Inno Setup 时再输出安装器。原生门失败会中止发行。GitHub 的“悦音 Windows 构建”工作流执行相同流程。

WebView2 SDK 固定为 1.0.2903.40，来源为 Microsoft.Web.WebView2 官方 NuGet 包；Core、WinForms 与 x64 Loader DLL 的微软签名必须有效，SDK 的 LICENSE.txt 和 NOTICE.txt 随完整包提供。它遵循微软 SDK 许可；悦音自有源码的 MIT 许可不替代该许可。完整 WebView2 浏览器运行时不随项目源码再分发。

主程序构建、安装、实际播放与第三方源结果按[本轮验收记录](悦音音乐040验收记录.md)的最终状态为准；仅具备源代码或独立宿主通过，不能算完整 Windows 安装包交付。

# DJ Music 0.5.1：Windows 使用与构建

DJ Music 是顶尖（Dingjian）GitHub 项目的面向用户产品名称。**0.5.1/build 9 仍在开发验收中，尚未发布。**0.5.0 已发布 Windows x64 安装器和完整 ZIP，历史下载与数据见[0.5.0 发行页](https://github.com/sun-dove/yueyin-music/releases/tag/yueyin-v0.5.0)和[0.5.0 验收记录](乐音音乐050验收记录.md)。

## 安装与升级

安装器文件名为 `DJ-Music-Setup-0.5.1-x64.exe`，便携包为 `DJ-Music-0.5.1-windows-x64.zip`；生成前仍须通过全部验收。沿用原 AppId、程序名 `yueyin_music.exe`、安装目录和数据目录 `sun-dove/YueyinMusic`。安装程序只移除目标实际指向本应用的乐音、悦音、Meizuo Music 或 MZ Music 旧快捷方式；名称和目标无法确认时保留文件。新快捷方式叫 DJ Music。

安装版与 ZIP 共用同一应用数据和曲库 `yueyin.sqlite`。已有账号、平台设置和外观数据保存在既有系统应用支持目录。Windows 显示名变化不会重置这些内容。

最低运行依赖为 .NET Framework 4.6.2、Visual C++ 2015–2022 x64 运行库及 Microsoft Edge WebView2 Runtime：

- [Visual C++ 运行库](https://learn.microsoft.com/cpp/windows/latest-supported-vc-redist)
- [WebView2 Runtime](https://developer.microsoft.com/microsoft-edge/webview2/)
- [.NET Framework 4.8](https://dotnet.microsoft.com/download/dotnet-framework/net48)

## 应用与图标

Windows 标题栏、任务栏、桌面快捷方式、安装器、开始菜单和应用内都使用 DJ Music 及用户提供的渐变音符图标。16px 仍能辨认音符；飘带在该尺寸下更难分辨。0.5.1 继续默认使用本机 Microsoft YaHei UI，并保留已交付的背景图片、字体选择与导入以及播放/下载音质设置。

## 已知的 0.5.0 范围

0.5.0 已支持 Windows 歌词、背景与字体切换、音质和真实三平台图标。下一轮改版的待评估功能包括首页/发现、聚合搜索、跨平台我的音乐、更多个人能力入口及 Windows 托盘、窗口尺寸记忆、单实例与媒体按键；它们不属于本次品牌更新，尚未接入独立版。

目前搜索、收藏统计说明及底部导航仍使用部分 9–11px 文字，桌面高分辨率可读性值得优先检查。Windows 默认字体已为 Microsoft YaHei UI，因此这不是整套界面的缺字体问题。新方案已将 0.6 信息架构和功能/体验验收场景写入[DJ Music 改版设计与验收计划](../DJ-Music-改版设计与验收计划.md)；开始复杂 UI 编码前先完成设计与红门审阅。

## 构建与验收

候选验收状态：Flutter 静态分析通过；全量 Flutter 测试 1894 项通过，18 项因 Linux/Android 主机缺少 Windows 原生宿主而跳过；Android 三 ABI release 构建、applicationId、DJ Music 标签、版本名和三包一致签名已核验。Windows 编译、原生门、ZIP、Inno Setup 安装器和 GUI/升级尚未通过，等待 `release/dj-music-0.5.1` 的 Windows runner；因此本候选版本未发布。

使用 Flutter 3.47.5 / Dart 3.13.4、Visual Studio C++ 桌面组件、Windows SDK、CMake 与 Inno Setup 6。构建脚本在 Windows runner 上检查依赖、完整测试、原生红/绿门、便携 ZIP 与安装器：

```powershell
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
flutter pub get --enforce-lockfile
flutter analyze --no-pub
dart format --output=none --set-exit-if-changed lib test
flutter test --no-pub -j 1
./scripts/build_video_windows.ps1 -FlutterSdk '<Flutter目录>' -DependencyDirectory '<构建缓存目录>'
```

实际Windows runner 构建、安装升级和 GUI 显示结果只有完整执行后才会记录；设计稿、资源可解析或单元测试都不代替这些发行验收。Android 发行使用用户原有稳定签名并保持三 ABI 分包。

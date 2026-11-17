# 乐音音乐 0.5.0：Windows 使用与构建

名称为“乐音音乐”，乐读 yuè。0.5.0 延续悦音音乐的安装身份、程序名 `yueyin_music.exe` 和数据目录，使用用户提供的黑白音符飘带图标。适用于 Windows 10/11 x64。

## 安装与升级

[0.5.0 发行页](https://github.com/sun-dove/yueyin-music/releases/tag/yueyin-v0.5.0)提供 `YueyinMusic-Setup-0.5.0-x64.exe` 和 `YueyinMusic-0.5.0-windows-x64.zip`。安装器沿用原 AppId 和安装目录，可覆盖升级。旧快捷方式只有在实际目标等于本次应用EXE时才会清理并换成新名称；无法核对的文件保留。

ZIP 完整解压后运行其中的 EXE，保留 DLL、data、data/lx-host 与许可证。设置仍使用系统应用支持目录下 `sun-dove/YueyinMusic`；曲库为 `yueyin.sqlite`。新版外观文件存放在该目录的 appearance 子目录，原账号、歌单、音源和平台音质键保留。免安装包的设置与安装版共用该用户目录。

最低运行依赖为 .NET Framework 4.6.2、Visual C++ 2015–2022 x64 运行库及 Microsoft Edge WebView2 Runtime。缺少运行库时按安装器或应用提示恢复环境：

- [Visual C++ 运行库](https://learn.microsoft.com/cpp/windows/latest-supported-vc-redist)
- [WebView2 Runtime](https://developer.microsoft.com/microsoft-edge/webview2/)
- [.NET Framework 4.8](https://dotnet.microsoft.com/download/dotnet-framework/net48)

## 两项音质

“我的”页只显示“播放音质”和“下载音质”。播放可选“优先最高可用”及固定档位；下载使用统一固定档位，二者分别保存。实际可用档位取决于歌曲、平台和音源，播放器保留实际来源、格式、音质与降档提示。

升级后尚未选择统一档位时，继续读取原各平台设置；原值不一致则显示“沿用原设置”。选择并应用后才统一三平台。原键不会删除。播放模式与固定档位一次保存，失败保留当前快照。

新下载和明确重试失败任务使用当前下载档位；正在下载的任务及暂停续传保留原档位。“存储位置”可选择本机文件夹，取消或目录保存失败不改变已有目录，不移动旧下载文件。

## 背景与字体

“更换背景”支持 PNG、JPEG、WebP，先预览柔化效果，点击“应用”后复制到应用目录。移动原图不影响已保存背景；取消、坏图或保存失败保留当前选择。恢复默认会清除该背景配置。保存图片后来缺失时回退默认，并提示重新选择。

“更换字体”列出本机实际字体，默认使用微软雅黑 UI；选择后可预览并应用。支持有效 TTF/OTF 导入，取消不保存；缺失字体回退默认。安装器没有附带苹方，合法安装或导入后才能使用。

背景在搜索、三平台收藏、设置及播放器透出。深浅主题覆盖层保留文字可读性；无背景时原配色保持。字体同步作用于正文、标题、歌词和弹窗。

## 歌词与关闭

宽屏播放页左侧封面、右侧完整歌词。窗口缩窄或高缩放时回退紧凑布局。同步歌词按时间高亮、按实际布局位置跟随；手动滚动或键盘浏览后暂停跟随，点击“回到当前歌词”恢复。点击有时间戳的行可定位播放；纯文本歌词不启用逐句定位。

默认点击 X 或按 Alt+F4 会“最小化并继续播放”，可从任务栏恢复。在“关闭主窗口时”选择“退出应用”后，两种关闭操作会结束应用；设置页另有独立退出按钮。退出前先清理音源宿主，原生层有等待上限。系统关机/注销遵循结束会话，不最小化。当前实现保留任务栏入口，没有新增托盘。

## 构建与验收

使用固定 Flutter 3.47.5 / Dart 3.13.4、Visual Studio C++ 桌面组件、Windows SDK、CMake 与 Inno Setup 6。依赖保持现有 lockfile 来源：

```powershell
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
flutter pub get --enforce-lockfile
flutter analyze --no-pub
dart format --output=none --set-exit-if-changed lib test
flutter test --no-pub -j 1
./scripts/build_video_windows.ps1 -FlutterSdk '<Flutter目录>' -DependencyDirectory '<构建缓存目录>'
```

脚本编译并核对固定 WebView2 SDK 1.0.2903.40 的微软签名，实际执行全部音源宿主门与退出清理门，再构建主程序。随后编译窗口/字体原生门：停用新处理器的同门必须失败，启用后必须通过。任何正式门失败都会中止发行；验收 EXE 不进入用户安装包。

原 Mconnect 构建和 Android 页面走既有路径。Android 独立入口同步新名称、图标及 0.5.0/build8，保留稳定包名与签名并继续三 ABI 分包。

WebView2及LX隔离边界继承 [0.4.0 Windows说明](https://github.com/sun-dove/yueyin-music/blob/main/docs/交付文档/悦音音乐040Windows说明.md)。平台图标来源见随包《平台图标来源说明》及仓库 [来源说明](https://github.com/sun-dove/yueyin-music/blob/main/design/platform-icons-010/来源说明.md)。本版图标原样保留白底，透明底与小尺寸细线简化没有生成。

实际全量结果、远端构建、原生及界面验收边界见 [0.5.0验收记录](https://github.com/sun-dove/yueyin-music/blob/main/docs/交付文档/乐音音乐050验收记录.md)。组件缩放门不代表已经修改用户的系统缩放设置；匿名元数据或脚本初始化不等于真实账号、歌曲完整播放或音质实测。

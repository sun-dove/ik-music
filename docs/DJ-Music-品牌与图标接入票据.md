# DJ Music：品牌与多平台图标接入票据

日期：2026-11-19。状态：用户确认 GitHub 品牌归属用 Dingjian、面向用户的桌面与应用名统一用 DJ Music，并指定 `D:/WorkSpace/Projects/music-app-icon` 作为多平台图标资源来源。

## 目标与兼容边界

0.5.0 已正式发行。本票据针对下一兼容版 0.5.1/build 9：所有客户端用户可见名称为 **DJ Music**。Dingjian 仅用于 GitHub 账户/组织或项目归属表达，不混入 Windows、Android、通知、设置和安装器。GitHub remote 暂时仍为 `https://github.com/sun-dove/yueyin-music.git`；仓库 URL 变化属于独立 GitHub 管理操作，不由本次本地改名自动完成。

固定不变：Android applicationId `app.videomusic.player`、release 签名、Windows AppId、AppUserModelID `sun-dove.YueyinMusic`、EXE `yueyin_music.exe`、Windows CompanyName/ProductName `sun-dove` / `YueyinMusic`、安装目录、数据库/Hive/偏好键、既有公开方法签名和 Mconnect 默认入口。Windows ProductName 参与 path_provider 数据目录推导，不能为显示品牌而更改。

新图标源已归档在 `assets/branding/dj-music/source/`。Windows x64 与 Android 是当前可发布目标；iOS/Linux 生成资源只作为源包保存，不代表已有这些平台构建与签名流水线。Android 自适应 launcher 与独立启动背景使用 yueyin overlay 资源，避免改变 `src/main` 的 Mconnect 共用资产。主窗口/启动器用 DJ Music；GitHub 项目路径和内部历史发行标签继续保留以保证链接有效。

历史 0.5.0 发行记录保持原样。Android 将 versionCode 从 8 升为 9，versionName 为 0.5.1；Windows FileVersion/ProductVersion 为 0.5.1.9、build name/number 为 0.5.1/9。Mconnect `1.5.0+16` 的默认版本保持。

## 场景与验收门

| 场景 | 功能门 | 体验门 |
| --- | --- | --- |
| 用户辨认 Windows 与 Android 应用 | app title、Android label、设置版本、Windows title/FileDescription 和安装器统一 DJ Music；Mconnect 原值保持 | 任务栏、开始菜单、桌面快捷方式、启动器、窗口标题与应用内设置一致 |
| Windows 用户查看次要说明与字体 | Windows 独立入口默认 Microsoft YaHei UI；字体切换与导入保持；现有 9–11 logical px 次要字样记录为待复核项 | 0.5.1 品牌测试只核对字体/品牌接线；字号、DPI、窗口矩阵留给 0.6 体验门实测，不伪称已经达到 12 px |
| Android 用户启动独立入口 | 五档 legacy density、adaptive/round/monochrome、splash 资源可解析；applicationId/signing/ABI 门保持 | launcher/splash 显示源图标且对比度可读；设备实测单独记录 |
| 用户从播放通知辨认独立入口 | DJ Music 入口使用 DJ Music 的通知频道标题和 fallback MediaItem；Mconnect 使用其旧 title；channel ID 保持 | Android 通知与播放器显示 DJ Music，无错误的 Mconnect 回退标题 |
| 用户覆盖升级 0.5.0 | Android versionCode > 8 且签名相同；Windows AppId/AppUserModelID/CompanyName/ProductName/EXE/路径回归 | 安装器只删除目标确属本程序的旧品牌快捷方式；未知目标保留 |
| GitHub 用户定位项目 | README 链接继续有效；GitHub 仓库地址的调整不由客户端标签触发 | README 的项目归属可写 Dingjian，发行客户端始终显示 DJ Music |

本票据的正式确定性门为 `test/windows_music_brand_test.dart`，覆盖文案、Windows 安装身份、Android 包/版本/资源与 Mconnect 保持。门先在 0.5.0 基线上预期失败，再逐个实现到绿。本地 analyze 和完整 test 已通过（1894 项通过、18 项显式跳过），Android 三 ABI release 包已构建并核验 applicationId、版本和旧证书一致。18 项跳过包含 10 项网易云真实网络探针、1 项既有设置用例和 7 项需显式启用的 Windows 原生宿主门，不能统称为非 Windows 环境导致。

2026-11-20，候选提交 `5ce545b06f4315ff8b55ba5a7643c1710e82c8aa` 的 [Windows 构建 44665051893](https://github.com/sun-dove/yueyin-music/actions/runs/44665051893) 成功：静态分析 0 issue、完整回归 1894 通过/18 跳过、7 项实际宿主门另行启用并全部通过、C++ 窗口/字体红→绿门、主程序、ZIP 和 Inno Setup 安装器均通过。本机从 0.5.0 覆盖升级后，启动前 5 个数据文件逐字节保持；桌面/开始菜单、窗口和应用内品牌、字体预览及正常退出已实际验收。Android 物理设备和 Windows 系统缩放矩阵仍未实测。详见[0.5.1 候选验收记录](交付文档/DJ-Music-051候选验收记录.md)。本分支尚未合入 main 或发布 Release。

## 受影响调用方与回滚

| 接入位置 | 受影响调用方 | 回滚方案 |
| --- | --- | --- |
| `lib/l10n/video_strings.dart`、`expanded_strings.dart`、`windows_music_strings.dart` | 独立 MaterialApp title、导航、设置版本、Windows 字体样例 | 恢复旧文案；Mconnect 文案入口本来就未更改 |
| `android/app/build.gradle.kts` 与 `android/app/src/yueyin/res/**` | 独立包标签、launcher、自适应/主题图标和启动背景 | 回滚 yueyin overlay/label，保留 Mconnect `src/main` 资源及 applicationId/签名 |
| `windows/runner/main.cpp`、`win32_window.cpp`、`floating_lyrics_window.cpp`、`Yueyin.rc` | 独立窗口标题、关闭对话框、悬浮歌词、EXE 版本资源和图标 | 恢复标题/文件描述/ICO；固定 AppUserModelID、CompanyName/ProductName、EXE 与目录不动 |
| `installer/yueyin.iss` | Setup 名称、安装组、发布文件名、旧快捷方式迁移 | 恢复旧名称；迁移逻辑只对精确路径且目标指向本程序时操作 |
| `AudioServicePlayerController` 与 `BackgroundAudioInitializer` 新增独立初始化入口 | Android 独立版通知频道显示名和 fallback MediaItem；原 `initialize({diagnostics})` 与 Mconnect 默认行为不变 | 独立入口恢复原初始化；不删除平台已保存 channel 配置或用户通知偏好 |
| `scripts/build_video_windows.ps1` 与测试 | Windows 0.5.1 发行身份与包名；品牌和升级门 | 继续保留历史 0.5.0 Release 和包；以更高兼容版回滚 |

## 0.5.0 品牌残留核对

- Windows 窗口、关闭确认、文件描述与旧 installer 显示使用历史名称；下一版本统一 DJ Music。
- Android manifest label、launcher 与 splash 原来未完整体现最新品牌；这次只在独立 yueyin sourceSet 使用新图标/启动背景。
- 播放通知原来固定使用 Mconnect 频道名。独立入口新增初始化方法，并在 `MainActivity` 仅对独立包更新已有频道的显示名。通知 ID 仍为 `com.mconnect.mconnect.audio`，沿用系统已存通知设置。没有当前曲目时继续发布空媒体项，原播放器契约保留。
- iOS/Linux 资源未宣称为发行能力；README、Release URL 和 GitHub remote 不批量改名。
- 字体没有新 glyph 证据；原品牌票据已要求的 Microsoft YaHei UI 默认、可选字体及 12 logical px 次要文字检查继续适用，不伪称此票据重新验证过实际设备字形。

用户指定图标源已从 Windows、Android、iOS、Linux 与 SVG 源完整复制归档。Windows ICO、Android density PNG 与前景 XML 关键文件的 SHA-256 与源一致。临时预览和系统实机测试若未执行，不记为已通过。

## 补齐安装和实际界面上的品牌

- 独立版 `VideoShell` 的宽屏侧栏和 `WindowsMyPage` 的页首都还在读取旧图。只替换两处图片来源，使用图标源中已经交付的 Windows PNG。原构造器、页面选择、字号和旧资源路径保留；其中导航 10px、统计/辅助文字 11px 是 0.6 可读性体验门的复核项。回滚时改回两处图片引用即可。
- Android 深色、浅色与 API 31 以上的启动主题都指向独立资源。`android:roundIcon` 由独立构建指定，主题图标复用白色矢量轮廓；通知栏的小号单色图由 `yueyin` 资源覆盖，Mconnect 继续使用主资源。Android 桌面小组件选择器和独立闲置文案同样由 `yueyin` 资源覆盖，保留组件 ID、通道 ID 和设置。回滚时恢复 `yueyin` 资源及 manifest 占位符。
- Inno Setup 在创建新快捷方式后执行旧品牌清理。清理名单只包含旧名称，当前名称不进入清理范围。保留旧快捷方式目标核对、安装目录和任务勾选行为。回滚时只恢复旧清理名单，不动产品安装身份。

# 悦音音乐010：Windows 改版接入票据

日期：2026-11-17。状态：用户已于本轮确认010实施、名称“乐音音乐”（乐读 yuè）和音符飘带图标。授权原话：“那就先用这个吧。读yue。开始搞吧记得换图标”。以下最小生产接入及默认最小化行为在本次授权范围内。

## 必须接入的原因

用户要求统一音质、全页背景/字体、桌面歌词与关闭设置。仅新增文件无法让正在运行的 Windows 入口使用它们：现有启动装配直接注入旧音质读取器，页面自行绘制不透明背景，原窗口直接弹“是/否”。因此需要以下最小可选接入。

所有原公开接口保留。新增字段可选，未装配新增组件的入口保持旧行为；旧平台音质键、账号、歌单、音源及数据库不改结构。此次明确改变悦音 Windows 的默认关闭交互：新版本启动装配后，默认最小化并继续播放。确认设计即确认这项用户可配置的行为变化。

## 接入点、受影响调用方及回滚

| 现有位置 | 变更原因及全部已知受影响调用方 | 回滚方案 |
| --- | --- | --- |
| `lib/main_video.dart` | Windows 初始化独立偏好/外观/原生控制，给 PreparedSourceRouter.fixedQuality 注入有效音质；同入口 customSourceResolved 音质记录及 runApp 装配同步 | Windows 分支停用新注入，恢复 preferences.quality 与原 VideoMusicApp 装配；新增配置保留，不清账号/数据库 |
| `lib/video_app/video_app.dart` | Windows 可选设置和播放页；`_quality` 的新增桌面分支、`_openPlayer`、`_download`、下载任务重试入口、`_cache` 的缓存提交及“我的”质量标签统一读取 | 切回旧页面及旧读取器；原公开构造缺省不变，Android 仍使用旧分支 |
| `lib/video_app/ui/video_theme.dart` | 新增可选主题扩展后，canvas/surface 从扩展取桌面透明度；无扩展时现有颜色精确不变 | 停用 Windows 新主题扩展，旧 light/dark 与所有调用方回到原色 |
| canvas/surface 的既有调用方 | `video_shell.dart` 外壳、底栏和迷你播放器；`my_page.dart` 账号与设置卡片；`catalog_pages.dart` 搜索、歌单、收藏及输入框；`player_page.dart` 的旧背景调用仅用于回归，新桌面页自行布局 | 由上项停用扩展恢复，不重写各页的数据、排序、账号或播放回调 |
| `lib/video_app/ui/video_shell.dart` 与新桌面账号组件接入 | Windows 平台入口需要实际图标和可读字体；既有 VideoShell 调用方为 VideoMusicApp 及 shell/expanded shell 门 | 新增图标/桌面选项关闭时仍用旧 IconData、旧页面；已登录头像保留 |
| `windows/runner/flutter_window.h/.cpp` 与 runner CMake | YUEYIN_BUILD 条件下注册新窗口/字体通道并优先处理 WM_CLOSE；调用方是悦音 Windows 初始化、设置页、X 与 Alt+F4 | 不注册新通道及新增消息处理，基类既有弹框路径恢复；Mconnect 分支不变 |
| `windows/runner/main.cpp`（如技术门要求） | 仅悦音构建在通道接管关闭后停用旧询问；窗口最小尺寸和原公开 SetAskBeforeClose 签名保留 | 恢复原 SetAskBeforeClose(true) 与原窗口启动，数据目录不变 |
| `pubspec.yaml` 的 assets 区及第三方来源说明 | 注册三张本地官方图标，应用离线显示；所有新增平台图标组件为调用方 | 停用新增资源组件并移除本轮资源声明；不改依赖版本、lockfile、Mconnect 版本 |

实现中发现其他生产路径必须修改时，先追加原因、调用方与回滚，不能以“顺手改一下”扩大范围。已有公开方法不删除、不改名、不改签名；新读取器和新桌面组件承担扩展。

## 数据、保存失败与回退

## 本轮品牌与发行接入追加

| 位置 | 原因及受影响调用方 | 回滚 |
| --- | --- | --- |
| `lib/l10n/video_strings.dart`、`expanded_strings.dart` | 独立入口标题、侧栏、设置版本同步新名称；原资源常量名称及调用签名保留 | 恢复旧显示文字，无数据变更 |
| `windows/runner/main.cpp`、`Yueyin.rc`、`installer/yueyin.iss` | 原生标题、EXE属性、快捷方式及安装器显示“乐音音乐”，独立版本0.5.0/build8 | 恢复显示文字/图标，AppId、AppUserModelID、EXE名与安装目录始终保留 |
| `Yueyin.rc` 的 CompanyName/ProductName | `path_provider_windows` 实际从这两个资源属性推导应用支持目录，进而影响Hive账号设置、下载任务、曲库及日志。必须保持 `sun-dove/YueyinMusic`；中文新名仅用于FileDescription、窗口标题和安装器等显示位置 | 保持0.4.0原资源值，无数据搬迁或目录迁移；品牌门校验两项资源稳定 |
| `assets/branding/yueyin`、独立Android图标资源、`windows/runner/resources/yueyin_icon.ico` | 用户明确要求替换图标；独立应用、任务栏、安装器与升级后的启动器为调用方 | 从上一发行提交恢复图标，不改原Mconnect图标 |
| `android/app/build.gradle.kts` 中已有独立构建分支 | 同步独立应用显示名与版本，包名与稳定签名不变 | 恢复独立分支显示/版本；不修改默认构建分支 |
| `scripts/build_video_windows.ps1`、Windows工作流、README与发行说明 | 新版构建与验收门、名称、版本及下载链接一致 | 停用新增装配并重新发行更高版本，不要求卸载、不删除设置 |
| `installer/yueyin.iss` 的升级快捷方式处理 | 新旧名称切换时可能残留“悦音音乐”入口。仅核对固定旧快捷方式的实际目标等于本次应用EXE后移除；新安装创建“乐音音乐”快捷方式。开始菜单旧目录只在空目录时移除 | 停用该新增处理；AppId、应用目录、账号与设置不变；无法核对目标时原快捷方式保留 |
| Windows 设置“存储位置”及下载权限失败重试 | 收口时发现旧回调只调用 Android SAF，Windows 点“选择文件夹”无法选目录。新增 Windows 文件夹选择方法，复用 DownloadNotifier 原保存/验证契约；仅在新 Windows 页面与权限失败重试接入，取消或保存失败不重试 | 停用新增 Windows 选择分支；原 `_directory`、Android SAF 与原目录偏好键不改；不会移动或删除已有下载文件 |

新增窗口通道的正式原生门与构建脚本只影响悦音独立 Windows 构建。新增品牌导出脚本复用既有尺寸验证，不修改旧导出脚本接口。

- 新 Windows 配置键独立，原平台音质、video.theme 和 sourceCollection v1 保留。首次缺统一质量仍委托旧读取；字体/背景配置无值时安全回退。
- 统一固定播放档位需要与既有 highestQuality 模式一致。保存过程保存旧快照，失败恢复有效配置和界面；不能只改变显示值。不得删除旧平台键来实现迁移。
- 图像与导入字体仅写悦音自己的独立数据目录。旧图/字体只有在新文件与配置保存成功且无句柄使用后才能清理；取消、失败和退出不删除仍在使用的文件。
- 回滚代码不要求卸载应用，不删新增偏好，也不清用户数据。发布采用新版本，不强推历史提交。

## 验收与审阅依据

对应《悦音音乐010-Windows界面与个性化设置设计》W01-W12。先在0.4.0基线上运行新增红门，再进行上述接入；主题/路由/布局变更按仓库约定执行红到绿验证，全量原门继续通过。

本票据明确需要用户确认的内容是设计与上述生产接入范围；已有 GitHub 开源、上传授权无需重复询问。本轮设计确认前不改产品代码或发新版安装包。

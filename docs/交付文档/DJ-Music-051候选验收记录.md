# DJ Music 0.5.1：候选验收记录

日期：2026-11-20。GitHub 项目归属名为 Dingjian，客户端产品名为 DJ Music。候选分支为 `release/dj-music-0.5.1`，构建提交为 `5ce545b06f4315ff8b55ba5a7643c1710e82c8aa`。本记录是出包后的验收证据，0.5.1 尚未合入 main 或发布 GitHub Release；公开发行仍为 0.5.0。

## 交付范围

本次完成客户端品牌和用户提供图标的接入。Windows 标题、侧栏、「我的」、字体预览、版本、安装器及快捷方式显示 DJ Music；Android 启动器、自适应/主题图标、明暗启动画面、通知与小组件使用独立版资源。Android applicationId 和签名，Windows AppId/AppUserModelID、EXE、CompanyName/ProductName、安装目录和数据目录保持。Mconnect 默认入口及版本保持。

首页、聚合搜索、「我的音乐」、托盘、窗口记忆和更多个人能力仍属于后续改版，未在 0.5.1 实现。字号 9–11px 的可读性问题仍在 0.6 体验门中跟踪。iOS/Linux 只有图标源包，未生成或验收对应平台安装包。

## Windows 构建及自动验收

[Windows 构建 44665051893](https://github.com/sun-dove/yueyin-music/actions/runs/44665051893) 于北京时间 2026-11-20 11:17 完成，结论为 success，head SHA 与上述构建提交一致。

- `flutter analyze --no-pub`：0 issue。
- 完整 `flutter test --no-pub -j 1`：1894 项通过，18 项显式跳过。
- 跳过范围：10 项网易云真实网络探针、1 项既有自动换源设置用例、7 项需显式启用的 Windows 原生宿主门。此前把 18 项全部描述为非 Windows 环境造成不准确，现更正。
- 构建脚本设置 `YUEYIN_SANDBOX_GATE=1` 后，7 项 Windows 真实宿主门全部通过，覆盖创建、取消、完整 LX 资产、网络旁路限制、超时和退出清理。
- C++ 桌面红门停用关闭处理器后在最小化断言真实失败，退出码为 1；随后绿门验证最小化、Alt+F4、独立退出、系统会话消息、原入口隔离，以及 30 次实际字体枚举和 GDI 句柄释放。
- Windows release 主程序、完整 ZIP、Inno Setup 安装器与 artifact 上传均成功。

artifact 名称为 `dj-music-0.5.1-windows-x64`，字节数 41883852；下载后的 SHA-256 为 `24fa6d48c668009e200941172402e4516c30970795ee267a793d92beb4e3c4c5`，与 GitHub 返回值一致。CI artifact 保留 14 天，长期交付副本位于本聊天的 outputs。

## 二进制与图标核对

ZIP 共 50 个文件，含 Flutter 资源、原生库、独立 LX 宿主、运行时许可及说明。主程序 FileVersion/ProductVersion 为 0.5.1，FileDescription 为 DJ Music，CompanyName/ProductName 为 `sun-dove` / `YueyinMusic`，OriginalFilename 仍为 `yueyin_music.exe`。

直接读取 EXE 的 PE 图标资源，16、20、24、32、40、48、64、128、256 共 9 档图像的字节散列均与正式 ICO 中对应图像一致。随包 ICO 和 Flutter 使用的 PNG 也与图标源一致。三份 WebView2 DLL 的微软 Authenticode 签名均为 Valid。安装器资源显示 DJ Music、0.5.1、DJ Music Contributors。

## 本机覆盖升级与实际界面

本机原版本为乐音音乐 0.5.0，安装路径为 `D:/Applications/YueyinMusic`。应用未运行时用候选安装器覆盖安装，退出码为 0；卸载登记变为 DJ Music version 0.5.1，路径及 AppId 保持。安装目录中的全部 50 个发行文件与 CI ZIP 的对应文件逐字节相同。

首次启动前逐一检查 `settings.hive`、`local_music.hive`、`player_memory.hive`、`download_tasks.hive`、`yueyin.sqlite`，5 个文件 SHA-256 全部与升级前一致。其中本地音乐和下载任务文件为空，不能据此推断非空曲库/下载历史已实测。旧乐音桌面和开始菜单快捷方式的目标在升级前已核对为本程序；安装后它们被移除，新的 DJ Music 两个快捷方式仍指向原 EXE。未知目标保留分支由代码与正式门覆盖，本次没有制造用户桌面样例。

通过 computer-use 实际操作 1186×793 窗口，确认：

- 原生标题、侧栏、页首新图标和 DJ Music 文案一致，「我的」页底部显示 `DJ Music · 0.5.1`。
- 旧曲目队列恢复，播放/下载音质、背景与字体设置入口可见；没有登录第三方账户或启动线上歌曲播放。
- 字体预览显示 Microsoft YaHei UI 和新品牌样例，中英文字形可见；取消后保留原设置。字号可读性和其他系统缩放未在本次重新验收。
- 升级前已有的「关闭主窗口时：退出应用」偏好保留，Alt+F4 正常退出，随后应用和 LX 宿主进程数均为 0。本次未改变该偏好。

GUI 运行结束后，设置、曲库及下载数据文件散列仍相同；`player_memory.hive` 从 386496 字节变为 421632 字节，运行期间追加了播放状态。升级兼容性的“5 文件字节一致”结论限定在安装完成、首次启动前，未将其扩大到应用运行之后。

## Android 三 ABI

三包均通过 AAPT 元数据与 apksigner 校验：applicationId 为 `app.videomusic.player`，标签 DJ Music，versionName 为 0.5.1。armeabi-v7a/arm64-v8a/x86_64 的 versionCode 分别为 1009/2009/4009，均高于相应 0.5.0 分包。

三包证书 SHA-256 均为旧证书 `e7ddc2327d50d557154d1f533201907dfe40ec5d145815792cc662bd0e5fa291`。没有重新生成签名或改为 universal 包。未进行 Android 物理设备覆盖安装、启动器/主题图标或通知栏实测，资源/签名校验不等同于设备体验验收。

## 最终候选包

本聊天交付目录：`C:/Users/Sun/Documents/Codex/2026-11-17/c-users-sun-documents-codex-2026/outputs/DJ-Music-0.5.1`。旧 0.5.0 文件保留在原目录。

| 文件 | 字节数 | SHA-256 |
| --- | ---: | --- |
| DJ-Music-Setup-0.5.1-x64.exe | 19091516 | 568862addc68260a7f1976108b14ea17d071aaa455898dd3b7b4c9a7d6ca2795 |
| DJ-Music-0.5.1-windows-x64.zip | 23332308 | 8c50a3bab2f70e673a943185cab63788131d2367599dabbbca116160df6ebb75 |
| DJ-Music-0.5.1-arm64-v8a.apk | 33477386 | 9c4a14849000e53234aae72ef4a5274e151bc8eb50833b44ea32e958d3839514 |
| DJ-Music-0.5.1-armeabi-v7a.apk | 29638526 | fe3e13f4f6fe6f7a2703fcdcbbafcc2834dfae5dee9251e5f4e11aee7a6e734f |
| DJ-Music-0.5.1-x86_64.apk | 36175704 | 500d88f4864ec7bb4a1ef0e4bd161f54ce116dee751bea86482ec804df344ad0 |

`SHA256SUMS` 包含全部五包，文件本身 SHA-256 为 `5aebc31f6eff36d1c1744147f070dcc546ee0830218ec2cf3f72ffdd99a7fed0`。出包后只整理文档，没有改写或重新打包上述二进制；ZIP 内使用说明仍是构建时的验收中快照，本记录为后续验收结论。

## 保留资料与清理边界

品牌票据、改版设计、图标源、两份界面稿、现有正式回归门、候选包、SHA256SUMS 和本记录属于正式交付。此次验收临时内容集中于聊天 `work/dj051-20261120`：`windows-artifact.zip`、`portable/`、`windows-ci.log`、`install.log` 和 `before-upgrade.json`。删除命令包含绝对路径、范围、重解析点和内容名单检查，但整条命令在执行前被自动审批拒绝，只返回 `blocked by policy`，没有更具体原因。因此该目录仍存在，不宣称清理完成，不改用其他方式绕过。

0.5.0 历史记录中受审批限制遗留的缓存和样例不属于本次新建内容，未将其当作本轮清理目标，也未宣称历史临时目录已清空。共享 Flutter/Gradle 工具链、稳定签名、应用数据和用户文件保留。

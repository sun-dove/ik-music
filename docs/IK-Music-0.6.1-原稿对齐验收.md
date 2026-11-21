# IK Music 0.6.1 原稿对齐验收

日期：2026-11-21。目标版本为 **0.6.1 / build 12**。当前已完成源实现、版本同步、126项完整定向装配/兼容验收、36组合真实应用矩阵及最终44张Flutter渲染图复核；发行前完整回归正在执行。发行构建、安装成品操作、升级和公开附件仍待核验。已公开的0.6.0/build11与其原始证据保持，不把历史结果改写成本轮结果。

## 一、场景与范围

用户指出当前界面与已审阅桌面稿不一致，并要求继续检查播放详情。本轮沿用已确认方案B，以默认关闭的`alignToDesign`分支恢复原稿布局，仅独立入口显式开启。设计、全部接入点和回滚见[原稿对齐与播放详情修订](IK-Music-原稿对齐与播放详情修订.md)。

| 场景 | 本轮实现目标 | 验收边界 |
| --- | --- | --- |
| 任意主区找歌 | 当前位置与共用搜索顶栏，提交真实查询并保留子页状态 | 顶栏有真实回调才出现；最终根装配待核验 |
| 发现音乐 | 真实歌曲封面网格、紧凑标题与探索卡、继续播放 | 每平台最多展示6首并明示；播放使用完整来源列表，不把演示歌单当作真实推荐 |
| 设置音效与外观 | 3D强调卡、并排五频竖滑杆、主题预览 | 保留能力限制、写失败回滚和实际处理帧状态 |
| 播放详情 | 封面下行内音源卡、真实ID入口、歌词字号与译文调整 | 未知格式保持未知；切歌或没有定位信息时禁用seek；跟随状态保留 |
| 搜索、曲库与最近播放 | 紧凑列式布局，窄窗折叠非关键列 | 分源失败/重试、分页、来源身份、完整队列和原始历史时间保持 |
| 下载管理 | 进行中/完成/失败分组，按用户任务执行批量动作和打开目录 | 离线缓存隔离；新增/已存在/重试/失败只说明入队结果，不声称已下载成功 |

跨源同录音识别、音源调度算法、Windows原生歌词鼠标穿透及独立字体没有本轮实现门，未接入产品。旧默认入口和公开数据契约保持。

## 二、已实际执行的定向门

正式日志根目录为会话`outputs/IK-Music-0.6.1-build12/验收证据`。以下只列已读取的结果；不同组合存在重叠，不相加为完整回归数。

| 验收组 | 已观察结果 | 正式证据 |
| --- | --- | --- |
| 主壳与发现 | 校准后的红门7通过/38行为失败；实现后45/45通过，含六宽×三字号×浅深主题36组合；旧相关41门通过 | `主壳发现-红门校准.log`、`主壳发现-绿门.log`、`主壳发现-绿门与兼容.log` |
| 设置 | 新11门通过；兼容与252布局组合所在30门全部通过 | `设置-新增红门.log`、`设置-新增绿门.log`、`设置-兼容与252布局.log` |
| 播放详情 | 新7门通过，含完整36布局组合及320宽150%长来源；旧相关51门通过 | `播放详情-红门.log`、`播放详情-绿门.log`、`播放详情-旧兼容回归.log` |
| 下载工作区 | 新12门通过，包含三任务组×六宽×三字号×浅深主题108组合 | `下载工作区-新增红门.log`、`下载工作区-新增绿门.log` |
| 下载目录适配 | 新目录场景与原文件打开门共7门通过 | `下载目录-红门.log`、`下载目录-绿门.log` |
| 独立版本同步 | PowerShell生成三文件，再运行`-Check`通过，显示IK Music 0.6.1 / 12 | `版本同步检查.log` |
| 根装配与最终兼容 | 四个完整测试文件126项通过、0失败、0跳过，包含36组合真实应用的五区、音效/外观、三下载组、来源行内展开和播放器 | `最终装配与兼容-完整定向.log` |
| 最终截图 | 浅深主题、1200/100%与390/150%四组共44张逐页真实Flutter渲染；首页推荐可见、字体继承、来源和播放详情层级已复核 | `真实Flutter-最终截图.log`、`验收截图/最终` |
| 完整静态及格式 | flutter analyze零问题；575文件格式零变化；版本同步及diff检查通过 | `发行前-flutter-analyze.log`、`最终完整静态.log`、`最终完整格式.log` |

六宽为320、390、720、900、1200、1440，字号100%、125%、150%。主壳第一轮矩阵的滚动finder同时命中了输入框内部滚动器，先校准为发现页滚动区域，再完整运行36组合；没有以测试定位错误冒充产品布局修复。设置、播放详情和下载的矩阵有在单条测试内循环执行的组合，表中的门数与布局次数分别记录。

最终根装配126项为四个完整文件的真实结果，包含36组合的新版实际应用；不是将上述重叠的局部门相加。最新播放详情11门、列表40门、设置13门（含252组合）及首页新增24px/首屏/字体门均纳入完整回归范围。完整回归最终数待其结束后读取；不使用0.6.0的2096结果代替本轮。

最后新增收口4门先实际失败：设置正文因旧居中上限偏到50px、下拉显式样式未继承字体、下载页重复标题、恢复失败入队报告抛错。只在对齐分支修正为左缘24、主题字体、一个正文标题及失败计数；字体样式使用相同inherit语义，防止切分支时文本动画插值异常。首页首屏与出处字体3红也已转绿，完整组合再次通过。最初截图夹具在真实Hive写入等待时阻塞，修为runAsync真实IO后重跑，不作为产品缺陷。

## 三、版本与兼容身份

`ik-version.json`是独立版本源，已更新为0.6.1/build12；`scripts/sync_ik_version.ps1`生成：

- `lib/video_app/ik/ik_version.dart`：IK Music、0.6.1、12。
- `windows/runner/ik_version.h`：固定版本0.6.1.12。
- `installer/ik_version.iss`：安装器版本0.6.1。

`ik_brand_test.dart`、`windows_music_brand_test.dart`、`video_settings_ui_test.dart`只同步IK固定版本字面量。Windows包内说明改为`ik 061 使用与构建.md`，对应品牌门检查同一文件；旧060说明保留历史。相关Flutter版本门待根任务统一时段执行。

Android applicationId继续为`app.videomusic.player`，签名配置沿用原稳定文件；预计三包versionCode分别为arm64-v8a 2012、armeabi-v7a 1012、x86_64 4012，必须以最终aapt读回确认。上一正式包证书SHA-256为`e7ddc2327d50d557154d1f533201907dfe40ec5d145815792cc662bd0e5fa291`，新包必须逐包比较，当前未声称新签名已核验。

Windows AppId `54A778C9-2261-4E1F-BA89-EE68844DA7AA`、AppUserModelID `sun-dove.YueyinMusic`、内部`yueyin_music.exe`、CompanyName/ProductName `sun-dove`/`YueyinMusic`及稳定数据目录保持。当前本机安装目录为`D:/Applications/ik-music`；本轮应进行同目录升级，不能重复执行已完成的旧目录迁移。

原Mconnect入口、`pubspec.yaml`的1.5.0+16及`pubspec.lock`未修改。版本准备前共享文件SHA-256分别为`7677E58FAD5FD4DC09DCFCF112522ED4BC7C29F19440755FB3DA206D9F5FAED7`与`501161FB5EE8D7256B54E9D7D8CD5929CEF1E124510445615D0B61B015FB7A12`，构建前后仍须复核。

## 四、已核对的构建路径，尚未执行构建

Android沿用正式脚本，精简发生在新隔离副本，稳定签名、三ABI与3D必须同时保留：

```powershell
./scripts/build_video_apk.ps1 `
  -FlutterSdk 'D:/Applications/AndroidDev/flutter' `
  -AndroidSdk 'D:/Applications/AndroidDev/android-sdk' `
  -Jdk 'D:/Applications/Java/jdk-17' `
  -ToolchainsRoot 'D:/Applications/AndroidDev' `
  -SigningProperties 'C:/Users/Sun/Documents/Codex/2026-10-29/xiang/work/signing/video-music-signing.properties' `
  -Compact -EnableSpatialAudio -Python 'D:/Applications/Python/python.exe' `
  -SqliteBinaryDirectory 'C:/Users/Sun/Documents/Codex/2026-11-17/c-users-sun-documents-codex-2026/outputs/IK-Music-构建输入/sqlite3-3.3.2' `
  -BuildDirectory '<执行前指定一个尚不存在的隔离构建绝对路径>'
```

上述Flutter、Android SDK、JDK、Python、签名配置和SQLite目录已检查存在，未读取或输出签名内容。缓存为`D:/Applications/AndroidDev/pub-cache`、`gradle-home`、`android-user`和`avd`；SQLite目录包含Windows x64及Android三ABI的固定3.3.2输入。脚本会再次按包内固定SHA校验，不关闭TLS、不改变共享依赖。核心构建为`flutter build apk --release --split-per-abi --no-pub --target lib/main_video.dart --build-name 0.6.1 --build-number 12`。

Windows沿`.github/workflows/yueyin-windows.yml`：同一run先产生3D单DLL、完整许可和可重建音频源码，Windows阶段再跑完整检查、实际音频信号/格式门、原生桌面门和Inno隔离红绿门，最后调用：

```powershell
$dll = "$env:RUNNER_TEMP/ik-spatial/spatial/libmpv-2.dll"
$hash = (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash
./scripts/build_video_windows.ps1 `
  -FlutterSdk $env:FLUTTER_ROOT `
  -DependencyDirectory "$env:RUNNER_TEMP/yueyin-native" `
  -Compact -SpatialAudioDll $dll -SpatialAudioSha256 $hash `
  -SpatialAudioLicenses "$env:RUNNER_TEMP/ik-spatial/licenses"
```

工作流固定Flutter3.47.5，Windows2022和Ubuntu24.04原生构建环境；临时缓存/输入位于各job的`RUNNER_TEMP`。本机常见Inno路径均未发现ISCC，不能把本机便携包生成等同安装器门通过。通用`scripts/release.ps1`及`ci.yml`的APK任务属于原Mconnect入口，不能代替以上独立发行链。

当前PATH与已检查的常规工具位置未找到`gh.exe`，未触碰凭据文件；根任务使用现有GitHub MCP。此项只说明本轮工具定位结果，不宣称认证或发布权限已验证。

## 五、拟交付九附件

当前均待生成或核验，不提供虚构大小、哈希、run或发行地址。Windows二进制与音频源码必须来自同一次最终run。

| 附件 | 作用 | 状态 |
| --- | --- | --- |
| `ik-0.6.1-arm64-v8a.apk` | Android ARM64分包 | 待构建/签名/ABI/设备核验 |
| `ik-0.6.1-armeabi-v7a.apk` | Android ARMv7分包 | 待构建/签名/ABI核验 |
| `ik-0.6.1-x86_64.apk` | Android x64分包 | 待构建/签名/ABI/设备核验 |
| `ik-Setup-0.6.1-x64.exe` | Windows安装器 | 待原生/音频/Inno/升级核验 |
| `ik-0.6.1-windows-x64.zip` | Windows完整便携目录 | 待构建/逐文件核验 |
| `ik-0.6.1-windows-manifest.json` | Windows长度与SHA清单 | 待由正式bundle生成 |
| `ik-audio-sources.tar.gz` | 同run可重建音频源码与许可 | 待同run核验 |
| `IK-Music-0.6.1-guide.md` | 对应版本最新版操作说明 | 中文草稿已写，最终结果待补 |
| `SHA256SUMS` | 前八项的完整SHA-256 | 待最终字节冻结后生成 |

上一正式0.6.0九附件结构已与正式验收记录及本地`SHA256SUMS`核对，作为结构参考和回滚材料保留。新版本不复用旧哈希或混入旧包。包体继续正规剥离未使用扫码依赖和旧大图，保留二维码显示、音频、认证、路径、许可与HRTF能力；实际大小须等新包生成后对比。

## 六、尚待核验

- 全量静态检查和回归、根入口真实路由、搜索提交、下载入队及目录打开。
- 真实Flutter成品与原稿逐页核对，含浅深主题、字体/背景、窄窗、播放器来源和歌词状态。
- 新版本Windows同run全部原生/音频/Inno门、安装器及ZIP；Android三ABI、稳定证书、版本、ZIP对齐与许可。
- Windows同目录升级前用户数据保护和启动前逐项对照、快捷方式/图标/版本与实际启动；新Android包设备操作。
- 最终构建提交、run、五包/配套文件的完整长度和SHA、公开后九附件远端一致性。

Android物理设备、真实第三方账号、任意歌曲完整播放和实际音质、耳机听感、蓝牙及持续功耗须按真实执行范围记录。0.6.0中Windows15/20与旧Android模拟器0/20的目录结果属于历史设备证据，不是0.6.1已通过结论。

本轮正式测试、中文票据、验收日志及最终交付材料长期保留。失败截图夹具新增的`C:/Users/Sun/AppData/Local/Temp/ik-app-integration-be5faf0a`含8文件65字节，按精确来源、绝对边界与进程预检后尝试PowerShell原生删除，自动审批拒绝并返回`blocked by policy`，目录仍在。正式`本轮截图临时目录清理.json`记录实际结果，不换工具绕过；其余正常退出的夹具自行精确清理。历史已拒绝清理路径不重试，也不计成本轮清理成功。

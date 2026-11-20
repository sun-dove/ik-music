# IK Music 安装迁移与品牌实施记录

## 最终发行门修正：Windows 临时目录长短路径

2026-11-20，Windows构建44738226054已完成主程序、原生红绿门、16份许可及12项PCM门，隔离Inno首次安装后的快捷方式断言失败。CI临时目录使用`C:\Users\RUNNER~1\AppData\Local\Temp`，Inno与ShellLink返回`runneradmin`长路径。根在本机真实WScript.Shell复现：同一个EXE以8.3短路径赋值后，TargetPath读回长路径，而工作目录、图标仍可保留短路径；原字符串比较因此误报。

本次是正式验收脚本的简单缺陷修复，仅影响`scripts/ik_installer_isolated_gate.ps1`中的`Assert-GateInstalled`，调用方仍为同脚本的旧安装、普通升级、新安装和再次升级四处，以及`build_video_windows.ps1`的隔离门执行。先用现有正式快捷方式与等价8.3预期目录复现红态，再把实际存在的文件/目录解析为完整路径比较；目标仍必须严格是预期安装目录中的`yueyin_music.exe`、`ik.ico`与索引0。失败信息补充实际三字段，不放宽任何安装目录、登记或文件检查。回滚为还原此验收函数；产品、迁移事务、旧公开接口和APK字节不变。真实Inno门仍须在新CI运行通过后才允许本机迁移。

后续事实修正：长短路径比较是本机真实复现的验收缺陷，但不是这次CI失败的完整原因。44742715003仍读到空目标；新增独立安装工作流保留实际字段和原LNK。44746910118证明中文文件名的LNK存在且1021字节，但英文runner的WScript读回目标/工作目录为空、图标为`,0`；下载原文件后，本机WScript及LNK原始结构均有正确目标。17d19c3将原中文入口复制为ASCII诊断名并严格核对两者SHA一致后再读取，44747502076实际红→绿：原中文路径仍空，同字节副本三字段全正确；错误跨目录顺序被拒绝，先卸旧后装新、旧/新普通升级、新卸载和未登记用户文件保留全部通过。正式门仍核验原中文入口存在、同字节副本及预期精确目标/图标索引，未放宽产品要求。生产快捷方式名称为ASCII的`IK Music`，迁移脚本不受此隔离样例中文名问题影响。

独立工作流是正式安装验收入口，不是产品模块；只在显式调用或诊断分支运行。原始LNK、JSON和卸载日志只含隔离样例，可用artifact保存14天。初次独立workflow曾因PS5读取无BOM的内联中文字符串失败，改为ASCII错误文本后实际运行成功；项目说明仍为中文。以上没有安装本机VS/Inno，也没有拿用户现装做故障注入。

日期：2026-11-20。用户已确认继续改版、打包、发布和安装迁移，旧文件清理稍后进行。本文接续已确认的《IK-Music-安装迁移与包体方案》。本轮不对用户当前安装执行卸载或迁移。

## 兼容变更票据

问题：显示名称仍为 ik，默认程序目录仍为 YueyinMusic；同 AppId 跨目录先装新再卸旧会破坏新登记。Android 依赖包含产品未调用的 mobile_scanner。

方案沿用先旧卸载、后新安装的协调流程，新增正式迁移脚本；安装器对未协调的跨目录覆盖给出明确提示。默认新目录 ik-music，普通单 EXE 升级通过 `UsePreviousAppDir=yes` 保持已经登记的目录（包括旧 YueyinMusic 和用户自定义位置），不会要求普通升级用户运行脚本。本机改到 `D:/Applications/ik-music` 使用正式迁移脚本。独立构建副本正规移除已证明无调用的依赖，再由 Flutter/Gradle 生成产物。

最小变更调用点：installer/yueyin.iss、独立 Windows/Android 构建脚本、Windows 独立入口显示文字、Android 独立资源与通知渠道显示名称、品牌门、新增迁移脚本与安装门。主入口 Mconnect、公开 Dart 接口、Windows AppId、EXE 文件名、CompanyName/ProductName、AppUserModelID、Android 包名与签名、共享 pubspec.yaml/pubspec.lock 均保持。

回滚：恢复安装器默认目录和显示字符串；独立构建关闭精简选项即可使用完整依赖。真实迁移必须预先提供 SHA-256 已核验的旧安装器；新安装失败先根据正确的新卸载登记退役失败的新装，再用旧安装器恢复旧目录。用户数据保留原位，只有明确发现数据损坏后才人工恢复受保护快照。

## 场景门与执行证据

正式门覆盖：新装默认目录、已迁移覆盖、自定义路径保持、旧卸载必须先于新安装、旧卸载失败阻断、新安装失败回滚、未知文件保留、重解析点/目录越界拒绝、安装前后数据清单一致，以及显示名/内部身份/图标完整性。

已执行的确定性证据：

| 门 | 红门 | 绿门 |
| --- | --- | --- |
| Windows/Android/通知/图标品牌 | 更改正式预期为 IK Music 后，8 门中 4 失败；实际仍为 ik | 同一两份测试最终 8/8 通过；原默认 Mconnect 断言继续通过 |
| 歌单分享品牌 | 精简副本中的既有“来自 ik”断言实际失败，实际分享品牌已为 IK Music | 只更新此独立品牌断言，歌单分享整组 11/11 通过 |
| 迁移事务顺序 | 实现缺失红门失败；`-Baseline` 故意先安装新程序、后卸旧时断言失败，退出 1 | 正常顺序、快照失败、卸旧失败阻断、新装失败回滚、路径互含/根目录拒绝、清单越界和数据变化识别通过；Windows PowerShell 5 与 PowerShell 7 均执行通过 |
| 精简依赖 | 在共享完整项目上执行精简门，因 mobile_scanner 仍在依赖图失败 | 隔离副本官方 `pub get --offline` 仅移除 mobile_scanner 5.2.3；其余依赖版本不变，插件注册图不含扫码插件，qr_flutter 等必要依赖保留 |
| 登录与二维码 | 既有分享旧品牌文字 1 门失败，不是扫码插件缺失 | QQ 二维码、账号恢复、酷狗登录页与歌单分享合计 39 门最终全绿（先 38 通过/1 品牌失败，修正后重跑相关整组 11 通过） |

真实 Inno 隔离门已实现并接到正式 Windows 构建脚本：使用每次随机 AppId、独立开始菜单名与临时 .NET fixture，不读取或写入正式产品登记，不清理用户旧品牌目录。覆盖错误跨目录写入红门、普通旧路径升级、先卸旧再新装、迁后再次覆盖、工作目录/图标/目标正确、未登记音乐文件不被卸载。当前主机没有 Inno/MSVC，按负责人安排交由 CI 的真实 Windows/Inno 执行。尚未获得此门绿结果，不能将确定性门当作真实安装门。

## 正式脚本接口

`scripts/ik_install_migration.ps1` 默认只读预检；`-Execute` 才实际迁移。输入包括：

```powershell
./scripts/ik_install_migration.ps1 `
  -InstallerPath <新版安装器绝对路径> -InstallerSha256 <已验证的新包SHA256> `
  -RollbackInstallerPath <已验证旧安装器绝对路径> -RollbackInstallerSha256 <旧包SHA256> `
  -BundleManifestPath <新版windows-manifest.json> -BundleManifestSha256 <清单SHA256> `
  -TargetDirectory 'D:/Applications/ik-music'
```

预检要求应用从托盘正常退出，发现进程仍在时明确停止，不强杀。执行会把快照和阶段记录存到 `%LOCALAPPDATA%/IKMusic/Migrations/时间-GUID`，ACL 仅当前用户与 SYSTEM 完全控制；凭据内容不进入 JSON、仓库、发行包或控制台。正式文件与数据按全量文件 SHA-256 验证，不静默抽样。失败只恢复程序，数据快照不自动覆盖。执行完成不自动启动程序，便于区分启动前数据一致与播放记忆追加。未知旧目录内容保留，用户本轮要求稍后清理。

Windows 发行脚本新增 `-Compact -BuildDirectory <尚不存在路径>`，创建独立副本，使用全新的发行 bundle，仅选编译产生的入口、DLL、data 并加入许可/图标/说明/迁移脚本，生成外部 `ik-<version>-windows-manifest.json`。必要运行时/许可缺失或混入旧卸载器、调试文件立即失败；三份 WebView2 DLL 必须 Microsoft 签名 Valid。

Android 发行脚本新增 `-Compact -BuildDirectory <尚不存在路径>`，仅在隔离副本剥离 mobile_scanner 与无引用旧图片；仍三 ABI 正规构建和稳定签名，不从已签名 APK 手删文件。`-EnableSpatialAudio -Python D:/Applications/Python/python.exe` 将固定 just_audio 0.9.46 复制到隔离副本 `.ik-packages/just_audio`，调用音效代理提供的适配脚本，再用 `pubspec_overrides.yaml` 正规解析；不会写全局包缓存。

Windows `-SpatialAudioDll <绝对路径> -SpatialAudioSha256 <固定哈希>` 必须先通过独立音效门才放入 bundle，不能以文件存在代替真实信号验证。音效门和最终 DLL 结果由对应正式记录给出。

## 网络与证据边界

隔离构建首次 SQLite 原生 hook 通过 Dart 下载 GitHub Release 遇到超时/握手失败。PowerShell 对同 URL 使用正常 TLS 可成功读取，初始化系统证书后 Windows 测试恢复；Android 三 ABI 仍偶发握手失败。因此新增 `scripts/prepare_ik_sqlite_offline.ps1`：只允许有构建配置记录的隔离目录；从当前 sqlite3 3.3.2 包内读取发行标签与四个固定 SHA-256，下载官方同版本二进制，使用包自带 `test-sqlite3` 本地输入；其 hook 会再次验证同一 SHA。未关闭 TLS，未改共享缓存，未替换 SQLite 版本或系统库。Windows 路径以 file URI 输入，防止 Dart 把盘符解析为 URI scheme。两个构建脚本均可用 `-SqliteBinaryDirectory <离线文件目录>` 启用。

Android 早期冻结副本三 ABI 正式 release 构建已退出 0。副本包含受控 just_audio HRTF 适配和精简依赖，路径为会话 `work/ik-build-20261120-spatial-android`。最终 UI 仍在整合，这一副本仅作依赖/原生验证，不能冒充最终发行；KEMAR 许可证自动拼接已写入准备脚本，但发生在此副本准备后，最终发行必须重新准备。用户真实安装没有卸载、移动或删除。

| ABI | 早期候选字节 | 相比旧 build 10 下载字节减少 | SHA-256 |
| --- | ---: | ---: | --- |
| arm64-v8a | 29,908,339 | 5,621,875 | 0FE1E4E690ACD319A4968A5344CFE130C7FA5667BCC37ECE0CEEDB6218D18836 |
| armeabi-v7a | 27,888,101 | 4,081,781 | D77C19ACDF3C8796E893BD644EB80DD611CC89036FAD2FD81F5FDCB5838BA710 |
| x86_64 | 31,492,548 | 6,801,520 | C8613F85FA1ED0A8198237292F0A1E3488D4B2C4120F8DED97BDFDDA6946D339 |

三包 `apksigner verify --print-certs` 通过，同稳定签名 SHA-256 `e7ddc2327d50d557154d1f533201907dfe40ec5d145815792cc662bd0e5fa291`；aapt 确认包名 `app.videomusic.player`、显示名 `IK Music`、versionName `0.6.0`，版本码分别 2011/1011/4011；每包仅目标 ABI。`zipalign -c -P 16 4` 三包均退出 0。

新 APK 中没有 libbarhopper、mobile_scanner 或旧 note-ribbons。各包新增 HRTF .so 为 305,640/302,340/306,328 字节，约 0.29 MiB。对比旧包，全量 ZIP 条目差异中最大的移除项为 libbarhopper 4,358,080/2,804,512/5,521,032 字节；classes.dex 减 1,103,456 字节；三种 ML Kit 模型分别移除 390,456、276,552、213,880 字节。旧包和新副本源码快照不同，整个包的净差额不能全部归因于单一依赖裁剪。真实设备 PCM、后台/路由切换门由音效代理继续验证。

实际调用 Jev `jev-1.14.0` 复核回滚边界与状态描述：选择“旧卸载成功且登记解除后才对失败新装进行回滚”和“实现/确定性门完成，真实安装待验”，两项 confidence 均 1.0。结果作为风险审查辅助；文件与阶段事实仍来自实际门。给定旧脚本路径不存在，使用技能指定官方 API 和进程环境密钥调用，密钥未输出或落盘。

本轮未执行垃圾清理。正式迁移/构建/验收脚本与本记录是长期交付；构建副本、编译日志、下载的 Inno 便携尝试材料均在会话 work 下留待后续明确清理。没有安装新的系统 Inno 或 MSVC。

## 冻结交付与回滚包

本机回滚安装器：`C:/Users/Sun/Documents/Codex/2026-11-17/c-users-sun-documents-codex-2026/outputs/ik-0.6.0/ik-Setup-0.6.0-x64.exe`，19,757,732 字节，SHA-256 `9B4BFA35F5C7A2B9ED213340441A5506994307216631F4E137A9747514E93860`。现装 EXE 固定版本仍为 0.6.0.10，与旧 portable 的 SHA-256 `3199292F01F635C079F8A175DF843339205584E49EC94FC3331AD65874E3AB66` 完全一致。现 HKCU 正式卸载登记仍指 `D:/Applications/YueyinMusic`；未执行迁移。

最终 fresh Android 调用（须等应用 UI/原生源码共同冻结后再执行）：

```powershell
./scripts/build_video_apk.ps1 `
  -FlutterSdk 'D:/Applications/AndroidDev/flutter' `
  -AndroidSdk 'D:/Applications/AndroidDev/android-sdk' `
  -Jdk 'D:/Applications/Java/jdk-17' `
  -ToolchainsRoot 'D:/Applications/AndroidDev' `
  -SigningProperties 'C:/Users/Sun/Documents/Codex/2026-10-29/xiang/work/signing/video-music-signing.properties' `
  -Compact -EnableSpatialAudio -Python 'D:/Applications/Python/python.exe' `
  -SqliteBinaryDirectory 'C:/Users/Sun/Documents/Codex/2026-11-17/c-users-sun-documents-codex-2026/work/ik-native-binaries/sqlite3-3.3.2' `
  -BuildDirectory '<尚不存在的正式构建副本绝对路径>'
```

脚本沿用签名配置文件，不输出口令；发行复制到主项目 `build/yueyin-release`，不会把别的 ABI 混进单包。Windows CI 调用添加 `-Compact -SpatialAudioDll <已通过门的单DLL> -SpatialAudioSha256 <固定哈希>`；`-Python` 默认 CI 的 python。只有存在 Inno 编译器才执行真实隔离红绿门和安装器编译，本机没此工具不能算门绿。

最终复核还增加发行清单版本门：EXE 显示名与四段固定版本必须和当前独立版本清单完全匹配。使用当前版本清单验证旧 build 10 时真实失败，避免把旧包误标成新版本。全量发布绿结果由 CI 成品生成后补充。共享 pubspec.lock SHA-256 始终为 `501161FB5EE8D7256B54E9D7D8CD5929CEF1E124510445615D0B61B015FB7A12`，未由本任务修改。

## 独立复核修正

只读故障注入发现：旧卸载与登记解除已经成功，但随后的阶段 JSON 写入失败时，原事务把整个 UninstallOld 动作放在 try 之外，导致直接退出而不恢复旧程序。先新增正式门，模拟卸载完成后日志写入失败；旧实现真实红，事件只有 Snapshot/UninstallOld，缺少 RestoreOld。新增可选 `OldInstallationRemoved` 回调，实际流程在已核验卸载成功、登记解除之后先设置内存状态，再写记录；异常按真实状态决定是否回滚。此前动作接口默认不变，卸载前失败仍只阻断。修正后 PowerShell 5/7 绿门通过，用户现装未参与故障注入。

Windows HRTF 包增加必须显式提供的 `-SpatialAudioLicenses`：`copy_ik_audio_licenses.ps1` 要求同次构建的16份非空文件，覆盖 mpv、FFmpeg、FreeType、FriBidi、HarfBuzz、libass、GCC/MinGW、KEMAR和源码构建说明，并校验KEMAR官方原文哈希。全部文件复制到 `third-party-audio-licenses/` 后再次逐文件核验，再写“对应源码下载说明.md”，明确同次发行附件名 `ik-audio-sources.tar.gz` 和仓库发行页面。只提供KEMAR目录时实际红；使用原生代理生成的真实16文件目录时实际绿。Windows CI 必须上传并在正式 Release 同时附加对应源码归档，不能只依赖14天有效的artifact。未提供SpatialAudioDll的原构建行为保持。

## 最终 build 11 Android 成品

2026-11-20 在应用UI、用户音量和原生音效共同冻结后，新建会话 `work/ik-final-build11-20261120`，从源重新复制并完整构建三ABI；没有沿用上述早期候选包。构建前后332个Dart产品文件、Android原生文件与版本清单逐字节比对一致。隔离副本登录/二维码/分享39门全部通过；Gradle release耗时541.3秒，完整构建脚本退出0。产品共享依赖文件未改动。

| ABI | 最终字节 | SHA-256 |
| --- | ---: | --- |
| arm64-v8a | 29,975,059 | 46A41A9D0A98E39133B241383F729989133B0D850BF766060B38A4D980B11D26 |
| armeabi-v7a | 27,938,441 | 8FD819909B6A66BAE54CFF6BFFCB380C1B599D9B93BC88AA58AFD745AB3F7EB3 |
| x86_64 | 31,559,268 | 84EF750C4BB0D1197E86506274EC3231F2AB2BD95430045C1F451136DF022211 |

逐包验证签名通过，与既有稳定证书一致；包名仍为 `app.videomusic.player`，名称 `IK Music`，versionName `0.6.0`，版本码2011/1011/4011。三包分别仅含目标ABI，`zipalign -c -P 16 4`全部通过；无扫码插件、barhopper或旧note-ribbons。`NOTICES.Z`解压为1,498,873字节，逐字比对原just_audio完整许可证和KEMAR完整原文均存在；HRTF库为305,640/302,340/306,328字节。正式构建输出位于项目 `build/yueyin-release`，协调任务另复制到会话正式 `outputs/IK-Music-0.6.0-build11`。

在本轮专用API30 x86_64 AVD `ik_spatial_api30` 保存 `ik-before-final-smoke` 快照后覆盖安装最终签名包，系统安装成功并确认版本4011/0.6.0。实际冷启动成功，发现、音乐库和账号设置导航正常；底栏静音按钮能切为静音图标与0滑杆，再次点击恢复。启动器显示新青蓝音符图标和IK Music名称。检查期间没有FATAL EXCEPTION、未处理异常或ANR，进程持续存活。所有操作仅发生在无用户真实数据的验收AVD。

此API30默认镜像的headless GPU/SwiftShader仅提供OpenGL ES 2能力，Impeller渐变shader出现uniform上限错误，截图主体可见但渐变效果不得记为通过；本轮不为模拟器限制改动产品渲染配置。Android真实PCM处理门另有独立记录，不能用导航冒烟代替音效门。Windows最终安装器仍须等待CI实际生成与隔离安装验收，现装目录和回滚安装器保持未动。

## 最终现包的内置音源入口实测

同一最终签名包在专用API30 AVD中通过顶部设置进入“音源”，未粘贴链接，未点击手动检查或重试，也未替换专用门。设备页面自动出现固定20项目录；“自动准备内置音源”开关处于开启，页面汇总明确显示“本机已准备 0 / 20 项”。连续滚动抓取6页UI语义及截图，按固定目录名称逐项对照，20/20条均观察到，没有漏项或抽样；这是目录与状态展示覆盖，不是20项本机可用结论。

| 实际设备状态 | 数量 | 说明 |
| --- | ---: | --- |
| 本机已准备 | 0 | 当前模拟器没有任何目录项可记为初始化成功 |
| 准备失败 | 15 | 非常道展开明确显示“脚本音源需要Android 8.0以上及支持隔离运行的Android System WebView”；未逐项展开另外14项，不能推断全是相同原因 |
| 等待联网 / 校验 | 1 | 常青展开显示“网络不可达，已保存的音源仍保留” |
| 暂不支持 | 3 | 小草、聚合、六音 |
| 使用范围受限 | 1 | 星海 |

Android系统查询确认该专用AVD当前WebView为 `com.android.webview 83.0.4103.120`。具体获取与受限初始化错误已经由自动链产生并在页面可展开查看，证明自动处理运行过；当前设备的网络与旧WebView限制仍使可用数为0。不能据此宣称Android20项全部就绪，也不能把目录可见当成歌曲可播放。

逐项机器证据在会话 `work/ik-final-catalog-device-status.json`，包含20个名称、实际状态、所在截图页与空的遗漏列表。UI语义原文和图像为 `ik-final-catalog-page-01` 至 `06` 的 `.xml/.png`；汇总 `ik-final-catalog-summary.png`、初始化失败详情 `ik-final-catalog-first-status.png`、网络详情 `ik-final-catalog-changqing.png`。检查没有修改产品源码、重建APK、安装WebView或写入用户真实环境。

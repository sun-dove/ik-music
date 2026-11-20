# IK Music 安装迁移与包体方案

日期：2026-11-20。本文是正式设计与只读盘点，不代表迁移或减包已经实施。本轮用户要求安装目录改为 `ik-music`、清理原程序目录、控制安装包体积；这更新了此前“安装目录保持不变”的约束。稳定 AppId、EXE 内部身份、用户数据和公开接口仍须兼容。本次仅新增本文，没有移动、删除安装文件或修改产品、安装器。

## 一、目标、范围与实际基线

本机当前目录 `D:/Applications/YueyinMusic`，目标目录 `D:/Applications/ik-music`，只读检查时目标尚不存在。现装版本为 `0.6.0/build 10`。资料来源：

- 当前安装目录：`D:/Applications/YueyinMusic`。
- 已验证完整包：`C:/Users/Sun/Documents/Codex/2026-11-17/c-users-sun-documents-codex-2026/work/ik060-20261120/portable`。
- 五份发行文件：同一会话目录的 `outputs/ik-0.6.0/`。
- 升级前快照与安装日志：`work/ik060-20261120/before-upgrade.json`、`install.log`。
- 来源提交、CI 与完整验收：沿用《交付文档/ik-060验收记录》，本次不把资源存在代替运行验收。

本文所有 MiB 按 1,048,576 字节计算，KiB 按 1,024 字节计算。以下是逻辑文件长度总和，不是 NTFS 分配空间，也不包含用户音乐、缓存与 Roaming 数据。

| 范围 | 文件数 | 字节 | MiB |
| --- | ---: | ---: | ---: |
| Windows 便携展开目录 | 50 | 56,744,774 | 54.116 |
| 当前安装目录 | 56 | 61,283,812 | 58.445 |
| 安装程序附加的卸载器与日志 | 2 | 4,479,549 | 4.272 |
| 历史安装遗留说明与旧 ICO | 4 | 59,489 | 0.057 |

已独立验证当前包内 50 个文件与安装目录的对应文件 SHA-256 全部一致，缺失 0、差异 0。对便携包全部 50 文件按 SHA-256 分组，未发现完整文件内容相同的重复项。

### 五包实际大小

| 交付文件 | 字节 | MiB | 说明 |
| --- | ---: | ---: | --- |
| `ik-Setup-0.6.0-x64.exe` | 19,757,732 | 18.842 | 已用 LZMA2 与 solid 压缩 |
| `ik-0.6.0-windows-x64.zip` | 24,273,510 | 23.149 | 50 文件，展开 54.116 MiB |
| `ik-0.6.0-arm64-v8a.apk` | 35,530,214 | 33.884 | 常见 ARM64 手机安装这一份 |
| `ik-0.6.0-armeabi-v7a.apk` | 31,969,882 | 30.489 | 32 位 ARM 设备使用 |
| `ik-0.6.0-x86_64.apk` | 38,294,068 | 36.520 | x86 设备与模拟器使用 |

五份下载文件合计 149,825,406 字节（142.885 MiB），这是不同系统/架构的发行集合，不能当作单台设备安装体积。Android 继续三 ABI 分包，不打 universal，不把其他 ABI 装入同一设备包。安装器不捆绑 ZIP、APK、源码或开发工具。

### Windows 最大单文件

| 文件 | 字节 | 占展开包 | 处理结论 |
| --- | ---: | ---: | --- |
| `flutter_windows.dll` | 21,274,112 | 37.49% | Flutter 引擎，必须保留 |
| `libmpv-2.dll` | 15,525,902 | 27.36% | Windows 实际音频后端，必须保留 |
| `data/app.so` | 12,993,416 | 22.90% | 当前应用 AOT 代码，必须保留 |
| `sqlite3.dll` | 1,667,072 | 2.94% | 曲库、历史、统计等数据库，必须保留 |
| `data/flutter_assets/packages/liquid_glass_widgets/shaders/liquid_glass_geometry_blended.frag` | 968,856 | 1.71% | 有共享导入可达链，不能仅凭新版未直接画玻璃就删 |
| `data/icudtl.dat` | 864,880 | 1.52% | Flutter 国际化数据，必须保留 |
| `data/lx-host/Microsoft.Web.WebView2.Core.dll` | 603,712 | 1.06% | LX 脚本宿主 SDK，必须保留 |
| `data/flutter_assets/packages/media_kit/assets/web/hls1.4.10.js` | 374,690 | 0.66% | 仅 Web 播放实现引用，可列为独立 Windows 构建裁剪候选 |
| `data/flutter_assets/assets/lx-runtime/forge-1.3.1.min.js` | 281,651 | 0.50% | LX V2/V3 实际加载，必须保留 |
| `yueyin_music.exe` | 222,208 | 0.39% | 原生窗口、通道、托盘与入口，必须保留 |
| `just_audio_windows_plugin.dll` | 181,248 | 0.32% | 已自动注册并参与链接，不可直接删 DLL |
| `data/lx-host/WebView2Loader.dll` | 165,968 | 0.29% | LX 宿主加载依赖，必须保留 |
| `flutter_secure_storage_windows_plugin.dll` | 159,744 | 0.28% | 凭据存储，必须保留 |
| `app_links_plugin.dll` | 141,312 | 0.25% | 分享链接接入，必须保留 |
| `share_plus_plugin.dll` | 134,656 | 0.24% | 分享能力，必须保留 |
| `data/flutter_assets/NOTICES.Z` | 132,042 | 0.23% | 第三方许可，不裁掉 |

前三项共 49,793,430 字节，占 87.75%。当前 18.842 MiB 安装器的主体来自必要运行时，不能承诺靠删除几张图片把它压缩到几 MiB。完整 LX 宿主 6 文件合计 835,053 字节，ZIP 内压缩载荷 245,266 字节，不能以省 0.23 MiB 下载为由损坏音源功能。三份 WebView2 DLL 的 Microsoft Corporation Authenticode 签名均为 Valid。

## 二、重复内容与减包候选

| 项目 | 实际证据与体积 | 建议及验收前提 |
| --- | --- | --- |
| 历史说明与旧 `yueyin_icon.ico` | 只在当前安装目录，不在新 ZIP；合计 59,489 字节 | 迁移旧目录时按确切归属清理，不宣称它们影响新安装器体积 |
| `ik.ico` 与 EXE 内嵌图标 | 图像内容重复但用途不同：快捷方式显式使用 `ik.ico`，EXE/托盘使用资源 | 两份保留，不能删除快捷方式指向的 ICO；本次不重复九档像素验收 |
| `assets/branding/yueyin/note-ribbons.png` | 95,830 字节；ZIP 内 88,281 字节；`pubspec.yaml` 声明，`lib/android/windows` 产品代码未查到引用 | 可在独立入口构建资产清单中排除；不得直接改共享默认资源契约，先验证完整 UI 和资源清单 |
| media_kit Web HLS JS | 374,690 字节；ZIP 内 110,796 字节；包仅在 `src/player/web/utils/hls.dart` 使用，Windows走 native libmpv | 独立 Windows 构建副本排除 Web-only 资产，重新生成 AssetManifest；不得只从完成包里删文件留下清单悬空 |
| liquid_glass_widgets 五份 shader | 1,142,816 字节；ZIP 内 237,488 字节；不同内容，没有相同哈希重复 | 暂不裁。实际可达链为 `main_video → video_app → ik_router → ik_floating_lyrics → settings_page → app_background → liquid_glass_widgets`。需隔离共享设置依赖、证明无调用并做背景/歌词/详情回归后才考虑；旧 Mconnect 的玻璃界面仍需保留 |
| Android mobile_scanner/ML Kit | `lib/` 无 `mobile_scanner` 导入；自动 GeneratedPluginRegistrant 仍注册。`libbarhopper_v3.so`：ARM64 4,358,080、ARM32 2,804,512、x86_64 5,521,032 字节；另有 barcode 模型 390,456 字节 | 这是较有价值的候选，但须从独立构建依赖图正规移除并重建，先核验扫码/登录的真实需求；不手删 APK 原生库、不改既有签名；净缩减以重建包为准 |
| `dartjni.dll`、JNI、just_audio Windows 插件 | JNI 通过 FFI 列表打包，just_audio 插件通过 generated registrant 链接；不能仅看新音频路径判无用 | 当前保留。依赖隔离需单独证明生成注册、动态库加载和 Android 插件链均安全，收益小于破坏风险 |
| 三平台图标 | 三图合计 98,645 字节，包中各一份且实际使用 | 保留；清晰度和识别性优先，不把不足 0.1 MiB 当首要减包目标 |
| forge/pako 与许可 | LX 引擎实际 `rootBundle.loadString`，main 注册许可证 | 必须保留，不裁运行库或许可 |

目前可证明的旧图+Web HLS候选合计仅 470,520 字节展开、199,077 字节 ZIP 载荷（约 0.449/0.190 MiB）。这只是两个现有条目的理论上限，尚未实施或验证构建，不能当成已节省。shader 的潜在上限也仅约 1.090 MiB 展开、0.226 MiB ZIP，不作为先删后测的理由。

Android 原生 `.so` 条目的 ZIP 长度等于原长度，是当前 APK 直接加载/对齐布局的一部分。不可为缩小表面下载数字直接重压 APK；这会改变签名、对齐和安装行为。继续由正式 Flutter/Gradle 流水线出包。R8 已启用，若进一步剥离依赖，要比较实际 APK 与已存在的稳定签名门。

减包方案比较：

1. **推荐：独立构建白名单与依赖裁剪。** 保持共享源码和旧入口默认，在受控临时构建副本中按 manifest 生成正式资源，移除证明不用的依赖；干净构建并核验全部功能。每个排除项记录路径、理由、调用搜索结果、门与节省字节。构建副本不包含用户数据，完成后按精确路径清理。
2. **不采用：完成产物直接删大文件/压壳。** DLL 注册和加载契约会失效，资源清单可能悬空，APK/微软签名可能破坏；对播放器和音源运行时风险高。UPX 或让用户自行补核心 DLL 不纳入此次方案。

桌面视觉重排优先用已有 Flutter 布局、渐变、阴影和短动画完成，不因视觉需求引入新渲染引擎或大纹理库。用户新增的 3D 环绕是音频处理能力，另见《IK-Music-3D音效技术调研》，不能用视觉动效替代。静态设计代码不能直接推导包体增长，最终仍以重建五包的实际数字为准。

## 三、安装目录迁移的关键风险

当前 `installer/yueyin.iss`：

- AppId 固定 `{54A778C9-2261-4E1F-BA89-EE68844DA7AA}`。
- `DefaultDirName={localappdata}\Programs\YueyinMusic`；未配置 `UsePreviousAppDir`，官方默认 **yes**。仅把 DefaultDirName 改成 ik-music，老用户仍会默认装回旧目录。
- 卸载日志默认 `UninstallLogMode=append`。同 AppId 用于确定能否附加日志，也决定 `_is1` 注册表键名；它不会自动把另一目录的旧安装全部迁走。
- 当前 HKCU 卸载登记指向 `D:\Applications\YueyinMusic\unins000.exe`，日志为同目录 `unins000.dat`。卸载器 4,409,602 字节、日志 69,947 字节，属于安装管理必需部分。
- 旧品牌快捷方式清理函数仅比较旧链接目标是否等于**新** `{app}\yueyin_music.exe`。一旦目录迁移，指向旧路径的链接不能通过该条件，必须同时认识已核验的旧、新目标。

不能先用同 AppId 安装新目录，再执行旧 `unins000.exe`：旧卸载器可能删除同名的新卸载登记、同路径的新快捷方式，或者覆盖安装维护状态。不能直接重命名文件夹并复制旧 `unins000.dat`；旧日志记录的文件路径仍归旧位置。也不把 `UninstallLogMode=overwrite` 当作迁移功能。

## 四、迁移两方案与推荐

| 方案 | 步骤 | 优点 | 代价与风险 |
| --- | --- | --- | --- |
| A：旧登记正常退出后，同身份安装新目录（推荐） | 提前验证新包和可回滚旧包；关闭应用并快照；精确核验旧卸载器/目录后正常卸载并等待；相同 AppId 新装 ik-music；验证后清理已归属旧残留 | 使用原安装器记录卸载程序文件；新目录获得全新的正确卸载日志；不会让旧卸载器事后误删新登记 | 中间有短暂不可用；失败必须用已验证旧安装器恢复程序，数据不重置；先在隔离场景证明旧卸载不触Roaming数据 |
| B：新包先落新目录，再手动退役旧文件 | 验证新目录可用、写新登记/快捷方式；按已归属清单删除旧文件与旧卸载器，绝不运行旧卸载器 | 可先检查新程序，缩短不可用时间 | 必须准确重建安装管理与回滚状态；旧日志可能包含多次历史升级文件；未知文件/失败恢复更复杂，不宜作为这次首选 |

推荐 A。保留同 AppId，不制造新旧两个“已安装应用”。新版本号/build 应递增，继续由 `ik-version.json` 同步。安装界面展示迁移前后目录，静默迁移必须携带明确且已规范化的目标 `/DIR="D:\Applications\ik-music"`。普通新用户默认 `{localappdata}\Programs\ik-music`，不能把本机 D 盘硬编码成所有用户的安装要求。

### 迁移状态与数据结构

新增迁移记录仅保存路径、版本、文件名、长度、哈希和阶段，不保存账号内容、私钥或音源正文：

```text
InstallMigrationPlan
  appId
  sourceDirectory / targetDirectory（规范化绝对路径）
  sourceUninstaller / sourceUninstallLog
  verifiedNewInstaller / verifiedRollbackInstaller
  dataDirectory
  phase: inspected → stopped → snapshotted → oldUninstalled
         → newInstalled → verified → cleaned
  ownedFiles[]: relativePath, length, sha256, evidence
  unknownFiles[]: relativePath, length（不自动删除）
  shortcuts[]: path, targetPath, iconLocation
```

旧目录识别同时要求稳定注册表 AppId、EXE CompanyName/ProductName/OriginalFilename、用户授权的安装根一致。拒绝系统根、盘符根、父目录、重解析点越界、旧新目录互相包含。若旧目录是用户自定义其他位置，不静默推测移动；只有确认属于当前产品且符合本轮指定的迁移目标才执行。

### 实施步骤

1. **包与目录预检。** 新安装器、回滚安装器均先下载完并校验；确认目标磁盘、可写性与空间。目标已有同产品则按正常升级处理，存在不明程序或文件则停止迁移依赖步骤，不覆盖。不要安装到旧目录的子目录。
2. **正常退出。** 使用现有退出握手，让播放记忆、统计、数据库 WAL 与 LX 子进程完成收尾。窗口关闭可能只最小化，不能当已退出；核对主程序、LX 宿主和相关文件占用。只有确认归属本程序的进程才进入停止方案。
3. **关闭状态下取证与可回滚备份。** 完整用户数据根、数据库与WAL/SHM、外观文件、音源/任务设置按已知归属快照；敏感数据备份仅本机权限保护，不写进仓库或发布包。必须分清“安装后尚未启动”与“启动后运行状态追加”的哈希时间点。用户音乐和自定义下载位置单独标记，默认不搬不删。
4. **先卸旧登记。** 在安装进入文件落盘之前，依据已核验记录执行精确旧卸载器并等待结束，携带 `/NORESTART` 与单独日志；状态、返回码和文件占用不通过时停止。不得从任意可写文件读出一段未经核验的 shell 命令执行。
5. **安装到新目录。** 相同 AppId、内部 `yueyin_music.exe`、CompanyName=`sun-dove`、ProductName=`YueyinMusic`、AppUserModelID=`sun-dove.YueyinMusic` 均不变。新目录只放新发行文件与本次生成的卸载文件，绝不复制旧 `unins000.exe/.dat`。迁移模式禁止 UsePreviousAppDir 把目录改回旧位置；已完成迁移后的自定义新位置应正常记忆，不能每次强制换位置。
6. **重建快捷方式与登记。** 新桌面、开始菜单快捷方式目标新 EXE，IconLocation 指新 `ik.ico,0`，WorkingDirectory 指新根；清理旧品牌/旧路径链接之前逐个确认 TargetPath 为已验证旧/新 EXE。名称相似但指向别的软件必须保留；开始菜单目录只在空时删除。核对卸载登记唯一且指新目录 `unins000.exe`。
7. **启动前验收。** 新发行清单全部文件长度/哈希匹配；用户数据哈希与步骤3一致；旧目录是否剩余、剩余归属与清理结果明确报告。功能门失败则不启动、不清理回滚包。
8. **新成品运行验收。** 启动新路径，验证同一账号/收藏/历史/队列/音质/背景字体、下载路径、音源宿主、托盘、单实例、桌面歌词。读取下载根可能仍指用户自选旧目录下的位置；这属于用户内容，不能随旧程序树递归清理，应按真实设置精确处理。
9. **精确清旧残留。** 优先由旧卸载日志处理旧程序文件。对余下历史文档/旧ICO等，必须有已验证发行清单或本次取证哈希才能逐项删除；未知文件保留并报告精确路径。只在目录确认无剩余且路径仍为核验旧根时移除空目录。禁止 `Remove-Item D:/Applications/YueyinMusic -Recurse` 一把梭，也不能枚举PowerShell路径后交cmd拼字符串删除。
10. **失败回滚。** 旧卸载前失败不触现装；旧卸载后新安装失败，用提前验证旧包恢复旧目录和同AppId登记，用户数据保持原位。若新安装已落盘，先按其正确新卸载记录清理失败的新登记，再恢复旧包；不能这时再运行旧卸载器。没有证据不得覆盖恢复用户数据备份；只有确认数据受损且明确归属时才使用保护性恢复步骤。

保留的是用户数据目录 `C:/Users/Sun/AppData/Roaming/sun-dove/YueyinMusic`，不是旧程序目录。`getApplicationSupportDirectory` 依赖 EXE 的 CompanyName/ProductName；本轮目录改名不能顺手改内部这两项。Windows 窗口偏好注册表 `Software\sun-dove\YueyinMusic\IkWindow`、安全凭据存储、Android包名/签名同样不变。

## 五、调用点与最小兼容变更

| 调用点 | 拟议变更 | 兼容与回滚 |
| --- | --- | --- |
| `installer/yueyin.iss` Setup | 新安装默认叶目录 ik-music；迁移时明确关闭旧路径重用；普通升级复用已验证的新路径 | 同 AppId；`installer/mconnect.iss` 不改；回滚原默认和迁移分支 |
| 安装器迁移预检与 PrepareToInstall，或正式发行迁移协调脚本 | 新增上面迁移记录与阶段控制；旧卸载必须在新文件/登记写入前完成 | 独立新逻辑，不修改运行中生产播放器；正式脚本属于交付物，不作为临时验证脚本遗留 |
| 旧快捷方式核对函数 | 新增可验证的旧目标参数或独立新函数；逐项核对旧/新目标 | 不扩大为按品牌通配删除；原默认路径的行为保持 |
| `scripts/build_video_windows.ps1` | 发布从全新、可审计的 bundle 输出；验证必要文件/无调试物/许可；减包候选只在明确独立构建副本实施 | 不改共享依赖缓存或原Mconnect默认构建；恢复候选资源即可回滚 |
| `scripts/build_video_apk.ps1`、独立Android依赖构建配置 | 若证实移除mobile_scanner，重新生成插件和签名三ABI | 先设计、红门和真实扫码/登录场景，不手改生成注册文件；签名包名保持 |
| 正式品牌/安装身份测试 | 更新旧 `Programs\YueyinMusic` 默认路径断言，新增旧到新迁移门 | 原Company/Product/AppId断言仍绿；不放宽为任意路径即可 |
| `lib/video_app/data/video_windows_storage.dart`、原生内部身份 | 无需变更 | 明确保持存储契约；用户数据不随程序目录搬迁 |

现有发行 `[Files]` 递归复制 runner Release。CI干净checkout已无多余安装遗留；本地重复构建仍要按确认来源重建正式bundle，防止旧说明、旧图标或临时验证文件混入。不能因名字含 test 或 txt 就删用户现有文件，LICENSE.txt/NOTICE.txt 属正式许可必须保留。

## 六、功能门与体验门：先红再实现

下表是待实施的正式场景门，不是本次已执行测试。当前版本预计在默认目录、旧目标清理、新卸载登记场景为红；先在隔离安装目录与测试用户环境真实复现，再实现迁移。用户真实安装目录不作为故障注入试验场。

| 门 | 真实场景 | 功能门 | 体验门 |
| --- | --- | --- | --- |
| I01 | 0.6.0装在YueyinMusic，更新到新品牌 | 旧目录识别准确，目标ik-music，唯一同AppId登记，旧卸载先于新登记 | 安装界面明确迁移到哪里；成功后仅新入口可见 |
| I02 | 只修改DefaultDirName的旧安装器 | 必须证明UsePreviousAppDir默认会留旧路径，新增分支后不再发生 | 目录页确实显示目标，不是安装结束才发现装回旧处 |
| I03 | 新安装/已迁移后再次覆盖/显式自定义新路径 | 三种路径策略正确且可重入；重复执行不再次卸错目录 | 用户选择不被下一次更新静默覆盖 |
| I04 | 旧目录含用户音乐、下载子目录或未知文件 | 精确所有权清单，未知内容不删；无重解析点越界 | 清理结果列出未清路径和原因，不能报“旧目录全清” |
| I05 | 包下载失败、空间不足、旧应用未退出、新安装失败 | 对应阶段停止；旧状态保留或用验证旧包回滚；不会双卸载 | 有具体错误与重试动作，进度不假成功 |
| I06 | 安装后卸载新版本 | 新unins路径正确；程序文件与快捷方式清除，用户数据仍在 | 系统已安装应用只有一项，卸载入口可用 |
| I07 | 迁移保留账户与本地曲库 | 停止状态完整快照；安装后启动前hash一致；Company/Product/数据路径不变 | 首次打开收藏、播放记忆、外观、下载路径恢复，无“像全新安装”的体验 |
| I08 | 图标与快捷方式迁移 | 逐目标校验，TargetPath/WorkingDirectory/IconLocation全新路径；无旧目标残留 | 桌面与开始菜单显示新名称和新图标；点击启动新目录EXE |
| P01 | 独立Windows资源裁剪 | 资源清单无悬空、50项基线必要依赖保留、许可齐、微软DLL签名Valid | 冷启动、各页、播放/均衡器/歌词/音源加载无缺资源错误 |
| P02 | Android剥离未使用扫码依赖 | 三ABI签名/版本/对齐正确，登录与插件链门通过，原入口默认保持 | 原有登录扫码路径如存在仍可使用；不能用“没有import”替代场景核验 |
| P03 | 安装包容量回归 | 新五包实际字节+展开文件清单与基线对比；新增大依赖需说明 | 用户仅下载所属平台/ABI；安装器不包含旧包或开发工具 |
| P04 | 3D界面与资源策略合并 | 不额外引入运行引擎；shader候选必须经过实际引用门 | 常用窗口/DPI不卡顿、低动效可控，不能以瘦身破坏视觉或播放 |

减包完成定义是“实测体积下降，功能门与体验门通过”，不以压缩参数变动或理论条目长度冒充已减包。Windows新包大小若因用户新增功能上升，必须报告增长项和候选移除项各自贡献，不预先编造固定下降比例。

## 七、本次结论与证据边界

本机安装目录改名可以与 Roaming 数据保持原位同时成立。推荐按正常卸载登记→同AppId新目录安装→验证后精确清旧残留执行；不能仅移动文件夹或在新装后运行旧卸载器。

当前没有“重复大图片挤满安装器”的证据。Windows前三项必要运行时占87.75%；确定的小资产候选只能省约0.190MiB ZIP载荷。较值得研究的是Android未使用扫码原生依赖，必须经过独立构建与登录体验验收。内部运行依赖、许可和正确卸载器完整保留。

按项目要求实际调用Jev辅助比较方案：模型 `jev-1.14.0` 对正常登记顺序迁移选择概率0.96、置信度0.94；对“证明后独立裁剪”选择概率1.00、置信度1.00。源码和包体结论来自本机只读确定性检查，Jev没有决定任何删除行为。本次请求仅发送公开功能与方案概述，未发送密钥、账号或文件内容。

Inno官方资料（2026-11-20读取）：

- [UsePreviousAppDir 默认 yes](https://jrsoftware.org/ishelp/topic_setup_usepreviousappdir.htm)
- [UninstallLogMode 默认 append](https://jrsoftware.org/ishelp/topic_setup_uninstalllogmode.htm)
- [AppId 与卸载日志、注册表键](https://jrsoftware.org/ishelp/topic_setup_appid.htm)
- [卸载器参数、NORESTART与日志](https://jrsoftware.org/ishelp/topic_uninstcmdline.htm)

本文保留为正式设计交付。本次没有创建临时测试、压缩包、脚本、备份或日志，没有执行安装、卸载、移动或删除操作。

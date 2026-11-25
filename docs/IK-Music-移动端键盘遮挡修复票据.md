# IK Music 移动端键盘遮挡修复票据

记录时间：2026-11-24T21:03:45+08:00。本票据是正式长期交付物，创建者为本轮 Codex `/root/delivery_support`。

## 状态与授权

**源码、完整回归及新 APK 的原生键盘复验已通过。** `0b9561d` 成品在 Android API30 x86_64、320×640 上完成输入、Enter 提交、再次输入和系统返回收键盘；新包证据见第九节。320×640 的旧 `5a5f3d8` 原生首红保留为历史，720×900 的旧宽窗边界未在本票据修复。整版本轮约定的成品验收和九附件冻结已完成，发布待实际执行。

这是已批准搜索能力的简单缺陷修复：共用搜索能输入、提交并保留状态的既有目标，在移动端系统键盘出现时没有得到满足。既有批准文档已包含原稿对齐 A01/A07、弹层一致性 R07/R09、发现状态 S05，且明确保留原生键盘待验边界；此次补齐真实场景和执行门。没有新增业务模块、服务或外部系统，无须另开复杂模块设计讨论。

负责人已确认：先正式 K01 红门，再新增可选 `mobileKeyboardLayout = false`，仅 `main_video` 移动平台显式开启；窄屏且 IME 可见时以 `Offstage` 隐藏固定品牌导航和底部播放栏，保留输入、页面和播放会话；IME 关闭恢复。授权范围仅本票据列出的布局文件及既有相关测试中的正式验收门。先定向红→绿、format、analyze；全仓测试及构建待负责人收到两个独立缺陷的最终源码后统一安排。

## 一、真实场景与首红

成品源提交：`5a5f3d8d97b582b2dbd1f21826eaf44ca6225b46`。新 x86_64 APK SHA-256：`b495f39a30b130b432e127316a536030860421b5198258a0e99edd7253eb7153`。复现使用新包进程 PID 2417，原生截图为 320×640。

最小步骤：

1. 启动已核新包，保持无曲目、无播放状态。
2. 进入搜索，点击实时输入框 `[24,197][296,241]` 的中心 `(160,219)`。
3. Android LatinIME 打开，真实键入匿名词 `music`。
4. 查看输入框文字与光标、记录 PNG/XML/IME 原始状态。
5. 发送系统 Enter，核对 query 确实提交，再记录新结果截图。

实际：XML 中 EditText 的 `text=music`、`focused=true`，Enter 后出现 `music` 结果；但首红 PNG 中白色播放面板约从 y=205 开始，输入文字区域被覆盖。输入框 `[24,197][296,241]` 与播放占位说明 `[12,216][308,268]` 相交为 `[24,216][296,241]`。播放栏显示“挑一首喜欢的音乐”，上一首、播放、下一首均禁用；无曲目、无播放也能复现。

IME 原始输出确认 `com.android.inputmethod.latin/.LatinIME`、`mInputShown=true`、`mShowRequested=true`、`mShowExplicitlyRequested=true`、`ADJUST_RESIZE`，目标 uid10130/pid2417。首红图片已由验收代理及本票据作者实际查看，全部九项最小复现引用均重新核过字节数和 SHA-256。完整 PID 日志未发现 FATAL、RenderFlex 或 overflow 字样，仍有 Impeller/shader 错误标记；日志不能记为干净，Enter 成功也不能让几何体验门变绿。

证据根目录：[C:/Users/Sun/Documents/Codex/2026-11-17/c-users-sun-documents-codex-2026/outputs/IK-Music-0.6.1-build12/验收证据/新成品-5a5f3d8-20261124](C:/Users/Sun/Documents/Codex/2026-11-17/c-users-sun-documents-codex-2026/outputs/IK-Music-0.6.1-build12/验收证据/新成品-5a5f3d8-20261124)。以下路径均相对该目录，原件只读保留。

| 原件 | 字节数 | SHA-256 |
| --- | ---: | --- |
| Android-首错A05-键盘输入被播放栏覆盖.json | 6230 | `e3304535078eea476adbd245cf8ea1e2a4b0dc5ffe686c647db81742e470405a` |
| Android-A05-最小复现与空播放器条件.json | 8411 | `785bc30d03d97854f5eb32aa79c250a0eb2a6d96ea15b2cce5c12d83dc4dec51` |
| Android-新截图/04-系统键盘真实输入music.png | 39156 | `b26b2bfa2adc2b583767a7802f2c632c129c2c896c1658969567e4bcb995abb7` |
| Android-新截图/04-系统键盘真实输入music.xml | 12312 | `f6d0c696fbd7e457ae8a1dba6f4bb8db313064645e34d8f298645d8d4c8f6870` |
| Android-逐命令原始输出/0026-stdout.log | 13681 | `e74f4cae7039cc207aab4fe267451b5b19b581572dfb2b9f290937c14c9a9dc9` |
| Android-新截图/05-真实Enter提交music结果.png | 34856 | `626459d818827b0f893bffa8ceb363ff866a81004afece84a94705256aa69177` |
| Android-新截图/05-真实Enter提交music结果.xml | 14963 | `67ce149da1936887c83fd0e92dc43c43f498bf4f49a3eff39616b258171cc77d` |
| Android-逐命令原始输出/0027-stdout.log | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| Android-逐命令原始输出/0027-stderr.log | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| Android-搜索键盘Enter段完整日志-PID2417.log | 102958 | `f575407916b9b92ee87a62ed99d28ac88f1568f082329c303f9df5bddde14236` |

## 二、根因与现有调用链

真实入口为 `lib/main_video.dart:367` → `VideoMusicApp(redesign:true, workspace:true, alignToDesign:true)` → 私有 `_VideoHome` → `lib/video_app/video_app.dart:2772` 的 `IkDesktopWorkspace`。组件名含 Desktop，但当前 Android 同样走此 workspace 分支。当前新包不走 `IkShell` 或旧 `VideoShell`。

`lib/video_app/ik/ik_workspace.dart:142` 的 Scaffold 未显式设置 `resizeToAvoidBottomInset`，默认按 IME 缩小 body。外层 Column 仍保留窄屏固定品牌导航（147–182）和固定 `playbackBar`（284），中部 Expanded 分到剩余高度。中部又有共用 `_WorkspaceTopBar` 加 Expanded/IndexedStack（263–277）。

`_WorkspaceTopBar` 的 controller 是该 StatefulWidget 自己持有（301–306），窄屏采用位置说明、间距和输入框的 Column，再加上下 padding（313–379）。剩余高度被固定上下区域消耗后，输入框仍有原布局尺寸，其绘制区域与后绘制播放栏相交。父级分配有限高度、后绘制元素覆盖前方元素，完全可能没有 RenderFlex 报错，因此仅查日志不足以发现此缺陷。

`IkSearchWorkspace._aligned` 在 `useSharedSearch=true` 时不再放第二个输入框（213–246）；此次可见输入是外壳共用输入。`IkPlaybackBar` 的 aligned 窄屏本身是标题、播放控制、音量/工具多行 Column（323–390），空播放器仍占高；共享组件的高度不能按“有无曲目”认定此问题消失。

独立 detailShell（`video_app.dart:148–180`）有自己的 Scaffold/Column/播放栏，属于不同路由；本票据只处理已复现的 root 共用搜索外壳，不扩大到详情、设置或独立播放器路由。

## 三、方案比较与推荐

| 方案 | 实现与影响 | 结论 |
| --- | --- | --- |
| 全局关闭 Scaffold 的 resize，或统一缩改共享播放器 | 关闭 resize 会使输入或结果进入键盘覆盖范围；改共享播放器会影响旧入口、Windows、详情和播放器调用方，仍需解释大字/小屏布局。 | 不推荐，影响面超出最小复现。 |
| 新增默认 false 的可选移动键盘布局，仅入口显式启用 | 保留 Scaffold 默认避让。有效条件为开关开启、宽度小于现有720阈值、`MediaQuery.viewInsetsOf(context).bottom > 0`。IME 中隐藏窄屏固定品牌导航及底栏，释放高度给共用输入和可滚动结果，IME 关闭恢复。 | 推荐，已获负责人确认，原公开缺省分支保留。 |

推荐分支通过固定位置的 `Offstage` 包装保留挂载状态。IME 开关只改变 `offstage`，不把品牌导航/播放器条件删除，不改变中间 child 槽位，不释放 `_WorkspaceTopBar` 的 controller，不重建 IndexedStack 页面，不停止或重置 provider 播放会话。默认 false 的旧分支保持当前结构；Windows 入口始终 false。

## 四、接口、数据结构与所有直接调用方

只新增可选 bool 命名参数及同名字段 `mobileKeyboardLayout = false` 到公开 `VideoMusicApp`、公开 `IkDesktopWorkspace`，经私有 `_VideoHome` 传递。现有参数、返回类型、名称和缺省行为保留；不新增后台返回字段，不改错误分类、搜索提交、分页、账号、下载或播放算法。

唯一入口 `main_video.dart` 显式传 `mobileKeyboardLayout: !PlatformUtils.isDesktop`，使用现有 PlatformUtils 导入。现有 width≥720 的宽窗布局不进入此次隐藏分支。开启本票据分支不等于改变所有历史入口的键盘策略。

本轮全量直接构造调用搜索结果如下，构造定义亦列出，行号为实施前源码：

| 文件与位置 | 类型/用途 | 本次处置 |
| --- | --- | --- |
| lib/main_video.dart:367 | 唯一产品 VideoMusicApp 入口 | 仅移动平台显式开启新增可选参数。 |
| lib/video_app/video_app.dart:94 | VideoMusicApp 构造定义 | 增加默认 false 可选字段，保持现有缺省。 |
| lib/video_app/video_app.dart:258–276 | `_home` → 私有 `_VideoHome` | 显式传递新增字段。 |
| lib/video_app/video_app.dart:279–313 | 私有 `_VideoHome` 构造/字段 | 可选默认 false，向 workspace 传递。 |
| lib/video_app/video_app.dart:2772 | 唯一产品 IkDesktopWorkspace 调用 | 仅把新增开关传入外壳。 |
| lib/video_app/ik/ik_workspace.dart:10 | IkDesktopWorkspace 构造定义 | 增加默认 false 可选字段，独立 opt-in 布局。 |
| test/ik_app_integration_test.dart:268 | VideoMusicApp 正式集成门 | 原缺省调用保留，列入后续全仓回归。 |
| test/ik_semantics_tree_test.dart:379 | VideoMusicApp 正式语义树门 | 原缺省调用保留。 |
| test/ik_semantics_tree_test.dart:489 | IkDesktopWorkspace 正式语义树门 | 原缺省调用保留。 |
| test/ik_shell_alignment_test.dart:104 | IkDesktopWorkspace 对齐门 | 原缺省调用保留。 |
| test/ik_workspace_test.dart:24 | IkDesktopWorkspace workspace 门 | 原门保留；可在此既有文件追加正式 K01 系列门。 |
| lib/video_app/video_app.dart:2798；lib/video_app/ik/ik_shell.dart:8；test/ik_shell_test.dart:21 | IkShell 调用/定义/正式测试 | 本次入口不走该分支；保持既有实现。 |

`VideoShell`、Mconnect 默认入口、`IkPlaybackBar` 两个公开构造、`_workspacePlaybackBar`、`_routeContent` 和 `_pageChildren` 的 Overlay 包装均保持既有实现。实施只涉及 `lib/main_video.dart`、`lib/video_app/video_app.dart`、`lib/video_app/ik/ik_workspace.dart`、既有相关测试及本票据；额外路径需先回报范围。

## 五、验收门先行

每个门均验真实用户可见结果和实际输入/命中，不能用断言“分支条件相等”冒充几何验收。确定性门不包含大模型、真实歌曲、账号或网络。新增门是正式长期验收用例，追加在既有相关 test 文件中；不创建临时 tests 目录，不删除原有测试。

| 门 | 真实场景 | 可执行验收与当前状态 |
| --- | --- | --- |
| K01-N 原生首红 | 已核新5a5、320×640、空播放器、LatinIME输入music | 上述PNG/XML交叠且文字不可见，**已红**。Enter提交功能局部成立，体验失败。 |
| K01-D 几何与命中 | 受控 widget 窄屏320×640，输入前后注入IME inset；空播放器及有曲目两种状态 | 先在当前实现跑红，随后只入口显式启用新参数。实际输入矩形完全落在应用可用区，中心/文字区域能命中输入而非播放栏；其与显示中的播放栏不相交，文字真实保留。不能只检查无异常。 |
| K02 状态恢复 | 实际点入输入、键入music、IME关闭，再次打开/关闭 | 输入controller/焦点按操作保留，query仍music；当前页面与IndexedStack状态不丢；关闭后导航和底栏恢复可命中。若有播放会话，曲目、队列和播放状态不被此布局分支重置。 |
| K03 公开缺省兼容 | 不传新增字段、显式false、宽窗；Windows入口 | 实际布局/控件可见及操作与原门一致。wide≥720即使有受控inset也保持既有宽窗行为；Windows入口的开关为false。 |
| K04 窄屏和大字 | 320与390宽，正常及大字，IME受控非零inset | 输入可见可命中；结果区域可滚动到提示/操作；不静默截断尺寸或状态覆盖。所有执行尺寸/inset/textScaler在结果中逐项列出。受控逻辑尺寸和inset不得冒充原生截图测值。 |
| K05 搜索状态 | 同IME条件下的加载、成功、空结果、各来源可重试失败和不可重试失败 | 手动输入/提交仍可用；成功结果/空文案可见；错误message、canRetry及账号入口的既有分类与可点状态保留。需由后续相关既有门/成品复验逐项证明；本票据落盘时**未验**。 |
| K06 新原生成品复验 | 新提交、新APK核SHA；复做输入music→Enter→Back收IME→再次输入 | 采集新PNG/XML/IME字段、当前Activity及完整新PID日志。要求可见、不交叠、可提交、收起恢复；有日志错误标记需如实保留。旧5a5证据保持原红，不能混作修后绿。 |
| K07 已绿门不退 | 原稿对齐、语义边界、workspace与旧入口 | 定向门先执行；负责人收到最终源码后统一安排全仓test及成品构建。全仓结果及新成品未返回前，不宣布本票据完成验收。 |

IME=0与IME>0必须实测交替；不能只 pump 一个最终画面。命中门检查实际 RenderObject/命中结果或输入焦点操作，输入状态门检查真实 controller 文本与提交回调，恢复门检查实际导航/播放控件的可见与命中。Windows兼容门必须保留原结构语义边界，不改既有 Overlay 包装来凑门。

## 六、实施顺序与回滚

1. 本中文票据正式落盘，并保持首红证据原件。
2. 在既有 test 文件追加正式 K01-D，运行当前产品实现得到真实几何/命中红；保存完整定向输出。
3. 仅新增上述可选参数与 opt-in 分支，入口移动端显式开启；IME切换使用固定Offstage槽位保留状态。
4. 执行定向红→绿及覆盖恢复/缺省/宽窗的门，运行指定文件 format 和 analyze，逐项列出实际结果。
5. 将最终源码、定向结果和剩余未验门交负责人。全仓/构建/原生复验由负责人统一窗口接续，避免混用冻结5a5与新源码。

回滚优先只关闭 `main_video` 的新开关（传false或省略），新可选字段与独立分支可保留但不激活，立即回到旧布局。若撤回整个修复，仅撤本票据授权的新增字段传递、独立布局分支与入口开关，不删除用户原有测试/文档，不回退其他任务源码。正式新增门保留并注明回滚后对应场景为红。

不涉及数据库迁移、账号凭据、安装签名、下载文件或播放算法，布局回滚不需要更改这些数据。回滚后必须核入口参数、默认调用方、原有门与实际成品源提交，不能以“编译成功”代替恢复核对。

## 七、独立A09边界与未完成事项

验收代理另有 A09 首红：来源菜单打开并实际滚动到网易/酷狗后，Android系统Back直接finish当前Activity到QuickstepLauncher，未先关闭菜单并留在搜索。正式首红原件为 [C:/Users/Sun/Documents/Codex/2026-11-17/c-users-sun-documents-codex-2026/outputs/IK-Music-0.6.1-build12/验收证据/新成品-5a5f3d8-20261124/Android-首错A09-来源菜单系统返回退出APP.json](C:/Users/Sun/Documents/Codex/2026-11-17/c-users-sun-documents-codex-2026/outputs/IK-Music-0.6.1-build12/验收证据/新成品-5a5f3d8-20261124/Android-首错A09-来源菜单系统返回退出APP.json)，4691字节，SHA-256 `b493b7daf486c43751d24c70dfe75c2e68d567b7f4c9904c936996b139806aae`。

只读定位：紧凑搜索来源使用 `ik_search_workspace.dart:388` 的 `IkSelect`；`ik_controls.dart:36` 的 MenuAnchor 只在builder的controller上开/关（89–96），没有当前菜单开态的应用层 Android返回消费/本地历史。全lib的PopScope只见于独立source_manager与kugou_playlists路由，不保护当前搜索。该控制流与A09实测一致；此阶段未读/跑SDK源码，不将框架内部行为作额外既定事实。

A09 的独立方案、确定性首红和修后结果见[来源菜单系统返回修复票据](IK-Music-来源菜单系统返回修复票据.md)。两项修复可独立回滚。

本票据所述源码核对与固定几何属于确定性工作，无需调用Jev。本阶段未创建临时验证产物，未触碰UI/ADB/安装/音乐凭据。正式首红证据、正式票据与后续正式门长期保留；本轮或历史已拒绝清理不重试。

## 八、实施接续记录

### 2026-11-24T21:15:43+08:00：确定性门已写，首次运行在环境准备失败

正式 K01/K02 已追加到既有 `test/ik_playback_bar_test.dart`，复用原播放器/内存库/fakes，使用真实 aligned 播放栏。覆盖320/390宽、640高、字号1/1.5、空播放器/有播放会话共8个场景；每个场景均交替IME inset 248、0、320、0，检查真实输入命中、可用区边界、搜索提交、controller/IndexedStack元素和播放状态保留、导航及底栏关闭后恢复。受控inset不是原生测量值。

第一次单场景定向命令：`flutter test --no-pub -j 1 test/ik_playback_bar_test.dart --plain-name 'K01/K02 320.0x640 1.0 空播放器 输入可命中及关闭恢复' --reporter expanded`。SQLite hook 下载官方 `sqlite3-3.3.2/sqlite3.x64.windows.dll` 超时，`Building native assets failed`，测试尚未进入，**不计确定性红门**。日志正式保存为 `Android-A05-首次定向测试环境失败.log`，1761字节，SHA-256 `3c3bcf7aaade4e77638b197fc4dde512e70be0440d5f7c9233fb7866c62b31bb`，原件位于本票据上述新5a5证据根目录。原生 K01-N 首红继续成立。

本机正式构建输入 `outputs/IK-Music-构建输入/sqlite3-3.3.2/sqlite3.x64.windows.dll` 已核为1667072字节、SHA-256 `35a668f1ba0700d3ae2647f09e375bd0335a9fb43decea5fbeb742bc2657abe7`，与安装的sqlite3 3.3.2包内固定SHA完全一致。当前主仓pubspec没有hooks配置；未改pubspec、共享缓存或产品源码，先与负责人接续已批准的定向测试离线配置，再执行真正红门。

### 2026-11-24：定向红转绿与待复验项

离线 SQLite 输入就绪后，实施前的 K01-D 在 320×640、字号 1.0、空播放器场景确实失败。系统键盘受控打开后，搜索框不能命中，`hitTestable()` 找到 0 个输入框。随后新增默认 `false` 的 `mobileKeyboardLayout`，由 `main_video` 仅在非桌面平台启用。窄屏且 IME 可见时，品牌导航与播放栏暂时隐藏，键盘收起后恢复。外壳保留原来的页面与播放实例。

| 门 | 实际执行结果 |
| --- | --- |
| K01-D、K02 | **8 项通过**。320×640、390×640 各测字号 1.0 与 1.5，每个尺寸和字号分别测空播放器、有播放会话。每项交替注入逻辑 inset 248、0、320、0，验证输入矩形、命中、两次提交 `music`、输入 controller 和页面元素继续使用同一实例、播放状态不变，以及导航和播放栏恢复命中。 |
| K03 | **6 项通过**。基线高度 960、字号 1.0、空播放器、逻辑 inset 248。320 宽分别省略参数与显式关闭，720 和 1200 宽分别关闭与开启，每项播放栏维持原尺寸并随可用区域上移，导航仍可命中。Windows 禁用开关已核实到入口源码。 |
| K04 | 通过以上 320/390 宽和两档字号的输入几何与恢复门。搜索结果区域使用受控列表，实际加载、结果提示与错误操作的滚动体验仍待验。 |
| K05 | 已执行搜索提交回调。加载、成功、空结果以及所有失败分类和重试状态仍待验证。 |
| K06 | 待以新 APK 重跑原生键盘输入、提交、收起和再次输入。 |
| K07 | 播放栏测试文件 18 项、workspace 测试文件 24 项均通过，总计 **42/42**，无跳过。7 个改动 Dart 文件格式检查 0 处变化，定向静态分析 0 项问题。全仓门及新产物未执行。 |

早期 900 高矩阵运行了全部 18 项，16 项通过。720×900、字号 1.0、逻辑 IME inset 248 处，开关为 `false` 和 `true` 都出现底部 **3.0 像素 RenderFlex overflow**。此次窄屏修复范围以 `<720` 为界，720×900 已知失败原样保留。最终 K03 以 960 高基线验证兼容性，未修复 720×900 边界。

SQLite 复用第八节同版官方 DLL。定向测试期间临时附加 `test-sqlite3` 配置，`finally` 恢复 `pubspec.yaml` 原始字节。前后 SHA-256 均为 `7677e58fad5fd4dc09dcfcf112522ed4bc7c29f19440755fb3da206d9f5faed7`。正式新增门与以下日志保留于源码及前述验收证据目录。测试使用既有文件，无单独临时测试文件。

| 正式日志（验收证据目录） | 字节数 | SHA-256 |
| --- | ---: | --- |
| Android-A05-确定性K01-几何命中红门.log | 5563 | `ab42a2513789d31ddc243d34614dfb74c71f9b6c7b37b299ec2ae7382d573fe7` |
| Android-A05-定向绿门.log（早期矩阵含两项失败） | 5361 | `21ce20d6de45628806397c8bc4440139c15300c371b84364a41de01b8dec5bc9` |
| Android-A05-A09-两文件定向门.log | 8129 | `9a4b944e6605602352f92c91cd65b87df2fc19e4ae854498266551a8c2a3a13c` |
| Android-A05-A09-最终定向-format.log | 373 | `4143c5a13bc17d5a0bf3e0665dbdaaf64ef8c92af863d6dc71a1fbf3438fe76b` |
| Android-A05-A09-最终定向-analyze.log | 447 | `6b40282b2debb32fd040e49a6223d2de48ac5efbabc90b7574bbff2fe5ca08a6` |

### 2026-11-24 全仓结果

三项修复合并后的全仓测试通过，243 套、2,700 项通过、18 项沿用原跳过原因、0 项失败。全仓格式和静态分析均通过，600 项输入首尾字节一致。[全仓逐案解析回执](<C:/Users/Sun/Documents/Codex/2026-11-17/c-users-sun-documents-codex-2026/outputs/IK-Music-0.6.1-build12/验收证据/移动端修复-20261124/三项修复最终全仓/全仓逐案解析回执.json>)。

该全仓结束时，720×900 加键盘的旧边界、带真实搜索状态的键盘场景和新 Android APK 原生体验仍待验；后续新包结果见下一节，旧宽窗边界继续保留。

## 九、2026-11-25 同提交新 APK 的 K06 原生复验

产品提交固定为 `0b9561d0042784f6f37d55a49bb0b6f079ec6534`。Windows `45487177180` 与 CI `45487177064` 均从该提交首次尝试成功，各完整执行 243 套、2,700 项通过、18 项按原条件跳过、0 项失败。独立 IK Android 经真实构建前冻结、隔离 Compact＋Spatial 构建及构建后审计生成稳定签名三 ABI；本次使用 x86_64 包，实读安装 APK 为 31,822,268 字节、SHA-256 `18005b8d9375e9da05684cddf999251913d6c1ee996b6b53f7e68d3493dab749`，版本 `0.6.1 (4012)`。没有用 CI 的 Mconnect APK 替代独立产品。

在既有 Android API30 x86_64 模拟器以 `adb install -r` 覆盖。首启前 21 个用户文件共 561,431 字节保持；目录变化仅为已批准的五个空代码缓存路径及共同 `code_cache` 的修改时间。新进程 PID `13710` 的真实搜索路径完成以下动作：

| 原生动作 | 本次结果 |
| --- | --- |
| 聚焦共用搜索并打开 LatinIME | 系统 `mInputShown=true`，320×640 图像完整显示输入行与键盘；输入框 `[24,66][296,110]` 不被底栏遮住，品牌导航和底栏暂时隐藏 |
| 输入 `music` 并按系统 Enter | 实际结果标题为 `“music”的搜索结果`，键盘关闭，导航与播放栏恢复 |
| 非默认本地筛选、空态滚动、切音乐库再返回 | 查询仍为 `music`，来源仍为本地；结果标题、筛选和空态坐标与切区前一致 |
| 再次打开系统键盘，再按一次系统返回 | 只收起键盘，当前 MainActivity 保持，播放栏恢复 |

K06 在上述设备与原生场景通过，K07 的全仓门也已完成；不把这一台模拟器扩大成所有尺寸、字号、物理设备或各类在线错误的原生覆盖。K05 的真实本地空态已有新证据，所有网络成功／失败／重试分类仍按实际观察分别列明；720×900 旧边界不因本次通过而关闭。

三项原生复验共 191 条命令、382 份输出，含 39 张 PNG 和 39 份 UI 树，全部按长度和 SHA-256 核对。这是三项共用证据集，不单独计作 K06 的命令数。六份新进程分段日志未见崩溃、ANR、未处理异常或布局溢出标记。完整出处为[Android 新成品原生复验结果](<C:/Users/Sun/Documents/Codex/2026-11-17/c-users-sun-documents-codex-2026/outputs/IK-Music-0.6.1-build12/验收证据/新成品-0b9561d-20261125/Android-新成品原生复验结果.md>)、[三门完整审计](<C:/Users/Sun/Documents/Codex/2026-11-17/c-users-sun-documents-codex-2026/outputs/IK-Music-0.6.1-build12/验收证据/新成品-0b9561d-20261125/Android-原生三门完整审计.json>)与[整版验收第十三节](IK-Music-0.6.1-原稿对齐验收.md#十三0b9561d同提交构建覆盖安装与成品续验2026-11-25)。

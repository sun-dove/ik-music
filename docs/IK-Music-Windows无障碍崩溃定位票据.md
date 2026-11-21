# IK Music Windows 无障碍崩溃定位票据

日期：2026-11-21。关联用户已授权的原稿对齐、播放详情优化、打包与发布任务。当前0.6.1源码候选为`84308f067a5a4498b91f20639a1977615edf2f58`，两构建流程及完整回归已绿；实际Windows安装验收发现原生崩溃，公开发行须等待本票据的实际体验门。

## 问题与已确认事实

Windows正式包已同目录升级至`D:/Applications/ik-music`，68个安装文件与完整清单一致；首次启动前18个用户数据文件与保护副本全部字节一致。正常启动后，无界面查询的50.3秒观察全程存活。读取窗口画面与辅助信息后，窗口曾退出；首次仅截图观察后也复现窗口不可用，不能归因于一次点击。

系统WER事件确认`yueyin_music.exe 0.6.1.12`在`flutter_windows.dll`中出现`0xc0000005`，RVA`0x3c16a`。同次stderr出现`accessibility_bridge.cc:114`的AXTree孤立节点错误。新旧0.6.0/0.6.1引擎DLL相同，SHA-256为`8BD7B61EEE31AA436EDB182DB41624D1CD3B2688A7E03622320DBEAE067B5251`；历史0.6.0也有同模块和RVA报告，因此没有证据表明本轮升级了引擎。

真实LLDB在正式安装EXE中捕获`0xc0000005`：RVA`0x3c16a`执行`movl 0x48(%rax), %eax`，`rax=0`，读取地址`0x48`。匹配的官方PDB与冻结DLL CodeView均为GUID`B396A1FA-F00B-4C1D-975F-B5E84FD5A4AE`、Age1；符号定位为内联`ui::AXNode::id()`（`ax_node.h:110`），调用点`AccessibilityBridge::CreateRemoveReparentedNodesUpdate`（`accessibility_bridge.cc:229`）。空父节点解引用已由真实寄存器和匹配符号确认；造成无效语义输入的具体产品控件仍需红门定位，不能把上游纯控件复现当作正式装配因果证明。原始55帧与寄存器保存于正式证据`Windows真实LLDB异常栈.log`，未取得内存转储。

精确SDK为Flutter3.47.5、framework`6a19cca56475dbfba1478ee68d7bd0c2ef891da1`、engine`af7e796e161ae0bb1ff0758c71a7105418bd9ded`。产品根Router、GlobalKey、IndexedStack与旧版相同，没有发现重复key。

## 真实场景与验收门

- 场景W-A11Y-01：使用屏幕阅读器或系统UI Automation后，五个主区继续显示、导航与操作。体验门要求窗口保持可用、所有导航名称与按钮动作可读，不能关闭全局无障碍来通过。
- 场景W-A11Y-02：鼠标提示浮层出现、消失及滚动后，语义树仍有唯一根。确定性门捕获真实Flutter发给引擎的每批语义更新，验证节点有父、根不成为其他节点的子节点、引用完整、被移除的提示不留下孤立节点；全批次执行，不抽样。
- 场景W-A11Y-03：未启用对齐分支的旧入口保持原公开接口与缺省行为；新版视觉布局和全部已绿回归保持。

先建立可重复红门，确认缺陷涉及产品语义结构后才实施最小修正；SDK或工具触发条件仅有相关性时继续调查，不用猜测修改控件。

## 最小修改与兼容边界

这是安装验收中的简单稳定性缺陷，优先沿用现有可选对齐分支增加必要语义边界，不新增模块或架构。用户已明确授权继续本版改版、修复、打包与发布。若事实要求修改生产路径，必须在本票据追加实际原因、全部调用方与回滚，再实施已授权范围；未经确认不升级SDK、不替换引擎、不禁用或删除全局Semantics。

已知受影响调用方：独立`main_video.dart` → `VideoMusicApp` → `IkDesktopWorkspace`；工作区导航及首页/播放栏已有Tooltip；旧`VideoShell`和原Mconnect入口保留。其他可能受影响控件须在定位后完整补充。

### 已确认输入与候选修复（2026-11-22）

独立语义更新builder在真实`VideoMusicApp`、Router、`WindowsAppearance`、真实五页装配中复现：有当前歌曲、推荐已加载、搜索导航提示显示后迟启无障碍，首批61个新节点包含7个没有任何遍历父引用的孤立节点。逐个`childIdentifier`与父标记映射确认，7个节点均来自当前未显示的`IkSettingsWorkspace`音频页：2个横向Slider和5个均衡器Slider。搜索导航提示自身正确挂在导航节点，不能用本事实支持修改导航。

正式安装程序在Windows语义回调入口的全部原始节点记录交叉确认：首批53个节点包含同型7个孤立节点，根0遍历其余节点完整；全部节点记录，无抽样。`Node2`共用child_count只提供遍历数组长度，命中测试数组在本SDK可具有不同实际长度，不能把其尾部内存当作有效节点。Windows桥只复制遍历数组，本票据的主图判定依据遍历父引用。

SDK的`RenderIndexedStack.visitChildrenForSemantics`只访问当前页；Slider的ValueIndicator `OverlayPortalController`在构造时常驻show，OverlayPortal默认把浮层注册到最近Overlay。隐藏设置页仍保留状态，其Slider浮层跨过IndexedStack注册到根路由Overlay，父Slider语义节点没有参与当前页，而浮层被根Overlay访问，造成孤立输入。

这是既有布局的安装验收缺陷，设计比较在实施前记录如下，沿用用户已明确授权的本版改版、稳定性修复与发布范围：

| 方案 | 行为与代价 |
| --- | --- |
| 为隐藏页加Offstage或TickerMode | 可以隐藏普通页面或暂停动画，但浮层已经注册到外层路由Overlay，无法为跨层浮层提供随页隐藏的生命周期；不作为修复依据。 |
| 新对齐分支每页增加稳定的本页Overlay | 最近Overlay和浮层均处于相同IndexedStack子树；只让当前页的语义树参与系统更新，保留五页State、输入、滚动位置；无需禁用无障碍或改SDK。推荐。 |

最小接口设计：`IkDesktopWorkspace`公开构造、返回类型、`alignToDesign=false`默认路径不变；新增私有页面装配方法，只在已启用的对齐分支给每页添加`Overlay.wrap`和按页序号稳定的Key。数据结构与所有业务回调保持。浮层默认仍查找最近Overlay；路由对话框继续用Navigator的根Overlay。

完整受影响调用方为：`main_video.dart`启用的`VideoMusicApp` → `_VideoHomeState.build` → `IkDesktopWorkspace`中的发现`IkHomePage`、搜索`IkSearchWorkspace`、曲库`IkLibraryWorkspace`、最近播放`IkRecentPage`、设置`IkSettingsWorkspace`。页内Tooltip、Slider ValueIndicator、MenuAnchor改为本页最近Overlay；共用顶栏及底部`IkPlaybackBar`不在此包装内。独立播放器、下载详情和原Mconnect/旧VideoShell不使用该私有方法。真实根、默认分支和已有装配门须覆盖这些调用方。

实现顺序：保留首批红证据 → 新增局部Overlay → 真实首批红转绿 → 完整页面切换、hover、滚动、设置区和返回状态门 → 既有兼容/视觉/完整回归 → 从修复提交重建Windows和三ABI → 同目录升级与原生辅助读取体验门 → 发布。若局部Overlay仍出现孤立节点则继续定位，不把候选修复写成完成。

体验验收补充：搜索文本和结果、设置区选择、各页ScrollableState在来回切换后保持；可见页Tooltip和下拉仍正确显示，隐藏页浮层不能被访问；首批及所有后续增量保持唯一根、完整父引用。回滚新增私有方法即可恢复冻结布局；正式0.6.0安装器、升级保护和修复前候选保留。无需改已安装数据、签名或安装身份。

源码核对后已实施私有`_pageChildren()`：对齐分支每页稳定`Overlay.wrap`，`clipBehavior: Clip.none`保持提示和菜单向页边缘扩展；默认直接返回原`pages`。目前仅为待验收修复，须以红门转绿和原生成品结果确认。

### 路由进入期间的第二个真实场景

局部页面Overlay使首批7个隐藏Slider节点消失，五个主区与全部设置区的语义流程通过；继续进入真实`/player`时，新路由过渡首批出现3个新的孤立Slider浮层。通过同一identifier映射，分别为`WindowsPlayerPage`内的底部进度`ik-bar-seek`、音量`ik-bar-volume`、歌词字号`ik-player-lyrics-size`。它们属于正在进入的新页面，不能把此红门归到旧首页或导航提示，也不能计入后续已坏图造成的级联错误。

场景W-A11Y-04：在无障碍开启时进入/返回播放详情和其他详情页，路由动画首帧到稳定帧、页面被遮挡期间均不能提交没有锚点的浮层。体验门要求转场保持、播放器控制和歌词字号可读可用、页面返回后恢复原输入/滚动；功能门捕获所有真实语义批次及其新增节点。已有真实根首次完整流程日志保留本场景红。

方案比较：只包装旧首页不能阻断新播放器浮层；只给某个Slider增加Semantics边界不能让被转场隐藏的父参与访问。推荐将**整个单路由内容**的最近Overlay留在该路由子树内，和每个IndexedStack页内Overlay一起解决两个可见性层次。继续使用原GoRouter和转场；不修改`createIkRouter`公开签名、不关闭动画或无障碍。

新增私有`_routeContent(Widget page)`仅当`widget.workspace && widget.alignToDesign`时返回稳定`Overlay.wrap(clipBehavior: Clip.none)`，缺省直接返回原Widget。完整接入点在`_VideoMusicAppState`已有三个builder：home、独立player、detailShell。`createIkRouter`中的首页、`/player`和全部经detailShell的目录/个人数据/下载/设置/账号/平台详情路由均覆盖；未知路由的`IkRouteError`只有普通文本及按钮，无常驻Slider，不改变其错误行为。回滚同时去除这三个局部包装即可恢复冻结实现；公开Router与业务字段、原入口保持。

先保留第二场景红和标记定位，再实施上述路由内容包装；完整根流程、默认分支、原路由门、全部36布局/视觉以及全回归重新验收。最终产物须来自包含两处修复的同一提交。

### 歌词字号嵌套提示的第三个真实断口

两层局部Overlay落盘后，校准后的真实应用首个完整场景已执行1981批：五个主区、状态往返和设置七个Slider真实操作均没有树错误。进入`/player`的第1989批仍出现一个新增孤点1606；其`childIdentity`逐项与Widget标记比较，唯一对应`ik-player-lyrics-size`。新播放栏进度和音量的浮层已经正确挂接。字号Slider的锚点没有独立节点，而可动作字号节点1580挂在Tooltip节点1579上；Tooltip自身与Slider各有一组OverlayPortal遍历标记，合并边界未保留Slider的父标记。正式红证据为`Windows无障碍-路由Overlay根首验夹具校准后.log`，本次按第一次无效批次立即失败，未把后续级联错误累计为缺陷数量。

场景W-A11Y-05：进入播放详情、显示或隐藏“歌词字号”提示、拖动或以辅助动作调整字号时，Slider值、增加/减少动作和提示均可读；Tooltip与Slider浮层分别具有有效锚点，全部真实语义批次通过。体验门要求原字号范围、歌词跟随和空歌词禁用行为保持，功能门同时核验语义动作与控件状态。

| 方案 | 行为与代价 |
| --- | --- |
| 修改SDK的遍历标记合并规则 | 影响全部控件和平台，需要独立引擎验证与重建；超出这次产品稳定性缺陷的最小范围。 |
| 为已定位的对齐版字号Slider增加独立Semantics容器 | 将Slider的锚点与外层Tooltip锚点分开，保留原提示、动作、范围、回调和视觉；只修正已证实的嵌套边界。推荐。 |

最小实现是在`WindowsPlayerPage._alignedLyricsPane`中保留外层Tooltip，把其原Slider包装于`Semantics(container: true)`。这是已有对齐分支的私有布局方法，不改变公开构造、方法签名、路由、Slider字段或数据格式。生产调用方只有`VideoMusicApp._playerPage`；私有方法由对齐版宽、窄布局调用，旧播放器默认分支不经过该方法。直接测试构造调用完整位于`ik_player_alignment_test.dart`、`ik_source_card_test.dart`、`windows_music_theme_test.dart`和`windows_music_ui_test.dart`，真实根装配门经生产factory创建播放器。回滚只移除这一个Semantics包装，并重新验收相关场景；用户已授权的本版稳定性修复、打包与发布覆盖此最小缺陷修正。

实施顺序：保存精确红批次和marker映射 → 增加独立容器 → 首场景完整绿 → 有歌/无歌与四个迟启位置全部八配置 → 默认分支、布局、截图和完整回归 → 从同一修复提交重建并验收两平台成品。当前仍为待验收候选，不以控件包装本身声称问题已经解决。

### 完整确定性门实际结果

三处最小修复后的首个完整真实根场景通过2326批语义更新，歌词字号22→26时显示字体与语义值一致，提示悬停/移除、播放器进入/返回、设置详情和待播放浮层均通过。完整文件随后实际执行14个案例，全部通过，累计19,317批、0树错误，306.3秒、退出0；八个真实根配置覆盖有歌/空PlayerState与搜索导航、无悬停、导航、播放栏上一首四个迟启位置，另六个案例覆盖真实播放栏与工作区/默认分支兼容。全部批次及每批全部节点检查，没有抽样。

八个真实根的最后累计批数依次为有歌2326/2265/2265/2267、空状态2049/2048/2046/2048；六个前置门为41/44/462/474/491/491。正式原始日志和逐案汇总为`Windows无障碍-三处修复14场景套件数据库校准后.log`、`Windows无障碍-三处修复正式14场景验收.json`。夹具校准保留历史：读取Slider/Tooltip真实子节点、将两种Hive保存置于真实IO区、在整个文件中只初始化一次真实内存SQLite并逐案清空全部表；这些是测试环境修正，没有增加产品reset、删除断言或跳过七个未进入场景的配置。

本机静态收口仅删除新测试的冗余`dart:typed_data`导入和格式化本页Overlay私有方法，测试正文及产品行为未改；原始门日志对应的文件哈希继续保留，冻结源码另记录最终哈希，最终Linux/Windows完整回归须重新执行这14个案例。完整格式检查576文件0变化，静态复验0问题。此图不变量检查器不模拟Windows AX的精确更新/删除顺序，也不代表真实原生UIA、音频DSP、账号、全部菜单或第三方曲目已验收；成品辅助操作与新提交构建仍是发布前必需门。

回滚：候选产品代码仍冻结在`84308f0`，正式旧0.6.0安装器及两平台升级保护保留。未公开0.6.1；如新增语义适配，保留可选缺省及独立提交以便回退，重新运行全部受影响门并从修正提交重建，不能修改已签名APK或把旧构建冒充新实现。

原始日志、事件与反汇编记录保存在本会话`outputs/IK-Music-0.6.1-build12/验收证据`。用户数据、WER私人内容和认证值不上传GitHub。

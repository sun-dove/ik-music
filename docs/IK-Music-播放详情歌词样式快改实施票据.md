# IK Music 播放详情与歌词样式快改实施票据

## 已确认场景与授权

用户已接受快速界面稿并要求继续实现，当前要求先看效果，本轮不执行测试、分析、格式检查、构建或安装。播放详情的现有留白和信息比例影响阅读，新候选调整左右占比、歌词居中，并加入用户可自行调节的字体、字号、背景、当前行颜色、其它行颜色和阴影。

主任务负责新增偏好模型与持久化、共享样式面板及产品装配；本子任务只修改 `lib/video_app/windows/windows_player_page.dart`，不修改歌词解析、播放控制、AX修复或其它页面。

## 方案与范围

用户最新截图明确指出：右上角按钮打开左侧替换面板，操作位置过远。方案一维持左侧替换会保留这个问题；方案二将样式编辑锚定在右上按钮旁，保留封面和歌词正文，按用户修正采用方案二。新增 `refinedLayout = false`、`IkPlayerLyricsPreferences? lyricsPreferences`、`List<String> systemFonts = const []` 三个可选参数，缺省仍使用原页面行为。

只在refinedLayout开启时使用现有紧凑页面的FittedBox和Overlay退场保护；最大内容宽度1460，宽屏左侧35%、歌词65%，封面最大320并适应可用高度。歌词行全宽且居中，自动滚动对齐中心；其余歌词手动浏览、点击定位、键盘操作、翻译及三秒自动恢复逻辑保留。

偏好通过ChangeNotifier监听，首次字号使用已存值或22；空字体和颜色回退当前主题。样式面板仍复用主任务提供的保存与重置入口，不直接读写其它配置。外壳使用Flutter原生RawMenuAnchor及现代Material样式，局部Overlay内定位；现字体选择器是Material MenuAnchor，因此外壳不再加入另一层Material菜单根，避免字体选择把整个样式编辑面板关闭。面板宽高受本页Overlay尺寸约束，内部可滚动，外点及Esc关闭。旧默认不读取偏好、不改变布局。

## 调用方与回滚

生产调用由 `video_app.dart` 中 `_playerPage` 创建WindowsPlayerPage，主任务在独立新版入口传参；既有直接测试或其它构造方不传新参数时保持原路径。公开既有参数、方法和返回类型不变，新增参数均可选。

回滚先撤 `refinedLayout` 接线恢复旧布局；必要时移除本文件新增分支和监听代码，保留用户已保存的偏好，不删用户数据。不动既有紧凑布局的退场保护和自动跟随时序。

## 待执行门规格

本轮按用户指令只实现，不执行这些门，不宣称验证通过。

1. 宽屏、窄屏、低高度及大字模式下封面和歌词正文保持原布局，面板位于右上按钮旁，边界不超视窗且可滚动；点外、Esc或关闭按钮能关闭，字体选择、滑块和色块操作不会误关整个面板。
2. 字体、字号、背景、两类歌词颜色和阴影实时反映；关闭页面再进入能恢复偏好；重置回主题默认。
3. 手动浏览后无操作三秒回当前行中央；连续滚动、拖动或按键期间不抢回；点击歌词定位、翻译和键盘浏览保持可用。
4. 返回或连续路由时保留原FittedBox/Overlay保护，无布局溢出或语义孤点；默认false的旧入口行为不变。

## 快速候选实施状态

三个可选参数及refinedLayout分支已落盘，并已由主任务接入本轮主入口。新分支保留原紧凑页FittedBox、Overlay和退场尺寸缓存，宽屏改为1460／35:65／封面最大320；窄屏仍在上下区域内分配高度。当前按用户新修正移除左侧封面替换分支，顶栏“歌词样式”改为就近锚定面板；关闭面板不会改变左侧内容或滚动位置。

已按主任务签名接入 `IkLyricsStylePanel` 和 `IkPlayerLyricsPreferences`，监听注册／替换／销毁随页面生命周期处理；保存、重置时显示busy并禁用面板操作，捕获保存失败反馈，显示值以偏好成功通知为准。歌词使用可选字体、背景、当前行色、其它行色及阴影，文字全宽居中，ensureVisible仅新分支使用0.5对齐。

按本轮指令没有运行测试、分析、格式检查、成品构建或安装。当前是供用户查看的快速候选，尚无本分支的执行验证结论。

最新修正的改动范围仅为WindowsPlayerPage的样式面板外壳、共享关闭提示文案和本票据；不改发现推荐、桌面歌词原生实现、偏好模型或公共选择器。面板当前最大宽364、最大高620，按所在局部Overlay尺寸缩小并在内部滚动；顶部工具在窄宽度下可换行。关闭文案改为“关闭样式面板”，封面不再被替换，也不因开关样式而复位左栏滚动。

主任务另明确授权新增 `VoidCallback? onFloatingLyricsSettings`，默认null保持旧行为；新播放详情的桌面歌词开关旁显示“桌面歌词设置”，主任务负责接到 `/settings/lyrics`。该入口只触发既有页面导航，不在本文件实现桌面原生行为。

回滚可仅恢复旧面板外壳或撤新增可选回调接线，原布局、歌词计时与已保存偏好不受影响。本子任务不提交，不执行工具验证；主任务后续编译快速预览不代表恢复测试或原生验收授权，验证继续暂停，等待用户明确恢复。

## 嵌套字体菜单点击分组的源码核对

主任务提出字体菜单在另一层Overlay绘制时是否会被外层误判为outside。仅阅读当前Flutter SDK后，现实现无需更改点击处理：`OverlayPortal` 保留其锚点的InheritedWidget上下文；内层Material MenuAnchor所创建的RawMenuAnchor通过 `_MenuControllerScope` 找到外层RawMenuAnchor并登记父子关系。Raw层计算 `RawMenuOverlayInfo.tapRegionGroupId` 使用 `root.menuController`，所以外层自定义TapRegion与字体下拉的 `_Submenu` TapRegion使用同一groupId；`RenderTapRegionSurface._classifyRegions` 将命中的同组全部区域视为inside，不调用外层outside回调。

字体菜单项的关闭路径另属Material层：`MenuItemButton._handleSelect` 查找Material `_MenuAnchorScope` 的root。外层只有RawMenuAnchor，没有Material菜单scope，因此Material root仍是字体下拉自身；选项点击仅关闭该下拉，不关闭外层Raw面板。未改公共选择器、未增加额外分组绕过或放宽关闭行为。上述为源码设计核对，不是运行结果；仍未执行测试、分析、格式检查、GUI、构建或安装验证。

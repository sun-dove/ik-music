# IK Music 桌面歌词轻量改版设计

日期：2026-11-26。状态：**用户已接受快速稿并明确“好吧那继续”；进入产品快速候选实现，按用户要求暂不验证**。

本稿回应用户对 Windows 桌面歌词粗糙、黑色“移／X”按钮和排版的反馈，并参考 LX Music Desktop 官方公开实现。用户本轮已表达六项可现场调整的需求：**字体、字号、底色、当前行色、其他行色、阴影**。这些需求先纳入交互预览，确认后进入本轮候选代码；它们在快速稿中可调、候选代码中已接入，不代表已安装产品已包含这些改动或原生效果已经验证。

快速稿已获用户接受，本轮按推荐方案 B 接入系统字体、字号、底色／透明、当前行色、其他行色、阴影，以及 hover 工具栏、锁定穿透和主设置解锁。工具栏位于正文外侧，出现时保持正文的屏幕位置。字体只使用系统已有候选，不下载或引入字体包。用户明确要求先产品候选且暂停验证，因此本轮不运行测试、静态分析、编译或 GUI 验证；下方已写门保留，执行延后，不得称为已验收完成。

生产接入采取独立 `CompactFloatingLyricsWindow` 和 IK 专用请求适配器，旧 GDI 窗口与共享服务公开方法保留。样式存独立可选偏好，缺省回退原字号与颜色，仅 `main_video.dart` 的 Windows 入口显式开启新版。涉及的调用方与回滚范围见第六节；本轮是用户确认后的实现，不把未验证候选描述成可发布成品。

新增适配器需要在 `FloatingLyricsService` 自身库中增加 `withPayloadAdapter` 工厂与内部委托实现。原因是现服务私有构造和私有成员使外部直接继承／实现不适合作为稳定的强类型适配点；新增工厂可共用 singleton 的事件流，避免第二个 channel handler 覆盖原回调。旧 singleton、show/update/hide 签名、默认 payload 和返回行为原样保留。旧直接调用方包括通用歌词 notifier、同步 controller、SettingsFloatingLyricsPage；它们继续使用原 instance。只有 IK 的新 service provider 使用工厂，IK strict action 和备用歌词页从该 provider 读取。回滚关闭 IK 可选入口即可回 instance，无需改旧调用或迁移数据。

## 一、背景与目标

目前 Windows 歌词已具备置顶、当前句、翻译、下一句、高亮、字号颜色、拖动、缩放、锁定和关闭事件。底层仍是 GDI 色键透明，文字固定黑描边；两个黑色文字按钮常驻，顶部固定留出控制区，压缩了正文空间。默认窗口高度下，翻译存在时下一句可能没有空间。

设置中的普通 Text 预览也不反映真实窗口的描边、行数和控制区，因此用户无法凭预览判断最终效果。

截图里的白色区域原因尚未确定。现代码使用 RGB(1,1,1) 色键透明，并非明确绘制白底；它可能来自底层窗口，也可能是实际透明合成异常。必须在真实 Windows 浅色、深色、复杂背景分别验证，不能仅凭截图把白底归因于某一行代码。

目标：让歌词本身占据视觉中心，控制按需出现；副行清楚且紧凑；锁定真正允许操作下层窗口；设置预览能解释实际呈现；原有播放、歌词校准和用户偏好保持兼容。范围限于 IK Windows 桌面歌词，不改播放器架构、不新增歌词来源、不引入 Electron 或额外 WebView 运行时。

## 二、方案对比

| 项目 | 方案 A：现 GDI 小修 | 方案 B：原生逐像素透明呈现（推荐） |
| --- | --- | --- |
| 改变 | 换小图标、hover 工具栏、缩减空白、统一主副行 | 同 A，加抗锯齿文字、柔和阴影、低透明圆角背景和连续裁剪扫色 |
| 绘制方式 | 保留 BitBlt + LWA_COLORKEY | 新原生路径以系统 GDI+ 或等价系统 API 绘制 32 位预乘 alpha 位图，再 UpdateLayeredWindow |
| 优点 | 代码改动少、验证范围较窄 | 能直接解决文字粗边与浮窗粗糙感，真实半透明与预览更容易一致 |
| 局限 | 透明硬边、固定描边仍限制观感；难以形成柔和背景 | 需要更多原生绘制、DPI、命中与穿透验收 |
| 兼容 | 新标记只开启新布局，缺省旧样式 | 新增明确的呈现路径，IK Windows 显式选择；旧 Show/Update 和旧 GDI 路径保留 |
| 包体 | 沿用当前依赖 | 使用 Windows 系统库，无新增打包运行时；最终报告实测包体差值 |

推荐 B，因为反馈针对完整的浮窗观感，只调整两个按钮仍会保留最明显的粗黑描边和硬透明边缘。实现需限制为小型原生浮窗，不照搬 LX 的完整滚动歌词、多项高级设置和音频可视化。

## 三、交互稿：用户看到什么

以下尺寸为逻辑设计目标，落地时按实际 DPI 测量，不能把逻辑像素直接当固定物理像素。

### 3.1 阅读状态

- 未操作时只显示“当前句 + 一个副行”，工具栏隐藏，顶部不永久空出 24px 按钮区。
- 当前句初始沿用原有字号和文字／高亮色；快速稿允许现场调整字体、字号、当前行色、其他行色和阴影，副行约为主行字号的 72%–78%。最终产品接入时保留旧用户偏好，不因预览换色重置原数据。
- 副行采用自动规则：当前有译文时显示译文；没有译文时显示下一句；末行没有副文本时只显示当前句。不强塞第三行。
- 未锁定时，使用可调整底色的轻圆角背景，移入时适度加深。快速稿展示底色变化；真实原生实现仍需保证完整区域可被鼠标命中。锁定后背景收起，只保留歌词。
- 保留用户已有窗口大小。新布局适配其尺寸；调整字号到当前高度放不下时，先去掉副行，再保证当前句完整可读，禁止出现半行文字。
- 长行沿用明确的滚动阅读行为；新绘制若实现连续扫色，必须与滚动偏移共用同一几何坐标，不能出现高亮与正文分离。

### 3.2 鼠标移入

窗口边缘出现一条紧凑工具栏，最多五项：**上一首、播放／暂停、下一首、锁定、关闭**。图标统一线宽与尺寸，有清楚的悬停反馈和名称提示；不再使用“移”“X”文字黑块。按钮有效点击区按至少 28×28 逻辑像素设计。

工具栏按已有窗口可用宽度排列；固定当前句位置，不因 hover 出现而让正文上下跳动。非按钮区域可以拖动，角部可以缩放。鼠标离开后收起工具栏；按住拖动或缩放期间保持操作状态，释放后再按实际鼠标位置决定是否收起。

未加载歌曲时，三个播放按钮显示禁用态，不能产生播放事件；锁定与关闭仍可用。窗口透明空白也能稳定唤出工具栏，不能要求用户恰好碰到某个文字笔画。

### 3.3 锁定、穿透与解锁

点击锁定后隐藏工具栏，停止拖动／缩放，并让整个歌词窗口鼠标穿透。鼠标点击应落到下层真实窗口。

解锁入口明确保留在主窗口的“设置 → 桌面歌词 → 锁定歌词”开关，提示为“锁定后可点击歌词下方窗口，在这里关闭锁定即可调整”。主窗口开关解除后，歌词立即恢复命中与 hover 控件。

不在穿透窗口内部另放一个声称可点的解锁按钮。两种点击状态应明确分开：

| 状态 | 点击应该到哪里 | 禁止出现的情况 |
| --- | --- | --- |
| 未锁定，点击工具栏 | 当前工具栏按钮，且只触发一次 | 点击按钮同时误触下层窗口 |
| 未锁定，工具栏已隐藏 | 非按钮区域的拖动／阅读区域 | 隐藏按钮保留旧热区，点击后意外切歌或关闭 |
| 已锁定 | 下层窗口 | 歌词仍挡住点击，或存在无法解释的局部可点区域 |
| 主窗口解除锁定 | 歌词恢复可交互 | 看起来解锁了但仍不可点击，或只能重开程序恢复 |

### 3.4 无歌词、暂停、关闭与重启

- 有歌曲但没有歌词：显示“暂无歌词”，副行显示当前曲名；播放按钮仍对应真实播放器状态。
- 没有歌曲：显示“播放歌曲后显示歌词”，不虚构歌词和播放状态；三个播放按钮禁用。
- 暂停时保持当前句，停止扫色，播放按钮变为继续播放；不额外加入自动隐藏选项。
- 点击关闭后同步关闭主窗口开关，并先停止同步定时器。后续切歌、播放状态变化、歌词网络返回都不能把窗口重新弹出。
- 下次启动：原偏好为关闭时不创建窗口；原偏好为开启时，在同步可用后恢复窗口；没有歌词先用上述空态。原偏好已锁定时保留锁定，主窗口的解锁入口必须立即可达。
- 新呈现创建失败时，主界面显示原生显示失败并提供重试，不能只把开关设成开启。保存失败沿用既有回滚顺序。

### 3.5 设置页

本轮快速稿在预览旁提供六项现场调整，操作后立即改变稿内效果：

| 已表达的需求 | 快速稿呈现与边界 |
| --- | --- |
| 字体 | 只列系统已有字体候选；缺失候选回退到系统字体。没有字体下载、导入或随包字体 |
| 字号 | 即时改变歌词字号，同时展示主副行比例与空间变化 |
| 底色 | 即时调整歌词浮窗背景色，便于在示例背景上比较效果 |
| 当前行色 | 即时调整正在演唱的主行颜色 |
| 其他行色 | 即时调整译文／下一句等非当前行颜色，与当前行区分 |
| 阴影 | 现场调整阴影效果，观察文字边缘和可读性 |

阅读、hover、锁定和无歌词状态仍由同一套样式驱动。快速稿中的播放、锁定和关闭只用于演示交互，不操作真实播放器或原生窗口；现场选择也不写入已安装应用设置。

本轮快速候选已将六项设置对应到独立样式偏好和原生请求，设置页接线由主任务同步完成，保留开关与锁定入口。原生必须实际收到样式变化，设置预览与真实窗口使用一致语义；目前没有编译、测试或实机验证，不能把代码已接入或网页可调当成产品完成。

自动副行规则仍保持本稿约定；本轮不增加位置坐标编辑、竖排、音频可视化或全歌词滚动。字体范围限系统已有候选，不引入字体包。

## 四、已有能力与可复用接口

| 能力 | 现状 | 本轮处理 |
| --- | --- | --- |
| 当前句、译文、下一句与歌词偏移 | FloatingLyricsPayload / FloatingLyricsSyncController 已提供 | 继续沿用，改呈现布局 |
| 播放控制 | Dart 已解析 controlRequested，接 playPause / previous / next；Windows 尚未发送 | Windows 工具栏按现事件格式补齐，不另造播放接口 |
| 开关失败反馈 | IK strict action 原生成功后保存，保存失败回滚 | 原样保留，在新呈现路径继续使用 |
| 原生关闭、锁定、尺寸事件 | closedByUser / lockChanged / windowResized 已接通 | 名称、参数类型和关闭顺序不变 |
| 字号、颜色 | 既有 settings 和 Hive 保存 | 保留用户原值，不强制换成新默认配色 |
| 背景、描边、阴影字段 | Dart 已有，Windows 当前没有应用 | 仅新样式赋予明确视觉效果，不能改变旧 Windows 缺省行为 |
| 位置 | Windows 只维持当前会话位置；Android 有单一 positionY 事件 | 本轮保留现能力，不借此次美化改写 Android 事件或新增跨屏位置持久化 |

当前原生文字高亮是整字符前缀，且 marquee 时关闭高亮。Dart 注释写有连续扫色，不能据此宣称 Windows 已完成。新呈现如实现连续裁剪，必须另有进度／暂停／长行的红绿门。

## 五、接口与数据结构：默认旧行为

既有 `FloatingLyricsService.show(payload, settings)`、`update(payload, settings)`、`hide()` 及 C++ `FloatingLyricsWindow::Show/Update` 签名保持不变。Channel 仍用 `com.mconnect.mconnect/floating_lyrics`；用户数据位置、旧方法、事件和既有设置键不改名。

建议新增可空请求配置 `windowsPresentation`；没有该字段时，不序列化新键，完全采用旧 GDI 呈现。IK Windows 独立入口显式设置该字段，Mconnect 和 Android 入口缺省不设置。它代表入口的呈现选择，不是只要读到共用 Hive 设置便自动启用的新全局开关。

入口选择与用户偏好应分开：颜色、字号、锁定等继续使用原设置；新呈现选择由 IK Windows 的显式装配决定。若后续需要持久化新样式的子偏好，可以新增可空字段，但向原生发送时仍由入口选择限制。这样旧 Mconnect 即使读取同一个设置文件，也不会继承 IK 新呈现。具体可通过新的配置适配器／可选构造入口完成，既有公开 show/update 签名不改。

本轮候选的请求结构：

```text
windowsPresentation: null | {
  version: 1,
  style: "compact",
  fontFamily: "Microsoft YaHei UI",
  fontSize: 23,
  backgroundColor: ARGB,
  currentLineColor: ARGB,
  otherLineColor: ARGB,
  shadowOpacity: 0.78,
  currentLineColorExplicit: false
}
```

整个配置可选，由 IK 专用适配器发送；未知版本或缺失字段的旧请求继续旧 GDI 路径。副行自动选择、锁定穿透按已确认规则实现，不增加无 UI 用途的开关。`currentLineColorExplicit=false` 时保留用户原有文字色到高亮色的扫色；用户显式选择当前行色后，当前行使用该实色。所有样式覆盖存入独立 Hive 键 `ik_windows_desktop_lyrics_style_v1`，缺省仍回退原 FloatingLyricsSettings。

为兼容旧调用，代码应新增选择器／新配置方法／新窗口类，而不是改旧方法签名或直接替换旧实现。旧请求即使发生在一次新样式请求之后，也应明确重新选择旧路径，避免对象缓存导致旧调用继承新版样式。

已有 `backgroundColor`、`strokeWidth`、`shadowOpacity`、`fontSize`、`textColor`、`highlightColor` 按原语义复用，不重定义旧字段。新字体缺省仍使用旧字体，新行色缺省回退旧配色。IK 样式 provider 在样式改变时独立重送最近 payload，避开旧同步 controller 的去重签名而不修改它；关闭事件清除待重送 payload，原生关闭锁存阻止延迟 update 复活，显式 show 才重新开启。

逐像素透明需要独立创建流程或明确重建窗口。不能在旧 `SetLayeredWindowAttributes` 之后直接混用 UpdateLayeredWindow，并假定它一定工作。创建／恢复失败都要向 strict action 回报失败。

## 六、生产落点、影响调用方与回滚

| 落点 | 必要改动与影响 |
| --- | --- |
| windows/runner 新紧凑歌词窗口文件，或 floating_lyrics_window 的新增呈现实现 | 新绘制与输入状态；旧公开 Show/Update 及 GDI 路径保留 |
| windows/runner/floating_lyrics_channel.cpp | 可选样式解析、窗口选择、播放事件参数；所有相同通道调用都必须缺省兼容 |
| windows/runner/CMakeLists.txt | 添加必需的原生文件／Windows 系统库；没有新打包运行时 |
| lib/features/floating_lyrics/data/floating_lyrics_models.dart，或新增 IK 配置适配器 | 可空请求配置与必要的 JSON 增量扩展；入口选择不作为共用设置自动启用；旧 JSON 往返保持 |
| lib/features/floating_lyrics/presentation/providers/floating_lyrics_provider.dart | 新样式去重与状态送达；原同步、关闭、校准行为保持 |
| lib/main_video.dart；lib/video_app/ik/ik_lyrics_action.dart、ik_floating_lyrics.dart、ik_runtime.dart | IK Windows 显式选新呈现；严格开启、首次同步、旧路由备用入口必须一致 |
| lib/video_app/ik/ik_settings_workspace.dart | 实际设置入口、真实版式预览、锁定解锁说明 |

已查明 `floating_lyrics_channel.cpp` 是原生 Show/Update 的唯一直接调用方。Dart 侧旧入口 `lib/app.dart` 使用普通同步 provider；IK 入口使用 `ikFloatingSyncProvider`，还有 strict action 和旧备用页的直接 show。不能仅改其中一个 show 就宣称所有入口一致。

原通用 `SettingsFloatingLyricsPage` 与 Android 既有布局不属于本次视觉替换范围。新增可选字段不得改变它们的缺省行为。

回滚：取消 IK Windows 的新呈现选择，恢复原 show/update → GDI 路径；用户旧颜色、字号、尺寸、开关偏好保留。新字段可保留但旧路径忽略。新旧显示模式切换要走受控隐藏／重建，确保没有两个桌面歌词窗。回滚不需要删除数据库或重置 Android 设置。

## 七、实现步骤

1. 已向用户展示快速稿并获“好吧那继续”确认；按已确认范围完成产品快速候选。
2. 本稿功能门与体验门保留。按用户明确要求，本轮不执行新红绿门、原门、静态、编译或成品验证，不能用阅读代码代替通过记录；恢复验证后先核红绿及既有门。
3. 新增原生透明呈现与输入状态，保持旧分支；补齐工具栏播放事件。
4. 在 IK Windows 入口显式接入可选样式，覆盖严格开启、同步、重启与备用路由；更新设置预览。
5. 完成功能红绿门和真实 Windows 体验门；所有原有绿色门继续通过，再进行候选构建、安装验证和版本收口。

## 八、验收门

以下是用户恢复验证后才执行的门，不是通过记录。用户本轮接受快稿并要求先实现快速候选，仍明确不启动验证。体验门先定义用户看到的结果，再由功能门保证它。

| 编号／真实场景 | 体验门 | 功能门 |
| --- | --- | --- |
| DL01 旧入口升级 | Mconnect／Android 保持原布局、锁定与设置 | 不带新字段仍走旧路径；旧 JSON、公开签名、事件形状保持；带新配置后再发旧请求也回旧路径 |
| DL02 阅读态 | 浅／深／复杂背景均清楚，无“移／X”黑块、永久顶部空带、半行文字 | 透明像素与主副行矩形正确；有译文／无译文／末行按规则；当前旧实现先红 |
| DL03 hover 与不可意外穿透 | 字间空白移入也出现工具栏，正文不跳；工具栏点击不会同时点击下层窗口；离开后无隐藏热区 | hover／drag／resize 状态机、控件有效命中区、事件恰好一次；未锁定不错误开启穿透 |
| DL04 锁定与解除 | 锁定后可点击下层窗口；主设置立即可解锁，解锁后工具栏可用 | 新模式锁定切换透明命中，旧锁定保持；解锁 update 必达，窗口不需要重开程序 |
| DL05 无歌词与无歌曲 | 两种空态文案正确；无歌时三个播放按钮禁用，有歌无歌词可控制播放器 | hasSong/isPlaying 真值参与绘制与命中；禁用状态不能发 controlRequested |
| DL06 播放、暂停与切歌 | 三项播放操作对应真实结果；暂停不扫色；切歌不残留旧歌词 | action 参数复用原契约；校准偏移一致；晚到更新不会覆盖新曲；长行扫色若启用不得错位 |
| DL07 开启失败与保存失败 | 失败行可见、可重试；不能显示成功开关却无窗口 | 原生失败不保存 enabled；保存失败回退；新模式失败不假成功；旧 strict 行为继续绿 |
| DL08 关闭不复活 | 关闭后切歌、暂停恢复、歌词返回都不重开，显式开启才出现 | closedByUser 先停 sweep，随后 hide 与禁用；延迟 update 不重新创建 |
| DL09 首启与重启恢复 | 初装默认关闭；原 enabled=true 按真值恢复；已锁定仍能从主窗解锁；无歌词恢复到空态 | 可选字段旧数据迁移为缺省；初始化／恢复只有一窗，无旧新窗叠加；失败时可恢复重试 |
| DL10 拖动、尺寸与 DPI | 拖动中不被更新拉回；缩放不卡控件；100%/150%/200% DPI、默认／最小尺寸、大字号无裁半行 | 几何统一按实际 DPI 处理；完成缩放保存有效尺寸；旧 clamp 不变；主行优先规则确定 |
| DL11 六项设置预览与真实送达 | 字体、字号、底色、当前行色、其他行色、阴影与真实窗口一致；缺失字体回退清楚 | 新配置加入去重；字体仅用系统已有候选；原用户配色字号不被重置；保存与回读一致；此门只在产品接入后执行 |
| DL12 生命周期与轻量 | 隐藏／重开无闪白、无残窗；包体差值可见 | 计时器与 GDI 对象释放，静置不持续增长；系统库依赖清单与构建体积实测，无额外运行时 |

现有 `floating_lyrics_service_test.dart`、`floating_lyrics_provider_test.dart`、`floating_lyrics_regression_test.dart`、`floating_lyrics_android_layout_test.dart` 是正式既有门，不能删除。新的透明合成、真实点击穿透和 DPI 行为必须有 Windows 本机证据，Dart mock 通过不替代这些体验门。

## 九、LX 官方参考与使用边界

固定提交：`323e4bac505da428adae8db6b58039fb2b36b86d`，仓库 `lyswhut/lx-music-desktop`。本稿参考交互和视觉原则，不引入其 Electron 运行时，不复制其源码。

| 参考点 | 已读取事实与官方来源 |
| --- | --- |
| 透明浮窗 | [main.ts 第 113 行](https://github.com/lyswhut/lx-music-desktop/blob/323e4bac505da428adae8db6b58039fb2b36b86d/src/main/modules/winLyric/main.ts#L113)：frame=false、transparent=true、hasShadow=false |
| hover 工具栏、背景 | [App.vue 第 171 行](https://github.com/lyswhut/lx-music-desktop/blob/323e4bac505da428adae8db6b58039fb2b36b86d/src/renderer-lyric/App.vue#L171)：默认隐藏工具栏，移入显示；未锁定背景 rgba(0,0,0,.2) |
| 锁定 | [App.vue 第 83 行](https://github.com/lyswhut/lx-music-desktop/blob/323e4bac505da428adae8db6b58039fb2b36b86d/src/renderer-lyric/App.vue#L83)、[config.ts 第 21 行](https://github.com/lyswhut/lx-music-desktop/blob/323e4bac505da428adae8db6b58039fb2b36b86d/src/main/modules/winLyric/config.ts#L21)：锁定去背景、隐藏工具栏、setIgnoreMouseEvents(true)；[主设置锁定开关](https://github.com/lyswhut/lx-music-desktop/blob/323e4bac505da428adae8db6b58039fb2b36b86d/src/renderer/views/Setting/components/SettingDesktopLyric.vue#L7)可解锁 |
| 工具栏范围 | [ControlBar.vue 第 4 行](https://github.com/lyswhut/lx-music-desktop/blob/323e4bac505da428adae8db6b58039fb2b36b86d/src/renderer-lyric/components/layout/ControlBar.vue#L4)：关闭、锁定、字号、透明度、活动行放大、置顶；它没有本稿建议的播放三按钮 |
| 字体与副行 | [LyricHorizontal/index.vue 第 36 行](https://github.com/lyswhut/lx-music-desktop/blob/323e4bac505da428adae8db6b58039fb2b36b86d/src/renderer-lyric/components/layout/LyricHorizontal/index.vue#L36)、[第 105 行](https://github.com/lyswhut/lx-music-desktop/blob/323e4bac505da428adae8db6b58039fb2b36b86d/src/renderer-lyric/components/layout/LyricHorizontal/index.vue#L105)：字体、字号、opacity、对齐、行距；扩展行更小 |
| 翻译与行数 | [core/lyric.ts 第 41 行](https://github.com/lyswhut/lx-music-desktop/blob/323e4bac505da428adae8db6b58039fb2b36b86d/src/renderer-lyric/core/lyric.ts#L41)：翻译／罗马音为扩展行。LX 当前是可滚动完整歌词，不能描述为其已提供固定“双行模式” |

本地只读调研证据保存在聊天工作区 `outputs/IK-Music-页面统一-20261125/验收证据/桌面歌词-LX参考与兼容方案调研-20261126.md`；12 份官方文件的固定 URL、字节数和 SHA-256 记录于同目录 `桌面歌词-LX官方来源索引-20261126.json`。来源读取不等于产品运行验证。

## 十、2026-11-26 快速候选实现记录（未经验证）

已新增 Windows 系统 GDI+ 的逐像素透明歌词窗，配置从原通道的可选 `windowsPresentation` 传入。原 `FloatingLyricsWindow` 两文件未修改，缺省请求仍使用旧路径；新增源文件及 `gdiplus.lib` 为系统绘制依赖，不引入新运行时。

候选代码包含六项样式、译文优先的主副行、长行缓慢往返、默认扫色、暂停冻结、正文外侧 hover 工具栏与图标名称、播放三动作、锁定穿透、主设置解除锁定、拖动／缩放和 DPI 变化处理。工具栏及名称向上扩展，靠近屏幕顶部时向下扩展，正文屏幕坐标保持。大字号放不下副行时先取消副行，并按可用高度压缩主行绘制尺寸，避免只露半行。

IK 专用工厂适配器与样式 provider 已接入严格开关、备用歌词设置页及同步 provider。样式写入先成功再发布状态；重送失败并入原设置错误状态。用户旧颜色／字号优先，系统字体不存在时回退微软雅黑 UI／系统无衬线字体。原始数据模型、旧 provider、原 channel 名和 Android 路径不改。

新增 `reset()` 与样式写入共用串行队列；先删除 IK 独立样式键，成功后发布空覆盖偏好，立即回退原颜色、字号、字体和默认演唱扫色。失败不清空当前状态。重置不删除原 FloatingLyricsSettings，也不影响播放器独立样式。

边界：Windows 跨重启坐标持久化与完整歌词滚动不在本轮范围；当前只保持会话内拖动位置。颜色预览为静态示意，缺省原生仍有演唱进度扫色。新原生按钮没有另建 UIA provider，其名称提示是视觉提示，原生辅助功能需另行验收。包体变化、资源占用、透明合成、DPI、穿透、关闭防复活和成品接线均尚无本轮验证结果。

按用户“先快速候选、暂停验证”的要求，本轮没有运行测试、analyze、格式验证、编译、GUI 或网络探测；没有形成可安装新包或公开发行结果。不得将本节的代码实现记录改写成验收通过。

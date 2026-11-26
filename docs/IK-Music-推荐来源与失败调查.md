# IK Music 推荐来源与失败调查

日期：2026-11-26。源码基线：`9ae0cc02a13123db67c2efd3e43351bcd4d33399`，产品代码对应候选 `6a5c5ed816bb1a600616ae15db518832f87e388a`。本次只读源码、现有正式测试及历史匿名证据，没有读取用户账号、Cookie、token、登录数据库，没有发网络请求或运行实机探测。本文是追加设计的调查输入，尚未实现或验收新功能。

## 一、用户场景与现状

用户希望 QQ／酷狗个人每日推荐拿不到时，可以先听以前搜索页里的推荐；发现页改为热门歌单并缩小卡图。两者对应不同的数据能力：旧搜索推荐实际是 `List<Song>`，真热门歌单目录需要 `List<Playlist>` 及真实来源。公共歌曲可以复用，不应改名冒充热门歌单。

当前个人入口与旧推荐独立。个人入口采用账号身份、凭据版本、完整响应和数量校验，失败时保留明确状态；旧推荐可能回退公开榜单或首页。新设计应把“个人结果是否可用”和“当前播放列表来自哪里”分别表达，避免有歌就把个人失败改成成功。

## 二、两张截图能确定什么

| 截图确切文案 | 对应代码状态 | 可以确定 | 不能确定 |
| --- | --- | --- | --- |
| QQ：“平台暂时无法提供推荐／可以稍后重试，或先听听其他平台的推荐。” | `PersonalDailyStatus.serviceUnavailable`，见 `lib/l10n/ik_personal_daily_strings.dart:31`、`:47` | 当前个人请求被归入服务不可用，不是成功或已确认个人空列表 | 无当前请求日志，无法区分没有私享卡片、HTTP拒绝、业务非0、WAF或其它异常；不能笼统断言账号已过期或官方永久停用 |
| 酷狗：“需要重新连接账号／当前登录信息不足，请重新连接酷狗音乐账号后再试。” | `PersonalDailyStatus.identityIncomplete` | 当前个人路径认为账号身份不足或归属不匹配，重连动作与这个状态一致 | 无字段诊断，无法断定缺哪一项；该状态可在发送个人请求前产生，也可在前置账号核对后产生，不能写成日推服务已经拒绝 |

截图文案由 `IkPersonalDailyWorkspace` 内的状态卡直接渲染，映射是源码确定性关系。本次没有替用户重连、读取私密字段或重复请求来猜原因。

## 三、现有接线、来源和数据结构

| 位置 | 实际行为 |
| --- | --- |
| `lib/video_app/video_app.dart:2814` | 新首页装配 `IkHomePage`；`workspacePageRefinements` 使公开推荐集中于发现 |
| `lib/video_app/video_app.dart:2849` | 上述新旗开启时不给搜索页传推荐；旧推荐分支保留，但新搜索只展示热词与搜索结果 |
| `lib/video_app/ik/ik_search_workspace.dart:655` | 旧完整推荐按单平台展示，取 `RecommendationsState.songsForPlatform()`，带来源说明与播放全部 |
| `lib/video_app/ik/ik_home_page.dart:72` | 新发现仅接受同平台 `fallbackToplist`／`fallbackHomepage`；旧个人枚举不会再混入公开区 |
| `lib/video_app/ik/ik_home_page.dart:669` | 当前网格是歌曲卡。列数上限4，然后平分全部宽度，封面高度为卡宽/1.15；这是宽屏卡图过大的确定原因 |
| `lib/video_app/ik/ik_router.dart:77` | `/daily?platform=...` 打开个人推荐；已有 `/playlist/:platform/:id` 在201行，歌单详情路由可以复用 |
| `lib/video_app/ik/ik_personal_daily_page.dart:74` | 仅监听选中平台 `personalDailyProvider(platform)`；strict 成功才显示其歌曲 |
| `lib/video_app/data/personal_daily_provider.dart:35` | `PersonalDailyState` 只有 `isLoading/result`，不含公共回退 |
| `lib/models/personal_daily_result.dart:19` | `PersonalDailyResult` 包含平台、状态、歌曲、原始数、有效去重数、获取时间、可选服务日期和错误码；最多展示30，不补齐 |
| `lib/models/recommendation_source.dart:39` | `RecommendationSource(platform,kind,label,note)` 与 `RecommendationResult(songs,source,error)` 已能表达公开榜单及首页来源 |
| `lib/features/discovery/presentation/providers/recommendations_provider.dart:87` | `loadLatestRecommendations()` 有请求代次；`retryLatestPlatform()` 保留其他来源。歌曲与来源必须取同批次结果 |
| `lib/l10n/ik_discovery_revision_strings.dart:34` | `sourceLabel/sourceNote` 已核同平台，能诚实呈现“榜单推荐／首页推荐” |

旧搜索推荐实际来源：

| 平台 | 方法与顺序 | 可承诺的来源 |
| --- | --- | --- |
| QQ | `QqPlatform.getDailyRecommendation()`（`qq_platform.dart:1058`）：有Cookie先 `_personalisedDaily()`，空或失败后 `getRankedSongs('27', num:30)`，再榜26 | 私享成功为旧 `personalPrivate`；回退是 `fallbackToplist`，标签为新歌榜／热歌榜，带说明 |
| 酷狗 | `KugouPlatform.getDailyRecommendation()`（`kugou_platform.dart:1068`）：旧官方 `getRecommend()`，无数据后 `fetchHomepageRecommendations()` | 公共回退为 `fallbackHomepage`，内容来自移动首页 `data` 与 `special.list.info[].songs`，去重后最多30 |
| 网易云 | `NeteasePlatform.getDailyRecommendation()`（`netease_platform.dart:71`）委托旧每日歌曲接口 | 与新的严格个人结果不同；现任务无需因 QQ／酷狗回退而改变它 |

QQ榜号由 `lib/platform/qq/qq_toplist_ids.dart` 明确：27新歌榜，26热歌榜。旧私享使用宽松HTML邻域提取及吞错详情，不能拿它证明严格个人验证成功。酷狗旧官方接口若有歌会标记 `personalizedDaily`，但该旧方法没有核个人身份，也不能借此证明当前个人推荐成功。

## 四、严格个人路径的失败条件

### QQ

入口：`lib/platform/qq/qq_platform.dart:833 getPersonalDailyRecommendations()`。

1. `_currentUser == null` 为未登录。完整音乐Cookie、恢复绑定或预期账号不匹配为身份不完整。`qq_api.dart:211 personalDailyMusicId` 要求正数 `qqmusic_uin`、非空 `qqmusic_encrypt_uin`，以及 `qm_keyst` 或 `qqmusic_key`。`qq_platform.dart:415 _matchesPersonalDailyIdentity` 另验用户平台、正数账号和OAuth别名无冲突。能搜索或能看到账户名称，不证明这些字段齐全。
2. `qq_api.dart:1456 getPersonalDailyPlaylist()` 读既有musicmac页面。严格解析要求同一完整卡片内唯一“今日私享”及唯一正数歌单ID；无卡、多卡、嵌套或ID冲突不会猜邻近歌单。HTTP200但没有确定私享ID会返回服务不可用。
3. `qq_api.dart:1473 getPersonalDailyPlaylistPage()` 通过musicu歌单模块每页200完整读取。HTTP401为会话过期；其它非200、访问拒绝、业务非0为服务不可用；结构、歌单ID、总数或分页完整性矛盾为无效响应。
4. 会话中途变化会丢弃旧结果；网络／超时单独归类。完整空列表为 `empty`；原始非空但所有行身份无效为 `invalidResponse`。成功在完整解析和去重后展示最多30。

### 酷狗

入口：`lib/platform/kugou/kugou_platform.dart:1160 getPersonalDailyRecommendations()`。

1. 要求真实正数用户ID、用户平台一致、ID并非旧兼容推断、API userid匹配，以及非占位 token／dfid／mid，mid不能为字面值 `mid`。缺项返回身份不完整，不发送个人请求。
2. `kugou_api.dart:870 getPersonalDailyAccount()` 先核凭据所属账号；返回ID不符也为身份不完整。
3. `kugou_api.dart:592 getPersonalDailySongs()` 请求 `gateway.kugou.com/everyday_song_recommend`，读取 `data.song_list`。
4. `kugou_platform.dart:1290 _decodePersonalDailyReply()` 将SSA响应头或业务20028判为需要平台验证；401为会话过期；403、WAF正文、其它非0业务码为服务不可用；结构非法为无效响应。
5. 有效行要求真实32位hash和非空 `ori_audio_name`，完整去重后最多30；不把首页歌曲拼进严格结果。

两平台共同的provider在 `personal_daily_provider.dart:113` 有12秒总期限。作用域是本地自然日、账号、账号平台、会话epoch、凭据revision与认证变化状态。迟到、退出或A→B→A前的响应不会接回当前个人列表。

## 五、两种内容方案与建议

| 方案 | 实施内容 | 能满足的目标 | 限制 |
| --- | --- | --- | --- |
| A：复用同平台公共歌曲 | QQ个人不可用时显示现有新歌榜／热歌榜；酷狗个人不可用时显示现有首页歌曲。保留个人失败原因、原连接／验证／重试动作与真实来源 | 用户“先用以前搜索里的推荐”可以采用；不需要引入新的外部内容协议 | 它仍是歌曲列表，不能替代或改名为热门歌单目录 |
| B：新增真实热门歌单目录适配 | 新增目录结果、来源和能力接口，按实际平台返回映射真实Playlist，点击复用已有歌单详情 | 对应发现页“热门歌单”的完整目标 | 三平台没有现成统一库存，属于新增复杂能力；必须先讨论确认设计和执行门，再实现 |

建议采用两个独立场景：A解决个人推荐失败后的可听内容；B作为发现页真热门歌单能力单独设计，不能为了减少工作把A包装成B。用户提出B代表功能意图，本调查尚未完成外部协议契约和设计确认，不开展实现或凭据探测。

A也有两个接入方式。直接读取已有 `RecommendationsState` 改动少，但只可接受同平台真实 `fallbackToplist / fallbackHomepage`，不能把旧 `personalPrivate` 当严格成功；重试还会重复旧私享／旧官方失败。推荐新增只服务新呈现的公共回退读取入口，复用QQ `getRankedSongs`27→26与酷狗 `fetchHomepageRecommendations()`，避免重复个人请求，保留旧公开方法和缺省路径。

## 六、拟新增可选组合数据与隔离

下列为待确认的设计形状，不是已加入代码的公开接口：

```dart
class IkDailyPresentationState {
  final PersonalDailyState personal;
  final RecommendationResult? fallback;
  final bool fallbackLoading;
  // 私有实现另持有当前平台、作用域和请求代次。
}
```

组合层保留 `PersonalDailyResult` 原含义。QQ／酷狗个人成功时只用个人歌曲；认证正在变化或个人正在请求时不接旧回退。非成功后可以展示同平台公共歌曲，标题明确写“QQ新歌榜／酷狗首页推荐”，并用一行简洁说明保留个人状态；连接、重新连接、验证后重试仍按原状态出现。0首、少于30首均显示真实数量；来源为空、来源平台不符或歌曲平台混杂的批次不得显示成成功。

刷新先尝试个人结果，公共结果只能按当前请求代次接纳；切平台只展示选中平台。私人结果仍由既有scope隔离；公共回退也要绑定平台、当前代次和读取时的账号epoch，避免旧状态覆盖刚成功的个人列表。退出账号立即清个人列表；公开回退若保留，也必须明确是公共内容。

公共读取应使用独立无用户会话客户端，或新增具有等价无会话副作用的入口。只用已有读取方法，不恢复或复制用户Cookie、token，不写会话。`createPlatformDio` 已可注入明确的空 `onSessionExpired`；使用时保留HTTP错误翻译和现有公开请求头，回退错误只作用于该回退区。

不能直接认为复用注册平台对象没有副作用。`main_video.dart:349` 已装 `attachVideoSessionGuard`，旧HTTP401／403只会作用于原请求epoch，已防迟到错误退出新账号；但旧路径仍可能使当前会话退出。严格个人方法使用请求级 `validateStatus` 自行解释403／WAF。新回退不应重新引入旧会话清理行为，也不应删除现有epoch保护。

## 七、热门歌单库存及新契约边界

`MusicPlatform`没有热门／推荐歌单目录方法。已有 `searchPlaylists`、`getUserPlaylists`、`getPlaylistDetail`。`PlaylistRecommendationsNotifier`（`lib/features/discovery/presentation/providers/playlist_recommendations_provider.dart:44`）虽名为歌单推荐，实际保存 `List<Song>`，且仅查询已登录平台的旧每日歌曲。

`Playlist`（`lib/models/playlist.dart:3`）可复用 `id/name/platform/songCount/coverUrl/creatorName`，默认 `editable/collected=false`。已有详情可用原平台与真实ID打开，不需要新建虚构歌单或跨平台补歌。

| 平台 | 已有库存 | 下一步设计须证明 |
| --- | --- | --- |
| 酷狗 | 既有 `KugouApi.getHomepage()` 返回的 `special.list.info[]` 是目录候选，无需新端点；当前只消费嵌入歌曲 | 真实目录ID、标题、封面、曲目数和完整详情；嵌入3首不能当完整歌单。热门排序尚未证实，未证实前只能称“首页歌单推荐” |
| 网易云 | `netease_endpoints.dart:20 recommendResource` 只是常量，没有调用方法 | 新API请求／响应、匿名或登录要求、目录来源以及完整分页，不以常量存在当已接入 |
| QQ | 没有已有热门歌单目录API方法 | 新公开目录契约；不得调用 `searchPlaylists('热门')` 后把搜索结果冒充官方热门目录 |

酷狗旧 `_parsePlaylist(editable:false)` 会令 `collected=true`（`kugou_platform.dart:1771`），不能直接照搬使公共歌单误显示已收藏。新目录应以真实收藏状态为准，默认不是已收藏。

拟新增目录载荷可复用 `Playlist`，外层附平台、来源类型、目录来源说明、获取时间、可选热度元数据、分页信息、明确错误类别。来源至少区分“官方热门目录”与“首页推荐”，未返回热度不捏造排名。能力默认不支持，所有新增字段可选或采用独立新模型，既有 `MusicPlatform` 方法签名、结果含义和调用方保持。

## 八、实施落点与回滚

| 落点 | 允许的新增范围 | 既有调用方与回滚 |
| --- | --- | --- |
| 新组合provider／新公共读取层 | 只服务IK可选分支，复用既有公共内容协议和真实歌曲 | 新个人页分支为直接调用方；关闭新分支即恢复当前strict-only页，不修改 `personalDailyProvider` 语义 |
| `IkPersonalDailyPage/Workspace` | 可选新呈现，分开个人状态与公共内容；保留旧构造默认 | `/daily` 的IK新装配显式开启；缺省继续当前页面，回滚撤销新接线 |
| `IkHomePage` | 可选目录呈现、限制卡片宽度并随宽度调整列数 | `VideoMusicApp` 新旗分支显式接线；旧歌曲卡、旧推荐路径保留 |
| 新热门目录适配 | 新方法、新结果、新provider；现有Playlist和详情路由复用 | 仅新增发现目录使用；旧搜索、用户歌单、推荐、播放和下载不改 |
| IK中文文案 | 新来源、简洁状态及公共回退说明 | 不改服务端协议字面值和旧国际化键，撤销新引用可回滚 |

严格日推实现、旧推荐方法、会话存储格式、账号读写、歌曲身份、音源和VIP权限都不需要因这次显示需求改变。若设计最终必须动既有生产路径，应在实施票据列原因、全部调用方和具体回滚，并取得负责人确认；本文只记录建议接入范围。

## 九、先写红门，再实现

下表是可执行场景规格，尚未新增或运行，不能标绿。体验门先定义可见结果，再约束功能返回。

| 场景 | 体验门 | 功能门 |
| --- | --- | --- |
| QQ／酷狗个人成功 | 只显示当前个人歌曲及实际数量，没有公共来源混入 | 不发公共回退请求，结果与选中平台一致 |
| QQ截图对应服务不可用 | 简洁保留个人失败说明与重试，公共成功后显示真实榜名 | strict状态不被改写，公共来源是27或26的实际返回 |
| 酷狗截图对应身份不完整 | 保留“重新连接”，可先播放首页推荐 | 缺身份不发个人歌曲请求，公共请求不携用户会话、不写会话 |
| 验证、过期、网络、超时、空及不支持 | 对应原操作仍可达，公共内容与个人状态不混淆 | 每个状态单独验；不把服务拒绝归为已登录成功，不为凑30补歌 |
| 公共回退失败或为空 | 公共区单独解释并重试，不能用成功外观占位 | 原个人失败保持；回退401／403不清当前个人会话 |
| 切平台及迟到响应 | 一次只见当前平台，刚成功的个人列表不被旧公共结果覆盖 | 完整执行退出、换号、A→B→A、同号换凭据和刷新代次；跨平台来源批次拒绝 |
| 播放与计数 | 播放全部等于可见同源完整列表；少于30按实际显示 | 去重、数量及队列身份一致，不静默截断后宣称完整 |
| 新热门歌单目录 | 卡片是真实歌单名／封面／来源；点击完整详情，返回保留所选平台 | 真实ID、分页、空、错误、详情取歌及非收藏状态全部验，不以嵌入几首替整份歌单 |
| 布局与兼容 | 宽窄窗、浅深主题、字号放大时卡图适度、说明和动作可达；旧页面不变 | 新可选默认关闭；既有绿门不破坏，原生鼠标、键盘、菜单与AX连续操作另验 |

现有历史匿名证据记录于2026-11-22：QQ私享页当次无标记，公开榜27返回30条；酷狗旧官方当次返回HTTP200的WAF正文，首页含10首主列表与10份歌单内共30首嵌入歌曲。记录没有保存完整歌单目录字段，不能证明目录点击或当前个人服务成功。后续真实验收应分别记录账号个人效果、公开目录和原生体验，不用替身门或历史匿名返回代替。

## 十、已确认的发现页数量与大窗布局规则

2026-11-26追加：用户接受上一轮呈现方案并要求继续，进一步指出发现页歌单数量少、大窗口底部留白。本节记录已经确认的界面规则，覆盖前文待确认内容中对应的数量、卡片布局和分页体验；外部目录请求与响应契约仍待真正集成时确认。用户要求先看快速版、暂不做验证，本轮仅更新文档和快速稿规则，不据此宣称产品适配、分页或验收已经完成。

- 歌单数量不设6个上限。卡片逻辑宽度以约150～190为目标，列数随实际可用内容宽度调整；扣除侧栏、边距和间隙后计算，不能固定四列再把封面无限拉宽。窄窗按可用空间收排，文字与操作仍完整可达。
- 当前快速稿以24个示例歌单为首批，再通过“加载更多”展示更多示例，示例总量可到48。24和48只说明这份预览的内容密度与交互，不是平台保证的页大小、正式内容上限或真实目录数据。
- 正式首批数量及每次追加数量由平台真实目录与分页能力决定。不得伪造总页数、加载标记或重复歌单补空；没有分页能力的来源只显示其实际返回范围，不显示可用的“加载更多”。
- 宽屏底部内容不足不能靠拉大封面填满。保持卡图尺度和行距；若真实平台支持更多数据，提供继续加载；若已到末尾，按实际数量收尾并明确“没有更多歌单”，允许自然留白。
- 每个平台分别保留已加载歌单、分页进度、加载／错误状态及滚动位置。切平台后再切回、打开详情再返回，都恢复原平台已加载列表与返回位置，不能每次退回首批或从顶部开始。
- 追加页失败时保留当前完整列表和位置，在列表末尾提供该平台的重试；重试作用于同一未完成页或游标，成功后再推进。首批失败与追加失败分别呈现，不能用整页空态遮住已经加载的内容。
- 服务明确没有更多时给清楚的末尾状态并停用继续加载；若下一页能力或结束条件尚未知，应标明该来源的已知范围，不把未知当作有更多，也不捏造已到全部末尾。

现有 `PlaylistRecommendationsState` 只有按平台的歌曲、错误和整体加载状态，没有真实目录、逐平台页码／游标、结束条件或返回位置。不得把这个旧歌曲provider改名后声称上述歌单分页已经具备；正式集成宜新增目录状态并保持旧默认调用不变。

目录新契约至少需要明确：真实 `Playlist` 身份与来源、首批请求参数和返回范围、平台是否支持继续读取、页码或不透明游标、可靠的结束条件、可选真实总量，以及首批／追加错误类别。总量与下一页信息没有返回时保持未知。合并按平台及真实歌单ID去重，去重不能掩盖重复页、错误游标或静默丢失；各平台状态与请求代次隔离，旧请求不能覆盖新刷新。

在真正接入来源目录时，再对首批及分页契约建立实际场景门：真实首批、连续追加、末页、追加失败重试、重复返回、平台切换、详情返回及刷新迟到响应。数量、游标推进、结束信号和列表完整性应从平台真实响应证明，不能以快速稿的24／48示例或历史首页嵌入歌曲替代。上述门本轮不执行，既有公开接口和产品默认路径不因文档更新而改变。

## 十一、已确认的快速候选实施范围

用户在来源与数量规则说明后继续要求实施，确认推进产品快速候选；同时明确本轮暂不验证。以该最新授权为准，本轮先记录门规格并编码，不运行首红、测试、静态检查、构建或实机探测。候选结果必须注明未验证，不将未运行门记绿，也不把公开源码契约当作当前平台服务可用证明。

采用前述A、B两项的独立新分支：`IkHomePage`、`IkPersonalDailyPage`新增可选 `refinedRecommendations=false`，旧默认继续现路径。新首页仅读取真实公开歌单目录，不填预览样例；新个人页保留strict结果，在QQ／酷狗当前个人状态非成功且不在加载／认证变化期间，以独立无会话客户端取得同平台公开回退。公共歌曲标明QQ新歌榜／热歌榜或酷狗首页推荐，不写回 `personalDailyProvider`，不重新读取或复制用户凭据。

新公共客户端复用已存在QQ榜单和酷狗首页歌曲读取方法；目录候选采用QQ公开分类歌单接口、网易公开歌单列表、酷狗现有首页 `special.list.info[]`。前两种请求／响应只根据公开文档或开源实现查明后落盘，记录资料来源；本轮不向音乐平台发送探测请求。目录首批目标24，只有明确分页契约的来源才追加；酷狗首页无分页，按真实当前目录收尾。成功与失败、完整目录身份、分页结束和迟到响应继续按第九、十节规格等待后续验证。

新增数据范围为独立公共客户端、新公共目录provider、新个人呈现组合provider，以及可选新页面。目录state分别保存各平台真实列表、首批／追加加载、错误、页偏移、结束状态与返回位置；列表按平台和真实ID合并。个人组合state保留原 `PersonalDailyState` 和独立 `RecommendationResult`，请求作用域继续受strict状态及会话epoch变化约束；重试公共列表不重写个人失败类型。公共HTTP401／403只成为该请求错误，不广播清理用户会话。

直接生产接入由 `VideoMusicApp` 的 `IkHomePage` factory及IK `/daily` factory显式传入新选项，其它默认调用不变。回滚关闭这两个新参数并撤销新provider依赖即可恢复原个人页、旧推荐和歌曲卡。旧平台公开方法签名、账号存储、登录、播放器、音源、下载和安装身份不改；不为快速候选创建假歌单、假排名或假数据成功状态。

公开协议资料固定为：[QQMusicApi目录实现](https://github.com/jsososo/QQMusicApi/blob/13b08afd3180cc74d76fff208956b77a560abd22/routes/songlist.js)、[网易公开歌单模块](https://github.com/neteasecloudmusicapienhanced/api-enhanced/blob/23d9e9d7ee5dfeccfc3b15916ccd9da1f76d3ea4/module/top_playlist.js)及其[weapi加密](https://github.com/neteasecloudmusicapienhanced/api-enhanced/blob/23d9e9d7ee5dfeccfc3b15916ccd9da1f76d3ea4/util/crypto.js)。QQ原始分页是 `sin/ein`、`data.list/data.sum`，代理自行添加的 `pageNo/total` 不能当官方字段；网易为weapi加密请求，不据模块地址直接裸GET。目录行采用本仓已有同平台歌单字段映射，所有结构错误显式失败，实际服务仍未探测。

本仓 `NeteaseCrypto.encryptRequest` 第一层AES使用随机secret作IV，与公开weapi两层固定IV不同。本轮不修改该旧公开方法，新建 `encryptPublicRequest` 只供新增无会话目录客户端调用，使用已存在密钥、RSA和AES私有函数，不增加依赖；全部旧调用方继续原行为。回滚新客户端及这个新增方法即可，不改旧加密、旧账号或既有请求路径。

本轮已落盘的快速候选由 `ik_public_recommendations.dart` 负责公开读取、`ik_playlist_catalog_provider.dart` 按平台保留目录及分页、`ik_daily_presentation_provider.dart` 组合strict和公共结果、`ik_discovery_catalog_page.dart` 渲染实际目录。QQ资料只确认 `sortId=5` 默认值，尚未证明该值的热门排序含义，所以界面显示“QQ音乐·公开歌单”；网易明确传 `order=hot`，显示“网易云·热门歌单”；酷狗显示“酷狗音乐·首页歌单”。QQ／网易缺可信下一页信息时不会猜页，酷狗首页不附假分页。快速稿24／48示例未进入产品。

目录新增分支保留平台列表和各自滚动控制器；失败只更新当前平台的错误，已有列表保持。个人回退使用当前strict结果对象作为请求键，该对象随原provider账号、会话revision和日界变化更换，旧公共响应不能覆盖新的个人作用域；strict加载和会话变化期间不触发回退。只改新呈现，不改变个人接口返回类型或状态含义。

以上“已落盘”仅指源码候选已写入。本轮按用户要求没有运行测试、静态检查、构建、原生验收或真实平台探测，外部接口响应、实际分页、布局和账号变化体验都未标记通过。后续验证仍按第九、十节范围，不能直接发布或称这两个新功能已经验收完成。

快速候选的入口参数已由主任务接线。为与用户看过的快速稿一致，新发现页的每日推荐／新歌速递／榜单采用三个等宽入口卡：图标24，圆角10，高度84；内容宽不超过600时保持三张紧凑小卡、高76并隐藏副标题，不增加巨大Hero。平台选择采用固定42高文字与2像素底线，选中不下沉、不出现勾号或Chip；窄窗允许换行。标题下单独显示“歌单推荐”和当前真实来源，QQ仍称公开歌单。网格列数按 `ceil((可用宽度+16)/206)` 且至少两列计算，再平分宽度，封面不超过190，列数不设6列上限。本次仅调整新页面和本票据，没有运行工具检查或验证。

## 十二、QQ官方“每日30首”与旧“今日私享”的补充调查及候选设计

2026-11-26用户再次提供QQ桌面官方“每日30首”截图，要求继续修复。截图证明官方客户端当时展示30首私人偏好歌曲，但没有歌单ID、请求或响应，因此不能据截图断言本程序已经获得同一批曲目。重新读取已发布0.6.1提交 `0b9561d0042784f6f37d55a49bb0b6f079ec6534` 可确认：搜索“推荐精选”使用 `recommendationsProvider → getDailyRecommendation()`，QQ走旧“今日私享”HTML尝试，失败后回退新歌榜27／热歌榜26；每平台外层只展示4首，全部推荐进入 `/recommendations`。这不是严格个人入口 `/daily`，历史有歌曲也不能证明取到截图的官方“每日30首”。

本轮新增公开证据来自以下固定版本。它们是开源实现与提交说明，不是QQ官方对第三方提供的稳定接口承诺；其中作者记录的真实账号结果不能替代本仓账号验收。

- [mygo QQ插件PR#4源码](https://github.com/Amamiya23/mygo-music-qq-plugin/blob/02be0e0385fedb61cbfeb9e0d78a20a35635944c/index.js)：个人推荐流 `music.recommend.RecommendFeed/get_recommend_feed`，`comm` 包含 `ct=20/cv=13020008/qq/authst/tmeLoginType`，参数 `direction=0/page=1/s_num=0/v_cache=[]`。成功数据要求 `retcode=0`，歌曲推荐卡位于 `v_shelf[].v_niche[].v_card[]`；每日卡类型为 `type=500/subtype=510/jumptype=10014`，普通歌单的 `subtype=0`。
- [mygo QQ插件PR#8源码](https://github.com/Lorpaves/mygo-music-qqmusic/blob/d8509cb91fb989bd141c5436151f91c8d26fd5b4/index.js)：每日卡另外要求 `time` 为北京时间当天，且仅有一张合格卡，使用其动态ID调用 `music.srfDissInfo.DissInfo/CgiGetDiss`。详情参数为 `disstid/dirid=0/tag=1/song_begin/song_num=50`，检查 `songlist/total_song_num/hasmore` 证明完整性。该版本的详情认证使用 `ct=11/cv=14090008/v=14090008/chid=10003505/tmeAppID=qqmusic` 和音乐账号会话。
- [qplayer QQ插件PR#2源码](https://github.com/TIMER-err/qplayer-qqmusic-plugin/blob/bc92a203f551b9f0f06cc4ff2ceb46f56b662183/src/main.js)：同样从个人推荐流取得“每日30首”卡片，并明确把它与 `GetRadarSong` 雷达／猜你喜欢分开。其仅按标题包含“每日／30首”取第一张的做法证据较弱，本仓不照搬；只有明确类型、当天日期和唯一动态ID才可进入详情。

方案A继续严格“今日私享”HTML，仅增加标题别名。这不能证明拿到“每日30首”，且HTML失效原因并未因此解决，不采用。方案B新增官方每日卡推荐流读取，保留旧方法及默认行为，仅IK新装配显式启用。采用B：它有明确卡片类型、服务端日期和动态ID，不借用榜单或雷达凑数。

接口与影响范围：`QqApi` 新增每日卡推荐流及对应歌单分页请求；`QqPlatform` 新增 `getDailyThirtyRecommendations({int limit=30, String? expectedAccountId})` 返回既有 `PersonalDailyResult`。`VideoQqPlatform` 新增可选 `dailyThirtyRecommendations=false`，只有显式true才在个人入口调用新方法，缺省继续 `super.getPersonalDailyRecommendations`。现有旧推荐、旧严格HTML方法、登录存储与全部旧调用签名不改。主入口 `main_video.dart` 的IK装配传 `dailyThirtyRecommendations: PlatformUtils.isWindows`，本轮仅Windows启用；撤销此参数即可回滚到原严格入口。

身份、来源和失败契约先于实现固定：新方法继续要求已登录用户、完整音乐Cookie、恢复绑定、预期账号和OAuth别名一致，固定当前Cookie与会话revision，不能把QQ号码直接冒充音乐ID。当前IK只实现QQ OAuth并在音乐登录时要求 `loginType=2`，本候选据此使用 `tmeLoginType=2`，不扩展微信登录或会话格式。请求只到已知QQ音乐HTTPS域名，不读取外部客户端或本机凭据存储。当天卡缺失／过期是服务暂不可用；字段缺失、日期／ID歧义、详情ID不符、数量矛盾或分页不完整是响应异常；HTTP401保留过期语义，403／WAF及业务非零为服务暂不可用，网络错误单独归类。以上都不清理用户会话。跨账号、凭据revision或北京时间日界的迟到结果不得被接纳。

读取规则为完整详情后去重、展示最多30首并保留真实原始／有效数量；不固定歌单ID，不拼接雷达或榜单，不把抓取时刻当推荐日期。`sourceDate`仅由当天卡的服务端 `time` 推导北京时间年月日，并按现有UI契约构造自然日期，避免将北京时间零点的UTC瞬间直接格式化成前一天；不改共用日期文案。公共榜单回退仍在独立呈现层并保留来源，不能把回退改写为该新个人方法成功。

实现步骤：先记录本节契约与门规格，再新增QQ请求／解析方法，最后接入默认关闭的 `VideoQqPlatform` 分支，由IK主装配显式开启。用户仍要求快版且暂停验证，本轮不运行以下门，不声明已取得截图曲目或服务可用。

| 真实场景 | 体验门 | 功能门 |
| --- | --- | --- |
| 当天唯一官方每日卡 | 个人页展示当天实际歌曲与数量 | 同一会话 `type500/subtype510/jumptype10014`、北京时间当天、唯一正数动态ID，详情来源与ID一致 |
| 普通歌单、雷达、旧私享、昨日卡 | 不冒充“每日30首”个人成功 | 普通推荐、标题相似、错误类型、无日期与过期卡全部不进入详情 |
| 完整详情与分页 | 播放全部对应可见同源列表，少于30按实显示 | 所有页完整、总数一致、结束信号一致，去重后最多30，字段异常不得静默成功 |
| 多张每日卡／错误ID／日期冲突 | 清楚显示个人服务或响应异常，公共回退另标来源 | 不猜选首卡，不猜固定ID，不把无可信结果当空歌单 |
| 登录变化与日界 | 退出或换号不残留旧个人歌曲 | 请求绑定账号、预期账号、Cookie快照、revision与北京时间日界，迟到全部丢弃 |
| HTTP、业务错误与WAF | 原连接／重试动作及失败类别仍可用 | 401、403、WAF、非零业务、结构错误和网络错误分别处理，不改会话存储 |
| 兼容与回滚 | 未启用调用方保持旧严格入口与旧搜索精选 | 新参数缺省false，旧公开签名不变，关闭IK显式参数即可回到原路径 |

本节源码候选已落盘：`qq_endpoints.dart` 只新增推荐流模块／方法常量；`qq_api.dart` 新增 `getDailyThirtyFeed/getDailyThirtyPlaylistPage`，使用Cookie快照和既有独立HTTP状态解释；`qq_platform.dart` 新增 `getDailyThirtyRecommendations`，旧 `getPersonalDailyRecommendations/getDailyRecommendation` 不变；`video_platforms.dart` 新增默认false的入口参数及条件分派。普通歌单和昨日卡被排除，缺日期、多个当天每日卡、结构或数量矛盾均不进入成功。详情读取保持完整分页，先按真实响应去重再限30。没有新增依赖或临时产物。

本轮只读取公开源码并写候选，没有运行测试、静态检查、格式检查、构建、实机或QQ个人请求，也没有读取用户Cookie／token。GitHub搜索和公开PR作者的验收描述只用于定位协议；本仓待验门仍未执行，不能据此宣称QQ账号日推已经恢复或与截图30首一致。

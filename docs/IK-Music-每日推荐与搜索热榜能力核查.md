# IK Music 每日推荐与搜索热榜能力核查

日期：2026-11-22。源码库存基线：`44b82fbbe81fb8773c9f2a60fdb76de9c2d6ca68`。本文件记录已有接口、数据模型、实际匿名探测及本轮可选呈现的组件验收。新增呈现的实际 19/19、324 视图与 972 平台单元结果见第九节；这些结果不证明新增外部 API、真实个人日推或 0.6.1 已发布。44 候选 Windows 播放详情的成品无障碍增量门失败，新提交重建后的成品门仍须执行，发行状态见[0.6.1验收记录](IK-Music-0.6.1-原稿对齐验收.md)。

## 一、结论与核查范围

44 基线已有三平台推荐列表和来源标签；本轮已增加 IK 可选呈现并实际通过三发现页的组件门，数据契约与平台实现保持。三平台不能作相同的内容承诺：QQ先尝试登录后的“今日私享”，不可用时回退公开新歌榜或热歌榜；网易云有每日歌曲接口，但本次匿名请求也返回歌曲，不能据此证明是用户的个人推荐；酷狗现有官方推荐接口被拒绝，本次首页回退能返回公开推荐歌曲。

搜索热词的现有产品方法只有QQ的`VideoCatalog.hotSearch()`。本次匿名请求及按该helper公开请求头复核都得到HTTP500空响应。网易云和酷狗没有已有热词适配方法；探测候选URL只是能力调查，本轮不接入新外部API。酷狗热词候选当次返回4词，网易云`hot/detail`候选为404；这不等于所有可能端点均已调查或产品已经支持这两个来源。

2026-11-22北京时间12:41:57至12:41:59完整执行8项固定公开GET；12:45:43另做1项QQ原helper请求头复核。全部9项响应读到文件末尾，没有重试或截断。未读取或使用用户账户、现存Cookie、token、登录数据库；网易云仅带公开客户端标识`os=pc; appver=3.0.18.203152`，没有请求登录或匿名注册。日志只保留HTTP状态、完整响应长度/hash和结构字段，不落盘响应令牌。

本机正式证据：

| 记录 | 字节数 | SHA-256 |
| --- | ---: | --- |
| `稳定性修复-各平台推荐与热搜匿名只读探测.json` | 11,289 | `8c9fed87799b184e9d853d5b858216af9e0ff19b8aca58b560063247224e6fb6` |
| `推荐与热搜-QQ原helper匿名头复核.json` | 886 | `25e81289b7e2a6f170dec028cc4ba8cef9438a77a5ae56272aefb543e8044f20` |

这两份记录位于本机交付目录`outputs/IK-Music-0.6.1-build12/验收证据`，不是公共下载附件。匿名HTTP探测与Flutter原生成品体验门分别记录；本次没有验证有效用户会话下的真实个人推荐、歌曲完整播放或服务长期稳定性。源码里2026-10的探针说明保留历史含义，不能覆盖本次实际返回。

## 二、已有推荐契约与模型

[MusicPlatform](https://github.com/sun-dove/ik-music/blob/44b82fbbe81fb8773c9f2a60fdb76de9c2d6ca68/lib/platform/base/music_platform.dart#L129)已有以下公开契约，保持签名和缺省行为：

```dart
Future<List<Song>> getDailyRecommendations();
bool get supportsDailyRecommendations => false;
Future<RecommendationResult> getDailyRecommendation();
```

单数方法返回列表及其来源；缺省实现调用旧复数方法，`source`为空。三个适配器都覆写单数方法，并声明`supportsDailyRecommendations == true`。这个能力位表示可以尝试取得推荐来源，不能单独解释为“已经验证个人日推”。

[RecommendationResult与RecommendationSource](https://github.com/sun-dove/ik-music/blob/44b82fbbe81fb8773c9f2a60fdb76de9c2d6ca68/lib/models/recommendation_source.dart#L21)现有字段如下：

| 类型 | 现有字段与含义 |
| --- | --- |
| `RecommendationResult` | `List<Song> songs`，缺省空；`RecommendationSource? source`，缺省null；`String? error`，缺省null |
| `RecommendationSource` | 必填`platform / kind / label`；可选`note`；`isPersonalized`根据`kind`计算 |
| `RecommendationKind` | `personalizedDaily / personalPrivate / fallbackToplist / fallbackHomepage / unavailable` |

`kind`由现有适配器赋值，没有“本次真实个人结果已验证”字段，没有更新日期或登录错误分类字段。网易云现实现只要有歌就给`personalizedDaily`；新界面仍须结合当前登录状态诚实呈现，不能把这个枚举当成匿名请求已证明个人个性化。

[Song](https://github.com/sun-dove/ik-music/blob/44b82fbbe81fb8773c9f2a60fdb76de9c2d6ca68/lib/models/song.dart#L6)保留平台原生`id / platform / name / artists / album / duration / coverUrl`，以及可选专辑、艺人、曲目序号与费用字段。列表、封面和播放应继续用这些真实对象；歌曲元数据、目录可见或推荐加载成功不等于播放权限和完整音质已经验证。

## 三、逐平台推荐实现与实际边界

### QQ音乐

| 层 | 精确方法与实现 |
| --- | --- |
| [QqApi](https://github.com/sun-dove/ik-music/blob/44b82fbbe81fb8773c9f2a60fdb76de9c2d6ca68/lib/platform/qq/qq_api.dart#L1394) | `Future<String?> getDailyPlaylistId()`，GET `https://c.y.qq.com/node/musicmac/v6/index.html`，携带该API已有Cookie，从“今日私享”附近HTML取playlist id |
| [QqPlatform](https://github.com/sun-dove/ik-music/blob/44b82fbbe81fb8773c9f2a60fdb76de9c2d6ca68/lib/platform/qq/qq_platform.dart#L795) | `Future<RecommendationResult> getDailyRecommendation()`；`Future<List<Song>> getDailyRecommendations()`委托单数方法取`songs` |
| 登录尝试 | `_api.cookie`非空才调用私有`_personalisedDaily()`；只有内存`_currentUser`而无Cookie时不会抓私享页 |
| 私享取歌 | `getPlaylistDetail(String playlistId)`后最多30首，来源`personalPrivate`、标签“今日私享”；页面解析、网络、超时和取歌失败被私有方法转为空，再尝试榜单 |
| 匿名或私享失败 | 用`getRankedSongs(String toplistId, {int offset = 0, int num = 100, String? period})`先取新歌榜27、再取热歌榜26，各请求`num: 30`；来源`fallbackToplist`，标签是真实榜名，`note`解释未登录或私享不可用 |
| 均无数据 | `unavailable`，带“QQ 每日推荐暂不可用”及来源说明 |

2026-11-22匿名PC页HTTP200，6,844字节，“今日私享”标记0次；未跟踪登录或脚本，因此不能验证登录后的私享能力。公开新歌榜27请求HTTP200、业务`code: 0`、`songlist`30条，证明当次公开榜单回退有数据。旧`musicToplist.ChartInfo/GetDailyRecommend`的2026-10失败记录属于历史，当前实现已经不调用它。

新呈现须把“今日私享”和“新歌榜/热歌榜”分开，榜单回退保留`note`。不能把公开30首榜单改名为用户的每日个性化推荐。

### 网易云音乐

| 层 | 精确方法与实现 |
| --- | --- |
| [NeteaseEndpoints](https://github.com/sun-dove/ik-music/blob/44b82fbbe81fb8773c9f2a60fdb76de9c2d6ca68/lib/platform/netease/netease_endpoints.dart#L19) | `recommendSongs = '/api/v3/discovery/recommend/songs'`，基址`https://music.163.com` |
| [NeteaseApi](https://github.com/sun-dove/ik-music/blob/44b82fbbe81fb8773c9f2a60fdb76de9c2d6ca68/lib/platform/netease/netease_api.dart#L318) | `Future<Map<String, dynamic>> getRecommendSongs()`，调用已有明文GET；API构造会生成公开客户端Cookie，恢复登录会话时合并已有Cookie |
| [NeteasePlatform](https://github.com/sun-dove/ik-music/blob/44b82fbbe81fb8773c9f2a60fdb76de9c2d6ca68/lib/platform/netease/netease_platform.dart#L61) | `Future<RecommendationResult> getDailyRecommendation()`；复数方法读取`data.dailySongs`并解析`Song`；有歌则标签“每日推荐”、`kind: personalizedDaily`，无歌则`source: null` |
| 登录判定 | `isLoggedIn`根据`_currentUser != null`，与公开客户端Cookie非空不同；推荐方法本身没有强制登录前置条件 |
| 错误边界 | [复数方法](https://github.com/sun-dove/ik-music/blob/44b82fbbe81fb8773c9f2a60fdb76de9c2d6ca68/lib/platform/netease/netease_platform.dart#L705)捕获所有异常并返回空列表；空、登录问题、网络或格式失败在此路径无法完整区分。保留这条共享旧行为，新UI不凭空补错误原因 |

2026-11-22未使用用户会话、仅带公开`os/appver`标识的匿名GET为HTTP200、业务`code: 200`、`data.dailySongs`32条。可观察到真实`id / ar / al / dt / fee / recommendReason`等字段。这个结果证明端点当次可匿名返回每日歌曲列表，不能证明这32首与某位用户有关，也不能断言这个接口一律必须登录。

新呈现应把匿名正响应称为“网易云推荐”或“平台推荐”，显示当前未登录状态；有效登录时可沿用现有“每日推荐”来源标签，但本轮仍未验证其真实个人效果。现路径为空时只能诚实显示“暂无可用推荐”并允许重试；不能把空列表确定归因为账号过期或网络故障。登录按钮是否出现依据现有账号状态，不依据猜测。

`recommendResource = '/api/v1/discovery/recommend/resource'`虽在端点表中存在，但当前库存没有与它对应的推荐歌单API方法；不能把端点常量存在当作已实现公共歌单推荐。

### 酷狗音乐

| 层 | 精确方法与实现 |
| --- | --- |
| [KugouApi](https://github.com/sun-dove/ik-music/blob/44b82fbbe81fb8773c9f2a60fdb76de9c2d6ca68/lib/platform/kugou/kugou_api.dart#L570) | `Future<Map<String, dynamic>> getRecommend()`，GET `http://mobilecdn.kugou.com/api/v3/recommend/song?format=json`；此方法没有传用户`token / userid`参数 |
| 首页回退 | `Future<Map<String, dynamic>> getHomepage()`，GET `http://m.kugou.com/?json=true` |
| [KugouPlatform](https://github.com/sun-dove/ik-music/blob/44b82fbbe81fb8773c9f2a60fdb76de9c2d6ca68/lib/platform/kugou/kugou_platform.dart#L1036) | `Future<RecommendationResult> getDailyRecommendation()`；先尝试私有`_fetchOfficialRecommendations()`，为空或失败后取首页 |
| 首页解析 | `Future<List<Song>> fetchHomepageRecommendations()`读取全部`data`及`special.list.info[].songs`，按hash等身份去重后最多30首；来源`fallbackHomepage`、标签“酷狗推荐” |
| 旧官方阳性分支 | 如果旧接口真返回`data.info`歌曲，既有实现直接赋`personalizedDaily`；没有针对用户会话的身份验证。本次没有取得这种阳性结果，不能把它当作已验证的个人日推 |
| 错误边界 | 官方拒绝记录诊断后尝试首页；首页失败或为空返回`unavailable`和明确`error`，供对应平台重试 |

2026-11-22官方推荐GET为HTTP200、27字节WAF非JSON响应；HTTP200不等于业务成功。首页GET为HTTP200和完整JSON，`data`10首、10个嵌入歌单合计30首，来源是公开首页模块。原始40条输入尚需按既有适配器去重和30首上限处理，不能把原始40条写成产品已经返回40首。

新界面保留“酷狗推荐”及首页来源说明；不能改称“每日个性化”。本次没有使用酷狗token或验证登录后的私人推荐。

## 四、搜索热词库存与接线

| 平台 | 已有方法/候选URL | 2026-11-22实际结果 | 产品能力边界 |
| --- | --- | --- | --- |
| QQ | [VideoCatalog.hotSearch()](https://github.com/sun-dove/ik-music/blob/44b82fbbe81fb8773c9f2a60fdb76de9c2d6ca68/lib/video_app/data/video_catalog.dart#L290)，`Future<List<String>> hotSearch()`；GET `https://c.y.qq.com/splcloud/fcgi-bin/gethotkey.fcg?format=json`，读`data.hotkey[].k` | 初次与按原helper两个公开头复核均HTTP500、0字节 | 方法已存在、当前本机探测失败；保留失败事实，不泛化为永久下线，也不以历史“30词”代替当前结果 |
| 网易云 | 无已有热词方法；调查候选`https://music.163.com/api/search/hot/detail` | HTTP404，HTML响应 | 只调查此候选，没有集成，未穷尽所有可能热词端点 |
| 酷狗 | 无已有热词方法；调查候选`http://mobilecdn.kugou.com/api/v3/search/hot?format=json&plat=0&count=30` | HTTP200、`status: 1 / errcode: 0`、`data.info`4条，字段`keyword / sort / jumpurl` | 当次匿名候选有效，但仍未集成；不能伪造30词或写成IK已支持 |

现有QQhelper解析非法响应时抛`VideoFailure`；[VideoApp._loadHotTerms()](https://github.com/sun-dove/ik-music/blob/44b82fbbe81fb8773c9f2a60fdb76de9c2d6ca68/lib/video_app/video_app.dart#L414)捕获失败，使手动搜索仍可用。在 44 库存中，旧视频搜索页接收`_hotTerms`，IK对齐搜索装配为`IkSearchWorkspace + IkSearchController`，尚未接入该热词列表。本轮工作副本已为此新增可选热词、加载、失败与重试输入并接原 helper；搜索装配的实际体验门由主修订票据 R05/R09 单独记录，不能从三发现页 19 门推断搜索已完整验收。

[IkSearchWorkspace](https://github.com/sun-dove/ik-music/blob/44b82fbbe81fb8773c9f2a60fdb76de9c2d6ca68/lib/video_app/ik/ik_search_workspace.dart#L189)的`useSharedSearch`表示复用IK顶栏搜索框，不是改用共享旧`SearchScreen`；44 基线查询为空时只显示`IkStrings.searchIntro`，新增可选输入的呈现与缺省保持另见主票据。旧[SearchScreen](https://github.com/sun-dove/ik-music/blob/44b82fbbe81fb8773c9f2a60fdb76de9c2d6ca68/lib/features/search/presentation/screens/search_screen.dart#L499)空态是搜索历史或输入提示，`searchSuggestions()`只从历史和当前歌曲名生成包含查询的建议，也不是服务端热搜。

本轮若为IK空态补“热门推荐”，可以复用已有推荐列表并保留来源标签，或可选接收已存在的QQ热词结果。歌曲推荐卡、公开榜单和搜索热词是不同内容；QQ热词失败时仍允许输入与提交，不能用硬编码词冒称实时热搜。网易云、酷狗的新热词URL留作调查记录，不在这次呈现修复中集成。

## 五、歌单、新歌与公开榜单的区别

| 内容 | 已有契约/模型 | 登录与能力边界 | 呈现要求 |
| --- | --- | --- | --- |
| 用户歌单 | `Future<List<Playlist>> getUserPlaylists()`；`Playlist`含真实`id / name / platform / songCount / creatorName / editable / collected / editId` | 依现有平台账号及歌单读取权限；不能将用户歌单称为服务端公共推荐歌单 | 音乐库同壳标签与真实歌单身份 |
| 当前“歌单推荐”provider | `PlaylistRecommendationsNotifier.loadRecommendations()`实际调用旧`getDailyRecommendations()`，state保存`List<Song>` | 只查询已登录平台；没有独立的推荐`Playlist`结果，也不保留来源模型 | 名称不能证明已具备最新公共歌单目录 |
| 新歌速递 | `Future<List<Song>> getNewSongs({int limit = 100, NewSongRegion region = NewSongRegion.all})` | QQ已有`newsong.NewSongServer/get_new_song_info`，六地区；网易云已有`/api/v1/discovery/new/songs`，不支持港台；酷狗`supportsNewSongs == false`且方法明确抛不支持 | 新歌按平台切换；能力或地区不支持应可见，不能用榜单或全部地区冒充 |
| 公开榜单 | `Future<List<Toplist>> getToplists()`与`Future<List<RankedSong>> getRankedSongs(String toplistId, {int offset = 0, int num = 100, String? period})` | QQ musicu目录/现代detail与legacy分页；网易云`/api/toplist`及歌单详情；酷狗`rank/list`及榜单取歌；访问可能失败，不能把公开目录成功写成全部歌曲可播 | 来源平台、真实榜名、周期/排名及缓存状态保持 |

具体已有新歌方法：QQ API `Future<Map<String, dynamic>> getNewSongs({int type = 5})`；网易云API `Future<Map<String, dynamic>> getNewSongsByArea({int areaId = 0, CancelToken? cancelToken})`、`getPersonalizedNewSongs({CancelToken? cancelToken})`，后者只作“全部地区”回退，不可冒充地区数据；酷狗现有`getNewSongs(...)`明确抛`UnsupportedActionException`。QQ新歌API失败目前会返回空列表，这个既有错误细度同样不在本次修改。

[Toplist与RankedSong](https://github.com/sun-dove/ik-music/blob/44b82fbbe81fb8773c9f2a60fdb76de9c2d6ca68/lib/models/toplist.dart#L8)已有封面、更新频率、周期、分组、排名与变动等字段；[ToplistsState](https://github.com/sun-dove/ik-music/blob/44b82fbbe81fb8773c9f2a60fdb76de9c2d6ca68/lib/features/toplist/presentation/providers/toplists_provider.dart#L26)保留所有被查询平台、逐平台错误和离线缓存标记。QQ固定热歌入口真实id为26，新呈现只在QQ平台标签下展示。

## 六、现有推荐provider与页面差异

[RecommendationsState](https://github.com/sun-dove/ik-music/blob/44b82fbbe81fb8773c9f2a60fdb76de9c2d6ca68/lib/features/discovery/presentation/providers/recommendations_provider.dart#L28)已有`songsByPlatform / errorsByPlatform / sourceByPlatform / isLoading / error`。`RecommendationsNotifier`查询所有声明推荐能力的平台，单次平台请求有12秒超时，并返回逐平台来源与错误。

已有`Future<void> loadRecommendations()`、`loadLatestRecommendations()`和`retryLatestPlatform(PlatformType platform)`。IK入口通过`IkRecommendationsNotifier`将旧加载调用委托给世代保护的新方法，账号变化时旧响应不覆盖新状态；局部重试保留其他来源。旧默认provider行为继续保留。

在 44 库存中，`IkHomePage`直接展示来源`label/note`，并用歌曲结果与错误平台并集保留失败来源；[/recommendations旧页面](https://github.com/sun-dove/ik-music/blob/44b82fbbe81fb8773c9f2a60fdb76de9c2d6ca68/lib/features/discovery/presentation/pages/recommendations_page.dart#L76)只按`songsByPlatform`建tabs、标题统一“每日推荐”，没有传来源模型，单纯失败且匿名无歌的平台可能没有tab。本轮显式新分支已改为固定三平台的可达入口，并显示当前来源、空或错误；首页、搜索和推荐采用同一个来源标签规则，实际源码与组件结果见第九节。链接所指的旧默认分支完整保持。

共享provider在全空且无已登录平台时设置“请先登录平台账号”；这个旧全页字段也不能覆盖已知的逐平台网络/服务错误。新IK呈现优先展示已有逐平台证据；网易云被旧适配器吞掉的异常仍只能给未细分状态，不能猜测并制造成功或确定错误分类。本轮不修改这些默认行为。

## 七、兼容呈现建议与拟验收门

| 方案 | 做法 | 判断 |
| --- | --- | --- |
| A：复用已有能力，新增IK可选呈现 | 三个既有页面只增加可选`alignToDesign = false`分支；选中平台单独渲染，保留来源/错误/空/不支持；复用现provider、真实Song/Toplist和播放动作 | 本轮推荐并采用。缺省路径保持，界面问题不扩大到平台协议或身份变更 |
| B：重新做推荐与热词协议 | 新增认证推荐、热词适配和错误细分接口，再改共享provider或默认页面 | 增加外部接口与兼容成本；不进入本轮。将来需要独立设计与真实场景门后再评估 |

本轮不修改共享旧`RecommendationsPage`默认分支、网易云吞错行为、公开接口签名、平台身份或会话，也不新增外部API。新的文案放在IK专属中文文案类；默认`alignToDesign == false`时行为与界面精确保留。

以下是实现前写明的场景与门规格。三发现页及已有通知器回归的实际红绿已在第九节记录；搜索、真实账号与原生成品按各自正式门范围记录，不据此一并称绿。实施遵守先读正式修订票据、实际体验首红、再实现使同门转绿：

| 场景 | 功能门 | 体验门 |
| --- | --- | --- |
| 默认用户打开三个旧页面 | 缺省构造与显式false使用原provider和动作 | 原默认页面内容与路由保持；新样式不漏入默认分支 |
| 用户切换推荐、新歌或榜单平台 | 三平台入口稳定，选中状态与真实平台身份对应 | 三个平台都可达；只渲染选中的平台内容，不纵向堆全部来源 |
| 单个平台失败或为空 | 保留对应`error/source`，其他结果不删 | 失败或空的平台tab仍可见，有恰当重试或空状态；不把错误显示成成功 |
| QQ匿名拿到公开新歌榜 | 保留`fallbackToplist`、真实榜名和note | 显示新歌榜/未登录回退说明，不标个人日推 |
| QQ私享正常或回退 | 私享歌曲与来源同时到达；失败回退仍带来源 | 成功显示“今日私享”，回退显示实际榜名与说明；不跨平台混用来源 |
| 网易云匿名正响应或未细分空响应 | 不修改原适配器；不虚构登录/网络分类 | 匿名有歌称平台推荐；空列表诚实显示暂无可用推荐，不能冒称已验证个人结果 |
| 酷狗官方拒绝后首页正常 | 来源`fallbackHomepage`和note保留 | 显示酷狗推荐/首页来源，不称每日个性化 |
| 网易云选择港台、或酷狗进入新歌 | 使用现有不支持能力/地区结果 | 有明确不支持说明，不用全部地区或榜单冒充该地区新歌 |
| 用户在榜单切平台 | 固定QQ热歌id26及所选平台真实榜单不变 | 固定26入口仅在QQ标签；网易云/酷狗标签不出现QQ固定入口 |
| 用户点击歌曲及更多动作 | 使用当前完整来源列表与真实startIndex，复用既有播放/队列/更多能力 | 所选歌曲正确播放或进入原动作；展示限制不截断实际播放列表 |
| 账号变化或迟到响应 | 既有latest世代与局部重试门保持 | 新账号/新刷新后不显示旧账户来源，另一平台结果仍保留 |
| 热词请求失败但用户想搜索 | 保留手动提交；热词与推荐不混淆 | 搜索框、提交仍可用；无伪造热榜词或错误成功提示 |
| 窄窗、浅深主题与字号变化 | 所有新分支与真实状态完整覆盖 | 平台选择、来源、错误操作和歌曲行可见，无溢出或隐藏的关键按钮 |

三发现页的上述场景已与已有通知器/兼容门共同实跑，结果见第九节。搜索和最终成品的独立范围仍按主票据验收。真实设备、有效账号下的个性化和服务可用性按实际执行范围记录，不能用模拟门或匿名返回替代。

## 八、Jev请求结构示例

这是供主修订设计使用的最小结构示例，不是本库存又一次实际Jev调用结果。`questions`是具名问题对象，`choice.criteria`是选项到说明的对象；同一`state`的独立问题可以一次提交，无需把任何header、密钥或账户信息放入请求内容。

```json
{
  "model": "jev-latest",
  "state": {"内容": "用户需求与已有接口事实"},
  "questions": {
    "content_group": {
      "type": "choice",
      "instructions": "根据state选择最合适的呈现组，保留真实内容来源。",
      "criteria": {
        "same_shell_tabs": "音乐库子内容保持同壳标签",
        "platform_switch": "新歌或榜单按平台切换",
        "source_badges": "推荐保留每日、榜单、首页的来源标签"
      }
    },
    "truthfulness": {
      "type": "noul",
      "instructions": "当前呈现是否保留真实来源和失败边界？true为保留，false为混淆。"
    }
  }
}
```

## 九、本轮可选呈现的实际组件验收

2026-11-22 三发现页已完成正式先红后绿。新增 `NewSongsPage`、`ToplistsPage`、`RecommendationsPage` 的可选 `alignToDesign` 缺省为 `false`，当前新版路由显式启用。三个页面仍使用原平台、通知器、地区与来源模型、完整曲目列表和实际更多执行器；没有接新平台 API 或修改旧公开业务方法。

| 正式范围 | 实际结果 | 完整证据 |
| --- | --- | --- |
| 原页面体验首红 | 19 门：18 失败、1 原默认成功，退出 1；完整 R09 为 324 视图、972 平台单元、1,620 项失败 | `发现页面可选呈现-正式首红.json` |
| 同门实现后首绿 | 19/19 成功、退出 0；324 视图、972 平台单元、0 失败，无抽样 | `发现页面可选呈现-正式首绿.json` |
| 既有七文件回归 | 42/42 成功、无跳过，原门不改 | `发现页面可选呈现-既有默认与来源回归.json` |
| 默认源码与断言 | 三页剥除明确可选呈现后与 44 完整源码一致，仅统一换行；八个数据/模型/播放器文件完整保持；正式门从 `void main()` 起断言及辅助逻辑与首红逐字一致，仅三处页面夹具接线 | `发现页面可选呈现-同门断言与缺省源码保持核对.json` |

R09 是浅深 × 六宽度 × 三字号 × 数据/错误/空态 × 三页的完整遍历，324 个视图每个都检查三个平台入口，共 972 平台单元。平台切换只呈现当前来源；网易港台及酷狗新歌不支持、失败保留与真实重试、QQ26 固定入口仅属 QQ、播放全部与原 `startIndex`、歌曲更多及取消均已进入场景。五个正式文件格式与 Dart 静态检查通过。

新增 `IkDiscoveryRevisionStrings.sourceLabel` 用对应平台、实际来源枚举与当前账号状态共同决定标签。QQ 仅 `personalPrivate` 且对应 QQ 登录显示“今日私享”，网易云仅 `personalizedDaily` 且对应网易登录显示“每日推荐”；酷狗不能因登录或旧个人枚举声称个人日推。缺失、跨平台或不能证明个人会话的来源显示“平台推荐”，榜单回退和首页回退保持真实类别。首页、搜索和推荐的实际源码调用链已独立逐项核对。这个界面判定用于诚实呈现，仍不代替真实账号个人效果的在线验证。

本节仅新增组件结果，前述 9 项真实匿名 HTTP 的原始状态、长度与 SHA-256 均保留，没有重新探测。QQ 热词的本次 500 事实、网易 32 首匿名结果、酷狗首页与尚未集成热词候选的边界不变。个人账号、歌曲完整播放、两平台新提交重建、R10 原生成品及远端九附件仍按主票据继续，不称 0.6.1 已公开。

## 十、追加个人日推协议调研（2026-11-22）

用户随后明确要三平台个人每日推荐30首，并指出两张新截图的标签与热词层级过多。本次没有重跑上述9项匿名请求，也没有读取用户凭据；改为核对固定提交的公开源码。网易 `/api/v3/discovery/recommend/songs` 仍存在，没有固定30参数；酷狗另找到新版 POST `gateway.kugou.com/everyday_song_recommend` 与 `everydayrec.service.kugou.com` 路由、Android签名和 `data.song_list`，它与前文被WAF拒绝的旧GET不是同一协议。QQ仍以musicmac“今日私享”卡片和对应歌单详情为可实行方向，未确认新的直达30歌曲协议。

新接口与严格结果状态、账号/纪元隔离、QQ卡片限定及完整分页、酷狗身份和字段映射、来源日期及实际数量要求已写在[追加设计第五、六节](IK-Music-歌单层级与每日30首追加设计.md)。该复杂外部接入须先讨论确认再编码；没有把公开源码入口当作真实个人响应成功，也没有以榜单/首页补够30。前文旧协议和匿名探测事实保留，不能继续据旧GET失败断言新版酷狗个人日推入口不存在。

同轮已完成歌单层级、搜索热词及推荐单平台呈现修复，追加账号提示与超时中文体验门。正式九门9/0/0、相关旧八文件193/0/0，最终无过滤全仓2571通过/0失败/18既有跳过；582文件格式零变化、静态零问题。884项开始前输入首尾保持，2项SDK着色器另记运行中补证；4条旧测试警告完整保留。合成热词、脚本化歌曲、登录及超时边界仅验确定性产品呈现，不改变本节个人日推未实现、未读取用户认证数据的结论。新源码未进入冻结95候选或本机安装，HTML可点击稿为示例，详见追加设计第十一节。

## 十一、个人每日推荐实施与验收进度（2026-11-22）

用户在听取独立个人入口、三平台来源和实际数量的说明后回复“继续”，确认实施追加设计的方案 B。第十节记录的是确认前的协议核查和当时的歌单、搜索验收结果。新版发现页现已接入独立“每日推荐”入口，可切换网易云、QQ 音乐和酷狗音乐。使用完整有效的对应账号会话后，页面按平台顺序显示实际曲目，最多 30 首。公开榜单和首页推荐继续由原精选入口呈现。[方案 B 确认与实现记录](IK-Music-歌单层级与每日30首追加设计.md#十二个人日推实施确认与正式契约)

| 平台 | 已接入的个人来源 | 仍需真实账号核实 |
| --- | --- | --- |
| 网易云音乐 | 先核对当前登录凭据对应的账号，再读取 `/api/v3/discovery/recommend/songs` 中的 `data.dailySongs`。 | 实际账号能否取到个人推荐、平台返回数量和更新日期。第三节的 32 首来自此前匿名探测。 |
| QQ 音乐 | 在同一完整音乐会话下读取 `musicmac` 页面里明确的“今日私享”卡片，再取歌单详情及所需分页。 | 登录后网页是否仍提供可识别的“今日私享”卡片、实际歌曲数量、更新日期，以及平台更改页面结构后的兼容性。 |
| 酷狗音乐 | 核对有效用户、设备身份及凭据归属，再用已接入的 Android 签名请求 `everyday_song_recommend`，读取 `data.song_list`。平台返回明确安全验证信号时，页面提示用户完成验证。 | 真账号的凭据是否满足新接口要求、推荐内容与返回数量、更新日期，以及 `time_length` 的单位。新日推歌曲暂不填入这个时长字段。 |

QQ 音乐的用户账号 ID 和音乐 ID 在登录或恢复时绑定。缺少关键身份字段、音乐 ID 为 0、账号与绑定不符时不发私享请求。卡片解析只接受同一张明确标有“今日私享”的 `playlist__item` 卡片内唯一有效的歌单 ID。相邻卡片、脚本、注释、模板、重复属性给出的不同 ID 都不能据以选取歌单。详情检查业务码、响应中的歌单 ID 和所需分页，任一页失败就丢弃本次结果。请求期间换账号、换凭据或切走再切回时，旧响应不能覆盖当前会话。HTTP 403 或详情响应里的平台拒绝访问提示显示服务不可用，当前账号状态保留。[QQ 新入口](../lib/platform/qq/qq_platform.dart) · [QQ 私享解析](../lib/platform/qq/qq_api.dart)

三个适配器解析完整结果后按平台原顺序去重，记录原始条数、有效去重条数和实际展示条数。点击“播放全部”时，队列使用本页展示的曲目。结果页区分未登录、身份信息不完整、会话过期、需要验证、网络失败、服务不可用、响应无效及空结果。当前三个接口的推荐日期均待真实响应确认，页面使用实际获取时间。[个人日推结果](../lib/models/personal_daily_result.dart) · [个人日推页面](../lib/video_app/ik/ik_personal_daily_page.dart)

联合复核新加三类场景。网易云与酷狗的连接、发送和接收超时各自保留超时标识，普通连接失败仍按网络失败显示。QQ 恢复存档时两个 OAuth 账号字段若互相矛盾，返回身份信息不完整并停止发请求。两个字段一致且音乐 ID 不同时，仍可读取私享。日推成功后可刷新当前平台，页面重新加载时立即清掉旧曲目。夹具校准后的正式首红共 5 项，4 项失败，只有 QQ 两字段一致的正例通过。联合首绿 02 中，同一组 5 项全部通过。

| 验收范围 | 已有记录 |
| --- | --- |
| 功能首轮通过 | `三平台与会话-功能首绿02.machine.log` 记录 144 项通过、0 失败、0 跳过，其中 77 项为三平台与会话新门，67 项为原 QQ 回归。后续新增边界在独立记录中验证。 |
| QQ 扩展功能门 | `个人每日推荐-联合首绿01.machine.log` 中的 35 项 QQ 门全通过，覆盖私享卡片、跨页完整性、重复 ID、账号和凭据轮换、HTTP 200 拒绝访问提示以及曲目数量。 |
| 联合首轮验收 | `个人每日推荐-联合首绿01.machine.log` 共 105 项可见用例，99 通过、6 失败，失败属于组件体验与集成范围。 |
| 联合第二轮验收 | `个人每日推荐-联合首绿02.machine.log` 完整执行 5 个文件的 108 项可见用例，其中界面体验 20、应用集成 2、状态管理 11、网易云与酷狗 38、QQ 37。108 项通过，0 失败、0 跳过、0 错误、0 布局或点击告警。`done.success=true`，32.981 秒，SHA-256 为 `01947e6b2624dd43c321f7c9e4266e5197e7089b30dcdb95b14b9c267859debf`。 |
| 全仓首轮的格式与静态 | 等价修正 9 项静态提示后，591 个文件的格式检查无变化，完整静态检查为 0 问题。 |
| 全仓首轮 | `全仓回归-个人日推最终01.machine.log` 完整执行 243 个入口，2677 项通过、2 项失败、18 项按既有条件跳过，唯一终态为失败，耗时 1590.682 秒。108 项个人日推检查均在通过项内。 |
| 修正后的定向检查 | `回归修复-定向验证01.machine.log` 中 88 项通过、0 失败、0 跳过。国际化预算实测 869 处、97 个文件及 1 处协议豁免。591 个文件格式无变化，完整静态分析为 0 问题。 |
| 全仓第二轮 | 无过滤执行全部 243 个入口，2679 项通过、0 失败、18 项按既有条件跳过。命令退出 0，实际耗时 1538.1202402 秒，唯一机器终态 `done.success=true`，测试计时 1534.003 秒。 |

全仓首轮发现两项问题。QQ 新解析器的两处固定服务端标题使国际化预算从 869 增到 871，现集中为一处注明协议用途的豁免常量。发现页在宽 390 像素、字号 150% 时 QQ 标签底部超出播放栏上沿 1 像素，现将该布局的标题和操作间距从 14 调为 12 像素。两项原门在定向及第二轮全仓均已通过。[两项修正的原因、范围与回滚](IK-Music-歌单层级与每日30首追加设计.md#十四完整回归首轮发现与最小修复票据)

第二轮的 108 项个人日推检查及 20 项既有语义检查全部通过，场景名称及出现次数与首轮一致，这两组用例已经包含在 2679 项通过结果中。日志仍有 3 条 Drift 调试警告和 1 条旧列表点击命中提示，与首轮相同。源码与资源 883 项、补充输入 10 项、冻结文档 4 份、环境开关 8 项和测试入口 243 个，首尾比对均无差异。

本机证据目录为 `outputs/IK-Music-0.6.1-build12/验收证据/个人每日推荐-20261122`。第二轮完整机器日志 `全仓回归-个人日推最终02.machine.log` 为 2,135,337 字节，SHA-256 为 `d634222f9b86dd7e1ad4f5781bdc8cb510303d5b4c10e7b3d98dd4f6727b5d59`。目录内的 `全仓回归-第二轮完整解析回执.json` 和 `全仓回归-第二轮完整逐案索引.json` 提供逐项核对，首轮失败日志和回执一并保留。

源码回归已完成，测试使用虚构账号和脚本化响应验证客户端请求、状态和界面动作。仍待使用真实账号验证三平台的个人推荐和实际播放，以及进行 Windows、Android 原生成品验收。此轮新源码尚未提交、构建、安装或公开，原 95 候选与此前歌单、搜索测试的证据保留。

# 网易发现歌单封面兼容修复票据

## 场景与已知边界

2026-11-26用户第二份预览截图中，发现页网易云24张歌单已有名称和数量，但封面全为占位；QQ与酷狗歌单封面正常。本票只处理新发现目录的网易图片加载，不改个人日推、日期、播放栏、账号或其它平台。

源码链为 `IkPublicRecommendations._neteasePlaylists` 从 `playlists[].coverImgUrl` 读取原始地址，保存到 `Playlist.coverUrl`，`_PlaylistCard` 传给 `VideoCover`，最终由独立的 `Image.network` 请求图片。目录请求使用Dio且配置了浏览器UA与网易官网Referer，但这些头不会自动传到Flutter的图片请求。现有 `VideoCover` 原样使用地址，不处理网易HTTP图片地址，也没有图片请求头。

`coverImgUrl`不是本轮发现的拼写错误：本仓既有网易歌单模型解析与历史真实记录均使用该字段；[公开网易目录实现](https://github.com/neteasecloudmusicapienhanced/api-enhanced/blob/23d9e9d7ee5dfeccfc3b15916ccd9da1f76d3ea4/module/top_playlist.js)请求 `/api/playlist/list`，仅重命名头像ID字段，未转换封面字段。没有证据支持改用歌曲专辑 `picUrl`，更不能只凭 `coverImgId` 拼造缺少hash路径的图片地址。

本仓 `docs/netease-wave-b-probe.md` 记录过 `http://p1.music.126.net/…`、`http://p4.music.126.net/…` 等完整图片URL，`netease-wave-b-report.md` 同时记录过p3/p4 HTTPS图片。公开Flutter客户端[YesPlayMusic图片加载实现](https://github.com/qier222/YesPlayMusic/blob/1778b57faac7d9297968685a307504942551ab1b/lib/cache/image_cache.dart)明确记录部分CDN会对Dart默认UA返回403，并设置浏览器UA。它只能支持本次兼容方向，不能证明用户这次24张失败一定是403。

本轮未读取截图对应目录响应、图片请求响应或错误日志，也未向音乐平台发验证请求。现阶段能确定的是图片路径缺少独立兼容处理；无法断言当前故障属于字段缺失、HTTP访问策略、CDN请求头、DNS、TLS或临时网络错误中的哪一种。

## 两个方案与选择

方案A修改全局 `VideoCover` 默认行为，全部远程图片统一改HTTPS并加网易请求头。该方案会影响其它平台、旧页面和非网易图片，不采用。

方案B新增默认关闭的网易图片兼容选项，仅新发现页的网易卡片显式开启。仅识别 `p1/p2/p3/p4.music.126.net` 的HTTP、HTTPS或协议相对完整图片地址，将scheme统一为HTTPS，保留原host、hash路径、图片文件名、查询参数及片段；图片请求附浏览器UA和 `Referer: https://music.163.com/`。其它来源和未启用调用方继续原行为。采用B，无新依赖、代理、缓存服务或凭据读取。

## 接口、调用方与回滚

`VideoCover` 新增可选 `neteaseImageCompatibility=false`。只有该值为true且URL是已知网易图片host时才处理scheme和请求头。缺失地址或图片加载失败时仍使用既有占位，不伪造封面；不修改 `Playlist` 结构和 `_neteasePlaylists` 原始字段含义。

直接启用调用方仅 `IkDiscoveryCatalogPage` 内的 `_PlaylistCard`，条件为 `playlist.platform == PlatformType.netease`。其余 `VideoCover` 调用、QQ和酷狗卡片、旧发现页、详情路由与底部播放栏保持原默认。回滚删除这处显式参数即可；新增默认参数可保留，不需要迁移账号或缓存。

用户已要求处理这批截图问题，因此本票属于已授权的简单图片兼容修复。用户“先不验证”仍有效，本轮只写票据与源码候选，不运行首红、测试、analyze、format、GUI、构建或网络验收，不把候选标绿。

## 待执行验收门

| 真实场景 | 体验门 | 功能门 |
| --- | --- | --- |
| 网易目录返回HTTP完整封面 | 卡片显示相应歌单封面，名称数量与封面身份不变 | 仅该已知host升级HTTPS；原hash路径、文件名、query全部保留；带浏览器UA和官网Referer |
| 网易目录返回HTTPS／协议相对地址 | 封面正常，布局不变 | HTTPS不降级；协议相对URL补HTTPS；不换host不猜ID |
| 缺地址或网络／图片解码失败 | 保持当前占位与可打开歌单行为 | 不把其它字段拼成假URL，不追加代理或无限重试 |
| QQ／酷狗与旧默认调用 | 原图及图片请求行为保持 | 默认false；未知host、其它平台无新增请求头或scheme改写 |
| 当前截图真实24张封面 | 每一张真实返回图片分别记录成功／失败，不能只抽样宣称全部恢复 | 后续在授权验证时保留真实错误类别；未取得HTTP响应前不把403当定论 |

## 本轮落盘状态

本票据在编码前记录，现已仅新增 `VideoCover` 可选处理和网易目录卡片调用参数。图片请求头仅包含固定浏览器UA及官网Referer，不包含Cookie／token；带userinfo或非标准端口的地址不套用该处理。原始 `coverImgUrl` 字段保留不改。没有新增测试或临时文件，没有清理用户缓存，没有提交或发布；所有验收门仍未执行，当前403根因仍未经真实响应证实。

## 第三份预览失败后的实际取证与更正

用户反馈第三份预览 `a0276f2` 的网易24张仍全部占位，因此本次授权仅对该故障做最小匿名目录／图片HTTP诊断；仍不运行全仓测试、analyze、format或GUI。此前“没有真实响应、403未证实”的记录属于上一轮历史结论，本节补上真实结果，不把之前候选描述成成功修复。

与产品相同的匿名 `POST https://music.163.com/weapi/playlist/list`，参数 `cat=全部/order=hot/limit=24/offset=0/total=true/csrf_token=''`，本次返回HTTP200、业务code200、24条歌单、total680、more=true。24条都有完整 `coverImgUrl`，全部为 `http://p1.music.126.net/…jpg` 或 `http://p2.music.126.net/…jpg`。字段与hash路径完整，名称数量和封面字段没有错配；不需要猜替代字段或图片ID。

对返回首图做同URL对照：

| 实际请求方式 | HTTP结果 | 正文 |
| --- | --- | --- |
| .NET HTTP或HTTPS，仅Dart UA | 403 | `text/html`，146字节 |
| .NET HTTP或HTTPS，单浏览器UA＋官网Referer | 200 | `image/jpg`，298618字节，可解码1254×1254 |
| 当前Dart 3.13独立客户端默认UA | 403 | `text/html`，146字节 |
| 按当前Flutter源码 `request.headers.add` 追加浏览器UA | 403 | `text/html`，548字节；请求同时带Dart与Mozilla两条UA |
| Dart `request.headers.set` 替换为单浏览器UA | 200 | `image/jpg`，298618字节，JPEG文件头 |
| Dart `client.userAgent` 设置单浏览器UA | 200 | 同一正常JPEG |

**已确认根因：前一候选给 `Image.network(headers: …)` 加UA时，Flutter当前SDK在 `_network_image_io.dart` 使用 `request.headers.add`。Dart `HttpClient` 已有默认 `Dart/3.13 (dart:io)`，追加后保留了两条UA，网易图片CDN仍拒绝。** 仅HTTPS和外部客户端单UA成功不能证明Flutter传头成功；这是上次候选遗漏的实际请求差异。当前目录不是没有封面，封面响应是403 HTML而不是图片。

证据正式保留于 `docs/验收证据/网易目录封面-20261126-匿名HTTP诊断.json`，包含匿名目录字段、24条真实完整URL、HTTP/HTTPS对照、Content-Type、长度、JPEG解码尺寸及Dart四种请求结果。未读取用户Cookie、账号存储或个人接口。暂存诊断脚本任务完成前精确删除，正式JSON属于本次交付证据保留。

## 本次修复方案与门

方案C使用全局 `HttpOverrides` 或更改整个Flutter共用客户端默认UA。影响全部网络图片，回滚和跨平台范围过大，不采用。

方案D保留 `neteaseImageCompatibility=false` 默认和精确图片host条件，只为该可选分支新增轻量图片provider。其独立 `HttpClient.userAgent` 为单浏览器UA，`Referer` 通过 `headers.set` 设置，完整读取图片字节后交Flutter现有解码器；失败仍原占位，错误缓存及时移除。其它平台和所有未开启调用仍走原 `Image.network`。采用D，无新依赖、外部代理、服务、全局override或凭据。

为使匿名取证与产品实际请求保持同一实现，纯Dart读取函数放于 `netease_cover_request.dart`；该文件仅负责精确host、HTTPS、单UA请求和有限超时。`VideoCover` 新的私有provider消费该函数，图片缓存仍使用Flutter现有内存缓存。回滚移除发现网易卡片上的显式选项即可恢复旧路径。

本次先记录根因和方案，再编码。功能门新增“调用实际新读取函数请求本次目录的全部24张，逐张状态和解码均有结果”，不静默抽样；Dart追加UA为故障对照，单UA为修复请求。该门只能证明HTTP取图与标准解码，最终Windows界面是否恢复仍由后续预览确认，不冒充已做GUI验收。

## 实际结果与交付边界

已使用产品新增的 `loadNeteaseCoverBytes` 函数请求本次匿名目录全部24条真实封面：**24／24返回HTTP200，24／24通过System.Drawing像素解码**。23张是JPEG、1张实际是PNG（服务URL仍以 `.jpg` 结尾），因此保留通用图片解码，不按扩展名强制JPEG。逐条URL、字节数、文件头、尺寸、格式和SHA-256均在正式JSON中，没有抽样或静默跳过。

已落盘 `lib/video_app/data/netease_cover_request.dart` 以及 `VideoCover` 的私有provider分支；目录原字段、现有默认false参数、精确网易图片host条件和网易卡片显式启用点保持。根因对照使用同一Dart 3.13运行时，未运行产品测试、analyze、format、GUI或全量平台检查。主任务统一编译新预览，原生最终显示仍待该预览确认。

平台边界：仓库README明确当前发行Windows／Android，`lib/main_video.dart` 原第4行和 `PlatformUtils` 已直接导入 `dart:io`，没有原先可用的Web产品入口承诺。本次读取函数只用现有Dart原生HTTP与Flutter图片解码，不增加原生插件或系统依赖；Windows／Android仍使用相同SDK能力，不据此宣称已对所有平台构建验收。

清理状态：两份本轮文本诊断脚本已删除。清理24张临时图片及空目录的PowerShell命令被自动审批拒绝，两次返回均仅为 `blocked by policy`，没有细分原因；命令未执行，收到停止要求后不再重试。故仓库 `.codex-netease-cover-bytes-20261126/` 的24张临时图片仍保留，精确路径在JSON `productRequestAllCovers[].file`。该目录不应纳入提交或打包；正式保留的交付证据是 `docs/验收证据/网易目录封面-20261126-匿名HTTP诊断.json`。本轮没有提交。

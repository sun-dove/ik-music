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

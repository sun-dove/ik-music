# 歌单同步封面与首曲回退

## 用户场景与现有原因

2026-11-26用户指出音乐库／我的歌单的酷狗列表只有48像素歌单图标，进入歌单也缺图；要求同步真实封面，没有封面时用首曲图片。此次属于已授权的小功能增强，保持旧默认分支并先记录体验门，不运行产品测试、analyze、format或GUI。

现有 `PlatformPlaylistsPage` 平台列表已经把 `Playlist.coverUrl` 传给 `_PlaylistCover`，但空URL与图片加载失败都直接落到图标；本地“我的歌单”更是固定 `const _PlaylistCover()`，不使用曲目图片。详情页已加载曲目，但头图使用 `widget.coverUrl ?? songs.first.coverUrl`，空字符串不回退，网络失败也不回退。列表与详情没有可复用的已加载完整详情缓存，不应为每个封面调用全量 `MusicPlatform.getPlaylistDetail()`。

平台原封面解析保持：酷狗 `KugouPlatform._parsePlaylist` 使用 `imgurl/image/pic/cover` 并替换 `{size}`，QQ与网易原模型同样已携带封面。没有读取用户实时目录响应，不能断言这次酷狗没有返回封面或字段变更；本次先完整消费既有同步模型，明确补上空／失败后的首曲回退。

## 两个方案

方案A在列表加载时逐份读取完整歌单并生成封面。大歌单和多列表会造成大量分页请求，列表刷新重复拉取，不采用。

方案B仅已构建的可见／邻近行先显示平台封面；缺失或加载失败才懒请求首条。请求最多2个并发，队列项在行销毁或账号变化后不开始；已有结果短时复用，刷新目录后使用新对象重新取。详情直接消费已加载首曲，不额外请求。采用B，不引入完整详情缓存、后台扫描或外部服务。

## 已有API契约与有限读取

只使用仓内已有方法和参数，不增加或猜测端点：

| 平台 | 现有方法 | 本次范围及图片字段 |
| --- | --- | --- |
| 酷狗 | `getUserPlaylistSongs(listid,page,limit)`、`getSharedPlaylistSongs(globalCollectionId,page,limit)`、`getPlaylistSongs(specialid,page,limit)` | 只page1/limit1；按既有editId／collection身份选请求，已知空结果才走既有对应ID回退；响应从 `data.info/songs/list/data/lists` 或根同名列表取第一项，复用已有 `trans_param.union_cover/album_img/image/cover/album_sizable_cover` |
| QQ | `QqApi.getPlaylistDetail(disstid,songBegin,songNum)` | 只begin0/num1；`req_0.data.songlist` 首项，按已有 `songInfo/song/musicData/data` 包装解开，真实album.mid使用仓内已有QQ专辑封面模板，或首曲显式cover |
| 网易云 | `NeteaseApi.getPlaylistDetail(id,n)` | 只n1，不遍历trackIds；`playlist.tracks` 首项 `al.picUrl/album.picUrl` |
| 本地 | `MyPlaylistsNotifier.getSongs(id)` | 本机既有存储读取，不访问平台，取首曲coverUrl或album.coverUrl；不改JSON存储格式 |

如果现有服务忽略条数仍返回多条，本能力只消费第一条并且绝不继续分页，不能把此读数称完整歌单。空歌单（已知songCount为0）不为图片发网络请求；首曲没有图片则保留占位，不挑别的歌冒称首曲。

## 接口、隔离和回滚

新增 `PlaylistArtwork({required Playlist playlist, required double size, double radius=6, Song? firstSong, bool allowFirstSongRequest=false})`。平台封面优先，空或图片加载失败后才首曲；详情提供 `firstSong` 且关闭请求，因此不重复取歌。网易图片复用已经实证的 `loadNeteaseCoverBytes`，避免重复UA；其它网络图片使用独立客户端单浏览器UA，不附账号或平台凭据。文件图片只支持原有真实file路径，不猜资源。

`PlatformPlaylistsPage`三个构造新增 `playlistArtwork=false`；`IkLibraryWorkspace`新增同名可选参数并透传，两者缺省保持旧界面。root仅给Windows IK装配显式开启。详情由独立协作者在已启用桌面表格分支接入共享widget，不同时修改该文件。

首曲provider只在fallback实际构建时监听，按 `Playlist` 原对象短时复用；依赖当前账号对象与音乐会话revision变化，账号退出／更换则失效，队列与结果不跨会话回填。全部旧平台公开签名、原目录provider、歌曲模型与账号存储不改。回滚关闭IK `playlistArtwork`，详情回滚移除共享widget接线即可。

## 验收门规格

| 场景 | 体验门 | 功能门 |
| --- | --- | --- |
| 同步平台封面有效 | 列表和详情均优先显示平台图 | 不请求首曲 |
| 平台封面空／加载失败 | 切到真实首曲图，标题和操作不变 | 只page1/limit1或已有firstSong，不读取完整分页 |
| 首曲也无图／空歌单／网络失败 | 稳定占位，可继续打开歌单 | 无无限重试，无假图，无越界挑别的歌 |
| 大量歌单与滚动 | 页面不因补图堵塞 | 最多2个首曲请求并发，取消未开始的离屏项；rebuild复用结果 |
| 刷新、换号、退出 | 新目录／新账号不残留旧首曲图 | 账号与会话revision变化使旧结果失效 |
| 网易图片与旧调用 | 网易真实图片使用单UA路径，旧默认仍原样 | 新参数默认false，未启用不新增请求 |

本轮只写候选，不执行以上门，不读取用户Cookie或个人接口；上轮24张临时图片清理曾被审批拒绝，本轮不再处理该目录。

## 本轮落盘

已新增 `playlist_first_cover_provider.dart` 和 `playlist_artwork.dart`，并为 `PlatformPlaylistsPage` 三个构造及 `IkLibraryWorkspace` 增加同名 `playlistArtwork=false` 参数透传。只有显式启用的列表会构建补图widget；其内部首曲provider直到平台图缺失／失败才被订阅。补取只消费第一项，最多2条并发，完成结果按当前Playlist实例保留3分钟；刷新产生新Playlist实例后重新取。未开始的离屏／旧会话队列项跳过，换号或同号凭据revision变化时不显示上轮数据；酷狗空首条后可能追加的一次既有ID回退也再次检查作用域。

详情协作者通过相同 `PlaylistArtwork` 传入已加载 `firstSong`，保持默认不补请求。首曲显式cover失败时允许同曲album.cover回退，仍无图才占位；所有图片请求无账号凭据。列表解码按实际显示像素限制，避免48像素图标占用整幅大图解码内存。未修改旧Playlist或Song结构、平台列表解析、目录分页和账号存储。

公开酷狗 `MakcRe/KuGouMusicApi` 的 `module/user_playlist.js` 同样确认现有 `page/pagesize` 用户目录参数，另一个 `playlist_track_all.js` 使用不同端点和 `begin_idx`，本轮没有将其混入或猜成当前仓库API。GitHub目录检索遇到匿名限额；新增代码依据仓内已存在方法、字段解析和样例，不据此宣称当前真实账号接口已经验证。

本轮未创建临时脚本、缓存或测试文件；没有运行测试、analyze、format、GUI、构建或真实个人接口，也没有提交。root负责Windows装配显式参数与统一预览构建。

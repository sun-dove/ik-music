# IK Music 酷狗收藏封面回退修复票据

日期：2026-11-26。状态：用户截图后的最小源码修复候选，未请求真实个人接口，未执行测试、分析、格式、GUI 或构建。

## 一、真实场景与源码原因

截图中酷狗“我喜欢”显示 117 首但仍是占位图；“默认收藏”和“导入歌单”显示 0 首。本次先修有歌曲却无法补图的明确源码缺口，不把另外两个 0 首凭截图改成猜测的数量，也不凭占位图断言平台没有返回图片。

已核对的本地事实：

1. `KugouPlatform._parsePlaylist` 在 `listid == detailId` 时将 `editId` 留空，但 `editable` 仍为 true。首曲封面 helper 却仅凭非空 `editId` 选择 `getUserPlaylistSongs`，导致相同 ID 的用户云歌单先走 `special/song`。此端点拒绝时 `_check` 抛出，外层会直接保留占位，后面的空列表回退并不会执行。
2. 首曲 helper 只读取一层列表；遇到前置空列表立即返回，后面有效的已知列表字段被忽略。其图片字段也遗漏 `sizable_cover`、`info.image` 和 `data.list_info.pic`。
3. 歌单首曲响应可能仅含歌曲标识，没有封面；仓内已有 `getSongInfo(hash)` 单曲元数据读取方法，当前 helper 没有利用它。本次最多补读一首的元数据，不取流、不播放、不分页。

公开源码证据只用于确认字段消费方式，不能代替当前账号接口实证：

- [MoeKoe Home.vue 固定提交](https://github.com/MoeKoeMusic/MoeKoeMusic/blob/6dc7067db1f98048e9b6e6c177b967ff39779b28/src/views/Home.vue) 读取 `sizable_cover`，分享歌曲信息读取 `info.image`。
- [MoeKoe PlaylistDetail.vue 固定提交](https://github.com/MoeKoeMusic/MoeKoeMusic/blob/6dc7067db1f98048e9b6e6c177b967ff39779b28/src/views/PlaylistDetail.vue) 使用 `response.data.songs`、`response.data.list_info`，歌单图取 `detail.pic`，曲目图取 `track.cover`。
- [KuGouMusicApi user_playlist.js 固定提交](https://github.com/MakcRe/KuGouMusicApi/blob/443d4a416dd344ccf7b022b9fb932e324afc77b4/module/user_playlist.js) 与本地目录读取均使用既有 `v7/get_all_list`。另一个公开 `playlist_track_all.js` 使用不同端点，本次不接入、不将其完整响应假装成当前私人云歌单端点。

GitHub 目录 API 本次遇到匿名限额；成功读取的是上述固定提交 raw 文件。没有访问用户 Cookie、令牌或私人歌单响应，因此本修复不能保证截图中三个列表的实时返回字段已经核实。

## 二、最小方案与兼容

方案 A 修改旧平台歌单解析器，让所有旧调用重新保留 editId，并修改全量歌曲解析。这会扩展到既有目录、导入、编辑和详情路径，不采用。

方案 B 只修新增封面 helper 的只读身份判断与图片回退。有编辑 ID，或 `editable == true` 且 ID 为云列表使用的纯数字时，直接使用 `editableId` 请求用户云歌单首条；不能只凭 `editable` 把无编辑 ID 的 `collection_…` 全局集合也当作 listid，共享集合和普通公开 ID 仍使用各自既有端点。成功响应先读取真实歌单元数据封面，再读第一首的已知封面字段，最后在首曲具有有效 hash 时调用既有 `getSongInfo` 补一次图片。采用 B。

不新增 API、模型字段、依赖或公开签名。仅修改 `playlist_first_cover_provider.dart` 新 helper，不改旧 `_parsePlaylist`、`getPlaylistDetail` 或用户数据。零首条目保持现有不补首曲规则；没有平台封面也没有歌曲时继续占位。若需要证明 0 首是否为计数解析问题，需单独取得当前接口证据，本次不猜。

每份补图最多仍为一页一首。已有错误或空数据不会触发整单拉取；既有身份回退至多一次，随后单曲元数据至多一次。全部操作仍处于原并发二的队列、当前账号／会话检查与三分钟短缓存范围内，账号变化后不继续或回填。只取第一首，不扫描后续歌曲寻找“更好看的图”。

## 三、调用方与回滚

调用方为已显式启用 `allowFirstSongRequest` 的 `PlaylistArtwork` 列表回退。平台原图可用时仍不订阅此 provider；详情已提供 `firstSong` 时仍消费已加载数据，不增加请求。回滚只撤新增 helper 内的身份和图片读取逻辑，旧平台接口、目录数量、账号和歌曲记录不变。

## 四、待执行门

以下仅为规格，用户暂停验证，尚未执行：

| 场景 | 体验门 | 功能门 |
| --- | --- | --- |
| 数字 ID 的自建云歌单 `editId == null && editable == true` | 非空歌单可取到真实首曲图 | 第一个请求直接是 userPlaylistSongs，page1/limit1，不先碰 special/song。无编辑 ID 的全局 collection 仍使用共享接口。 |
| 平台详情携带 `list_info.pic` | 优先显示原歌单图 | 不再为该响应额外补单曲元数据。 |
| 首曲含 `sizable_cover` 或 `info.image` | 使用对应真实封面 | 模板替换为 480，非图片字符串不阻断其它有效候选。 |
| 首曲仅有有效 hash | 在原占位位置补上同曲元数据图片 | 最多一次 getSongInfo，不调用播放取流，不拉完整歌单。 |
| 空列表、0 首、无 hash、失败或换号 | 保持稳定占位，列表仍能操作 | 不伪造图片／数量，不扫描其它曲目，作用域变化后不回填。 |
| 旧调用 | 原目录解析与默认 UI 保持 | 未改既有公开方法、模型和返回行为。 |

正式票据长期保留；无临时测试文件和个人响应落盘。编译和预览由主任务统一处理。

## 五、源码落盘

已仅在新 helper 实施上述身份路由、封面候选校验、首项读取和单曲元数据回退；私有源、旧平台解析、`Playlist` 公开模型和 0 首计数均未修改。图片候选必须是 HTTP(S) 或协议相对有效地址，空值、`null`、非图片字符串会继续查下一已知候选，避免一个无效前置字段阻断后面的真实封面。

当前没有个人接口实证，以上门未执行，不能声称截图中的 117 首歌单已经在成品成功加载封面。本修复是供下一份预览验证的源码候选。

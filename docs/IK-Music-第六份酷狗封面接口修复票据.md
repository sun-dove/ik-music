# IK Music 第六份酷狗封面接口修复票据

日期：2026-11-26。范围：Windows 快速预览的酷狗歌单首曲封面回退。用户要求快速出包，暂停 tests、analyze、format 和 GUI 验收继续有效。

## 一、场景与已确认原因

用户第五份截图中，“我的歌单 → 酷狗音乐 → 我喜欢”有 117 首，但封面仍为占位。第五份只根据静态代码修正请求路由和字段，未确认真实接口；本轮不能继续沿用当时的推测作为已解决原因。

本轮为定位这一缺陷，使用本机应用已有酷狗会话做最小只读诊断。会话仅在内存使用，认证请求只发送到酷狗原有域名，不输出或落盘令牌、账号、歌单 ID、曲名、完整个人响应或图片地址，也未改写用户数据。

实际结果：

- 原歌单目录接口成功，三项数量为 0／117／0，三项 `pic` 都为空。用户头像 `create_user_pic` 不作为歌单封面。
- 第五份实际调用的 `/v4/get_list_all_file`，page 1／pagesize 1／show_album_info 1，返回 `status:0,error_code:20010`，没有首曲。
- 同一会话、同一列表的新 `/v4/get_list_all_file_v3`，page 1／pagesize 1，另带 `type:0,area_code:1,allplatform:1,show_cover:1`，返回 `status:1,error_code:0,count:117` 和一条歌曲。首曲已有 `cover` 与 `trans_param.union_cover`。
- 按当前图片组件的单一浏览器 UA 请求这条 `union_cover`，HTTP 200，JPEG 46,962 字节，480×480，内存像素解码成功。

因此确认的失败点是旧首曲接口拒绝，而不是这张图的下载或解码。旧接口的 20010 不能在此场景被直接推断为整个账号失效，因为同会话目录和新接口都成功。证据见[脱敏诊断回执](验收证据/酷狗首曲封面-20261126-定向诊断.json)。这不是成品 GUI 验收或完整回归。

公开协议对照：[KuGouMusicApi 固定提交 playlist_track_all_new.js](https://github.com/MakcRe/KuGouMusicApi/blob/443d4a416dd344ccf7b022b9fb932e324afc77b4/module/playlist_track_all_new.js)。本轮以实际响应为依据，不假设所有字段或账号都等同。

## 二、最小方案与兼容

方案 A：替换旧 `getUserPlaylistSongs` 的端点。会改变既有全量歌单详情、同步、导入及其他调用行为，不采用。

方案 B：新增只读 `getUserPlaylistCoverPreview(String listid)`，固定只请求第一页一首，使用已实证的新端点和 `show_cover` 参数。仅新增 Windows 封面 provider 的自建歌单路径及已有云回退调用新方法。采用 B。

这是既有酷狗接入的简单缺陷修复，不新增服务、依赖、存储或复杂流程。保持旧公开方法的签名、实现和返回行为。新方法仍使用同一 `KugouApi` 的会话、签名和既有 Dio。原并发二、作用域检查、平台封面优先和最多首曲补图保持。0 首不请求首曲，不借头像或其他歌单伪造图片。

## 三、调用方与回滚

- 新端点常量：`KugouEndpoints.userPlaylistCoverPreview`。
- 新 API：`KugouApi.getUserPlaylistCoverPreview`，只供 `playlist_first_cover_provider.dart` 的酷狗封面分支调用。
- UI：已显式开启 `PlaylistArtwork.allowFirstSongRequest` 的 Windows 音乐库歌单列表。平台原图存在且可用时仍不发首曲请求。
- 旧 `getUserPlaylistSongs`、`getPlaylistDetail`、Mconnect、Android、账号与歌单记录不改。
- 回滚：将新增封面分支恢复第五份调用，移除新增方法及端点常量；不涉及用户数据迁移。

## 四、门与本轮范围

| 真实场景 | 体验门 | 功能门 | 当前状态 |
| --- | --- | --- | --- |
| 117 首歌单无自定义封面 | 原占位位置显示第一首真实封面 | 新接口只请求 page1／pagesize1，解析 `data.info[0].trans_param.union_cover` | 旧请求实红；新协议请求与图片下载解码成功，产品 GUI 待用户查看 |
| 0 首歌单且原图为空 | 保留占位 | 不请求首曲，不伪造数量或图 | 沿用规则，未执行产品门 |
| 网络失败或换号 | 列表仍可操作，不回填其他会话结果 | 原队列及会话检查继续生效 | 未执行产品门 |
| 平台原图已可用 | 显示原图 | 不追加首曲请求 | 未执行产品门 |
| 旧平台调用 | 原有行为 | 旧方法和默认接线不变 | 源码范围核对；未做回归 |

本轮只进行上述故障定位和随后预览编译，不恢复暂停中的测试或 GUI 验收。诊断脚本通过标准输入运行，图片与响应仅在内存，没有新增临时验证文件。本文和脱敏回执为正式交付资料，长期保留。

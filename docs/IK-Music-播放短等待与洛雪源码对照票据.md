# IK Music 播放短等待与洛雪源码对照票据

日期：2026-11-26。状态：用户再次要求缩短失败歌曲的等待，允许只读参考洛雪公开源码；本轮只实施源码，不运行测试、检查、构建或产品验证。

## 问题与真实来源

前一轮的 7 秒解析、6 秒加载、25 秒会话只在 `router.guarded` 为 true 时生效。音源策略的 `autoSwitch`、`highestQuality`、`sourceFirst` 全部 false 时，远程歌曲仍走旧播放器的 10 秒取流、10 秒加载和失败后控制器重建／再次加载。仅继续减少三个数字不能修复这个遗漏。

另有叠加：平台 Dio 缺省连接／收发 15 秒，幂等 GET 最多重试两次并退避；当前官方多源回调仅 QQ 显式绑定取消，网易、酷狗没有；同一坏源会在最高可用模式的不同音质重复联网；媒体加载失败会走基础播放器的重建。Dart Future 超时本身不能撤销底层连接，因此必须同时取消请求、阻止层内重试和隔离迟到结果。

本次只读核对洛雪仓库固定提交 `323e4bac505da428adae8db6b58039fb2b36b86d`，完整树返回 `truncated=false`，未下载或执行项目：

- [usePlayEvent.ts](https://github.com/lyswhut/lx-music-desktop/blob/323e4bac505da428adae8db6b58039fb2b36b86d/src/renderer/core/useApp/usePlayer/usePlayEvent.ts#L16)：加载看门狗实际为 **25 秒**；同曲首次超时刷新 URL，再超时跳曲；媒体错误最多刷新两次 URL。
- [action.ts](https://github.com/lyswhut/lx-music-desktop/blob/323e4bac505da428adae8db6b58039fb2b36b86d/src/renderer/core/player/action.ts#L66)：取流失败有一次即时再试，429 延迟 2–6 秒；用曲目标识和取消阻止陈旧结果。
- [request.ts](https://github.com/lyswhut/lx-music-desktop/blob/323e4bac505da428adae8db6b58039fb2b36b86d/src/common/utils/request.ts#L12)：通用网络默认 **15 秒**，默认最多三次重试。不能把“洛雪统一三秒切源”作为结论。

本轮借鉴的是错误事件直接推进、明确上限和取消边界，具体 3／3／9 秒来自用户要求的更短等待；仍留在当前曲，不复制洛雪自动跳下一曲的行为。

## 两种方案

| 方案 | 影响 | 选择 |
| --- | --- | --- |
| A：全局把 Dio、基础播放器和所有下载超时改短 | 会影响登录、个人推荐、收藏、下载、本地文件和其他入口，仍有多层重试与迟到请求问题 | 不采用 |
| B：IK Windows 的 `quickSourceRecovery` 覆盖全部远程播放，按候选限定网络与媒体预算 | 自动切源关闭时仍只使用原策略允许的候选；网络限时和禁止重试仅对播放候选 scope 生效，其他请求不改 | 推荐并按用户继续指令实施 |

## 接口与实现

1. `quickSourceRecovery` 缺省仍 false；开启时所有远程曲目进入 `SourceSession`，无需用户打开自动切源。候选生成保持现有 `SourceCollection` 策略，不擅自启用其他源，不更改音质偏好。
2. 快速候选解析 **3 秒**、装载 **3 秒**、会话解析／加载预算 **9 秒**；保留剩余候选和继续入口。原生设备停止、清理与销毁可能有额外耗时，不能声称任何损坏设备都在九秒内返回。
3. `SourceSession` 新增缺省 false 的 `skipUnreachableSources`。快速播放遇到确定的网络、DNS、超时或服务不可达时，本轮跳过该源剩余音质；缺曲、无会员或某档位不可用不推断整源不可达。旧下载和会话不传参数，保留原规则。
4. 新 `QuickSourceTransport.install(Dio)` 装配请求拦截器；新 `QuickSourceTransport.run(token, request, failedHosts: ...)` 建立仅限当前异步调用链的播放 scope。候选内部所有官方元数据、取流、LX HTTP 请求绑定同一取消，单请求不超过 scope 剩余三秒；scope 内明确网络／5xx 失败不进入旧重试拦截器，坏 host 在当前取流轮次内快速拒绝。scope 外原样透传，不修改全局 Dio 配置、Cookie 或公开账号 API。
5. 主任务仅在 Windows 给 `qqDio`、`neteaseDio`、`kugouDio`、`sourceEngine.dio`、`customSourceDio` 安装拦截器；quick 播放器内部包裹 `resolve`。旧非多源策略允许的 HTTP 回退保留，沿用原缺曲／权益／音质错误矩阵并共享同一三秒窗口；LX 已在候选中，不通过 legacy 再解析一次。下载及后台初始化不进入 scope，不减少它们的预算。
6. `VideoPlayerNotifier` 仅新增可选 `audioDisposeTimeout` 透传，默认保留基础播放器三秒值；quick 销毁等待为 500 毫秒，受管媒体的停止、暂停和播放命令各最多等待一秒。基础播放器的通用音频操作预算保留，避免改变本地文件路径。故障仍走原重建隔离，禁止同一失败 URL 在重建后重新联网。已成功媒体保存设置不断音、暂停／恢复、迟到 token 保护继续保持。
7. 媒体加载不只等待 `open()` Future：quick 包装监听加载期间的真实错误，明确错误立即失败；准备好才交给播放。不能把只有 URL 或命令已投递当成音频可播，旧控制器事件在新候选开始前失效。

上述为确定性网络错误与状态机，不需要 Jev。

## 调用方与回滚

| 文件 | 变化 |
| --- | --- |
| `multi_source/source_coordinator.dart` | 新可选源级网络失败跳过，默认不启用 |
| `multi_source/multi_source_player.dart` | quick 全远程覆盖、3／3／9、作用域调用和媒体错误及时反馈 |
| `multi_source/quick_source_transport.dart` | 新增仅播放作用域的网络包装 |
| `lib/l10n/ik_source_recovery_strings.dart` | 新增 quick 专属失败、DNS 与剩余候选文案，原 SourceStrings 保留 |
| `playback/video_player_notifier.dart` | 新可选构造透传，旧默认保留 |
| `main_video.dart` | 主任务添加 Windows 拦截器装配，其他账号功能不进入 scope |

不改基础 `PlayerNotifier`、账号 API 公开签名、原生音频后端、UI、源更新器或下载逻辑。回滚 Windows `quickSourceRecovery` 即恢复旧路径；可同时移除五处 install，新包装无 scope 时本身不改变行为。无存储迁移，不清理用户数据。

## 待验收门（本轮不执行）

| 场景 | 功能门 | 体验门 |
| --- | --- | --- |
| 三个自动策略全 false | 远程歌曲仍进入短会话，候选不超出原策略 | 失败不再落入旧长等待，设置开关不被修改 |
| DNS、连接／收发超时、5xx | 候选三秒取消，下层重试零次，坏 host 不反复联网 | 及时显示失败并尝试下一允许候选 |
| 最高可用下同源多音质 | 网络失败跳过该源剩余档位，缺曲／档位错误仅影响对应候选 | 明确不适用或失败，不把未尝试写成播放成功 |
| 媒体 URL 返回但解码器报错／加载不完成 | 加载期错误立即失败，三秒装载上限，旧 token/实例不串入新媒体 | 不先显示成功后长时间假播放，不出现旧歌声音 |
| 九秒预算耗尽 | 已试／未试完整保留，继续不从第一个坏源重来 | 显示继续入口，仍停在当前歌曲 |
| 设置保存、暂停恢复、快速切歌 | 沿用有效媒体及 generation/token 保护 | 设置不断音，暂停不自动播，迟到不抢播 |
| 收藏、推荐、登录、下载、后台初始化 | 不在播放 scope 的请求原超时和重试保持 | 其他页面无新增短超时错误 |

当前只读了上述公开源码和本地实现，未实时请求任何用户歌曲或运行产品。所有门待验，不能写成已通过。

## 源码实施结果

已落盘 quick 全远程 3／3／9 秒路径及五个 Dio 的作用域装配接口。网络、DNS、5xx 在播放 scope 内即时完成失败，不等待脚本自行反复请求；同轮坏 host 与整源剩余音质不重复联网。作用域状态逐播放会话创建，迟到旧请求不会污染下一首的 host 集合。

额外只读本机 `media_kit-1.2.6` 的 `NativePlayer.open`：它只等待 `loadlist` 和 `playlist-pos` 命令，未等待实际音频读入；项目 Windows 控制器随后会发 ready。quick 因此在三秒加载窗口内等待新媒体的正时长事件或明确错误，不把命令提交完成误当已可播放。流媒体不提供时长时此路径会按超时失败；本项目处理歌曲流，未知时长的直播不是本轮承诺范围。取消释放本轮监听，旧控制器的 Future 与事件保留令牌隔离。

预算耗尽显示“已尝试 X 个候选，剩余 Y 个；可继续尝试”，尝试数不含已跳过项且继续标志不丢。剩余为零显示“当前启用且兼容的候选均未能播放”；因内部错误提前停止时显示请求中断，不冒称已经尝试全部。DNS 能确定时显示“音源地址无法解析”，不把模糊故障猜为 DNS。

本轮未运行 tests、analyze、format、build、GUI、实时音源探测或其他验证命令，未提交，未操作用户播放器进程或保存配置，未生成临时验证文件。以上是源码结果，实际耗时与运行兼容仍待验。

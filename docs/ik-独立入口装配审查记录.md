# ik 独立入口装配审查记录

日期：2026-11-20。范围为实际 `VideoMusicApp(redesign:true)`、独立路由、`main_video` 的账号、下载、播放和个人能力装配。仅查阅源码不足以宣布完成，因此新增正式 `test/ik_app_integration_test.dart`，以真实 Router、页面及 providers 验收；边界只替换平台网络/认证/音频设备，Hive 使用每次创建的系统临时目录，SQLite 使用真实内存数据库。

## 已确定问题与最小兼容修复

| 问题与复现场景 | 证据 | 最小修法与当前状态 |
| --- | --- | --- |
| 改版首次装配时本地曲库在 build 阶段第二次初始化 | 实际装配门抛 Riverpod `Tried to modify a provider while the widget tree was building`，调用链为 `initState → _initialize → _initializeLocal → LocalMusicNotifier.initialize → loadFromIndex` | 仅 `redesign` 分支将 `_initialize` 移到首帧回调，增加 mounted 检查；旧默认入口仍立即启动。已由根授权子任务修改，后续同门不再出现此异常 |
| 从首页 `/login/:platform` 登录后不自动同步收藏；外部账号变化留下旧收藏 | 旧监听器只处理 `expiredPlatform`，只有 `_account` 自己 push 的返回才调用 `_sync` | 根已新增改版账号 ID 变化监听，失效 epoch、清空当前来源、安排新同步；装配门检查登录成功、A→B 与退出 |
| 移动版“统一音质”只读写 QQ | `_myPage` 无 WindowsAppearance 时固定传 QQ 到 `_quality`，网易和酷狗继续读旧分平台值 | 根已新增可选统一 preferences，独立 main 显式传入；旧默认不变。装配门检查三个平台与下载 resolver 一致 |
| 非桌面显示不可点击的背景/字体入口 | 原 WindowsMyPage 共用到移动版，但 onBackground/onFont 为空 | 根已新增可选显示开关，只在新版非桌面隐藏无能力项；旧默认保留 |
| 共用内容页绕过独立下载音质 | Album/Toplist 缓存、PlaylistDetail 批量下载硬编码 low；共享歌曲菜单自动挑会员最高档；DownloadButton 长按也是 low | 根已新增缺省为空的下载品质 provider，独立 main 注入统一读取器，公共缺省行为保持 |
| 分享歌单与备份文件仍露旧品牌 | ShareService 使用 AppConstants.appName；BackupService 固定 mconnect-backup 前缀 | 已通知根和运行时子任务，以可选品牌/前缀参数隔离；保留 mconnect:// 与格式标签以兼容旧分享数据 |
| 新接入的分享入口缺少独立入站处理 | Android Manifest 已声明 ACTION_VIEW/ACTION_SEND，而 main_video 未挂 DeepLinkService；原 app 装配绑定 Mconnect router | 已通知运行时子任务增加独立导航适配，不能直接使用原 appRouter |
| 悬浮歌词宿主拒绝时缺少页面失败反馈 | 共用 SettingsFloatingLyricsPage 的启停 await 没有捕获服务异常 | 已通知运行时子任务补独立能力与错误反馈，不把开关值等同于窗口已显示 |
| 非法详情返回首页触发重复 GlobalKey | 实际装配门 `go('/album/not-a-platform/missing') → 回到首页 → 打开播放器` 捕获 `Duplicate GlobalKey` | 根授权 root GoRoute 使用恒定 key 的 NoTransitionPage，避免旧首页退栈动画与新首页同时拥有 _homeKey；同门已绿，最终全集再次通过 |
| 账号变化时共享平台歌单缓存可能仍属于旧身份 | platformPlaylistsProvider 不 watch auth，页面仅 initState 加载；现有 load token 只区分请求，不区分身份 | 已建议仅独立 runtime 在身份变化时 invalidate 并重新加载，原 Mconnect 默认保持 |
| 带路径冷启动链接抢在独立链接运行时之前成为 Router 初始页面 | Android 接受 `mconnect` scheme，现有歌曲解析器也接受 `mconnect://song/play?...`；GoRouter 14.8.1 原样使用非空 path，此时首页尚未挂载，链接运行时推播放器也找不到首页 State | 先写真实装配门：延迟 app_links 初始返回，必须先显示首页，然后链接交付打开同一播放器并可返回；根授权独立 Router 固定从 `/` 启动 |
| Android 热链接由 Flutter 默认深链和 app_links 同时处理 | Manifest 未关闭 Flutter 自动深链，独立运行时已经订阅 app_links；两条路径可能竞争导航 | 根授权新增 `flutterDeepLinkingEnabled` 占位符，独立 `VIDEO_MUSIC_BUILD` 设 false，原 Mconnect 设 true 保持原默认；先在正式路由门检查隔离约束 |

下载主入口当前保留旧的细分错误修复与已下载播放页；独立 `/downloads` 同时提供共享下载中心。装配门会分别验证可访问，不强迫删除原有精细恢复能力。

上述冷/热链接修复的调用方为独立 `createIkRouter`、Android `MainActivity` 的 Flutter 启动配置及独立 `IkLinkRuntime`；不改公开分享格式、歌曲解析器或原 Mconnect 路由。回滚时撤销独立 Router 初始位置及 Android 占位符接线即可，用户数据无变更。方案 A 让 app_links 统一交付并确保首页先挂载；方案 B 让 GoRouter 自己解析外部分享并重写共享解析器。选择 A，继续使用已验证的分享协议和播放器，避免两套解释逻辑。

## 正式装配门覆盖

门包含四导航、推荐/榜单/新歌与榜单详情、歌单/本地/历史/下载、音效/悬浮歌词/统计/智能编辑器/备份、搜索更多进入专辑与歌手、同一播放器与迷你播放器/队列返回、非法详情返回首页、路由登录后的收藏同步、窄屏实际页面。不能把目录匹配测试代替这些点击路径。

初次运行在真实启动异常处失败；修复后进入页面交互。已修正测试夹具的中文返回按钮、播放器收起按钮、限定所有者的有限滚动和真实 IO 推进方式。账号 ID 监听曾精确临时停用，正式账号门在 `syncs=[]` 缺少 `(qq, account-a)` 处真实变红（6 秒、退出码 1），随后立即恢复，最终全集同门通过。

冷启动门和 Android 隔离约束在修改前真实失败（5 秒、退出码 1）：首帧找不到 `IkShell`，Manifest 缺少配置元数据。修复独立 Router 初始位置、占位符后，冷启动单门 3 秒通过；最终两个正式文件一起运行，`flutter test --no-pub -j 1 test/ik_routes_test.dart test/ik_app_integration_test.dart --timeout 45s` 在 39 秒内 **11 门全部通过、0 跳过、退出码 0**。其中 9 条是实际应用装配点击，2 条是路由匹配与 Android 构建隔离约束。测试文件与 Router 的 Dart analyze 为 0 问题，最终格式检查无改动。

跨门曾卡在第三条品质保存后的下一条 `setUp settings.clear()`，并非智能歌单或页面死循环：Hive `ReadWriteSync` 保留上一个写入 Future 的 FakeAsync zone，下一条门的监听落进已结束 zone。夹具通过既有 `WindowsMusicPreferences.write` 边界，在 `setUpAll` 捕获的真实 IO zone 内执行实际 `settings.putAll/flush`，保持真实 Hive；额外重新构造偏好并 `load()`，三个来源仍读回无损档位。修复后质量和工具相邻两门 10 秒通过，全集继续通过。夹具播放器使用既有零延时记忆落盘参数与 Noop 记忆存储，避免无关的五秒定时器留到 widget invariant；产品定时器行为未改。

此处证据覆盖 Flutter 实际装配与配置隔离，不等同于 Android 设备 Intent 或 Windows 安装包目视验收，后者由主任务构建安装继续完成。

## 临时文件与保留边界

正式测试与本文长期保留。第一次失败运行及两次被中断运行的临时 Hive 留下以下精确目录，均为本门创建的 settings/local_music/listening_stats/smart_playlists Hive：

- `C:/Users/Sun/AppData/Local/Temp/ik-app-integration-688d6aef`
- `C:/Users/Sun/AppData/Local/Temp/ik-app-integration-5a0f6690`
- `C:/Users/Sun/AppData/Local/Temp/ik-app-integration-dfc983ef`

逐一核对路径和来源后，三次原生 PowerShell 精确删除均被自动审批拒绝（blocked by policy），没有重试被拒绝动作或换语言绕过，不能声明已清理。后续测试提前打开所需盒，正常结束执行精确目录校验与清理，单门临时数据已按此方式正常释放。临时 debugPrint 已全部移除；日志 `C:/Users/Sun/AppData/Local/Temp/ik-app-integration-current.log` 在最终取证后首次精确删除同样被自动审批拒绝，保留本次 11 门完整通过证据，没有再尝试。

最后两次定位跨门 Hive 锁的运行也因精确停止而留下 `C:/Users/Sun/AppData/Local/Temp/ik-app-integration-b16225d6` 与 `C:/Users/Sun/AppData/Local/Temp/ik-app-integration-4279731f`。已核对创建时间分别对应 14:11:29 和 14:15:02 的本门运行；根据主任务要求不再重复已遭策略拒绝的同类清理动作，保留明确记录。最终正常 11 门执行的临时目录已自动关闭并删除。

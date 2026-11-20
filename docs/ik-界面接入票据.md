# ik 界面接入与体验门

日期：2026-11-20。范围由《ik-完整改版实施与验收》K03–K06、K08 及用户“在这一版都做完”确认。

## 问题与接入

新主题已经生成青绿色配色，但共享 `VideoTheme.canvas/surface` 仍返回旧粉灰色，导致背景、迷你播放器和播放页不一致。搜索与曲库用跨来源的 `dedupeKey` 高亮，会同时选中不同来源的同名歌。首页缺少推荐来源说明、空状态和失败区域操作；曲库需要清楚区分未登录、同步中、部分同步和网络失败。

采用已有独立壳方案：为共享主题新增可选颜色扩展读取，缺省颜色和字号精确不变；独立页面使用平台和歌曲 ID 识别当前曲目。推荐与搜索复用既有请求状态，不更换数据存储或播放器。播放器新增可选 `WindowsSourceDetails`，只显示调用方提供的已知来源、格式、码率与状态，不推测真实音质。可点卡片打开详情及既有换音质/尝试详情操作。

## 调用方与回滚

| 文件 | 受影响调用方 | 回滚 |
| --- | --- | --- |
| `VideoTheme` | 独立页面、Windows 外观、旧 Video 页面 | 删除新主题扩展，返回旧配色 |
| `VideoMiniPlayer` | 独立与旧 Video 外壳 | 未带新主题扩展时仍为原字号 |
| `WindowsPlayerPage` | `VideoMusicApp._playerPage`、既有测试 | 省略新增可选 `sourceDetails` 即保持旧界面 |
| `IkSearchPage/IkLibraryPage/IkHomePage` | 新四主区 | 停用 `redesign` 返回旧入口，无数据迁移 |

## 正式门

`test/ik_ui_experience_test.dart` 验证主题旧默认、新主题透明背景、搜索部分失败/重试/分页/筛选、跨平台高亮、收藏隔离/未登录/同步反馈、首页来源说明与操作；`test/ik_source_card_test.dart` 验证音源详情、未知值与播放页窄屏及字号缩放。它们属于用户要求的正式回归交付，长期保留。先运行失败断言，再实现到绿，不将静态路由匹配作为页面验收。

## 推荐账号代次与动态取色补充

推荐共享方法的旧调用方仍可使用 `loadRecommendations()`；新增 `loadLatestRecommendations()` 先清空可能属于旧账号的内容并递增请求代次，完成后只接受当前代次。独立 `IkRecommendationsNotifier` 使用新方法；`main_video` 通过 provider override 接入。调用方为首页、推荐详情及登录后刷新；原 Mconnect provider 继续旧类。回滚只需移除独立 override。`test/ik_recommendations_generation_test.dart` 验证迟到旧账号响应不会覆盖当前内容。

评估 D5 的封面动态取色由 Flutter 内建 `ColorScheme.fromImageProvider` 实现，复用现有封面缓存，不新增依赖或外部服务。仅新版播放器提供 `IkCoverTheme`，封面缺失/解码失败使用原主题；封面和明暗变化以代次隔离，旧请求不得覆盖新封面。用户自定义背景继续透明。`test/ik_cover_theme_test.dart` 使用内存生成的真实 PNG 验证红、蓝图像取色和失败回退，不写临时图片。

## 本轮执行结果

2026-11-20 的实际失败门分别捕获：新版画布仍是旧粉灰、同名跨来源歌曲同时高亮、未登录时旧账号列表仍可见、首页缺少推荐出处；音源卡片未创建；安全推荐方法与封面组件缺失；详情 Scaffold 盖住背景；320 宽/150% 字号下同步错误只有约 12px 的文本宽度；推荐等待最慢来源后才显示。上述失败后完成实现，再运行同门。

最终四个新文件共 **49 条通过，0 跳过**：`ik_recommendations_generation_test` 2 条、`ik_cover_theme_test` 1 条、`ik_ui_experience_test` 20 条、`ik_source_card_test` 26 条。覆盖搜索部分失败/登录/分页、收藏与账号状态、窄屏错误可读和按钮可点、首页入口与推荐出处、未知音源字段、透明背景、迷你播放器、深浅主题 × 320/720/900/1200 宽度 × 100/125/150% 字号、真实封面取色及旧请求迟到隔离。取色测试最初因图片解码从 Flutter 假时钟区启动而未完成，将挂载置于 `runAsync` 后获得实际 PNG 取色结果；未修改期望或假定颜色。

另运行既有 `windows_music_ui_test` 20 条、`windows_music_theme_test` 4 条、`recommendations_provider_test` 9 条，**33 条全部通过**，确认旧构造、颜色、关闭文案、歌词跟随、背景、头像和旧推荐行为保持。最后全仓 analyze/回归、成品安装与真实 Windows GUI 由总验收记录，不用本页的 widget 门代替。

安全推荐现以每来源完成先更新，局部重试只请求失败平台。自定义背景时新版 Scaffold/AppBar 透明，导航表面保留 86% 不透明度；旧主题未装配扩展时值不变。窄屏/大字账号操作移到状态行下方，保留完整错误说明。所有新增测试和本票据是正式交付，没有本子任务临时文件待清理。

## 音源真值与本地收藏状态补充

复核发现，多源会话经 `ResolvedSource` 播放脚本返回的 URL，未必刷新官方 `videoStreamInfoProvider`。卡片若读取该歌旧缓存，会把上一次官方格式/码率当作当前备用源事实。新增 `SourcePlaybackView.sourceName/format/bitrate` 可选字段，只在当前 `_active` 已开始播放时填入；加载、切歌、暂停、取消和失败的状态缺省为空。原公开参数与原文案不改。新版播放卡片在多源状态下只读取这组字段，未知即未知；旧窗口路径保留原来的 `qualityAbove` 行为。受影响调用方为独立播放器进度回调及 `_playerPage`；回滚取消新版字段读取即可，播放算法和存储不变。

`IkLibraryPage` 新增可选 `localLoading=false`、`localError=null`、`onRetryLocal=null`，由独立入口接 `likesProvider` 并以既有 `loadAllLikes()` 重试。界面区分加载、读取失败、真正空列表；失败时保留已有曲目。新增门先以缺少参数/字段失败，再实现并复验，正式门包括 `ik_source_evidence_test`、本地收藏体验门与独立装配中的历史官方数据不污染当前卡片断言。

补充实际执行：`flutter test --no-pub -j 1 test/ik_source_evidence_test.dart test/ik_ui_experience_test.dart test/ik_source_card_test.dart test/video_multi_source_player_test.dart`，**53 条通过、0 跳过，测试计时 13 秒**。前两组新增参数/字段编译红与未知来源摘要显示平台名的断言红均已运行；实现后三组新门及原多源播放五门全部绿。实际播放源信息在切歌、取消后清空，迟到解析不回填；本地收藏加载/失败不误显示空库，可点重试；未知来源卡片不把所属平台冒充实际来源。独立装配中故意注入历史官方 FLAC/990kbps 的集成断言另由总装配门执行，不用本页定向门代替。

## 导入导出可达品牌补充

独立入口沿用共享歌单页后，导出菜单/分享标题仍显示 `Mconnect JSON`，导入提示及本地分享导入失败也带旧品牌。这属于已确认改名范围内的文案接入缺陷，不新增模块。共享 `PlatformPlaylistsPage` 新增可选 JSON 显示名，`ImportPlaylistPage` 新增可选格式提示和本地导入失败文案，`MyPlaylistsNotifier` 新增可选无法识别/导入失败文案。缺省继续原值；仅 ik 路由和 `main_video` 的 provider override 传入集中于 `IkStrings` 的新文案。受影响调用方为 ik 路由、独立 provider 容器以及两份既有页面测试；旧入口不传参数，不改变存储、公开返回值或导入导出协议。

回滚移除独立入口新增参数和 provider override 即可。功能门确认 `mconnect.playlist` JSON 标记和 `mconnect://` 分享协议仍可往返；体验门确认新版菜单、分享标题、导入提示、无法识别及失败状态不显示旧品牌，原入口仍显示既有值。门补在正式 `platform_playlists_page_test.dart` 与 `import_playlist_page_test.dart` 中，先运行到红，再实现到绿；不新增临时测试文件。

实际先执行两页门，因新可选参数和集中常量缺失编译失败；实现后连同原门及 `i18n_budget_test` 共 **23 条通过、0 跳过，13 秒**。其中新增五门覆盖新版 JSON 菜单及分享标题、ik 分享署名、真实兼容链接的写入失败，以及新旧入口 provider 的无效链接/异常文案。硬编码中文实测 **867 处/97 文件**，未抬高基线。

## 字体失效显示与预览主题补充

用户导入字体被外部删除时已有真实回退与错误提示，但设置行仍显示保存的旧字体名。新增 `WindowsAppearance.currentFontLabel` 只供 ik 入口读取，字体错误时明确显示默认字体；旧 `fontLabel` 继续原值，不清用户设置。共享 `showWindowsFontPicker` 新增可选 `preserveTheme=false`，新版调用传入 `true`，只以选中字体替换当前主题文字字体，保留青绿配色和新版字号。旧调用仍用原外观预览逻辑。调用方为独立“我的”页两处装配；回滚移除两处新参数/读取即可。

既有 `windows_music_appearance_test` 的真实字体导入、删除、重启回退门新增当前显示名断言；既有 `windows_music_dialogs_test` 新增新旧预览配色与字体切换断言，先编译红再实现到绿。错误行继续用已有可恢复提示，不新增弹框或独立功能。

执行结果：先运行取得新 getter/可选参数缺失的编译红；实现后真实字体文件复制、导入、删除、重启与回退的 **9 条外观门通过**。字体弹框门初次新加的旧字号断言错误地用原始主题中空字号比较挂载后的 Material 默认值，改为比较切字体前后的实际主题字号，同时固定新版正文为 15px，再完整执行 `windows_music_dialogs_test` 9 条、`ik_ui_experience_test` 22 条、`import_playlist_page_test` 10 条，**41 条全部通过、0 跳过，21 秒**。定向 11 个变更源码/测试文件静态检查 **0 问题**。

同次包含根任务增加的共享排名字号门：此前已实际运行得到期望 12、实测 11 的断言红，根任务按新版主题适配共享页小字后，该门和全部 22 条独立界面门一起绿。上述文件与票据为正式回归交付；本子任务没有额外临时产物需保留。
## 可达共享页面的小字号补充

独立路由接入的专辑、歌手、本地音乐、收藏、榜单与下载页仍有 10–11px 的辅助文案。原 Mconnect 必须保留现状；本轮仅在检测到已确认的 ik 主题扩展时，将这些低于 12px 的文字提升到 12px。新增 `VideoTheme.readableSize(context, legacy)`，旧主题原样返回传入字号，不修改页面构造、业务回调或数据。调用方为上述页面和榜单排名徽标，以及独立下载弹层。回滚为去掉这些字号读取，保留已有主题。正式体验门对相同排名徽标检查旧 10/11 与新版 12，并在大字号布局下复验。


# IK Music 歌单详情分列与歌曲右键快改票据

## 场景、授权与范围

用户截图中歌单详情仍是歌名／歌手堆成两行的ListTile，宽屏中部大面积空白；用户希望歌手单独放在中间，并支持歌曲行右键操作。主任务已授权现有展示与交互的小增强，用户仍暂停验证。本子任务只改歌单详情、必要表格展示和共享菜单扩展，不改最近播放页面，不运行测试、分析、格式检查、GUI、构建或安装，不提交。

实际路由为IK路由中的 `/playlist/:platform/:id` → `PlaylistDetailPage`。主任务在新版 `createIkRefinedWorkspaceRouter` 接线，不改旧路由公开签名。

## 两个方案与选择

方案一直接替换公共歌单页面和歌曲菜单会扩大旧入口影响；方案二增加默认关闭的桌面表格分支及新的定点菜单入口，旧调用缺省保留，采用方案二。`PlaylistDetailPage.desktopTable = false`，宽屏开启后使用歌曲／歌手／专辑／时长／操作列，沿现IK歌曲表格的间距、边线、字号和当前播放底色；窄宽度保留两行歌曲信息。

右键和更多按钮使用同一个新菜单入口，仍复用既有SongAction动作枚举、liveSongActionDeps与performSongAction，不复制收藏、下载、分享等行为。新菜单在鼠标globalPosition或更多按钮处显示现代圆角锚定菜单，旧showSongActionsMenu与showSongActionsSheet公开签名不变。近期页面需要的额外“移除记录”动作由其子任务提供回调；共享扩展不删除任何数据。

## 接口与受影响调用方

1. 新增 `PlaylistDetailPage.desktopTable` 可选布尔，默认false。新分支保留播放全部、单曲播放、下载按钮／音质选择、长按进入多选、全选／全不选、批量下载、批量加入／移出、自建歌单拖动排序。
2. 新增 `showSongActionsMenuAt(context, ref, {required song, Offset? position, isLiked, isDownloaded, isLocal, List<SongMenuExtraAction> extraActions})`，position为空时锚定调用按钮，非空时按指针位置打开。
3. 新增SongMenuExtraAction只描述额外菜单标签、图标、enabled和异步onSelected回调；现有SongAction枚举、原入口签名和默认结果类型不变。新入口返回原SongActionResult并沿用原成功／失败反馈。
4. 共享展示私有函数可提取泛型复用，但旧showSongActionsSheet仍使用PopupMenuItem<SongAction>原类型、原样式和原锚定策略。受影响的旧调用为共享showSongActionsMenu及直接showSongActionsSheet调用方；均不需要改参。新调用方仅歌单桌面分支和最近播放新分支。

## 回滚

主任务撤desktopTable接线即可恢复旧歌单行；最近播放新入口可单独撤接。旧菜单仍可调用，数据操作完全由既有依赖处理。回滚不得删收藏、文件、下载或播放队列；不动先前底栏、AX或歌词样式修正。

## 待执行门规格

本轮不执行，只记录后续门，不能宣称已通过：

- 宽屏列标题与歌曲行列宽对应，长歌名／歌手／专辑省略，时长和操作可见；窄宽度保留可读两行，不横向溢出。
- 鼠标右键在点击处打开，更多按钮在按钮处打开；二者行动列表和实时喜欢／下载状态一致；点外和Esc关闭，无旧底部弹窗。
- 点击行播放仍使用完整歌单，长按／多选、批量操作和下载按钮保持；自建歌单拖动排序及失败回滚不变。
- 本地文件仍按原isLocal限制菜单项；未登录、下载失败、收藏失败等沿原错误反馈，不伪造成功。
- desktopTable缺省false与原共享菜单入口保留旧行为、类型及AX分支，不要求改所有调用方。

## 快速候选落盘记录

`desktopTable` 分支及两种歌曲行入口已落盘。内容宽度达到760×文字缩放时显示五列，歌曲／歌手／专辑弹性比例5:3:3，时长64×文字缩放、操作96、序号／勾选／拖动区40像素；窄窗口保留歌名和歌手两行。表格沿用现有IK边线、当前播放底色、14号主文字与40像素封面，不引入新表格框架。自建歌单仍在原ReorderableListView中，长按多选及全部批量函数没有替换。

新共享入口已提供给最近播放子任务：`SongMenuExtraAction` 的字段为label、icon、onSelected和enabled，额外操作执行结果仍是SongActionResult。新菜单使用现有PopupMenu路由的定位与关闭能力，独立添加圆角／边框／轻阴影，position按globalPosition转根Overlay坐标；不使用底部sheet。原公共入口签名、旧SongAction枚举和动作执行器不变。

本子任务未修改IK路由或最近播放接线，由主任务与最近播放子任务各自完成。没有运行测试、分析、格式检查、GUI验证、构建或安装，没有提交；当前仅为待预览快速候选，待验门未执行。

## 歌单图与详情图片的最新修正

用户继续指出歌单列表与详情图片不一致，详情内部歌曲也缺图。旧头图仅使用 `widget.coverUrl ?? songs.first.coverUrl`：空字符串不会触发回退，平台图加载失败也直接变占位；原CachedNetworkImage不会自动继承新版VideoCover的网易兼容读取。只修头图仍无法补齐歌曲行，因此本轮同时处理详情头图及每首歌曲的小图。

方案一单独替换头图URL会留下失败回退与歌曲行问题；方案二消费列表子任务提供的同一封面helper，平台封面优先、无效或失败时首歌封面兜底，歌曲行也使用兼容图片入口，采用方案二。仅desktopTable分支启用，旧默认不变；空歌单保留头部及占位，不伪造图片。小屏行也显示小封面，同时保留歌名／歌手、选择、下载和更多入口。

列表和封面helper由原生调查子任务负责，详情文件由本子任务独占；不改共享菜单、最近播放或队列。回滚撤详情封面分支即可，不改歌单内容、收藏、下载、排序。后续待验门为平台图成功／空串／失败回退、首歌无图／失败、空歌单、网易CDN、各宽度歌曲小图及列表详情一致；用户仍暂停测试、分析、格式检查、GUI与构建验证，本轮不执行。

详情已按协定接入 `PlaylistArtwork(playlist: 原平台封面信息, firstSong: 已加载songs.firstOrNull, size: 96, radius: 8)`，保留默认 `allowFirstSongRequest = false`，所以详情不额外请求歌单歌曲。新版空歌单现在保留头部与明确空态，而非直接隐藏全部头图。歌曲行宽屏40像素、窄屏32像素封面，空歌曲图URL回退专辑图；使用 `VideoCover(neteaseImageCompatibility: true)` 读取网易图片，不依赖旧CachedNetworkImage自动继承。旧header绘制仍只用于desktopTable=false。

本次未改播放／下载／批量／拖排函数，未改共享菜单、最近播放、队列或其它子任务文件，也未运行验证与提交。共享helper由其负责子任务落盘，主任务统一编译预览。

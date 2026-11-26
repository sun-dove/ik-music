# IK Music 播放等待缩短与安卓预览票据

日期：2026-11-26。用户最新要求：“其他暂时先不改了。这个播放失败轮询的时间看看还能再短不，然后打个安卓包我看看”。授权范围为既有失败等待的小幅缩短、Android预览构建；界面、音源顺序、账号、推荐与其他功能不改。

## 一、真实场景与目标

用户在Windows第七份预览中仍觉得失败歌曲尝试耗时偏长。当前quick路径是3秒解析、3秒媒体加载、9秒轮预算；Android尚未启用此快路径，仍走既有较长等待。目标是坏源更快让位、剩余候选仍可继续，且Android正常播放不能被误当超时。

源码确认Android `JustAudioController.play()` 转发just_audio的长生命周期Future，直到暂停、停止或曲终才结束；Windows的MediaKit命令Future较短。现quick的`play().timeout(1s)`不能直接对Android启用。Android共享音频控制器销毁也有焦点订阅与解绑顺序，不应套用Windows500ms销毁窗口。

## 二、方案选择

方案A：全局降低基础播放器、Dio和原生控制器超时，或通过并发抢多个音源绕过等待。会影响登录／下载／本地文件与设备重建，不采用。

方案B：新增可选quick时间参数，默认保持3／3／9；仅IK Windows和Android入口显式设为**解析2秒、媒体加载2.5秒、每轮解析与加载6秒预算**。修正快路径中的平台差异，旧签名和缺省行为兼容，原串行候选与取消令牌保留。采用B。

这是已有失败恢复的小增强，不引入新服务、接入或架构；按用户现次授权实施。原来明确DNS／连接失败已即时跳过，本轮不重复增加等待；慢但可用的网络也可能较早超时，这是用户要求更短等待的取舍，继续入口保留。

## 三、接口、调用方与兼容

- `MultiSourceVideoPlayerNotifier` 新可选 `quickResolveTimeout=3s`、`quickLoadTimeout=3s`、`quickBudget=9s`；`ExpandedSourcePlayerNotifier`、`IkCatalogPlayerNotifier` 可选透传。旧调用缺省保持。
- `QuickSourceTransport.run` 新可选 `timeout=3s`，与本轮解析上限保持一致；无播放scope的账号／目录／下载／后台请求仍原样透传。
- `main_video.dart` 的播放器与五个Dio在Windows或Android启用quick；显式2s／2500ms／6s。`preservePlaybackOnSettingsChange`仍仅Windows，UI快速改版各开关不扩到Android。
- `_SourceAudio` 中一秒play/stop/pause命令窗口仅作用真实 `MediaKitWindowsAudioController`。Android保留原长play Future与原停止／暂停操作上限；setUrl本身等待真实load完成，不加Windows正时长门。
- 销毁窗口仅Windows quick为500ms，Android保留原3秒。旧代次、token和失效实例检查不变，不并发抢源、不取消正常媒体。
- 不更改基础PlayerNotifier、旧SourceSession缺省、账号API、下载时限、候选生成规则、源开关或用户数据。

## 四、计时边界

6秒是候选解析／加载的机会预算，不是点击到最终返回的绝对时限。会话前目录提交、旧加载收尾、暂停／用户淡出，及故障设备的订阅取消、播放器销毁重建、音效／倍速恢复、互斥等待、进度定位仍可能额外耗时。不能将源码预算冒充手机实测耗时或承诺所有异常设备六秒结束。

## 五、待验门

| 场景 | 体验门 | 功能门 |
| --- | --- | --- |
| 坏源无响应 | 更早进入下一允许候选 | 解析最多2s且scope同步取消；不反复请求同坏host |
| URL已到但媒体装载不完成 | 不长时间假播放 | 加载最多2.5s与轮剩余取最小；旧URL不在重建后重复联网 |
| 预算耗尽仍有候选 | 可继续且不从第一个坏源重新开始 | 轮预算6s，真实已试／剩余保留，不把未试写成已失败 |
| Android正常歌曲持续播放 | 不在一秒后中断 | play长Future不套命令超时，错误仍经原token／请求代次处理 |
| Android取消和切歌 | 旧媒体不抢回，通知控制继续可用 | stop/pause/dispose保原安卓边界，不提早复用共享内核 |
| 本地文件、账号、推荐、下载 | 原行为 | 无quick scope不受缩短影响；旧参数缺省3／3／9 |
| Android安装预览 | 可选对应ABI覆盖安装 | 包名app.videomusic.player、稳定签名、版本0.6.2及1013/2013/4013，三个独立ABI |

用户继续要求快速看程序且暂停产品tests/analyze/format/GUI；本轮不恢复这些验证。仅人工核代码、编译和交付包身份／签名／架构核对，不将其写成播放或体验门全绿。

## 六、Android构建与回滚

旧6a构建在2026-11-26重启中断且没有APK，本次使用新的隔离源码目录，不混用旧目录产物。沿用D:/Applications/AndroidDev Flutter/SDK/Pub/Gradle和JDK17，稳定签名配置仍引用原私有位置。保留既有HRTF适配与精简依赖，SQLite采用固定版本正式构建输入。只执行准备与`flutter build apk --release --split-per-abi --no-pub --target lib/main_video.dart`，不调用内含产品测试的完整发行脚本；脚本既有门不删除或修改。

本机8个LX私有脚本不进入公共Git、云构建或APK，不把Windows相邻目录桥接冒充Android迁移功能。版本／签名与用户数据保持；Android包只供用户体验，不自动安装设备或发布Release。

回滚：IK入口恢复Windows-only quick及原3／3／9时间，不传新参数；新增可选参数保留也不影响旧调用。撤销Android快路径与平台命令适配即可恢复旧Android恢复边界，无数据迁移。正式编译日志、使用说明与产物回执保留，临时文件按精确来源清理；历史被自动审批拒绝清理的目标不重试。

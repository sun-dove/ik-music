# IK Music 3D 音效技术调研

日期：2026-11-20。状态：设计附件，待讨论确认。依据用户“重新设计、增加真正 3D 环绕、包小不臃肿”的要求开展只读核查；没有增加产品开关、修改播放器、下载依赖或重编依赖。此前修复保持冻结。

## 结论与功能定义

**现有发行包不能仅增加一条滤镜字符串就实现 3D 音效。** 安装目录的 libmpv 是裁剪构建，实际缺少常用空间滤镜。Android 当前链路也没有应用自定义 PCM 处理入口。必须先确定原生处理方案与体积预算，再编码。

建议把首个可验收目标定义为“耳机 3D 空间化”：普通双声道输入作为两个虚拟声源，用 HRTF 卷积产生耳间时差、强度差和方向相关的频谱线索，输出双声道供耳机播放；可调整强度和方向。前后、上下感受还与耳型、耳机及个体有关，需要盲听验收。单纯 Haas 延迟、声像摇摆、左右扩宽、混响或交叉馈送可作为单独效果，但不足以兑现这个目标。双声道不能恢复原录音不存在的对象位置；本次不承诺 Dolby/Atmos 解码、扬声器多声道或头部追踪。

现有 `AudioLevel.spatial/dolby` 是向 QQ/网易云/酷狗请求平台音质的标识，不能作为本机 3D DSP 已运行的证据；已处理过的音源也应避免重复空间化。

## 当前链路与本机证据

| 项目 | 核对结果 |
| --- | --- |
| Windows | `main_video → ExpandedSourcePlayerNotifier → _SourceAudio → MediaKitWindowsAudioController → RealMediaKitWindowsBackend → media_kit 1.2.6`。`media_kit_libs_windows_audio 1.0.9`固定附带 2023-09-24 的音频裁剪版 libmpv。 |
| 实际 DLL | `D:/Applications/YueyinMusic/libmpv-2.dll`，15,525,902 字节（14.81 MiB）；实际返回 `mpv v0.36.0-403-g652a1dd907`、FFmpeg `n6.0`、client API `0x20001`。SHA-256：`0A5A0B476866C91A639A4E511E8153968F8FA23564461B0AA09ACDBA816164A4`。 |
| Android | `AudioServicePlayerController → JustAudioController → just_audio 0.9.46 → Media3 ExoPlayer 1.4.1`。当前 `AudioPipeline`仅使用 Android `LoudnessEnhancer`和`Equalizer`；插件原生解码器也只接受这两种 effect。 |
| Android 扩展条件 | just_audio 可提供 `androidAudioSessionIdStream`，适合绑定系统 session effect；但没有公开自定义 `AudioProcessor`注入点，原生当前直接 `new ExoPlayer.Builder(context)`。自己的 PCM DSP 需要受控的播放器插件扩展，并配置 Media3 AudioSink。 |
| 当前接口 | `PlayerAudioController`不能直接加必需成员；已有 `VerifiedEqualizerCapable`证明可用附加能力接口兼容扩展。新能力须穿过`_SourceAudio`与 Android 服务包装，并在播放器重建后恢复。 |
| EQ 共存 | Windows 每次 EQ 调用都写整个`af`；新空间链若另写`af`会互相删除。必须由一个处理链协调器组合 EQ、空间处理、增益和必要的变速滤镜。Android 也需明确处理顺序，不能凭两个系统开关猜顺序。 |

本机使用 PowerShell 内存编译的 C# P/Invoke 直接装载该 DLL，创建独立 libmpv 实例，`config=no`、`ao=null`、`vo=null`。用内存生成的 48 kHz、16-bit、双声道 WAV 经仅监听 `127.0.0.1` 的短连接提供输入，读取原生事件和日志；不通过现有播放器、不发声音、不产生音频文件。各实例、连接均已释放。

| 探针 | 实际结果 |
| --- | --- |
| 无滤镜基线 | 初始化、加载成功；解码参数为 48 kHz/stereo/s16。 |
| `haas`、`stereowiden`、`bs2b`、`headphone`、`sofalizer`、`surround`、`afir`、`alimiter` | 八项均由 DLL 明确报告`No such filter`，随后音频滤镜初始化失败。 |
| `pan` | 当前链解析失败；不能将本次错误进一步等同于“已证实不存在该滤镜”。 |
| `equalizer=f=1000:t=q:w=1:g=-6` | 名称被接受，但本次 s16 输入因`aresample filter not present`无法协商格式，随后报告`Disabling filter lavfi.00 because it has failed`。这说明既有 EQ 也需要真实信号门；不能据此断言所有输入格式都失败。 |
| 设置返回值 | 上述不存在的滤镜，`mpv_set_property_string("af", ...)`仍返回 0，`af`还能读回请求字符串。设置成功只代表接受配置，后续加载时仍可失败。 |

还有一层假成功风险：当前 media_kit 的公开`NativePlayer.setProperty`调用`mpv_set_property_string`后丢弃返回值。因此现有`setAudioFilterVerified`的 Future 完成，**并未验证滤镜初始化或处理后的信号**。新 3D 能力必须补原生真值门，并把 EQ 一同纳入组合链回归；本轮没有借调研修改既有 EQ。

本机另有完整 FFmpeg 8.1.1，确实列出上述空间滤镜。仅以它作算法参考，不能推导发行 DLL 的能力。对“左声道单脉冲、右声道静音”的 48 kHz 输入，经管道读取 float PCM：旁路峰值 L=0.5/R=0；`bs2b`变为约 L=0.394691/R=0.016343，`stereowiden`约 L=0.4/R=0.15。证明这些处理会改信号，**不证明空间方向或 HRTF 成效**。仓库没有 HRTF/SOFA 数据，本轮没有下载，未进行 HRTF 音频或听感验收。`adb devices`为空，Android 系统空间器未实测。

## 两种方案比较与推荐

| 方案 | 做法与支持范围 | 代价与限制 |
| --- | --- | --- |
| A：复用后端空间滤镜/系统能力 | Windows 定制现有 libmpv/FFmpeg 构建，只加入`sofalizer + libmysofa`或`headphone/afir`及必需的重采样、混合、限幅；仍在当前解码/播放链。Android 可探测系统 Spatializer，旧设备 Virtualizer 仅作受限替代。 | Windows 必须替换当前裁剪 DLL，现包不能直接用；SOFA 数据与库的许可、体积需核对。Android 系统效果依设备、路由、格式和用户系统设置，普通 app 不能保证统一开启、方向或连续强度。两平台声音与能力不能一致。 |
| B：小型共享原生 DSP | 一个原生 FIR/HRTF 核心及有限方向系数表；Windows 作为定制的小型 mpv 音频滤镜编入**同一** libmpv，Android 接 Media3 `AudioProcessor`，共享算法与资产，独立入口显式选用。 | 要维护两处薄适配和可重现构建。Windows 当前 libmpv/MediaKit **没有公开的解码后 PCM 插件钩子**；`stream_cb`只提供输入字节，`render`是视频 API，不能把小 DLL 挂上去就声称可行。必须先完成定制 mpv 滤镜插入原型；Android 必须有受控插件扩展。 |

**推荐 B 作为“小包、两平台可验证”的目标方案，先做 Windows 最小原型，验过信号和包体才扩展 Android。** 保留现有解码器，不另开第二播放器、不捆绑完整 FFmpeg、不引入大型音频引擎。若维护定制 mpv 不可接受，可选择 A 的 Windows HRTF 功能并诚实限定 Android 能力；不以 Haas 扩宽替代“真正 3D”。最终选择需在设计讨论中确认。

### 包体与计算预算

- 现有 libmpv 为 **14.81 MiB**；本机完整`ffmpeg.exe`为 **216.86 MiB**、`ffprobe.exe`为 **216.67 MiB**，均不应随包加入。替换 libmpv 时只留一个 DLL，不能原版与新版并存。
- A 的增量由实际编译选项、静态库和 HRTF 文件决定，本轮没有构建，不能报虚构成品数。提议接受门：Windows 解压增量不超过 **5 MiB**，Android 单 ABI 不超过 **2 MiB**；超过即回设计讨论。它们是拟定预算，不是测量结果。
- B 的系数表可精确计算：24 个方位 × 3 个仰角 × 2 耳 × 256 taps × float32 = **144 KiB/采样率**；44.1/48 kHz 两套为 **288 KiB**。还需许可允许随包分发的真实 HRTF 数据，不能把粗略延迟表冒充测量 HRTF。较密方向网格或更长脉冲会按比例增加。
- B 的原生代码大小尚未编译。建议验收预算：Windows/Android 每个 ABI 的**代码与资产合计新增不超过 2 MiB**；APK 继续分 ABI，不把三套 native 库装进一个包。两声源、双耳、256 taps、48 kHz 直接 FIR 约 **49.15M MAC/s**，手机 CPU/耗电必须实测；SIMD、分块卷积或更短 IR 的选择以信号与耗电门为准。
- Haas/ITD/交叉馈送不需要 HRTF 资产，算力和内存更小，但应称“立体声扩展/耳机交叉馈送”。本次不把节省体积等同于满足 3D 定位。

## 接口与状态草案

均为待实现的新接口，不修改已有公开默认契约。新增持久键例如`ik.spatial.v1`，缺省`enabled=false`；旧备份缺键时保持原声。能力不持久化，每次后端或输出设备变化重查。

```text
SpatialSettings {
  enabled=false, strength=0..1, mode=binaural,
  azimuthDegrees=0, elevationDegrees=0, profileId
}
SpatialCapabilities {
  backendId, generation, supportsBinaural, supportsStrength,
  sampleRates, inputChannelCounts, outputRoute, unavailableReason
}
SpatialState {
  desiredSettings, effectiveSettings, status,
  backendGeneration, requestId, failureKind, retryable, rolledBack
}
status = off | preparing | applying | active | unsupported | failed
failureKind = backendMissing | formatUnsupported | assetInvalid |
              graphRejected | renderFailed | deviceChanged | timedOut

SpatialAudioCapable.queryCapabilities() -> SpatialCapabilities
SpatialAudioCapable.applySpatialVerified(settings, requestId)
  -> {effectiveSettings, backendGeneration, initialized, processedFrames}
```

`active`要求原生确认当前图已初始化且实际处理帧计数前进；无歌曲时只能是准备好/等待播放，不能提前显示已生效。算法的“实际产生空间处理”由固定黄金信号门证明，运行时帧计数只证明本次确实进入处理节点。失败显示原因和重试，只有成功确认后才更新有效设置；设备不支持时禁用相关控件。

拟增`IkSpatialCoordinator`串行处理设置请求，合成一份处理链配置。链顺序明确为：必要的格式转换 → EQ/增益余量 → 空间卷积 → 对齐的干湿混合 → 防过载 → 当前音量/睡眠淡出。空间强度不能借`setVolume`伪实现；现有音量守护会恢复音量，且它改变的是响度而非空间。

## 生命周期、共存与回滚

1. **切歌、换源、播放器重建**：绑定后端 generation 与歌曲请求代次。新实例按最新 EQ+空间配置重建，迟到旧结果不发布成功；seek/换曲清空 FIR 历史，避免上一曲尾音泄漏。采样率、声道数或输出路由变化先重新协商，不能沿用不匹配的系数。
2. **开关与强度**：0 为旁路，干湿信号延迟对齐；参数用短平滑过渡，避免突跳和噪声。具体时长先提议 20 ms，以脉冲/阶跃门与听感确认。处理开关不改变播放位置、队列和登录/音源状态。
3. **EQ 共存**：用单一配置快照生成链；切换 EQ 不能删空间节点，切空间不能清 EQ。保留旧 EQ 接口入口；仅 ik 的新增能力路径选择组合链。Android 使用自有 PCM EQ 或明确经过设备验证的顺序，不能把顺序不定的 OEM effect 视作统一实现。
4. **失败回滚**：应用前保留最后已验证的链与播放状态。图构建或设备变化失败时恢复旧链/旁路，避免坏滤镜令音乐停播；回滚也失败则暂停并明确显示，禁止继续显示“已开启”。关闭、退出、音频服务重建释放 DSP 状态与原生资源。
5. **重复空间化**：Android 能提供已空间化属性时设置对应 AudioAttributes；当前 just_audio 公共层未暴露，需要原生适配。Windows 系统增强或已加工的双耳音源不能可靠自动识别时，由设置明确提示检查，不能假定全部已禁用。

## 先红后绿的真实验收门

| 门 | 可执行判据 |
| --- | --- |
| 能力与错误真值 | 用**发行包自己的** DLL/ABI 喂静音或脉冲，缺滤镜、坏参数、损坏 HRTF 均必须`unsupported/failed`；`setProperty`返回 0、读回字符串、UI 开关置位均不能令门绿。现 DLL 缺八种滤镜与 EQ 自动禁用作为已知反例。 |
| 原声旁路 | 关闭与强度 0，在固定 PCM 格式下与无 DSP 样本一致；若格式转换不可避免，先声明误差上限并校准延迟，不能单用相关性掩盖音量变化。 |
| 空间传递 | 左/右单脉冲、中央单声道、定频与扫频覆盖全部所支持采样率/方向，输出与离线 HRTF 黄金卷积一致。检查 ITD、ILD、方向频响、左右镜像及前后/仰角差异；只出现延迟或串音不足以通过 HRTF 门。 |
| 强度/EQ 组合 | 0/25/50/75/100% 均测处理输出、对齐与平滑；五段 EQ、正负最大增益与空间组合验证频响/余量。近满幅正弦与随机信号检查 NaN/Inf、削波和峰值，不用“更响”冒充更好。 |
| 状态与切换 | 连续切歌、seek、换源、离线文件、暂停恢复、睡眠淡出、音频服务重建、耳机拔插/蓝牙切换；故障注入后原链或旁路恢复，旧请求不能覆盖新状态，旧曲尾音不泄漏。 |
| 成品链路 | Windows 通过 WASAPI loopback 或受控 PCM 输出验证安装包真正输出变化；Android 每个 ABI至少设备/模拟器 PCM 处理证据，真实耳机与后台服务补设备门。离线算法门不能替代真实播放链。 |
| 包体/性能/体验 | 按上述单 ABI/单 DLL 增量门核对产物；固定机器测处理延迟、CPU、内存、长播断音和 Android 耗电。耳机音量匹配的盲听检验定位与自然度，UI 明确待播放、应用中、实际生效、不支持、失败回滚。未确定阈值的项目必须在编码前补定。 |

## 实施次序与待确认项

先确认耳机 HRTF、支持平台、强度/方向交互及 2 MiB 目标预算；再选许可明确的 HRTF 资产和原生适配路径。随后只做可丢弃的最小音频原型，证明当前播放器链能插入并获取处理输出；通过真实信号与包体门后才接产品 UI、持久化、备份与平台回归。若 Windows 必须重编 libmpv 或 Android 插件受控分支不被接受，应重新讨论支持范围，不能边画开关边声称后端已具备能力。

### 方案选择的结构化复核

按本机 Jev 使用规则，2026-11-20 实际调用官方接口，模型返回`jev-1.14.0`。向模型提供了上述已观测的播放器限制、两方案的维护代价、未构建的不确定性与小包要求，只询问“应优先做哪个方案的原型”；没有用模型代替滤镜存在性、PCM 接入或包体测量。

结果为 B 小型共享 DSP，概率 **0.74**，confidence **0.61**；先同时探查 A/B 再选架构为 **0.23**，A 后端滤镜与系统效果为 **0.03**。判断倾向 B，但仍存在先比较原型的合理余地；因此本文推荐只代表首个原型的优先顺序，不代表 B 已被证明能满足信号、性能和包体门，也不代替用户的设计确认。指定旧路径的`jev.ps1`不存在，本次使用已安装 Jev 技能记录的官方 HTTP 方式，凭据只从当前进程环境读取。

### 查证来源

- 仓库：`lib/features/player/data/media_kit_windows_audio_controller.dart`、`player_audio_controller.dart`、`playback_notification_service.dart`、`lib/video_app/multi_source/multi_source_player.dart`、`lib/features/player/data/playback_fade_controller.dart`。
- 本机锁定依赖源码：`media_kit-1.2.6/lib/src/player/native/player/real.dart`、`media_kit_libs_windows_audio-1.0.9/windows/CMakeLists.txt`、`just_audio-0.9.46/android/src/main/java/com/ryanheise/just_audio/AudioPlayer.java`。
- [FFmpeg sofalizer 文档](https://ffmpeg.org/ffmpeg-filters.html#sofalizer)：HRTF/SOFA、`--enable-libmysofa`和耳机双耳处理要求。
- [Android Spatializer](https://developer.android.com/reference/android/media/Spatializer)：API 32，按设备/路由查询`isAvailable/isEnabled/canBeSpatialized`。
- [Android Virtualizer](https://developer.android.com/reference/android/media/audiofx/Virtualizer)：API 35 弃用，效果依输入/输出设备，不保证统一渲染。
- [Android AudioAttributes.Builder](https://developer.android.com/reference/android/media/AudioAttributes.Builder)：已空间化内容标记与空间化行为。
- mpv v0.36.0 公开头文件：[client.h](https://github.com/mpv-player/mpv/blob/v0.36.0/libmpv/client.h)、[stream_cb.h](https://github.com/mpv-player/mpv/blob/v0.36.0/libmpv/stream_cb.h)、[render.h](https://github.com/mpv-player/mpv/blob/v0.36.0/libmpv/render.h)。

本附件是本轮唯一新增文件。所有本机探针脚本、PCM、HTTP 内容都在进程内存/管道中使用，未留下临时测试、音频或编译文件；没有新增产品依赖，没有改变已安装应用。

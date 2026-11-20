# IK Music 小型 HRTF 原生能力

这套核心把双声道当作左右两个虚拟声源，使用 MIT KEMAR 实测 HRTF 做双耳 FIR 卷积。方向/仰角改变系数，强度做延迟对齐的干湿混合；20ms 核过渡防突变，关闭与强度零为旁路。256 taps，44.1/48kHz 两套表，共 294,912 字节。原声没有对象位置，功能不宣称 Atmos 解码或头部追踪。

原始数据由 Bill Gardner 和 Keith Martin（MIT Media Lab，1994）测量；`data/MIT-KEMAR-LICENSE`保留官方许可原文，要求研究/商业应用署名。`data/mit-kemar-diffuse.zip`是固定原始资产，`generate_hrtf.py`校验哈希后生成系数头文件，可重复生成；左右半球来自原始左右耳镜像，方向间做相邻实测值插值，48kHz 用窗 sinc 在生成期重采样。

## Windows 构建

Ubuntu 24.04/WSL 或 GitHub `ubuntu-24.04`，安装这些构建依赖（不会随安装包分发）：

```sh
sudo apt-get update
sudo apt-get install -y --no-install-recommends gcc-mingw-w64-x86-64-posix g++-mingw-w64-x86-64-posix meson ninja-build pkg-config nasm autoconf automake libtool
python3 native/ik_spatial/download_sources.py --directory "$RUNNER_TEMP/ik-sources"
python3 native/ik_spatial/generate_hrtf.py
gcc -O3 -std=c11 -Wall -Wextra -Werror native/ik_spatial/ik_spatial.c native/ik_spatial/ik_spatial_gate.c -lm -o "$RUNNER_TEMP/ik-spatial-gate"
"$RUNNER_TEMP/ik-spatial-gate"
bash native/ik_spatial/build_windows.sh "$RUNNER_TEMP/ik-native" "$RUNNER_TEMP/ik-sources"
```

产物为`$RUNNER_TEMP/ik-native/mpv/libmpv-2.dll`。上传同一次 CI 的 artifact 后交 Windows job；Windows 必须用`verify_windows.ps1 -LibraryPath ... -Python python -OutputDirectory ...`验证实际 DLL 解码、HRTF PCM 与 EQ，再运行`verify_formats.py --dll ... --output-dir ...`验证 9 种格式的文件/HTTP、EQ、HRTF、倍速组合；后者需要 FFmpeg 命令程序生成门素材，但它不随产品分发。只替换原有单 DLL，不增加完整 FFmpeg 程序，DLL 上限为 17,623,054 字节（原版加 2 MiB）。不能只靠核心单元门就发布。

mpv 固定提交`652a1dd907`（现有依赖同系列），FFmpeg 6.0、FreeType 2.13.2、FriBidi 1.0.13、HarfBuzz 8.3.0、libass 0.17.1。`download_sources.py`固定每份源的 URL 和 SHA-256。FFmpeg 应用上游 binutils 2.41 兼容补丁，并新增`ikhrtf`滤镜；mpv 不修改旧公开 ABI。滤镜通过无锁原子导出`ik_spatial_processed_frames(requestId)`报告实际处理帧；不用 mpv 0.36 `af-metadata`同步查询（该查询在真实门中重入核心锁）。

源归档保留全部第三方版权/许可证；许可证集合输出到构建目录的`licenses`，应与新 DLL 一起分发。对应可重建源归档、此目录的修改与构建脚本须随发行提供，满足 LGPL 修改/重新链接要求；禁止只发没有对应源的二进制。Windows 系统库继续动态链接，算法不依赖额外音频引擎。

## Android 受控构建

不修改 Pub 缓存。`scripts/prepare_ik_build.ps1 -Platform android -EnableSpatialAudio`把固定 just_audio 0.9.46 复制到隔离`.ik-packages/just_audio`，调用`prepare_android.py`添加 Media3 AudioProcessor、JNI 与共用 C 核心，用副本 override 后正常构建。关闭音频 offload，确保 PCM 经过节点。关闭/强度零输出干声，切歌/seek 重新 flush；不支持格式明确返回失败状态。

Android 通道`ik.music/spatial`只提供支持查询、请求设置、真实帧读数；UI显示待处理/实际生效/失败。每个 ABI 原生库需单独核验大小和 PCM，最后仍按仓库要求三 ABI 分包；不能把“编译成功”当作设备播放验收。

在启用空间节点的隔离工程中，以`flutter build apk --release --target=scripts/spatial_device_gate.dart --target-platform=android-x64 --split-per-abi`构建设备门；安装到 x86_64 设备后启动，通过 adb logcat 检查全部`IK_SPATIAL_GATE PASS`记录和不存在`IK_SPATIAL_GATE FAIL`。ARM 设备应改成对应 target-platform。设备门必须包括实际帧、右耳静音输入产生卷积输出、参数修改/seek、停止重载及关闭；不能只看到第一条 PASS 就结束。此 target 只用于验收，正式包仍使用产品入口。

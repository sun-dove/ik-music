"""仅修改指定隔离构建包，不触碰 Pub 全局缓存。"""
import argparse
import hashlib
from pathlib import Path
import shutil

parser = argparse.ArgumentParser()
parser.add_argument("--package-dir", required=True)
args = parser.parse_args()
package = Path(args.package_dir).resolve()
if ".ik-packages" not in package.parts:
    raise SystemExit("拒绝修改非 .ik-packages 隔离包")
root = Path(__file__).resolve().parent
if "version: 0.9.46" not in (package / "pubspec.yaml").read_text(encoding="utf-8"):
    raise SystemExit("仅支持固定 just_audio 0.9.46")
java = package / "android/src/main/java/com/ryanheise/just_audio"
player = java / "AudioPlayer.java"
text = player.read_text(encoding="utf-8")
needle = "ExoPlayer.Builder builder = new ExoPlayer.Builder(context);"
assert text.count(needle) == 1, "播放器初始化接缝变化"
replacement = """ExoPlayer.Builder builder = new ExoPlayer.Builder(context,
                new androidx.media3.exoplayer.DefaultRenderersFactory(context) {
                    @Override
                    protected androidx.media3.exoplayer.audio.AudioSink buildAudioSink(
                        Context c, boolean floats, boolean params) {
                        return new androidx.media3.exoplayer.audio.DefaultAudioSink.Builder(c)
                            .setEnableFloatOutput(false)
                            .setEnableAudioTrackPlaybackParams(params)
                            .setAudioProcessors(new androidx.media3.common.audio.AudioProcessor[] {
                                new IkSpatialProcessor()
                            }).build();
                    }
                });"""
text = text.replace(needle, replacement)
text = text.replace("AudioOffloadPreferences.AUDIO_OFFLOAD_MODE_ENABLED",
                    "AudioOffloadPreferences.AUDIO_OFFLOAD_MODE_DISABLED")
player.write_text(text, encoding="utf-8")
plugin = java / "JustAudioPlugin.java"
text = plugin.read_text(encoding="utf-8")
text = text.replace("BinaryMessenger messenger = binding.getBinaryMessenger();",
                    "BinaryMessenger messenger = binding.getBinaryMessenger();\n        IkSpatialProcessor.attach(messenger);")
text = text.replace("methodCallHandler = null;", "methodCallHandler = null;\n        IkSpatialProcessor.detach();")
plugin.write_text(text, encoding="utf-8")
shutil.copy2(root / "android/IkSpatialProcessor.java", java)
native = package / "android/src/main/ik_spatial"
native.mkdir(parents=True, exist_ok=True)
for filename in ("ik_spatial.c", "ik_spatial.h", "ik_hrtf_data.h"):
    shutil.copy2(root / filename, native)
for filename in ("ik_spatial_jni.c", "CMakeLists.txt"):
    shutil.copy2(root / "android" / filename, native)
shutil.copy2(root / "data/MIT-KEMAR-LICENSE", package)
gradle = package / "android/build.gradle"
text = gradle.read_text(encoding="utf-8")
text += """
android {
    ndkVersion '28.2.13676358'
    defaultConfig {
        minSdk 21
        externalNativeBuild { cmake { arguments '-DANDROID_STL=c++_static' } }
        consumerProguardFiles 'ik-spatial.pro'
    }
    externalNativeBuild {
        cmake { path 'src/main/ik_spatial/CMakeLists.txt'; version '3.22.1' }
    }
}
"""
gradle.write_text(text, encoding="utf-8")
(package / "android/ik-spatial.pro").write_text(
    "-keep class com.ryanheise.just_audio.IkSpatialProcessor { *; }\n", encoding="utf-8")
print("just_audio 0.9.46 受控 HRTF PCM 适配已应用；需要设备处理帧门")
for path in (player, java / "IkSpatialProcessor.java", native / "ik_spatial.c"):
    print(path.relative_to(package), hashlib.sha256(path.read_bytes()).hexdigest())

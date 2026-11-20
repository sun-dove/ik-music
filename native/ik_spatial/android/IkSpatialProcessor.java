package com.ryanheise.just_audio;

import androidx.media3.common.C;
import androidx.media3.common.audio.AudioProcessor;
import androidx.media3.common.audio.BaseAudioProcessor;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.HashMap;
import java.util.Map;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodChannel;

/** 受控 PCM 适配：不替换解码器，设置与实际处理状态分开。 */
public final class IkSpatialProcessor extends BaseAudioProcessor {
    static { System.loadLibrary("ik_spatial"); }
    private static volatile IkSpatialProcessor current;
    private static volatile Settings desired = new Settings(false, .65, 0, 0, 0);
    private static MethodChannel channel;
    private long nativeHandle;
    private volatile long appliedRequest = -1;
    private volatile long frames;
    private volatile String failure;
    private volatile double inputRightEnergy, outputRightEnergy;

    private static final class Settings {
        final boolean enabled;
        final double strength, azimuth, elevation;
        final long request;
        Settings(boolean e, double s, double a, double v, long r) {
            enabled=e; strength=s; azimuth=a; elevation=v; request=r;
        }
    }

    public static void attach(BinaryMessenger messenger) {
        channel = new MethodChannel(messenger, "ik.music/spatial");
        channel.setMethodCallHandler((call, result) -> {
            if (call.method.equals("supports")) { result.success(true); return; }
            if (call.method.equals("apply")) {
                Map<?, ?> args = (Map<?, ?>)call.arguments;
                double strength = ((Number)args.get("strength")).doubleValue();
                double azimuth = ((Number)args.get("azimuth")).doubleValue();
                double elevation = ((Number)args.get("elevation")).doubleValue();
                if (!Double.isFinite(strength) || !Double.isFinite(azimuth) ||
                    !Double.isFinite(elevation) || strength<0 || strength>1 ||
                    azimuth < -180 || azimuth>180 || elevation < -30 || elevation>30) {
                    result.error("invalid_settings", "Invalid spatial settings", null); return;
                }
                desired = new Settings(Boolean.TRUE.equals(args.get("enabled")), strength,
                    azimuth, elevation, ((Number)args.get("requestId")).longValue());
                result.success(null); return;
            }
            if (call.method.equals("read")) {
                IkSpatialProcessor processor = current;
                Map<String, Object> report = new HashMap<>();
                report.put("requestId", processor == null ? -1L : processor.appliedRequest);
                report.put("processedFrames", processor == null ? 0L : processor.frames);
                report.put("error", processor == null ? null : processor.failure);
                report.put("inputRightEnergy", processor == null ? 0.0 : processor.inputRightEnergy);
                report.put("outputRightEnergy", processor == null ? 0.0 : processor.outputRightEnergy);
                result.success(report); return;
            }
            result.notImplemented();
        });
    }

    public static void detach() {
        if (channel != null) channel.setMethodCallHandler(null);
        channel = null;
        desired = new Settings(false, .65, 0, 0, 0);
        current = null;
    }

    @Override
    protected AudioFormat onConfigure(AudioFormat input) {
        releaseNative();
        current = this;
        if ((input.sampleRate != 44100 && input.sampleRate != 48000) ||
            (input.channelCount != 1 && input.channelCount != 2) ||
            input.encoding != C.ENCODING_PCM_16BIT) {
            failure = "format_unsupported";
            return AudioFormat.NOT_SET;
        }
        nativeHandle = create(input.sampleRate);
        failure = nativeHandle == 0 ? "native_initialization_failed" : null;
        return nativeHandle == 0 ? AudioFormat.NOT_SET :
            new AudioFormat(input.sampleRate, 2, C.ENCODING_PCM_16BIT);
    }

    @Override
    public void queueInput(ByteBuffer input) {
        Settings settings = desired;
        if (appliedRequest != settings.request) {
            int result = configure(nativeHandle, settings.enabled, (float)settings.strength,
                (float)settings.azimuth, (float)settings.elevation);
            if (result != 0) { failure = "native_configuration_failed"; return; }
            appliedRequest = settings.request;
            frames = 0;
            inputRightEnergy = outputRightEnergy = 0;
        }
        int count = input.remaining() / (inputAudioFormat.channelCount * 2);
        ByteBuffer out = replaceOutputBuffer(count * 4).order(ByteOrder.nativeOrder());
        int result = process(nativeHandle, input, input.position(), out, count,
            inputAudioFormat.channelCount);
        if (result != 0) { failure = "native_processing_failed"; return; }
        // 小窗口信号诊断：设备门证明真实PCM经过处理，避免仅计帧假绿。
        if (frames < 4096) {
            double inputEnergy = 0, outputEnergy = 0;
            int observed = (int)Math.min(count, 4096-frames);
            for (int i=0; i<observed; ++i) {
                double dry = input.getShort(input.position()+(i*inputAudioFormat.channelCount+inputAudioFormat.channelCount-1)*2)/32768.0;
                double wet = out.getShort(i*4+2)/32768.0;
                inputEnergy += dry*dry;
                outputEnergy += wet*wet;
            }
            inputRightEnergy += inputEnergy;
            outputRightEnergy += outputEnergy;
        }
        input.position(input.limit());
        out.position(count * 4);
        out.flip();
        frames += count;
        failure = null;
        current = this;
    }

    @Override
    protected void onFlush() {
        if (nativeHandle != 0) resetNative(nativeHandle);
        frames = 0;
        inputRightEnergy = outputRightEnergy = 0;
        appliedRequest = -1;
    }

    @Override
    protected void onReset() { releaseNative(); }

    private void releaseNative() {
        if (nativeHandle != 0) destroy(nativeHandle);
        nativeHandle = 0;
        frames = 0;
        inputRightEnergy = outputRightEnergy = 0;
        appliedRequest = -1;
    }

    private static native long create(int sampleRate);
    private static native void destroy(long handle);
    private static native void resetNative(long handle);
    private static native int configure(long handle, boolean enabled, float strength,
        float azimuth, float elevation);
    private static native int process(long handle, ByteBuffer input, int offset,
        ByteBuffer output, int frames, int channels);
}

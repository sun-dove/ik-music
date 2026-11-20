import 'package:flutter/services.dart';

import 'spatial_audio_capability.dart';

/// 只由独立 IK 音频能力调用；普通 just_audio 包没有通道时明确不支持。
class AndroidSpatialAudio implements SpatialAudioCapable {
  static const _channel = MethodChannel('ik.music/spatial');

  @override
  Future<bool> supportsSpatialAudio() async {
    try {
      return await _channel.invokeMethod<bool>('supports') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> applySpatialAudio(SpatialSettings settings, int requestId) =>
      _channel.invokeMethod<void>('apply', {
        ...settings.toMap(),
        'requestId': requestId,
      });

  @override
  Future<SpatialProcessingReport> readSpatialAudio() async {
    final report = await _channel.invokeMapMethod<String, Object?>('read');
    return SpatialProcessingReport(
      requestId: (report?['requestId'] as num?)?.toInt() ?? -1,
      processedFrames: (report?['processedFrames'] as num?)?.toInt() ?? 0,
      error: report?['error'] as String?,
    );
  }
}

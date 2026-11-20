class SpatialSettings {
  const SpatialSettings({
    this.enabled = false,
    this.strength = 0.65,
    this.azimuth = 0,
    this.elevation = 0,
  });

  final bool enabled;
  final double strength, azimuth, elevation;

  SpatialSettings copyWith({
    bool? enabled,
    double? strength,
    double? azimuth,
    double? elevation,
  }) => SpatialSettings(
    enabled: enabled ?? this.enabled,
    strength: (strength ?? this.strength).clamp(0, 1),
    azimuth: (azimuth ?? this.azimuth).clamp(-180, 180),
    elevation: (elevation ?? this.elevation).clamp(-30, 30),
  );

  Map<String, Object> toMap() => {
    'enabled': enabled,
    'strength': strength,
    'azimuth': azimuth,
    'elevation': elevation,
  };

  factory SpatialSettings.fromMap(Object? value) {
    if (value is! Map) return const SpatialSettings();
    double number(String key, double fallback, double low, double high) {
      final v = value[key];
      return v is num && v.isFinite ? v.toDouble().clamp(low, high) : fallback;
    }

    return SpatialSettings(
      enabled: value['enabled'] == true,
      strength: number('strength', 0.65, 0, 1),
      azimuth: number('azimuth', 0, -180, 180),
      elevation: number('elevation', 0, -30, 30),
    );
  }
}

class SpatialProcessingReport {
  const SpatialProcessingReport({
    required this.requestId,
    required this.processedFrames,
    this.error,
  });
  final int requestId, processedFrames;
  final String? error;
}

/// 附加能力；旧播放器无需实现，不能从开关状态推定后端支持。
abstract interface class SpatialAudioCapable {
  Future<bool> supportsSpatialAudio();
  Future<void> applySpatialAudio(SpatialSettings settings, int requestId);
  Future<SpatialProcessingReport> readSpatialAudio();
}

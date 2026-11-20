import 'package:hive_flutter/hive_flutter.dart';

import '../../features/audio_effects/presentation/providers/audio_effects_provider.dart';
import '../../features/offline_cache/data/cache_settings_repository.dart';
import '../../features/offline_cache/presentation/providers/offline_cache_provider.dart';

/// IK 新入口单次落盘后发布；计算在写队列里，两个字段并发不互相覆盖。
class IkStrictAudioSettings extends AudioEffectsSettingsNotifier {
  IkStrictAudioSettings({
    AudioEffectsSettings? initial,
    Future<void> Function(Map<String, dynamic>)? write,
  }) : _write =
           write ??
           ((value) =>
               Hive.box('settings').put('audio_effects_settings', value)),
       super(
         MemoryAudioEffectsSettingsStore(
           (initial ??
                   AudioEffectsSettings.fromJson(
                     Hive.isBoxOpen('settings')
                         ? Hive.box('settings').get('audio_effects_settings')
                         : null,
                   ))
               .toJson(),
         ),
       );
  final Future<void> Function(Map<String, dynamic>) _write;
  Future<void> _tail = Future.value();
  Future<void> _commit(
    AudioEffectsSettings Function(AudioEffectsSettings) update,
  ) {
    final operation = _tail.then((_) async {
      final next = update(state);
      await _write(next.toJson());
      if (mounted) state = next;
    });
    _tail = operation.catchError((Object _) {});
    return operation;
  }

  @override
  Future<void> setFadeEnabled(bool enabled) =>
      _commit((s) => s.copyWith(fadeEnabled: enabled));
  @override
  Future<void> setFadeDuration(Duration duration) => _commit(
    (s) => s.copyWith(
      fadeDuration: Duration(
        milliseconds: duration.inMilliseconds.clamp(200, 3000),
      ),
    ),
  );
  @override
  Future<void> setSleepTimerDuration(Duration duration) => _commit(
    (s) => s.copyWith(
      sleepTimerDuration: Duration(minutes: duration.inMinutes.clamp(5, 120)),
    ),
  );
  @override
  Future<void> setSleepTimerState({
    required bool enabled,
    required Duration remaining,
  }) => _commit(
    (s) => s.copyWith(
      sleepTimerEnabled: enabled,
      sleepTimerRemaining: Duration(
        seconds: remaining.inSeconds.clamp(0, 7200),
      ),
    ),
  );
  @override
  Future<void> setEqualizerEnabled(bool enabled) =>
      _commit((s) => s.copyWith(equalizerEnabled: enabled));
  @override
  Future<void> setEqualizerPreset(EqualizerPreset preset) => _commit(
    (s) => s.copyWith(
      equalizerPreset: preset,
      equalizerBandGains: preset == EqualizerPreset.custom
          ? s.equalizerBandGains
          : preset.bandGains,
    ),
  );
  @override
  Future<void> setEqualizerBandGain(int index, double gain) => _commit((s) {
    if (index < 0 || index >= s.equalizerBandGains.length) return s;
    final gains = [...s.equalizerBandGains];
    gains[index] = gain.clamp(-12, 12);
    return s.copyWith(
      equalizerPreset: EqualizerPreset.custom,
      equalizerBandGains: gains,
    );
  });
}

class _InitialCacheRepository extends CacheSettingsRepository {
  const _InitialCacheRepository(this.initial);
  final OfflineCacheSettings initial;
  @override
  Future<OfflineCacheSettings> load() async => initial;
}

class IkStrictCacheSettings extends OfflineCacheSettingsNotifier {
  IkStrictCacheSettings({
    OfflineCacheSettings? initial,
    Future<void> Function(Map<String, dynamic>)? write,
  }) : _write =
           write ??
           ((value) =>
               Hive.box('settings').put(offlineCacheSettingsKey, value)),
       super(
         repository: _InitialCacheRepository(
           initial ??
               OfflineCacheSettings.fromJson(
                 Hive.isBoxOpen('settings')
                     ? Hive.box('settings').get(offlineCacheSettingsKey)
                     : null,
               ),
         ),
       );
  final Future<void> Function(Map<String, dynamic>) _write;
  Future<void> _tail = Future.value();
  Future<void> _commit(
    OfflineCacheSettings Function(OfflineCacheSettings) update,
  ) {
    final operation = _tail.then((_) async {
      await ready;
      final next = update(state);
      await _write(next.toJson());
      if (mounted) state = next;
    });
    _tail = operation.catchError((Object _) {});
    return operation;
  }

  @override
  Future<void> setSizeLimitMb(int value) =>
      _commit((s) => s.copyWith(sizeLimitMb: value.clamp(128, 32768)));
  @override
  Future<void> setWifiOnly(bool value) =>
      _commit((s) => s.copyWith(wifiOnly: value));
  @override
  Future<void> setAutoRetry(bool value) =>
      _commit((s) => s.copyWith(autoRetry: value));
  @override
  Future<void> setAutoCleanup(bool value) =>
      _commit((s) => s.copyWith(autoCleanup: value));
  @override
  Future<void> setOfflineMode(bool value) =>
      _commit((s) => s.copyWith(offlineMode: value));
}

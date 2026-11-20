import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/audio_effects/presentation/providers/audio_effects_provider.dart';
import '../../features/player/presentation/providers/player_provider.dart';

enum IkAudioStatus { idle, applying, applied, unsupported, failed }

class IkAudioState {
  const IkAudioState(this.status);
  final IkAudioStatus status;
}

final ikAudioRuntimeProvider =
    StateNotifierProvider<IkAudioCoordinator, IkAudioState>((ref) {
      final player = ref.read(playerProvider.notifier);
      final coordinator = IkAudioCoordinator(
        setFade: (enabled, duration) =>
            player.setFadeOptions(enabled: enabled, duration: duration),
        applyEqualizer: player.applyEqualizerSettingsVerified,
      );
      ref.listen(
        audioEffectsSettingsProvider,
        (_, next) => unawaited(coordinator.apply(next)),
      );
      // 延迟首次发布，避免 provider 在 widget 建树过程中更新自身依赖。
      final initial = ref.read(audioEffectsSettingsProvider);
      unawaited(Future<void>.microtask(() => coordinator.apply(initial)));
      return coordinator;
    });

class IkAudioCoordinator extends StateNotifier<IkAudioState> {
  IkAudioCoordinator({required this.setFade, required this.applyEqualizer})
    : super(const IkAudioState(IkAudioStatus.idle));

  final void Function(bool, Duration) setFade;
  final Future<void> Function(AudioEffectsSettings) applyEqualizer;
  AudioEffectsSettings? _last;
  int _generation = 0;

  Future<void> apply(AudioEffectsSettings next, {bool force = false}) async {
    if (!mounted) return;
    final previous = _last;
    _last = next;
    if (previous?.fadeEnabled != next.fadeEnabled ||
        previous?.fadeDuration != next.fadeDuration) {
      setFade(next.fadeEnabled, next.fadeDuration);
    }
    if (!force &&
        previous?.equalizerEnabled == next.equalizerEnabled &&
        listEquals(
          previous?.effectiveEqualizerBandGains,
          next.effectiveEqualizerBandGains,
        )) {
      return;
    }
    final generation = ++_generation;
    state = const IkAudioState(IkAudioStatus.applying);
    try {
      await applyEqualizer(next);
      if (mounted && generation == _generation) {
        state = const IkAudioState(IkAudioStatus.applied);
      }
    } on UnsupportedError {
      if (mounted && generation == _generation) {
        state = const IkAudioState(IkAudioStatus.unsupported);
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        state = const IkAudioState(IkAudioStatus.failed);
      }
    }
  }

  Future<void> retry() =>
      apply(_last ?? const AudioEffectsSettings(), force: true);
}

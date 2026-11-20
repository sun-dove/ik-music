import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/features/audio_effects/presentation/providers/audio_effects_provider.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/video_app/multi_source/multi_source_player.dart';
import 'package:mconnect/video_app/multi_source/source_collection.dart';
import 'package:mconnect/video_app/multi_source/source_coordinator.dart';
import 'package:mconnect/video_app/video_preferences.dart';

import 'support/content_page_fakes.dart';

class _Box extends Fake implements Box {
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => defaultValue;
}

class _VerifiedAudio extends IdleAudioController
    implements VerifiedEqualizerCapable {
  bool fail = false;
  List<double>? gains;
  @override
  Future<void> applyEqualizerVerified({
    required bool enabled,
    required List<double> bandGains,
  }) async {
    if (fail) throw StateError('equalizer rejected');
    gains = bandGains;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('K06 独立多源播放器必须透传可验证音效能力和底层失败', () async {
    final audio = _VerifiedAudio();
    final player = MultiSourceVideoPlayerNotifier(
      settings: SourceSettings(VideoPreferences(_Box())),
      router: PreparedSourceRouter(
        platformResolver: (_) => FakeContentPlatform(type: PlatformType.qq),
        fixedQuality: (_) => AudioLevel.low,
      ),
      resolve: (_, _, _) => throw const SourceFailure('unused', 'unused'),
      audioController: audio,
    );
    addTearDown(player.dispose);
    const settings = AudioEffectsSettings(
      equalizerEnabled: true,
      equalizerPreset: EqualizerPreset.vocal,
    );
    await player.applyEqualizerSettingsVerified(settings);
    expect(audio.gains, settings.effectiveEqualizerBandGains);
    audio.fail = true;
    await expectLater(
      player.applyEqualizerSettingsVerified(settings),
      throwsStateError,
    );
  });
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/audio_effects/presentation/providers/audio_effects_provider.dart';
import 'package:mconnect/video_app/ik/ik_strict_settings.dart';

void main() {
  test('U03 音效写失败不更新state，并发两个字段按最新值串行合并', () async {
    var fail = true;
    var writes = 0;
    final gate = Completer<void>();
    final notifier = IkStrictAudioSettings(
      initial: const AudioEffectsSettings(),
      write: (_) async {
        writes++;
        if (fail) throw StateError('save');
        await gate.future;
      },
    );
    addTearDown(notifier.dispose);
    await expectLater(notifier.setFadeEnabled(true), throwsStateError);
    expect(notifier.state.fadeEnabled, isFalse);
    fail = false;
    final a = notifier.setFadeEnabled(true);
    final b = notifier.setEqualizerEnabled(true);
    expect(notifier.state.fadeEnabled, isFalse);
    gate.complete();
    await Future.wait([a, b]);
    expect(notifier.state.fadeEnabled, isTrue);
    expect(notifier.state.equalizerEnabled, isTrue);
    expect(writes, 3);
  });
  test('U03 缓存写失败不更新state，后续重试可用且不丢离线设置', () async {
    var fail = true;
    final notifier = IkStrictCacheSettings(
      write: (_) async {
        if (fail) throw StateError('save');
      },
    );
    addTearDown(notifier.dispose);
    await notifier.ready;
    await expectLater(notifier.setOfflineMode(true), throwsStateError);
    expect(notifier.state.offlineMode, isFalse);
    fail = false;
    await Future.wait([
      notifier.setOfflineMode(true),
      notifier.setSizeLimitMb(2048),
    ]);
    expect(notifier.state.offlineMode, isTrue);
    expect(notifier.state.sizeLimitMb, 2048);
  });
}

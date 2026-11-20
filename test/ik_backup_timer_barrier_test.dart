import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/audio_effects/presentation/providers/audio_effects_provider.dart';
import 'package:mconnect/features/audio_effects/presentation/providers/sleep_timer_provider.dart';
import 'package:mconnect/features/backup/data/backup_store.dart';
import 'package:mconnect/features/backup/domain/backup_models.dart';
import 'package:mconnect/video_app/ik/ik_backup_service.dart';

class _RestoreStore implements BackupStore {
  _RestoreStore(this.write);
  final Future<void> Function(BackupData) write;
  @override
  int get schemaVersion => 1;
  @override
  Future<BackupData> collect() async => BackupData(
    settings: {
      'audio_effects_settings': const AudioEffectsSettings(
        fadeEnabled: true,
        equalizerEnabled: true,
        equalizerPreset: EqualizerPreset.rock,
        sleepTimerEnabled: false,
      ).toJson(),
    },
  );
  @override
  Future<BackupImportReport> restore(BackupData data) async {
    await write(data);
    return const BackupImportReport();
  }

  @override
  Future<void> clearAll() async {}
}

void main() {
  testWidgets('K06 等待已发出计时写入再导入，导入期间不重启旧计时', (tester) async {
    final pendingWrite = Completer<void>();
    final importing = Completer<void>();
    final order = <String>[];
    final timer = SleepTimerNotifier(
      pausePlayback: () async {},
      initialEnabled: true,
      initialRemaining: const Duration(minutes: 2),
      persist: ({required enabled, required remaining}) async {
        order.add('old-write');
        await pendingWrite.future;
        order.add('old-finished');
      },
    );
    final service = IkBackupService(
      store: _RestoreStore((_) async {
        order.add('import');
        await importing.future;
      }),
      currentTimer: () => timer,
      reloadEffects: () {
        order.add('reload');
        timer.dispose();
      },
    );
    String? raw;
    unawaited(service.exportToJson().then((value) => raw = value));
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    expect(order, ['old-write']);
    var completed = false;
    unawaited(service.importFromJson(raw!).then((_) => completed = true));
    await tester.pump();
    expect(order, ['old-write']);
    await tester.pump(const Duration(seconds: 30));
    expect(order, ['old-write']);
    pendingWrite.complete();
    await tester.pump();
    expect(order, ['old-write', 'old-finished', 'import']);
    timer.setEnabled(true);
    await tester.pump(const Duration(seconds: 30));
    expect(order, ['old-write', 'old-finished', 'import']);
    importing.complete();
    await tester.pump();
    expect(completed, isTrue);
    expect(order.last, 'reload');
  });

  testWidgets('K06 成功恢复后睡眠计时不会用旧内存覆盖导入的音效', (tester) async {
    final effectsStore = MemoryAudioEffectsSettingsStore(
      const AudioEffectsSettings(
        sleepTimerEnabled: true,
        sleepTimerRemaining: Duration(minutes: 2),
      ).toJson(),
    );
    final container = ProviderContainer(
      overrides: [
        audioEffectsSettingsStoreProvider.overrideWithValue(effectsStore),
      ],
    );
    container.read(sleepTimerProvider);
    await tester.pump();
    final service = IkBackupService(
      store: _RestoreStore((data) async {
        await effectsStore.write(
          Map<String, dynamic>.from(
            data.settings['audio_effects_settings'] as Map,
          ),
        );
      }),
      currentTimer: () => container.read(sleepTimerProvider.notifier),
      reloadEffects: () {
        container.invalidate(sleepTimerProvider);
        container.invalidate(audioEffectsSettingsProvider);
        container.read(audioEffectsSettingsProvider);
        container.read(sleepTimerProvider);
      },
    );
    String? raw;
    unawaited(service.exportToJson().then((value) => raw = value));
    await tester.pump();
    var done = false;
    unawaited(service.importFromJson(raw!).then((_) => done = true));
    await tester.pump();
    expect(done, isTrue);
    await tester.pump(const Duration(seconds: 30));
    final restored = AudioEffectsSettings.fromJson(effectsStore.value);
    expect(restored.fadeEnabled, isTrue);
    expect(restored.equalizerPreset, EqualizerPreset.rock);
    expect(restored.equalizerEnabled, isTrue);
    expect(restored.sleepTimerEnabled, isFalse);
    expect(container.read(sleepTimerProvider).enabled, isFalse);
    container.dispose();
  });

  testWidgets('K06 导入失败后原计时继续，解析失败也恢复运行', (tester) async {
    var writes = 0;
    final timer = SleepTimerNotifier(
      pausePlayback: () async {},
      initialEnabled: true,
      initialRemaining: const Duration(minutes: 2),
      persist: ({required enabled, required remaining}) async {
        writes++;
      },
    );
    final service = IkBackupService(
      store: _RestoreStore((_) => Future.error(StateError('disk-full'))),
      currentTimer: () => timer,
      reloadEffects: () => fail('failed import must not reload'),
    );
    Object? failure;
    unawaited(
      service.importFromJson('broken').catchError((Object error) {
        failure = error;
        return const BackupImportReport();
      }),
    );
    await tester.pump();
    expect(failure, isA<BackupFormatException>());
    await tester.pump(const Duration(seconds: 10));
    expect(writes, 1);
    expect(timer.state.enabled, isTrue);
    String? raw;
    unawaited(service.exportToJson().then((value) => raw = value));
    await tester.pump();
    failure = null;
    unawaited(
      service.importFromJson(raw!).catchError((Object error) {
        failure = error;
        return const BackupImportReport();
      }),
    );
    await tester.pump();
    expect(failure, isA<StateError>());
    await tester.pump(const Duration(seconds: 10));
    expect(writes, 2);
    expect(timer.state.enabled, isTrue);
    timer.dispose();
  });
}

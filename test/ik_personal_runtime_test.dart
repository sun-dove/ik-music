import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/database/app_database.dart';
import 'package:mconnect/features/audio_effects/presentation/providers/audio_effects_provider.dart';
import 'package:mconnect/features/backup/data/backup_service.dart';
import 'package:mconnect/features/library/presentation/providers/history_provider.dart';
import 'package:mconnect/features/library/presentation/providers/likes_provider.dart';
import 'package:mconnect/l10n/ik_runtime_strings.dart';
import 'package:mconnect/video_app/ik/ik_audio_page.dart';
import 'package:mconnect/video_app/ik/ik_audio_runtime.dart';

void main() {
  test('K06 文件选择器 UTF-8 字节保持中文并拒绝非法编码', () {
    const content = '{"歌单":"夜曲 🎵","字体":"微软雅黑"}';
    expect(BackupService.decodeFileBytes(utf8.encode(content)), content);
    expect(
      () => BackupService.decodeFileBytes([0xff, 0xfe]),
      throwsFormatException,
    );
  });

  test('K04 新全量入口不截断，旧入口仍保持原数量', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.songsDao.insertSongs([
      for (var i = 0; i < 501; i++)
        SongsCompanion.insert(
          id: '$i',
          platform: 'qq',
          name: '收藏$i',
          artists: '歌手',
          fingerprint: '$i',
        ),
    ]);
    await db.likesDao.restoreLikeRows([
      for (var i = 0; i < 501; i++)
        UserLike(id: i, songId: '$i', platform: 'qq', addedAt: i),
    ]);
    for (var i = 0; i < 201; i++) {
      await db.historyDao.recordListen('$i', 'qq');
    }
    final likes = LikesNotifier(db.likesDao, db.songsDao);
    final history = HistoryNotifier(db.historyDao, db.songsDao);
    addTearDown(likes.dispose);
    addTearDown(history.dispose);
    await likes.loadLikes();
    await history.loadHistory();
    expect(likes.state.songs, hasLength(500));
    expect(history.state.entries, hasLength(200));
    await likes.loadAllLikes();
    await history.loadAllHistory();
    expect(likes.state.songs, hasLength(501));
    expect(history.state.entries, hasLength(201));
    expect(likes.state.songs.first.id, '500');
  });

  test('K06 定时剩余时间保存不重复修改音效，失败可重试', () async {
    var fades = 0;
    var eqs = 0;
    var fail = true;
    final coordinator = IkAudioCoordinator(
      setFade: (_, _) => fades++,
      applyEqualizer: (_) async {
        eqs++;
        if (fail) throw StateError('backend unavailable');
      },
    );
    addTearDown(coordinator.dispose);
    const settings = AudioEffectsSettings(equalizerEnabled: true);
    await coordinator.apply(settings);
    expect(coordinator.state.status, IkAudioStatus.failed);
    await coordinator.apply(
      settings.copyWith(sleepTimerRemaining: const Duration(seconds: 20)),
    );
    expect(fades, 1);
    expect(eqs, 1);
    fail = false;
    await coordinator.retry();
    expect(coordinator.state.status, IkAudioStatus.applied);
    expect(eqs, 2);
  });

  test('K06 旧响应不能覆盖新的均衡器状态', () async {
    final pending = <Completer<void>>[];
    final coordinator = IkAudioCoordinator(
      setFade: (_, _) {},
      applyEqualizer: (_) {
        final completer = Completer<void>();
        pending.add(completer);
        return completer.future;
      },
    );
    addTearDown(coordinator.dispose);
    final first = coordinator.apply(
      const AudioEffectsSettings(equalizerEnabled: true),
    );
    final second = coordinator.apply(
      const AudioEffectsSettings(equalizerEnabled: false),
    );
    pending.last.complete();
    await second;
    pending.first.completeError(StateError('old failure'));
    await first;
    expect(coordinator.state.status, IkAudioStatus.applied);
  });

  testWidgets('K06 音效失败有重试，重试成功可见', (tester) async {
    var fail = true;
    final coordinator = IkAudioCoordinator(
      setFade: (_, _) {},
      applyEqualizer: (_) async {
        if (fail) throw StateError('offline');
      },
    );
    await coordinator.apply(const AudioEffectsSettings(equalizerEnabled: true));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioEffectsSettingsStoreProvider.overrideWithValue(
            MemoryAudioEffectsSettingsStore(),
          ),
          ikAudioRuntimeProvider.overrideWith((ref) => coordinator),
        ],
        child: const MaterialApp(home: IkAudioPage()),
      ),
    );
    expect(find.text(IkRuntimeStrings.audioApplyFailed), findsOneWidget);
    fail = false;
    await tester.tap(find.text(IkRuntimeStrings.retry));
    await tester.pumpAndSettle();
    expect(find.text(IkRuntimeStrings.audioApplied), findsOneWidget);
  });
}

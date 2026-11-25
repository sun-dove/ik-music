import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/download/domain/entities/download_task.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/video_app/ik/ik_download_submission.dart';

Song song(String id) =>
    Song(id: id, platform: PlatformType.qq, name: id, artists: const []);
DownloadTask task(
  String id, {
  bool cache = false,
  DownloadStatus status = DownloadStatus.waiting,
}) => DownloadTask(
  id: cache
      ? DownloadTask.buildCacheId(song(id), AudioLevel.high)
      : DownloadTask.buildId(song(id), AudioLevel.high),
  song: song(id),
  quality: AudioLevel.high,
  status: status,
  isOfflineCache: cache,
  createdAt: DateTime(2026),
);

void main() {
  test('A06 恢复失败时不入队，准确报告全部提交失败', () async {
    final report = await submitIkDownloads(
      songs: [song('一'), song('二')],
      qualityFor: (_) => AudioLevel.high,
      readTasks: () => throw StateError('不得读取'),
      start: (_, _) async => fail('不得入队'),
      ready: Future<void>.error(StateError('恢复失败')),
    );
    expect(
      (report.added, report.existing, report.retried, report.failed),
      (0, 0, 0, 2),
    );
  });
  test('A06 恢复完成之前不提交，已持久化下载不会被重复新增', () async {
    final restored = Completer<void>();
    final tasks = <DownloadTask>[];
    var started = false;
    final pending = submitIkDownloads(
      songs: [song('恢复中')],
      qualityFor: (_) => AudioLevel.high,
      readTasks: () => tasks,
      start: (_, _) async => started = true,
      ready: restored.future,
    );
    await Future<void>.delayed(Duration.zero);
    expect(started, isFalse);
    tasks.add(task('恢复中', status: DownloadStatus.completed));
    restored.complete();
    final report = await pending;
    expect(started, isFalse);
    expect((report.added, report.existing), (0, 1));
  });
  test('A06 入队报告区分新增、已有、失败重试与立即失败，缓存不阻塞手动任务', () async {
    final tasks = [
      task('已有'),
      task('重试', status: DownloadStatus.failed),
      task('缓存', cache: true),
    ];
    final calls = <String>[];
    final report = await submitIkDownloads(
      songs: ['新增', '已有', '重试', '失败', '缓存', '新增'].map(song).toList(),
      qualityFor: (_) => AudioLevel.high,
      readTasks: () => tasks,
      start: (song, quality) async {
        expect(quality, AudioLevel.high);
        calls.add(song.id);
        tasks.removeWhere((t) => t.id == DownloadTask.buildId(song, quality));
        tasks.add(
          task(
            song.id,
            status: song.id == '失败'
                ? DownloadStatus.failed
                : DownloadStatus.waiting,
          ),
        );
      },
    );
    expect(
      (report.added, report.existing, report.retried, report.failed),
      (2, 2, 1, 1),
    );
    expect(calls, ['新增', '重试', '失败', '缓存']);
    expect(tasks.where((t) => t.isOfflineCache), hasLength(1));
  });

  test('A06 单项抛错或未生成任务不能报成功，后续条目继续处理', () async {
    final tasks = <DownloadTask>[];
    final report = await submitIkDownloads(
      songs: ['抛错', '无任务', '后续'].map(song).toList(),
      qualityFor: (_) => AudioLevel.high,
      readTasks: () => tasks,
      start: (song, _) async {
        if (song.id == '抛错') throw StateError('写入失败');
        if (song.id == '后续') tasks.add(task(song.id));
      },
    );
    expect(
      (report.added, report.existing, report.retried, report.failed),
      (1, 0, 0, 2),
    );
  });

  test('A06 同歌不同质量仍是不同任务；空提交不调用下载器', () async {
    final tasks = [task('同歌')];
    final report = await submitIkDownloads(
      songs: [song('同歌')],
      qualityFor: (_) => AudioLevel.lossless,
      readTasks: () => tasks,
      start: (song, quality) async => tasks.add(
        DownloadTask(
          id: DownloadTask.buildId(song, quality),
          song: song,
          quality: quality,
          createdAt: DateTime(2026),
        ),
      ),
    );
    expect(report.added, 1);
    expect(tasks, hasLength(2));
    final empty = await submitIkDownloads(
      songs: [],
      qualityFor: (_) => throw StateError('未调用'),
      readTasks: () => tasks,
      start: (_, _) async => fail('不得调用'),
    );
    expect(
      (empty.added, empty.existing, empty.retried, empty.failed),
      (0, 0, 0, 0),
    );
  });
}

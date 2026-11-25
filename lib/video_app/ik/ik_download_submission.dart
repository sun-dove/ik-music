import '../../features/download/domain/entities/download_task.dart';
import '../../models/audio_quality.dart';
import '../../models/song.dart';

class IkDownloadSubmissionReport {
  const IkDownloadSubmissionReport({
    this.added = 0,
    this.existing = 0,
    this.retried = 0,
    this.failed = 0,
  });
  final int added, existing, retried, failed;
}

/// 独立入口入队反馈适配，原下载器的 `Future<void>` 契约保持。
Future<IkDownloadSubmissionReport> submitIkDownloads({
  required List<Song> songs,
  required AudioLevel Function(Song) qualityFor,
  required List<DownloadTask> Function() readTasks,
  required Future<void> Function(Song, AudioLevel) start,
  Future<void>? ready,
}) async {
  try {
    await ready;
  } catch (_) {
    return IkDownloadSubmissionReport(failed: songs.length);
  }
  var added = 0, existing = 0, retried = 0, failed = 0;
  for (final song in songs) {
    try {
      final quality = qualityFor(song);
      final id = DownloadTask.buildId(song, quality);
      final before = readTasks().where((task) => task.id == id).firstOrNull;
      if (before != null && before.status != DownloadStatus.failed) {
        existing++;
        continue;
      }
      await start(song, quality);
      final after = readTasks().where((task) => task.id == id).firstOrNull;
      if (after == null || after.status == DownloadStatus.failed) {
        failed++;
      } else if (before != null) {
        retried++;
      } else {
        added++;
      }
    } catch (_) {
      failed++;
    }
  }
  return IkDownloadSubmissionReport(
    added: added,
    existing: existing,
    retried: retried,
    failed: failed,
  );
}

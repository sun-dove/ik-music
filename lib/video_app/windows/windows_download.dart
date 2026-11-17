import 'package:file_picker/file_picker.dart';

import '../../features/download/data/download_directory_service.dart';
import '../../features/download/domain/entities/download_task.dart';
import '../../features/download/presentation/providers/download_provider.dart';
import '../../models/audio_quality.dart';

Future<DownloadRootResult?> chooseWindowsDownloadDirectory(
  DownloadNotifier notifier,
) async {
  final path = await FilePicker.getDirectoryPath();
  return path == null ? null : await notifier.setCustomDownloadRoot(path);
}

/// 暂停任务继续原档位；用户明确重试失败任务时采用当前档位。
Future<void> retryWindowsDownload(
  DownloadNotifier notifier,
  DownloadTask task,
  AudioLevel quality, {
  required DownloadState Function() readState,
}) async {
  if (task.status == DownloadStatus.paused || task.quality == quality) {
    await notifier.resumeDownload(task.id);
    return;
  }
  final nextId = task.isOfflineCache
      ? DownloadTask.buildCacheId(task.song, quality)
      : DownloadTask.buildId(task.song, quality);
  if (task.isOfflineCache) {
    await notifier.cacheSongs([task.song], quality: quality);
  } else {
    await notifier.startDownload(task.song, quality);
  }
  await notifier.resumeDownload(nextId);
  if (readState().tasks.any((value) => value.id == nextId)) {
    notifier.cancelDownload(task.id);
  }
}

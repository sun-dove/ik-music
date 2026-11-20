import 'dart:io';

import '../../../l10n/ik_runtime_strings.dart';
import '../domain/backup_models.dart';
import 'backup_service.dart';
import 'backup_store.dart';

/// 独立改版选择的安全合并入口；旧 AppBackupStore.restore 保持原契约。
class GuardedAppBackupStore extends AppBackupStore {
  GuardedAppBackupStore({
    required super.database,
    super.playlists,
    super.smartRules,
    super.settings,
    this.recoveryDirectory,
    required this.appVersion,
  });

  final Directory? recoveryDirectory;
  final String appVersion;
  bool _restoring = false;

  @override
  Future<BackupImportReport> restore(BackupData data) async {
    if (_restoring) throw StateError('backup_import_in_progress');
    _restoring = true;
    try {
      final originalPlaylists = await playlists.captureStorageSnapshot();
      final originalRules = await smartRules.loadRules();
      final originalSettings = await settings.read();
      final File recovery;
      try {
        recovery = await BackupService(
          store: this,
          appVersion: appVersion,
          fileNamePrefix:
              'ik-before-import-${DateTime.now().microsecondsSinceEpoch}-',
        ).exportToFile(directory: recoveryDirectory);
      } catch (_) {
        throw const FileSystemException(IkRuntimeStrings.backupSnapshotFailed);
      }
      try {
        // SQL 的歌曲、收藏、统计写入一起提交；任何外部写失败都会回滚 SQL。
        return await database.transaction(() => super.restore(data));
      } catch (_) {
        var recovered = true;
        // 每个介质独立恢复，不能因其中一个失败而跳过另外两个。
        for (final restore in <Future<void> Function()>[
          () => playlists.restoreStorageSnapshot(originalPlaylists),
          () => smartRules.saveRules(originalRules),
          () async {
            await settings.clear();
            await settings.write(originalSettings);
          },
        ]) {
          try {
            await restore();
          } catch (_) {
            recovered = false;
          }
        }
        throw BackupRestoreException(
          recovered: recovered,
          recoveryPath: recovery.path,
        );
      }
    } finally {
      _restoring = false;
    }
  }
}

class BackupRestoreException implements Exception {
  const BackupRestoreException({
    required this.recovered,
    required this.recoveryPath,
  });
  final bool recovered;
  final String recoveryPath;

  @override
  String toString() => recovered
      ? IkRuntimeStrings.backupRecovered(recoveryPath)
      : IkRuntimeStrings.backupRecoveryFailed(recoveryPath);
}

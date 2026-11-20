import '../../features/audio_effects/presentation/providers/sleep_timer_provider.dart';
import '../../features/backup/data/backup_service.dart';
import '../../features/backup/domain/backup_models.dart';
import 'ik_version.dart';

/// ik 恢复前暂停计时写入；旧 BackupService 入口保持原行为。
class IkBackupService extends BackupService {
  IkBackupService({
    required super.store,
    required this.currentTimer,
    required this.reloadEffects,
  }) : super(appVersion: IkVersion.label, fileNamePrefix: 'ik-backup-');

  final SleepTimerNotifier Function() currentTimer;
  final void Function() reloadEffects;
  bool _importing = false;

  @override
  Future<BackupImportReport> importFromJson(String raw) async {
    if (_importing) throw StateError('backup_import_in_progress');
    final timer = currentTimer();
    _importing = true;
    var restored = false;
    try {
      await timer.pauseForSettingsRestore();
      final report = await super.importFromJson(raw);
      restored = true;
      reloadEffects();
      return report;
    } finally {
      // 成功时旧实例必须保持停止，新的计时器从导入值创建。
      if (!restored) timer.resumeAfterSettingsRestoreFailure();
      _importing = false;
    }
  }
}

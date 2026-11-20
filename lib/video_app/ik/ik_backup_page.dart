import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../features/audio_effects/presentation/providers/audio_effects_provider.dart';
import '../../features/audio_effects/presentation/providers/sleep_timer_provider.dart';
import '../../features/backup/data/backup_service.dart';
import '../../features/backup/data/guarded_backup_store.dart';
import '../../features/backup/presentation/pages/backup_page.dart';
import '../../features/library/presentation/providers/history_provider.dart';
import '../../features/library/presentation/providers/likes_provider.dart';
import '../../features/library/presentation/providers/my_playlists_provider.dart';
import '../../features/smart_playlists/presentation/providers/smart_playlists_provider.dart';
import '../../features/stats/presentation/providers/listening_stats_provider.dart';
import '../../l10n/ik_runtime_strings.dart';
import 'ik_audio_runtime.dart';
import 'ik_backup_service.dart';
import 'ik_version.dart';

final ikBackupServiceProvider = Provider<BackupService>(
  (ref) => IkBackupService(
    store: GuardedAppBackupStore(
      database: database,
      appVersion: IkVersion.label,
    ),
    currentTimer: () => ref.read(sleepTimerProvider.notifier),
    reloadEffects: () {
      ref.invalidate(sleepTimerProvider);
      ref.invalidate(ikAudioRuntimeProvider);
      ref.invalidate(audioEffectsSettingsProvider);
      ref.read(audioEffectsSettingsProvider);
      ref.read(sleepTimerProvider);
      ref.read(ikAudioRuntimeProvider);
    },
  ),
);

class IkBackupPage extends ConsumerWidget {
  const IkBackupPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => BackupPage(
    service: ref.watch(ikBackupServiceProvider),
    onImported: () async {
      await Future.wait([
        ref.read(likesProvider.notifier).loadAllLikes(),
        ref.read(historyProvider.notifier).loadAllHistory(),
        ref.read(myPlaylistsProvider.notifier).load(),
        ref.read(smartPlaylistsProvider.notifier).load(),
        ref.read(listeningStatsProvider.notifier).load(),
      ]);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(IkRuntimeStrings.restoreRestart)),
        );
      }
    },
  );
}

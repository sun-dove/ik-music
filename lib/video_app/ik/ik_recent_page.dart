import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/library/presentation/providers/history_provider.dart';
import '../../features/player/presentation/providers/player_provider.dart';
import '../../l10n/ik_strings.dart';
import '../../l10n/ik_workspace_strings.dart';
import '../../models/song.dart';
import 'ik_catalog_pages.dart';

class IkRecentPage extends ConsumerWidget {
  const IkRecentPage({
    super.key,
    required this.onNavigate,
    required this.onMore,
  });
  final ValueChanged<String> onNavigate;
  final ValueChanged<Song> onMore;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider),
        player = ref.watch(playerProvider);
    final songs = history.entries.map((entry) => entry.song).toList();
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 20,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      IkStrings.history,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    OutlinedButton.icon(
                      onPressed: () => onNavigate('/listening-stats'),
                      icon: const Icon(Icons.insights_outlined, size: 18),
                      label: const Text(IkStrings.stats),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  IkWorkspaceStrings.recentHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                Text(IkWorkspaceStrings.tracks(songs.length)),
                if (history.isLoading) const LinearProgressIndicator(),
                if (history.error != null) ...[
                  Text(
                    history.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  TextButton(
                    onPressed: ref
                        .read(historyProvider.notifier)
                        .loadAllHistory,
                    child: const Text(IkWorkspaceStrings.retry),
                  ),
                ],
              ],
            ),
          ),
        ),
        SliverList.builder(
          itemCount: songs.length,
          itemBuilder: (context, index) => IkSongTile(
            song: songs[index],
            onTap: () => ref
                .read(playerProvider.notifier)
                .playPlaylist(songs, startIndex: index),
            onMore: () => onMore(songs[index]),
            playing: player.currentSong?.dedupeKey == songs[index].dedupeKey,
          ),
        ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 20)),
      ],
    );
  }
}

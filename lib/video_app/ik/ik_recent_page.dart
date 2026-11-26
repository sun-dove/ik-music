import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/share/song_actions.dart';
import '../../features/library/presentation/providers/history_provider.dart';
import '../../features/library/presentation/providers/likes_provider.dart';
import '../../features/player/presentation/providers/player_provider.dart';
import '../../l10n/ik_recent_strings.dart';
import '../../l10n/ik_strings.dart';
import '../../l10n/ik_alignment_strings.dart';
import '../../l10n/ik_workspace_strings.dart';
import '../../models/platform_type.dart';
import '../../models/song.dart';
import 'ik_catalog_pages.dart';
import 'ik_song_table.dart';

class IkRecentPage extends ConsumerWidget {
  const IkRecentPage({
    super.key,
    required this.onNavigate,
    required this.onMore,
    this.onMoreWithContext,
    this.alignToDesign = false,
    this.contextActions = false,
  });
  final ValueChanged<String> onNavigate;
  final ValueChanged<Song> onMore;
  final void Function(BuildContext, Song)? onMoreWithContext;
  final bool alignToDesign;
  final bool contextActions;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    final currentSong = contextActions
        ? ref.watch(playerProvider.select((state) => state.currentSong))
        : ref.watch(playerProvider).currentSong;
    final groups = contextActions ? _recentGroups(history.entries) : null;
    final songs = groups == null
        ? history.entries.map((entry) => entry.song).toList()
        : groups.map((group) => group.latest.song).toList();
    final playingIndex = groups == null
        ? -1
        : _recentPlayingIndex(groups, currentSong);
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
                  contextActions
                      ? IkRecentStrings.hint
                      : IkWorkspaceStrings.recentHint,
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
        if (alignToDesign && songs.isNotEmpty)
          const SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            sliver: SliverToBoxAdapter(child: IkSongTableHeader()),
          ),
        SliverList.builder(
          itemCount: songs.length,
          itemBuilder: (rowContext, index) {
            final group = groups?[index];
            void more() {
              if (group == null) {
                onMore(songs[index]);
              } else {
                _showRecentActions(
                  context,
                  ref,
                  group,
                  position: _menuPosition(rowContext),
                );
              }
            }
            final row = alignToDesign
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: IkSongTableRow(
                      song: songs[index],
                      index: index,
                      onPlay: () => ref
                          .read(playerProvider.notifier)
                          .playPlaylist(songs, startIndex: index),
                      onMore: more,
                      onMoreWithContext: group != null
                          ? (buttonContext) => _showRecentActions(
                              context,
                              ref,
                              group,
                              position: _menuPosition(buttonContext),
                            )
                          : onMoreWithContext == null
                          ? null
                          : (buttonContext) => onMoreWithContext!(
                              buttonContext,
                              songs[index],
                            ),
                      playing: group != null
                          ? playingIndex == index
                          : currentSong?.id == songs[index].id &&
                                currentSong?.platform ==
                                    songs[index].platform,
                      detail: IkAlignmentStrings.listenedAt(
                        group?.latest.listenedAt ??
                            history.entries[index].listenedAt,
                      ),
                    ),
                  )
                : IkSongTile(
                    song: songs[index],
                    onTap: () => ref
                        .read(playerProvider.notifier)
                        .playPlaylist(songs, startIndex: index),
                    onMore: more,
                    playing: group != null
                        ? playingIndex == index
                        : currentSong?.dedupeKey ==
                              songs[index].dedupeKey,
                  );
            if (group == null) return row;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onSecondaryTapDown: (details) => _showRecentActions(
                context,
                ref,
                group,
                position: details.globalPosition,
              ),
              child: row,
            );
          },
        ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 20)),
      ],
    );
  }
}

Future<SongActionResult?> _showRecentActions(
  BuildContext context,
  WidgetRef ref,
  _RecentSongGroup group, {
  Offset? position,
}) => showSongActionsMenuAt(
  context,
  ref,
  song: group.latest.song,
  position: position,
  isLiked: ref.read(likesProvider).songs.contains(group.latest.song),
  isLocal: group.latest.song.platform == PlatformType.local,
  extraActions: [
    SongMenuExtraAction(
      label: IkRecentStrings.remove,
      icon: Icons.history_toggle_off_rounded,
      onSelected: () async {
        final removed = await ref
            .read(historyProvider.notifier)
            .removeRecentSongsHistory(group.songs);
        return SongActionResult(
          success: removed,
          message: removed
              ? IkRecentStrings.removed
              : IkRecentStrings.removeFailed,
        );
      },
    ),
  ],
);

Offset? _menuPosition(BuildContext context) {
  final box = context.findRenderObject();
  return box is RenderBox && box.hasSize
      ? box.localToGlobal(Offset(box.size.width, box.size.height))
      : null;
}

class _RecentSongGroup {
  _RecentSongGroup(this.latest, this.contentKey);
  final HistoryEntry latest;
  final String? contentKey;
  final List<Song> songs = [];
  final Set<({String id, PlatformType platform})> identities = {};
}

List<_RecentSongGroup> _recentGroups(List<HistoryEntry> entries) {
  final ordered = entries.asMap().entries.toList()
    ..sort((a, b) {
      final byTime = b.value.listenedAt.compareTo(a.value.listenedAt);
      return byTime == 0 ? a.key.compareTo(b.key) : byTime;
    });
  final groups = <_RecentSongGroup>[];
  final seen = <({String id, PlatformType platform})>{};
  final byContent = <String, _RecentSongGroup>{};
  for (final item in ordered) {
    final entry = item.value;
    final identity = (id: entry.song.id, platform: entry.song.platform);
    if (!seen.add(identity)) continue;
    final contentKey = _recentContentKey(entry.song);
    var group = contentKey == null ? null : byContent[contentKey];
    if (group == null) {
      group = _RecentSongGroup(entry, contentKey);
      groups.add(group);
      if (contentKey != null) byContent[contentKey] = group;
    }
    group.songs.add(entry.song);
    group.identities.add(identity);
  }
  return groups;
}

String? _recentContentKey(Song song) {
  String normalized(String text) =>
      text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  final title = normalized(song.name);
  final artists = song.artists
      .map((artist) => normalized(artist.name))
      .toSet()
      .toList()
    ..sort();
  const unknownArtists = {
    '',
    'unknown',
    'unknown artist',
    '未知',
    '未知歌手',
    '未知艺术家',
  };
  if (title.isEmpty ||
      artists.isEmpty ||
      artists.any(unknownArtists.contains)) {
    return null;
  }
  return jsonEncode([title, artists]);
}

int _recentPlayingIndex(List<_RecentSongGroup> groups, Song? current) {
  if (current == null) return -1;
  final exact = groups.indexWhere(
    (group) => group.identities.contains((
      id: current.id,
      platform: current.platform,
    )),
  );
  if (exact >= 0) return exact;
  final contentKey = _recentContentKey(current);
  if (contentKey == null) return -1;
  return groups.indexWhere((group) => group.contentKey == contentKey);
}

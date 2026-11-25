import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/share/song_actions.dart';
import '../../../../core/theme/platform_accent.dart';
import '../../../../core/widgets/app_scrollbar.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../l10n/ik_discovery_revision_strings.dart';
import '../../../../models/platform_type.dart';
import '../../../../models/song.dart';
import '../../../../platform/base/music_platform.dart';
import '../../../../video_app/ik/ik_song_table.dart';
import '../../../download/presentation/widgets/download_button.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../providers/new_songs_provider.dart';

/// 新歌速递 — new releases per platform and region.
///
/// A platform that cannot serve the selected region says so in place of the
/// list (`该地区暂不支持` / `暂不支持新歌速递`), because an empty list is
/// indistinguishable from "no new songs today".
class NewSongsPage extends ConsumerStatefulWidget {
  const NewSongsPage({super.key, this.alignToDesign = false});

  final bool alignToDesign;

  @override
  ConsumerState<NewSongsPage> createState() => _NewSongsPageState();
}

class _NewSongsPageState extends ConsumerState<NewSongsPage> {
  PlatformType _selectedPlatform = PlatformType.netease;

  @override
  void initState() {
    super.initState();
    final state = ref.read(newSongsProvider);
    if (!state.hasAnyData && !state.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(newSongsProvider.notifier).load();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(newSongsProvider);
    if (widget.alignToDesign) return _buildAligned(context, state);
    final platforms = PlatformType.musicServices.where((platform) {
      return state.songsForPlatform(platform).isNotEmpty ||
          state.noticeForPlatform(platform) != null ||
          state.errorForPlatform(platform) != null;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('新歌速递'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(newSongsProvider.notifier).refresh(),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              itemCount: NewSongRegionLabels.ordered.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final region = NewSongRegionLabels.ordered[index];
                return ChoiceChip(
                  label: Text(newSongRegionLabels[region]!),
                  selected: state.region == region,
                  onSelected: (_) =>
                      ref.read(newSongsProvider.notifier).load(region: region),
                );
              },
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(newSongsProvider.notifier).refresh(),
              child: AppScrollbar(
                builder: (controller) => ListView(
                  controller: controller,
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    if (state.isLoading && !state.hasAnyData)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    for (final platform in platforms)
                      _PlatformNewSongsSection(
                        platform: platform,
                        songs: state.songsForPlatform(platform),
                        notice: state.noticeForPlatform(platform),
                        error: state.errorForPlatform(platform),
                        onRetry: () =>
                            ref.read(newSongsProvider.notifier).refresh(),
                        onPlay: (index, songs) => ref
                            .read(playerProvider.notifier)
                            .playPlaylist(songs, startIndex: index),
                      ),
                    if (!state.isLoading && platforms.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: Text('暂无新歌数据，下拉刷新重试')),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAligned(BuildContext context, NewSongsState state) {
    final platform = _selectedPlatform;
    final songs = state.songsForPlatform(platform);
    final error = state.errorForPlatform(platform);
    final notice = state.noticeForPlatform(platform);
    final currentSong = ref.watch(
      playerProvider.select((state) => state.currentSong),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text(IkDiscoveryRevisionStrings.newSongs),
        actions: [
          IconButton(
            tooltip: IkDiscoveryRevisionStrings.refresh,
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(newSongsProvider.notifier).refresh(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final platform in PlatformType.musicServices)
                    ChoiceChip(
                      label: Text(platform.displayName),
                      selected: _selectedPlatform == platform,
                      onSelected: (_) =>
                          setState(() => _selectedPlatform = platform),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final region in NewSongRegionLabels.ordered)
                    ChoiceChip(
                      label: Text(newSongRegionLabels[region]!),
                      selected: state.region == region,
                      onSelected: state.isLoading
                          ? null
                          : (_) => ref
                                .read(newSongsProvider.notifier)
                                .load(region: region),
                    ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(newSongsProvider.notifier).refresh(),
              child: AppScrollbar(
                builder: (controller) => CustomScrollView(
                  controller: controller,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    if (state.isLoading)
                      const SliverAsyncStateView(
                        hasScrollBody: true,
                        child: AsyncStateView.loading(skeleton: true),
                      )
                    else if (error != null)
                      SliverAsyncStateView(
                        child: AsyncStateView.error(
                          title: IkDiscoveryRevisionStrings.newSongsFailed(
                            platform,
                          ),
                          message: error,
                          onRetry: () =>
                              ref.read(newSongsProvider.notifier).refresh(),
                        ),
                      )
                    else if (songs.isEmpty)
                      SliverAsyncStateView(
                        child: AsyncStateView.empty(
                          key: ValueKey('new-songs-notice-${platform.name}'),
                          title:
                              notice ?? IkDiscoveryRevisionStrings.noNewSongs,
                          message: notice == null
                              ? IkDiscoveryRevisionStrings.refreshHint
                              : null,
                        ),
                      )
                    else ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              FilledButton.icon(
                                onPressed: () => ref
                                    .read(playerProvider.notifier)
                                    .playPlaylist(songs),
                                icon: const Icon(Icons.play_arrow),
                                label: const Text(
                                  IkDiscoveryRevisionStrings.playAll,
                                ),
                              ),
                              Text(
                                IkDiscoveryRevisionStrings.songsCount(
                                  songs.length,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: IkSongTableHeader(),
                        ),
                      ),
                      SliverList.builder(
                        itemCount: songs.length,
                        itemBuilder: (context, index) {
                          final song = songs[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: IkSongTableRow(
                              song: song,
                              index: index,
                              playing:
                                  currentSong?.id == song.id &&
                                  currentSong?.platform == song.platform,
                              onPlay: () => ref
                                  .read(playerProvider.notifier)
                                  .playPlaylist(songs, startIndex: index),
                              onMore: () =>
                                  showSongActionsMenu(context, ref, song: song),
                              onMoreWithContext: (buttonContext) =>
                                  showSongActionsMenu(
                                    buttonContext,
                                    ref,
                                    song: song,
                                  ),
                            ),
                          );
                        },
                      ),
                    ],
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Region order for the chips (the enum's declaration order is the display
/// order; kept here so the page does not depend on that by accident).
class NewSongRegionLabels {
  NewSongRegionLabels._();

  static const List<NewSongRegion> ordered = [
    NewSongRegion.all,
    NewSongRegion.chinese,
    NewSongRegion.western,
    NewSongRegion.japanese,
    NewSongRegion.korean,
    NewSongRegion.hongKongTaiwan,
  ];
}

class _PlatformNewSongsSection extends StatelessWidget {
  const _PlatformNewSongsSection({
    required this.platform,
    required this.songs,
    required this.notice,
    required this.error,
    required this.onRetry,
    required this.onPlay,
  });

  final PlatformType platform;
  final List<Song> songs;
  final String? notice;
  final String? error;
  final VoidCallback onRetry;
  final void Function(int index, List<Song> songs) onPlay;

  @override
  Widget build(BuildContext context) {
    final accent = PlatformAccent.colorOf(context, platform);
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                platform.displayName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (songs.isNotEmpty)
                Text(
                  '${songs.length} 首',
                  style: TextStyle(fontSize: 12, color: cs.outline),
                ),
            ],
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 16, color: cs.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    error!,
                    style: TextStyle(fontSize: 12, color: cs.error),
                  ),
                ),
                TextButton(onPressed: onRetry, child: const Text('重试')),
              ],
            ),
          ),
        if (notice != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: cs.outline),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    notice!,
                    key: ValueKey('new-songs-notice-${platform.name}'),
                    style: TextStyle(fontSize: 12, color: cs.outline),
                  ),
                ),
              ],
            ),
          ),
        for (var i = 0; i < songs.length; i++)
          _NewSongTile(
            song: songs[i],
            accent: accent,
            onTap: () => onPlay(i, songs),
          ),
      ],
    );
  }
}

class _NewSongTile extends ConsumerWidget {
  const _NewSongTile({
    required this.song,
    required this.accent,
    required this.onTap,
  });

  final Song song;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: 48,
      height: 48,
      color: accent.withValues(alpha: 0.12),
      child: Icon(Icons.fiber_new, color: accent),
    );
    return ListTile(
      onTap: onTap,
      onLongPress: () => showSongActionsMenu(context, ref, song: song),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: song.coverUrl == null || song.coverUrl!.isEmpty
            ? placeholder
            : CachedNetworkImage(
                imageUrl: song.coverUrl!,
                width: 48,
                height: 48,
                memCacheWidth: 96,
                fit: BoxFit.cover,
                placeholder: (_, _) => placeholder,
                errorWidget: (_, _, _) => placeholder,
              ),
      ),
      title: Text(
        song.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 15),
      ),
      subtitle: Text(
        song.album?.name != null && song.album!.name.isNotEmpty
            ? '${song.artistNames} · ${song.album!.name}'
            : song.artistNames,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: cs.outline),
      ),
      trailing: DownloadButton(song: song, size: 22),
    );
  }
}

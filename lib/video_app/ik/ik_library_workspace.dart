import 'package:flutter/material.dart';

import '../../l10n/ik_strings.dart';
import '../../l10n/ik_workspace_strings.dart';
import '../../l10n/video_strings.dart';
import '../../models/platform_type.dart';
import '../../models/song.dart';
import '../data/video_catalog.dart';
import '../ui/catalog_pages.dart';
import '../ui/video_shell.dart';
import 'ik_controls.dart';
import 'ik_song_table.dart';

class IkLibraryWorkspace extends StatefulWidget {
  const IkLibraryWorkspace({
    super.key,
    required this.libraries,
    required this.syncing,
    required this.loggedIn,
    required this.onSync,
    required this.onPlay,
    required this.onMore,
    required this.onNavigate,
    required this.onDownloads,
    required this.onAccounts,
    required this.localLikes,
    required this.localLoading,
    this.localError,
    required this.onRetryLocal,
    this.currentSong,
    this.alignToDesign = false,
  });
  final Map<PlatformType, VideoLibrary> libraries;
  final Set<PlatformType> syncing, loggedIn;
  final ValueChanged<PlatformType> onSync;
  final void Function(Song, List<Song>) onPlay;
  final ValueChanged<Song> onMore;
  final ValueChanged<String> onNavigate;
  final VoidCallback onDownloads, onAccounts, onRetryLocal;
  final List<Song> localLikes;
  final bool localLoading;
  final String? localError;
  final Song? currentSong;
  final bool alignToDesign;
  @override
  State<IkLibraryWorkspace> createState() => _IkLibraryWorkspaceState();
}

class _IkLibraryWorkspaceState extends State<IkLibraryWorkspace> {
  String _source = 'all';
  @override
  Widget build(BuildContext context) {
    final merged = <String, Song>{
      for (final song in widget.localLikes) videoSongKey(song): song,
    };
    for (final platform in widget.loggedIn) {
      for (final song in widget.libraries[platform]?.songs ?? <Song>[]) {
        merged[videoSongKey(song)] = song;
      }
    }
    final songs = merged.values
        .where((song) => _source == 'all' || _source == song.platform.name)
        .toList();
    final loading = widget.localLoading || widget.syncing.isNotEmpty;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 22,
                  runSpacing: 14,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      IkWorkspaceStrings.library,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    OutlinedButton.icon(
                      onPressed: () => widget.onNavigate('/import-playlist'),
                      icon: const Icon(Icons.playlist_add_rounded, size: 18),
                      label: const Text(IkWorkspaceStrings.importPlaylist),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  IkWorkspaceStrings.libraryHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    if (widget.alignToDesign)
                      Semantics(
                        selected: true,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2,
                              ),
                            ),
                          ),
                          child: Text(
                            IkWorkspaceStrings.likes,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      )
                    else
                      TextButton(
                        onPressed: () {},
                        child: const Text(IkWorkspaceStrings.likes),
                      ),
                    TextButton(
                      onPressed: () => widget.onNavigate('/platform-playlists'),
                      child: const Text(IkStrings.playlists),
                    ),
                    TextButton(
                      onPressed: () => widget.onNavigate('/local-music'),
                      child: const Text(VideoStrings.localMusic),
                    ),
                    TextButton(
                      onPressed: widget.onDownloads,
                      child: const Text(VideoStrings.download),
                    ),
                    TextButton(
                      onPressed: () => widget.onNavigate('/smart-playlists'),
                      child: const Text(IkStrings.smart),
                    ),
                  ],
                ),
                const Divider(height: 24),
                Wrap(
                  spacing: 20,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      IkWorkspaceStrings.tracks(songs.length),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    IkSelect<String>(
                      alignToDesign: widget.alignToDesign,
                      label: IkWorkspaceStrings.source,
                      value: _source,
                      items: {
                        'all': IkWorkspaceStrings.allSources,
                        for (final platform in PlatformType.values)
                          platform.name: videoPlatformLabel(platform),
                      },
                      onChanged: (value) => setState(() => _source = value),
                    ),
                    TextButton.icon(
                      onPressed: widget.onAccounts,
                      icon: const Icon(Icons.person_outline_rounded, size: 18),
                      label: const Text(IkWorkspaceStrings.connect),
                    ),
                    for (final platform in widget.loggedIn)
                      TextButton(
                        onPressed: widget.syncing.contains(platform)
                            ? null
                            : () => widget.onSync(platform),
                        child: Text(
                          '${IkWorkspaceStrings.sync} · ${videoPlatformLabel(platform)}',
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                if (loading) const LinearProgressIndicator(),
                if (widget.localError != null)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.localError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: widget.onRetryLocal,
                        child: const Text(VideoStrings.retry),
                      ),
                    ],
                  ),
                for (final platform in widget.loggedIn)
                  if (widget.libraries[platform]?.error case final error?)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        '${videoPlatformLabel(platform)} · ${error.message}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                if (songs.isEmpty && !loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 34),
                    child: Text(IkStrings.emptyLikes),
                  ),
              ],
            ),
          ),
        ),
        if (widget.alignToDesign && songs.isNotEmpty)
          const SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            sliver: SliverToBoxAdapter(child: IkSongTableHeader()),
          ),
        SliverList.builder(
          itemCount: songs.length,
          itemBuilder: (context, index) {
            final song = songs[index];
            if (widget.alignToDesign) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: IkSongTableRow(
                  song: song,
                  index: index,
                  onPlay: () => widget.onPlay(song, songs),
                  onMore: () => widget.onMore(song),
                  playing:
                      widget.currentSong != null &&
                      videoSongKey(widget.currentSong!) == videoSongKey(song),
                ),
              );
            }
            final playing = widget.currentSong?.dedupeKey == song.dedupeKey;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: LayoutBuilder(
                builder: (context, size) => Material(
                  color: playing
                      ? Theme.of(context).colorScheme.primary
                            .withValues(alpha: .07)
                      : Colors.transparent,
                  child: InkWell(
                    onTap: () => widget.onPlay(song, songs),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: Theme.of(context).dividerColor
                                .withValues(alpha: .1),
                          ),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 30,
                            child: Text(
                              '${index + 1}'.padLeft(2, '0'),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          VideoCover(url: song.coverUrl, size: 40, radius: 7),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 5,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  song.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  song.artistNames,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          if (size.maxWidth >= 620) ...[
                            const SizedBox(width: 20),
                            Expanded(
                              flex: 3,
                              child: Text(
                                song.album?.name ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            SizedBox(
                              width: 80,
                              child: Text(
                                videoPlatformLabel(song.platform),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                          IconButton(
                            tooltip: VideoStrings.play,
                            onPressed: () => widget.onPlay(song, songs),
                            icon: Icon(
                              playing
                                  ? Icons.graphic_eq_rounded
                                  : Icons.play_arrow_outlined,
                              size: 20,
                            ),
                          ),
                          IconButton(
                            tooltip: IkStrings.more,
                            onPressed: () => widget.onMore(song),
                            icon: const Icon(Icons.more_horiz, size: 20),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
      ],
    );
  }
}

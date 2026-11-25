import 'package:flutter/material.dart';

import '../../features/library/presentation/pages/platform_playlists_page.dart';
import '../../features/local_music/presentation/pages/local_music_page.dart';
import '../../features/smart_playlists/presentation/pages/smart_playlists_page.dart';
import '../../l10n/ik_contextual_error_strings.dart';
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
    this.onMoreWithContext,
    required this.onNavigate,
    required this.onDownloads,
    required this.onAccounts,
    required this.localLikes,
    required this.localLoading,
    this.localError,
    required this.onRetryLocal,
    this.currentSong,
    this.alignToDesign = false,
    this.simplifySources = false,
    this.stableCategoryTabs = false,
    this.contextualErrors = false,
    this.expiredPlatform,
    this.downloadsBuilder,
  });
  final Map<PlatformType, VideoLibrary> libraries;
  final Set<PlatformType> syncing, loggedIn;
  final ValueChanged<PlatformType> onSync;
  final void Function(Song, List<Song>) onPlay;
  final ValueChanged<Song> onMore;
  final void Function(BuildContext, Song)? onMoreWithContext;
  final ValueChanged<String> onNavigate;
  final VoidCallback onDownloads, onAccounts, onRetryLocal;
  final List<Song> localLikes;
  final bool localLoading;
  final String? localError;
  final Song? currentSong;
  final bool alignToDesign;
  final bool simplifySources;
  final bool stableCategoryTabs;
  final bool contextualErrors;
  final PlatformType? expiredPlatform;
  final WidgetBuilder? downloadsBuilder;
  @override
  State<IkLibraryWorkspace> createState() => _IkLibraryWorkspaceState();
}

class _IkLibraryWorkspaceState extends State<IkLibraryWorkspace> {
  String _source = 'all';
  String _category = 'likes';
  final _visited = <String>{'likes'};
  static const _categories = {
    'likes': IkWorkspaceStrings.likes,
    'playlists': IkStrings.playlists,
    'local': VideoStrings.localMusic,
    'downloads': VideoStrings.download,
    'smart': IkStrings.smart,
  };

  Widget _stableCategory(BuildContext context, MapEntry<String, String> entry) {
    final selected = entry.key == _category;
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: selected ? null : true,
      child: Material(
        key: ValueKey('ik-library-category-${entry.key}'),
        color: Colors.transparent,
        child: InkWell(
          onTap: selected
              ? null
              : () {
                  if (entry.key == 'downloads' &&
                      widget.downloadsBuilder == null) {
                    widget.onDownloads();
                    return;
                  }
                  setState(() {
                    _category = entry.key;
                    _visited.add(entry.key);
                  });
                },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: selected ? colors.primary : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    entry.value,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                      color: selected
                          ? colors.primary
                          : colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.alignToDesign
      ? LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxWidth <
                MediaQuery.textScalerOf(context).scale(600);
            final categories = [
              for (final entry in _categories.entries)
                if (widget.stableCategoryTabs)
                  _stableCategory(context, entry)
                else
                  Semantics(
                    selected: entry.key == _category,
                    child: entry.key == _category
                        ? Container(
                            key: ValueKey('ik-library-category-${entry.key}'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                    width: 2,
                                  ),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  entry.value,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                  ),
                                ),
                              ),
                            ),
                          )
                        : TextButton(
                            key: ValueKey('ik-library-category-${entry.key}'),
                            onPressed: () {
                              if (entry.key == 'downloads' &&
                                  widget.downloadsBuilder == null) {
                                widget.onDownloads();
                                return;
                              }
                              setState(() {
                                _category = entry.key;
                                _visited.add(entry.key);
                              });
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: entry.key == _category
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.zero,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: entry.key == _category
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(entry.value, maxLines: 1),
                              ),
                            ),
                          ),
                  ),
            ];
            return Column(
              children: [
                Padding(
                  padding: compact
                      ? const EdgeInsets.fromLTRB(16, 12, 16, 0)
                      : const EdgeInsets.fromLTRB(24, 28, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (compact)
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                IkWorkspaceStrings.library,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            IconButton(
                              tooltip: IkWorkspaceStrings.importPlaylist,
                              onPressed: () =>
                                  widget.onNavigate('/import-playlist'),
                              icon: const Icon(Icons.playlist_add_rounded),
                            ),
                          ],
                        )
                      else
                        _heading(context),
                      SizedBox(height: compact ? 4 : 20),
                      if (compact)
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(children: categories),
                        )
                      else
                        Wrap(spacing: 10, runSpacing: 4, children: categories),
                      const Divider(height: 1),
                    ],
                  ),
                ),
                Expanded(
                  child: IndexedStack(
                    index: _categories.keys.toList().indexOf(_category),
                    children: [
                      for (final category in _categories.keys)
                        _visited.contains(category)
                            ? KeyedSubtree(
                                key: ValueKey('ik-library-content-$category'),
                                child: switch (category) {
                                  'playlists' =>
                                    widget.simplifySources
                                        ? const PlatformPlaylistsPage.compactEmbedded(
                                            jsonFormatLabel:
                                                IkStrings.playlistJson,
                                          )
                                        : const PlatformPlaylistsPage.embedded(
                                            jsonFormatLabel:
                                                IkStrings.playlistJson,
                                          ),
                                  'local' => const LocalMusicPage.embedded(),
                                  'downloads' => widget.downloadsBuilder!(
                                    context,
                                  ),
                                  'smart' => const SmartPlaylistsPage.embedded(
                                    safeDelete: true,
                                  ),
                                  _ => _likes(context, includeHeading: false),
                                },
                              )
                            : const SizedBox.shrink(),
                    ],
                  ),
                ),
              ],
            );
          },
        )
      : _likes(context);

  Widget _heading(BuildContext context) => Column(
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
    ],
  );

  Widget _likes(BuildContext context, {bool includeHeading = true}) {
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
          padding: EdgeInsets.fromLTRB(24, includeHeading ? 28 : 16, 24, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (includeHeading) ...[
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
                        onPressed: () =>
                            widget.onNavigate('/platform-playlists'),
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
                ],
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
                    if (widget.contextualErrors)
                      _syncIssue(context, platform, error)
                    else
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          '${videoPlatformLabel(platform)} · ${error.message}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                if (widget.contextualErrors)
                  if (widget.expiredPlatform case final platform?
                      when platform.isMusicService &&
                          !widget.loggedIn.contains(platform))
                    _issueNotice(
                      context,
                      key: ValueKey('ik-library-expired-${platform.name}'),
                      title: IkContextualErrorStrings.syncNeedsAccount(
                        videoPlatformLabel(platform),
                      ),
                      action: TextButton(
                        onPressed: widget.syncing.contains(platform)
                            ? null
                            : widget.onAccounts,
                        child: const Text(IkContextualErrorStrings.reconnect),
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
                  onMoreWithContext: widget.onMoreWithContext == null
                      ? null
                      : (buttonContext) =>
                            widget.onMoreWithContext!(buttonContext, song),
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

  Widget _syncIssue(
    BuildContext context,
    PlatformType platform,
    VideoFailure error,
  ) {
    final needsAccount =
        error.kind == VideoFailureKind.notLoggedIn ||
        error.kind == VideoFailureKind.sessionExpired;
    return _issueNotice(
      context,
      key: ValueKey('ik-library-error-${platform.name}'),
      title: IkContextualErrorStrings.syncFailed(videoPlatformLabel(platform)),
      reason: error.message,
      action: needsAccount || error.canRetry
          ? TextButton(
              onPressed: widget.syncing.contains(platform)
                  ? null
                  : needsAccount
                  ? widget.onAccounts
                  : () => widget.onSync(platform),
              child: Text(
                needsAccount
                    ? IkContextualErrorStrings.reconnect
                    : IkContextualErrorStrings.retrySync,
              ),
            )
          : null,
    );
  }

  Widget _issueNotice(
    BuildContext context, {
    required Key key,
    required String title,
    String? reason,
    Widget? action,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: key,
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.error,
            ),
          ),
          if (reason != null) ...[
            const SizedBox(height: 6),
            Text(
              reason,
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 4), action],
        ],
      ),
    );
  }
}

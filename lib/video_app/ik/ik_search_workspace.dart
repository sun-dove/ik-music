import 'package:flutter/material.dart';

import '../../l10n/ik_strings.dart';
import '../../l10n/ik_alignment_strings.dart';
import '../../l10n/ik_workspace_strings.dart';
import '../../l10n/video_strings.dart';
import '../../models/platform_type.dart';
import '../../models/song.dart';
import '../data/video_catalog.dart';
import '../ui/catalog_pages.dart';
import '../windows/windows_platform_icon.dart';
import 'ik_catalog_pages.dart';
import 'ik_controls.dart';
import 'ik_search.dart';
import 'ik_song_table.dart';

class IkSearchWorkspace extends StatefulWidget {
  const IkSearchWorkspace({
    super.key,
    required this.search,
    required this.onPlay,
    required this.onLike,
    required this.onMore,
    this.likedKeys = const {},
    this.currentSong,
    this.onAccount,
    this.alignToDesign = false,
    this.useSharedSearch = false,
  });
  final IkSearchController search;
  final void Function(Song, List<Song>) onPlay;
  final ValueChanged<Song> onLike, onMore;
  final Set<String> likedKeys;
  final Song? currentSong;
  final ValueChanged<PlatformType>? onAccount;
  final bool alignToDesign, useSharedSearch;
  @override
  State<IkSearchWorkspace> createState() => _IkSearchWorkspaceState();
}

class _IkSearchWorkspaceState extends State<IkSearchWorkspace> {
  final _text = TextEditingController();
  PlatformType? _filter;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.search,
    builder: (context, _) => widget.alignToDesign
        ? _aligned(context)
        : CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(20),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        VideoStrings.search,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _text,
                        textInputAction: TextInputAction.search,
                        onSubmitted: widget.search.submit,
                        decoration: InputDecoration(
                          hintText: IkStrings.searchHint,
                          prefixIcon: const Icon(Icons.search),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: VideoStrings.search,
                            onPressed: () => widget.search.submit(_text.text),
                            icon: const Icon(Icons.arrow_forward),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: IkSelect<String>(
                          label: IkWorkspaceStrings.source,
                          value: _filter?.name ?? 'all',
                          items: {
                            'all': IkWorkspaceStrings.allSources,
                            for (final platform in widget.search.platforms)
                              platform.name: videoPlatformLabel(platform),
                          },
                          onChanged: (value) => setState(
                            () => _filter = PlatformType.values
                                .where((platform) => platform.name == value)
                                .firstOrNull,
                          ),
                        ),
                      ),
                      if (widget.search.query.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 28),
                          child: Text(IkStrings.searchIntro),
                        ),
                    ],
                  ),
                ),
              ),
              for (final platform in widget.search.platforms)
                if (_filter == null || platform == _filter)
                  if (widget.search.groups[platform] case final group?) ...[
                    SliverToBoxAdapter(
                      child: ListTile(
                        leading: WindowsPlatformIcon(platform: platform),
                        title: Text(videoPlatformLabel(platform)),
                        subtitle: Text(
                          IkStrings.results(group.songs.length, group.total),
                        ),
                      ),
                    ),
                    SliverList.builder(
                      itemCount: group.songs.length,
                      itemBuilder: (context, index) {
                        final song = group.songs[index];
                        return IkSongTile(
                          song: song,
                          onTap: () => widget.onPlay(song, group.songs),
                          playing:
                              widget.currentSong != null &&
                              videoSongKey(widget.currentSong!) ==
                                  videoSongKey(song),
                          liked: widget.likedKeys.contains(videoSongKey(song)),
                          onLike: () => widget.onLike(song),
                          onMore: () => widget.onMore(song),
                        );
                      },
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                        child: Column(
                          children: [
                            if (group.loading) const LinearProgressIndicator(),
                            if (group.error case final error?) ...[
                              Text(
                                error.message,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                              if (error.canRetry)
                                TextButton(
                                  onPressed: () =>
                                      widget.search.retry(platform),
                                  child: const Text(VideoStrings.retry),
                                ),
                              if (widget.onAccount != null &&
                                  (error.kind == VideoFailureKind.notLoggedIn ||
                                      error.kind ==
                                          VideoFailureKind.sessionExpired))
                                TextButton(
                                  onPressed: () => widget.onAccount!(platform),
                                  child: Text(
                                    VideoStrings.loginPlatform(
                                      videoPlatformLabel(platform),
                                    ),
                                  ),
                                ),
                            ] else if (!group.loading && group.songs.isEmpty)
                              const Text(IkStrings.noResults),
                            if (!group.loading &&
                                group.hasMore &&
                                group.error == null)
                              TextButton(
                                onPressed: () =>
                                    widget.search.loadMore(platform),
                                child: const Text(VideoStrings.loadMore),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
            ],
          ),
  );

  Widget _aligned(BuildContext context) => CustomScrollView(
    slivers: [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        sliver: SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.search.query.isEmpty
                    ? VideoStrings.search
                    : IkAlignmentStrings.searchResults(widget.search.query),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              if (!widget.useSharedSearch) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _text,
                  textInputAction: TextInputAction.search,
                  onSubmitted: widget.search.submit,
                  decoration: InputDecoration(
                    hintText: IkStrings.searchHint,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      tooltip: VideoStrings.search,
                      onPressed: () => widget.search.submit(_text.text),
                      icon: const Icon(Icons.arrow_forward),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              IkSelect<String>(
                alignToDesign: true,
                label: IkWorkspaceStrings.source,
                value: _filter?.name ?? 'all',
                items: {
                  'all': IkWorkspaceStrings.allSources,
                  for (final p in widget.search.platforms)
                    p.name: videoPlatformLabel(p),
                },
                onChanged: (value) => setState(
                  () => _filter = PlatformType.values
                      .where((p) => p.name == value)
                      .firstOrNull,
                ),
              ),
              if (widget.search.query.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 28),
                  child: Text(IkStrings.searchIntro),
                ),
            ],
          ),
        ),
      ),
      for (final platform in widget.search.platforms)
        if (_filter == null || _filter == platform)
          if (widget.search.groups[platform] case final group?) ...[
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              sliver: SliverToBoxAdapter(
                child: Column(
                  children: [
                    Row(
                      children: [
                        WindowsPlatformIcon(platform: platform),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            videoPlatformLabel(platform),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Text(
                          IkStrings.results(group.songs.length, group.total),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    if (group.songs.isNotEmpty) const IkSongTableHeader(),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              sliver: SliverList.builder(
                itemCount: group.songs.length,
                itemBuilder: (context, index) {
                  final song = group.songs[index];
                  return IkSongTableRow(
                    song: song,
                    index: index,
                    onPlay: () => widget.onPlay(song, group.songs),
                    onMore: () => widget.onMore(song),
                    onLike: () => widget.onLike(song),
                    liked: widget.likedKeys.contains(videoSongKey(song)),
                    playing:
                        widget.currentSong != null &&
                        videoSongKey(widget.currentSong!) == videoSongKey(song),
                  );
                },
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
              sliver: SliverToBoxAdapter(
                child: Column(
                  children: [
                    if (group.loading) const LinearProgressIndicator(),
                    if (group.error case final error?) ...[
                      Text(
                        error.message,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      if (error.canRetry)
                        TextButton(
                          onPressed: () => widget.search.retry(platform),
                          child: const Text(VideoStrings.retry),
                        ),
                      if (widget.onAccount != null &&
                          (error.kind == VideoFailureKind.notLoggedIn ||
                              error.kind == VideoFailureKind.sessionExpired))
                        TextButton(
                          onPressed: () => widget.onAccount!(platform),
                          child: Text(
                            VideoStrings.loginPlatform(
                              videoPlatformLabel(platform),
                            ),
                          ),
                        ),
                    ] else if (!group.loading && group.songs.isEmpty)
                      const Text(IkStrings.noResults),
                    if (!group.loading && group.hasMore && group.error == null)
                      TextButton(
                        onPressed: () => widget.search.loadMore(platform),
                        child: const Text(VideoStrings.loadMore),
                      ),
                  ],
                ),
              ),
            ),
          ],
    ],
  );
}

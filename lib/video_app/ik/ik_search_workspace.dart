import 'package:flutter/material.dart';

import '../../features/discovery/presentation/providers/recommendations_provider.dart';
import '../../l10n/ik_discovery_revision_strings.dart';
import '../../l10n/ik_library_revision_strings.dart';
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
    this.onMoreWithContext,
    this.likedKeys = const {},
    this.currentSong,
    this.onAccount,
    this.alignToDesign = false,
    this.useSharedSearch = false,
    this.hotTerms = const [],
    this.hotLoading = false,
    this.hotError,
    this.onRetryHot,
    this.recommendations,
    this.loggedIn = const {},
    this.onBrowseRecommendations,
    this.onRetryRecommendation,
  });
  final IkSearchController search;
  final void Function(Song, List<Song>) onPlay;
  final ValueChanged<Song> onLike, onMore;
  final void Function(BuildContext, Song)? onMoreWithContext;
  final Set<String> likedKeys;
  final Song? currentSong;
  final ValueChanged<PlatformType>? onAccount;
  final bool alignToDesign, useSharedSearch;
  final List<String> hotTerms;
  final bool hotLoading;
  final String? hotError;
  final VoidCallback? onRetryHot, onBrowseRecommendations;
  final RecommendationsState? recommendations;
  final Set<PlatformType> loggedIn;
  final ValueChanged<PlatformType>? onRetryRecommendation;
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
              if (widget.search.query.isEmpty &&
                  widget.onRetryHot == null &&
                  widget.recommendations == null)
                const Padding(
                  padding: EdgeInsets.only(top: 28),
                  child: Text(IkStrings.searchIntro),
                ),
            ],
          ),
        ),
      ),
      if (widget.search.query.isEmpty) ..._discoverySlivers(context),
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
                    onMoreWithContext: widget.onMoreWithContext == null
                        ? null
                        : (buttonContext) =>
                              widget.onMoreWithContext!(buttonContext, song),
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

  List<Widget> _discoverySlivers(BuildContext context) {
    final recommendations = widget.recommendations;
    final colors = Theme.of(context).colorScheme;
    return [
      if (widget.onRetryHot != null ||
          widget.hotTerms.isNotEmpty ||
          widget.hotLoading ||
          widget.hotError != null)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  IkLibraryRevisionStrings.hotSearch,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  IkLibraryRevisionStrings.hotSearchSource,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (widget.hotLoading) const LinearProgressIndicator(),
                if (widget.hotError != null) ...[
                  Text(widget.hotError!, style: TextStyle(color: colors.error)),
                  if (widget.onRetryHot != null)
                    TextButton(
                      onPressed: widget.hotLoading ? null : widget.onRetryHot,
                      child: const Text(VideoStrings.retry),
                    ),
                ] else if (!widget.hotLoading && widget.hotTerms.isEmpty)
                  const Text(IkLibraryRevisionStrings.hotSearchEmpty),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final term in widget.hotTerms)
                      ActionChip(
                        label: Text(term),
                        onPressed: () => widget.search.submit(term),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      if (recommendations != null) ...[
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 20,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      IkLibraryRevisionStrings.recommendationSelection,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (widget.onBrowseRecommendations != null)
                      TextButton(
                        onPressed: widget.onBrowseRecommendations,
                        child: const Text(
                          IkLibraryRevisionStrings.browseRecommendations,
                        ),
                      ),
                  ],
                ),
                Text(
                  IkLibraryRevisionStrings.recommendationHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (recommendations.isLoading) const LinearProgressIndicator(),
              ],
            ),
          ),
        ),
        for (final platform in PlatformType.musicServices)
          if (_filter == null || _filter == platform) ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 6),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        WindowsPlatformIcon(platform: platform, size: 20),
                        Text(
                          videoPlatformLabel(platform),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(
                          IkDiscoveryRevisionStrings.sourceLabel(
                            recommendations.sourceForPlatform(platform),
                            platform: platform,
                            loggedIn: widget.loggedIn.contains(platform),
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    if (recommendations.errorsByPlatform[platform]
                        case final error?) ...[
                      Text(error, style: TextStyle(color: colors.error)),
                      if (widget.onRetryRecommendation != null)
                        TextButton(
                          onPressed: recommendations.isLoading
                              ? null
                              : () => widget.onRetryRecommendation!(platform),
                          child: const Text(VideoStrings.retry),
                        ),
                    ] else if (!recommendations.isLoading &&
                        recommendations.songsForPlatform(platform).isEmpty)
                      const Text(IkDiscoveryRevisionStrings.noRecommendations),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              sliver: SliverList.builder(
                itemCount: recommendations
                    .songsForPlatform(platform)
                    .length
                    .clamp(0, 4),
                itemBuilder: (context, index) {
                  final songs = recommendations.songsForPlatform(platform);
                  final song = songs[index];
                  return IkSongTableRow(
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
                  );
                },
              ),
            ),
          ],
        const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
      ],
    ];
  }
}

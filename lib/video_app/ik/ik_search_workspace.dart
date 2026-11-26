import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../features/discovery/presentation/providers/recommendations_provider.dart';
import '../../l10n/ik_discovery_revision_strings.dart';
import '../../l10n/ik_library_revision_strings.dart';
import '../../l10n/ik_page_revision_strings.dart';
import '../../l10n/ik_quick_workspace_strings.dart';
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
    this.compactDiscovery = false,
    this.fullRecommendations = false,
    this.recommendationsInDiscovery = false,
    this.platformResultTabs = false,
    this.useSharedSearch = false,
    this.dismissSourceMenuOnBack = false,
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
  final bool compactDiscovery;
  final bool fullRecommendations;
  final bool recommendationsInDiscovery;
  final bool platformResultTabs;
  final bool dismissSourceMenuOnBack;
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
  final _scroll = ScrollController(keepScrollOffset: false);
  final _scrollOffsets = <String, double>{};
  String? _scrollViewKey;
  double? _pendingScrollOffset;
  bool _initialResultsLoading = false;
  PlatformType? _filter;
  PlatformType? _resultPlatform;
  String? _resultQuery;
  bool _expandedHotTerms = false;
  PlatformType _recommendationPlatform = PlatformType.netease;
  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _restoreSearchScroll(String key) {
    final loading =
        widget.search.query.isNotEmpty &&
        widget.search.groups.values.any(
          (group) => group.loading && group.page == 0,
        );
    if (_scrollViewKey != key || (loading && !_initialResultsLoading)) {
      if (_scrollViewKey != null &&
          _pendingScrollOffset == null &&
          _scroll.hasClients) {
        _scrollOffsets[_scrollViewKey!] = _scroll.position.pixels;
      }
      _pendingScrollOffset = _scrollOffsets[key] ?? 0;
    }
    _scrollViewKey = key;
    _initialResultsLoading = loading;
    final offset = _pendingScrollOffset;
    if (loading || offset == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_scroll.hasClients ||
          _scrollViewKey != key ||
          _initialResultsLoading ||
          _pendingScrollOffset != offset) {
        return;
      }
      _pendingScrollOffset = null;
      _scroll.jumpTo(offset.clamp(0, _scroll.position.maxScrollExtent));
    });
  }

  List<PlatformType> get _resultPlatforms => [
    for (final platform in const [
      PlatformType.netease,
      PlatformType.qq,
      PlatformType.kugou,
      PlatformType.local,
    ])
      if (widget.search.platforms.contains(platform)) platform,
  ];

  PlatformType? get _selectedResultPlatform {
    final platforms = _resultPlatforms;
    if (platforms.contains(_resultPlatform)) return _resultPlatform;
    return platforms.contains(PlatformType.qq)
        ? PlatformType.qq
        : platforms.firstOrNull;
  }

  void _restorePlatformScroll(String key, PlatformType? platform) {
    final queryChanged = _resultQuery != widget.search.query;
    if (queryChanged) {
      _resultQuery = widget.search.query;
      _scrollOffsets.removeWhere(
        (savedKey, _) => savedKey.startsWith('ik-search-results-'),
      );
    }
    final group = widget.search.groups[platform];
    final loading = widget.search.query.isNotEmpty &&
        group != null && group.loading && group.page == 0;
    if (queryChanged || _scrollViewKey != key ||
        (loading && !_initialResultsLoading)) {
      if (!queryChanged && _scrollViewKey != null &&
          _pendingScrollOffset == null && _scroll.hasClients) {
        _scrollOffsets[_scrollViewKey!] = _scroll.position.pixels;
      }
      _pendingScrollOffset = _scrollOffsets[key] ?? 0;
    }
    _scrollViewKey = key;
    _initialResultsLoading = loading;
    final offset = _pendingScrollOffset;
    if (loading || offset == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || _scrollViewKey != key ||
          _initialResultsLoading || _pendingScrollOffset != offset) {
        return;
      }
      _pendingScrollOffset = null;
      _scroll.jumpTo(offset.clamp(0, _scroll.position.maxScrollExtent));
    });
  }

  Widget _platformTabs(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final platform in _resultPlatforms)
            Semantics(
              selected: platform == _selectedResultPlatform,
              button: true,
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: TextButton(
                  key: ValueKey('ik-search-platform-${platform.name}'),
                  onPressed: () => setState(() => _resultPlatform = platform),
                  style: TextButton.styleFrom(
                    foregroundColor: platform == _selectedResultPlatform
                        ? colors.primary : colors.onSurfaceVariant,
                    backgroundColor: platform == _selectedResultPlatform
                        ? colors.primary.withValues(alpha: .08)
                        : Colors.transparent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ExcludeSemantics(
                        child: WindowsPlatformIcon(platform: platform, size: 18),
                      ),
                      const SizedBox(width: 8),
                      Text(IkQuickWorkspaceStrings.platformTab(platform)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.search,
    builder: (context, _) => widget.alignToDesign || widget.platformResultTabs
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

  Widget _aligned(BuildContext context) {
    final preserveScroll =
        widget.fullRecommendations || widget.recommendationsInDiscovery ||
        widget.platformResultTabs;
    final selectedPlatform = _selectedResultPlatform;
    final key = widget.search.query.isEmpty
        ? widget.recommendationsInDiscovery
              ? 'ik-search-hot-terms'
              : 'ik-search-recommendations'
        : widget.platformResultTabs
        ? 'ik-search-results-${widget.search.query}-${selectedPlatform?.name}'
        : 'ik-search-results-${widget.search.query}';
    if (widget.platformResultTabs) {
      _restorePlatformScroll(key, selectedPlatform);
    } else if (preserveScroll) {
      _restoreSearchScroll(key);
    }
    final scrollView = CustomScrollView(
      key: preserveScroll ? ValueKey(key) : null,
      controller: preserveScroll ? _scroll : null,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.compactDiscovery)
                  _compactSearchHeader(context)
                else
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
                if (!widget.platformResultTabs && !widget.compactDiscovery &&
                    ((!widget.fullRecommendations &&
                            !widget.recommendationsInDiscovery) ||
                        widget.search.query.isNotEmpty)) ...[
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
                ],
                if (widget.platformResultTabs && widget.search.query.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _platformTabs(context),
                ],
                if (widget.search.query.isEmpty &&
                    widget.onRetryHot == null &&
                    (widget.recommendations == null || widget.platformResultTabs))
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
          if (widget.platformResultTabs
              ? widget.search.query.isNotEmpty && platform == selectedPlatform
              : _filter == null || _filter == platform)
            if (widget.search.groups[platform] case final group?) ...[
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    children: [
                      if (widget.platformResultTabs)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            IkStrings.results(group.songs.length, group.total),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        )
                      else Row(
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
                          videoSongKey(widget.currentSong!) ==
                              videoSongKey(song),
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
                      if (!group.loading &&
                          group.hasMore &&
                          group.error == null)
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
    if (!preserveScroll) return scrollView;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if ((notification is UserScrollNotification &&
                notification.direction != ScrollDirection.idle) ||
            (notification is ScrollStartNotification &&
                notification.dragDetails != null)) {
          // 分批返回时，用户的新浏览位置优先于尚待恢复的旧位置。
          _pendingScrollOffset = null;
        }
        return false;
      },
      child: scrollView,
    );
  }

  Widget _compactSearchHeader(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Row(
      children: [
        Expanded(
          child: Text(
            widget.search.query.isEmpty
                ? VideoStrings.search
                : IkAlignmentStrings.searchResults(widget.search.query),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ),
        if (!widget.platformResultTabs && ((!widget.fullRecommendations &&
                !widget.recommendationsInDiscovery) ||
            widget.search.query.isNotEmpty)) ...[
          const SizedBox(width: 12),
          SizedBox(
            width: constraints.maxWidth < 460 ? 140 : 180,
            child: IkSelect<String>(
              alignToDesign: true,
              dismissOnSystemBack: widget.dismissSourceMenuOnBack,
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
        ],
      ],
    ),
  );

  List<Widget> _discoverySlivers(BuildContext context) {
    final recommendations = widget.recommendationsInDiscovery || widget.platformResultTabs
        ? null
        : widget.recommendations;
    final colors = Theme.of(context).colorScheme;
    final globalError =
        (widget.compactDiscovery || widget.fullRecommendations) &&
            recommendations != null &&
            !recommendations.isLoading &&
            recommendations.totalCount == 0 &&
            recommendations.errorsByPlatform.isEmpty
        ? recommendations.error
        : null;
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
                if (widget.compactDiscovery)
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        IkLibraryRevisionStrings.hotSearch,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        IkLibraryRevisionStrings.hotSearchSource,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (widget.hotTerms.length > 10) ...[
                        Text(
                          _expandedHotTerms
                              ? IkLibraryRevisionStrings.hotSearchTotal(
                                  widget.hotTerms.length,
                                )
                              : IkLibraryRevisionStrings.hotSearchPreview(
                                  widget.hotTerms.length,
                                ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        TextButton(
                          onPressed: () => setState(
                            () => _expandedHotTerms = !_expandedHotTerms,
                          ),
                          child: Text(
                            _expandedHotTerms
                                ? IkLibraryRevisionStrings.collapseHotSearch
                                : IkLibraryRevisionStrings.expandHotSearch,
                          ),
                        ),
                      ],
                    ],
                  )
                else ...[
                  Text(
                    IkLibraryRevisionStrings.hotSearch,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    IkLibraryRevisionStrings.hotSearchSource,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
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
                    for (final term
                        in widget.compactDiscovery && !_expandedHotTerms
                            ? widget.hotTerms.take(10)
                            : widget.hotTerms)
                      ActionChip(
                        side: widget.compactDiscovery ? BorderSide.none : null,
                        backgroundColor: widget.compactDiscovery
                            ? colors.surfaceContainerHighest.withValues(
                                alpha: .35,
                              )
                            : null,
                        label: widget.compactDiscovery
                            ? Text(
                                term,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              )
                            : Text(term),
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
                      widget.fullRecommendations
                          ? IkPageRevisionStrings.platformRecommendations
                          : IkLibraryRevisionStrings.recommendationSelection,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (widget.compactDiscovery || widget.fullRecommendations)
                      IkSelect<PlatformType>(
                        alignToDesign: true,
                        label: IkLibraryRevisionStrings.recommendationPlatform,
                        value: _recommendationPlatform,
                        items: {
                          for (final platform in PlatformType.musicServices)
                            platform: videoPlatformLabel(platform),
                        },
                        onChanged: (platform) =>
                            setState(() => _recommendationPlatform = platform),
                      ),
                    if (!widget.fullRecommendations &&
                        widget.onBrowseRecommendations != null)
                      TextButton(
                        onPressed: widget.onBrowseRecommendations,
                        child: const Text(
                          IkLibraryRevisionStrings.browseRecommendations,
                        ),
                      ),
                  ],
                ),
                if (!widget.fullRecommendations)
                  Text(
                    widget.compactDiscovery
                        ? IkLibraryRevisionStrings.compactRecommendationHint
                        : IkLibraryRevisionStrings.recommendationHint,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (recommendations.isLoading) const LinearProgressIndicator(),
              ],
            ),
          ),
        ),
        for (final platform in PlatformType.musicServices)
          if (widget.compactDiscovery || widget.fullRecommendations
              ? _recommendationPlatform == platform
              : _filter == null || _filter == platform) ...[
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
                        if (!widget.fullRecommendations)
                          WindowsPlatformIcon(platform: platform, size: 20),
                        if (!widget.fullRecommendations)
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
                        if (widget.fullRecommendations) ...[
                          Text(
                            IkPageRevisionStrings.recommendationCount(
                              recommendations.songsForPlatform(platform).length,
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          TextButton.icon(
                            onPressed:
                                recommendations
                                    .songsForPlatform(platform)
                                    .isEmpty
                                ? null
                                : () {
                                    final songs = recommendations
                                        .songsForPlatform(platform);
                                    widget.onPlay(songs.first, songs);
                                  },
                            icon: const Icon(
                              Icons.play_arrow_rounded,
                              size: 18,
                            ),
                            label: const Text(IkPageRevisionStrings.playAll),
                          ),
                        ],
                      ],
                    ),
                    if (widget.compactDiscovery || widget.fullRecommendations)
                      if (IkDiscoveryRevisionStrings.sourceNote(
                            recommendations.sourceForPlatform(platform),
                            platform: platform,
                          )
                          case final note?)
                        Text(
                          note,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    if (globalError != null) ...[
                      Text(globalError, style: TextStyle(color: colors.error)),
                      if (!widget.loggedIn.contains(platform) &&
                          widget.onAccount != null)
                        TextButton(
                          onPressed: () => widget.onAccount!(platform),
                          child: Text(
                            VideoStrings.loginPlatform(
                              videoPlatformLabel(platform),
                            ),
                          ),
                        ),
                    ] else if (recommendations.errorsByPlatform[platform]
                        case final error?) ...[
                      Text(
                        (widget.compactDiscovery ||
                                    widget.fullRecommendations) &&
                                error == 'timeout'
                            ? IkLibraryRevisionStrings.recommendationTimeout
                            : error,
                        style: TextStyle(color: colors.error),
                      ),
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
            if (widget.fullRecommendations &&
                recommendations.songsForPlatform(platform).isNotEmpty)
              const SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverToBoxAdapter(child: IkSongTableHeader()),
              ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              sliver: SliverList.builder(
                itemCount: widget.fullRecommendations
                    ? recommendations.songsForPlatform(platform).length
                    : recommendations
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

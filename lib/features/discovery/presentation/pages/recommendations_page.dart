import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/platform_accent.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/share/song_actions.dart';
import '../../../../core/widgets/app_scrollbar.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../l10n/ik_discovery_revision_strings.dart';
import '../../../../models/song.dart';
import '../../../../models/platform_type.dart';
import '../../../../video_app/ik/ik_song_table.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../download/presentation/widgets/download_button.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../providers/recommendations_provider.dart';

class RecommendationsPage extends ConsumerStatefulWidget {
  const RecommendationsPage({super.key, this.alignToDesign = false});

  final bool alignToDesign;

  @override
  ConsumerState<RecommendationsPage> createState() =>
      _RecommendationsPageState();
}

class _RecommendationsPageState extends ConsumerState<RecommendationsPage>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  int _lastTabCount = 0;
  PlatformType _selectedPlatform = PlatformType.netease;

  @override
  void initState() {
    super.initState();
    ref.listenManual(authProvider.select((s) => s.loggedUsers), (
      previous,
      next,
    ) {
      if (!mounted || previous == next) return;
      ref.read(recommendationsProvider.notifier).loadRecommendations();
    });
    final state = ref.read(recommendationsProvider);
    if (state.songsByPlatform.isEmpty && !state.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(recommendationsProvider.notifier).loadRecommendations();
      });
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  void _syncTabController(int length) {
    if (length <= 0) {
      _tabController?.dispose();
      _tabController = null;
      _lastTabCount = 0;
      return;
    }
    if (_lastTabCount != length) {
      final previousIndex = _tabController?.index ?? 0;
      _tabController?.dispose();
      _tabController = TabController(length: length, vsync: this);
      // Preserve index if still valid
      if (previousIndex < length) {
        _tabController!.index = previousIndex;
      }
      _lastTabCount = length;
    }
  }

  Color _platformColor(PlatformType platform) =>
      PlatformAccent.colorOf(context, platform);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(recommendationsProvider);
    if (widget.alignToDesign) return _buildAligned(context, state);
    final platforms = state.songsByPlatform.keys.toList();
    _syncTabController(platforms.length);

    return Scaffold(
      appBar: AppBar(
        title: const Text('每日推荐'),
        actions: [
          // `tooltip` is what an icon-only button needs, and it is also the
          // mechanism this page's accessibility case asserts.
          //
          // **Two semantic channels — do not confuse them.** `IconButton
          // (tooltip:)` publishes through `Tooltip`, which builds
          // `Semantics(tooltip: message)`: the text lands in the semantics
          // **tooltip** field, NOT in **label**. That mismatch is why the first
          // version of the audit test failed: it asserted
          // `find.bySemanticsLabel('刷新')` (label channel) and found 0 while the
          // button was perfectly fine. The test now reads `getSemantics(...)`
          // and asserts the field the tooltip actually writes to.
          //
          // Deliberately NOT wrapped in `Semantics(label: '刷新')`: a
          // non-container `Semantics` does not create its own node, it merges
          // into the nearest *enclosing* node — which for an `AppBar` action is
          // an app-bar-level ancestor, so the label would end up describing the
          // wrong node. If the label channel is wanted here later, the right
          // mechanism is the icon's own `Icon(semanticLabel: ...)`, which merges
          // upward into the button; that needs its own verified round.
          IconButton(
            tooltip: '刷新',
            // **Controlled experiment (W3-B).** `Icon(semanticLabel:)` is
            // supposed to put the text into the **label** channel — what a screen
            // reader announces as the button's content description — unlike
            // `tooltip`, which lands in the **tooltip** channel. Whether it
            // survives `IconButton`'s own semantics (i.e. actually reaches the
            // button's node) is what the audit test measures. If that assertion
            // fails, this `semanticLabel` is inert and gets removed again rather
            // than left in as a guess.
            icon: const Icon(Icons.refresh, semanticLabel: '刷新'),
            onPressed: () => ref
                .read(recommendationsProvider.notifier)
                .loadRecommendations(),
          ),
        ],
        bottom: _tabController != null
            ? TabBar(
                controller: _tabController!,
                tabs: platforms.map((p) => Tab(text: p.displayName)).toList(),
              )
            : null,
      ),
      body: state.isLoading
          ? const AsyncStateView.loading()
          : platforms.isEmpty
          ? state.error != null
                ? AsyncStateView.error(
                    title: '加载失败',
                    message: state.error!,
                    onRetry: () => ref
                        .read(recommendationsProvider.notifier)
                        .loadRecommendations(),
                  )
                : const AsyncStateView.empty(
                    title: '请先登录平台账号',
                    icon: Icons.wb_sunny_outlined,
                  )
          : TabBarView(
              controller: _tabController!,
              children: platforms.map((platform) {
                final songs = state.songsForPlatform(platform);
                return _PlatformRecommendations(
                  platform: platform,
                  songs: songs,
                  error: state.errorsByPlatform[platform],
                  platformColor: _platformColor(platform),
                  onRetry: () => ref
                      .read(recommendationsProvider.notifier)
                      .loadRecommendations(),
                );
              }).toList(),
            ),
    );
  }

  Widget _buildAligned(BuildContext context, RecommendationsState state) {
    final platform = _selectedPlatform;
    final songs = state.songsForPlatform(platform);
    final source = state.sourceForPlatform(platform);
    final error = state.errorsByPlatform[platform];
    final loggedIn = ref.watch(
      authProvider.select((state) => state.isLoggedIn(platform)),
    );
    final label = IkDiscoveryRevisionStrings.sourceLabel(
      source,
      platform: platform,
      loggedIn: loggedIn,
    );
    final note = IkDiscoveryRevisionStrings.sourceNote(
      source,
      platform: platform,
    );
    final currentSong = ref.watch(
      playerProvider.select((state) => state.currentSong),
    );
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text(IkDiscoveryRevisionStrings.recommendations),
        actions: [
          IconButton(
            tooltip: IkDiscoveryRevisionStrings.refresh,
            icon: const Icon(Icons.refresh),
            onPressed: () => ref
                .read(recommendationsProvider.notifier)
                .loadRecommendations(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
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
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref
                  .read(recommendationsProvider.notifier)
                  .loadRecommendations(),
              child: AppScrollbar(
                key: ValueKey('ik-recommendations-${platform.name}'),
                builder: (controller) => CustomScrollView(
                  controller: controller,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.primary.withValues(
                                      alpha: .09,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    label,
                                    style: TextStyle(color: colors.primary),
                                  ),
                                ),
                                if (!loggedIn)
                                  TextButton.icon(
                                    onPressed: () =>
                                        context.push('/login/${platform.name}'),
                                    icon: const Icon(Icons.login, size: 18),
                                    label: const Text(
                                      IkDiscoveryRevisionStrings.login,
                                    ),
                                  ),
                              ],
                            ),
                            if (note != null &&
                                note.isNotEmpty &&
                                note != error) ...[
                              const SizedBox(height: 8),
                              Text(
                                note,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (songs.isEmpty)
                      if (error != null)
                        SliverAsyncStateView(
                          child: AsyncStateView.error(
                            title:
                                IkDiscoveryRevisionStrings.recommendationsFailed(
                                  platform,
                                ),
                            message: error,
                            onRetry: () => ref
                                .read(recommendationsProvider.notifier)
                                .loadRecommendations(),
                          ),
                        )
                      else if (state.isLoading)
                        const SliverAsyncStateView(
                          hasScrollBody: true,
                          child: AsyncStateView.loading(skeleton: true),
                        )
                      else
                        const SliverAsyncStateView(
                          child: AsyncStateView.empty(
                            title: IkDiscoveryRevisionStrings.noRecommendations,
                            message: IkDiscoveryRevisionStrings.refreshHint,
                          ),
                        )
                    else ...[
                      if (state.isLoading)
                        const SliverToBoxAdapter(
                          child: LinearProgressIndicator(),
                        ),
                      if (error != null)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                            child: Card(
                              color: colors.errorContainer,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      error,
                                      style: TextStyle(
                                        color: colors.onErrorContainer,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    ElevatedButton(
                                      onPressed: () => ref
                                          .read(
                                            recommendationsProvider.notifier,
                                          )
                                          .loadRecommendations(),
                                      child: const Text(
                                        IkDiscoveryRevisionStrings.retry,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
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

class _PlatformRecommendations extends StatelessWidget {
  final PlatformType platform;
  final List<Song> songs;
  final String? error;
  final Color platformColor;

  /// Retries the recommendation load. The provider has no per-platform entry
  /// point, so a failed platform is reloaded together with the others.
  final VoidCallback onRetry;

  const _PlatformRecommendations({
    required this.platform,
    required this.songs,
    required this.error,
    required this.platformColor,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (songs.isNotEmpty) {
      return _SongList(songs: songs, platformColor: platformColor);
    }

    // A failed platform used to render as an error with no way out. Rule 3 of
    // `AsyncStateView` is exactly this case: an error state must offer a retry.
    if (error != null && error!.isNotEmpty) {
      return AsyncStateView.error(
        title: '${platform.displayName}每日推荐加载失败',
        message: error,
        onRetry: onRetry,
      );
    }

    return AsyncStateView.empty(
      title: '${platform.displayName}暂无每日推荐',
      icon: Icons.music_note_outlined,
    );
  }
}

class _SongList extends ConsumerWidget {
  final List<Song> songs;
  final Color platformColor;

  const _SongList({required this.songs, required this.platformColor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppScrollbar(
      builder: (controller) => ListView.builder(
        controller: controller,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: songs.length,
        itemBuilder: (context, index) {
          final song = songs[index];
          return ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: platformColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: platformColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            title: Text(
              song.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15),
            ),
            subtitle: Text(
              song.artistNames,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
                fontSize: 13,
              ),
            ),
            trailing: DownloadButton(song: song, size: 22),
            onTap: () {
              ref
                  .read(playerProvider.notifier)
                  .playPlaylist(songs, startIndex: index);
            },
          );
        },
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/discovery/presentation/providers/recommendations_provider.dart';
import '../../features/player/presentation/providers/player_provider.dart';
import '../../l10n/ik_alignment_shell_strings.dart';
import '../../l10n/ik_discovery_revision_strings.dart';
import '../../l10n/ik_personal_daily_strings.dart';
import '../../l10n/ik_strings.dart';
import '../../l10n/ik_workspace_strings.dart';
import '../../l10n/video_strings.dart';
import '../../models/recommendation_source.dart';
import '../../models/song.dart';
import '../ui/catalog_pages.dart';
import '../ui/video_shell.dart';
import 'ik_catalog_pages.dart';

/// 仅由独立入口覆盖 provider，旧产品继续使用原刷新行为。
class IkRecommendationsNotifier extends RecommendationsNotifier {
  @override
  Future<void> loadRecommendations() => loadLatestRecommendations();
}

class IkHomePage extends ConsumerStatefulWidget {
  const IkHomePage({
    super.key,
    required this.onNavigate,
    required this.onPlayer,
    required this.onPlay,
    required this.onMore,
    this.onMoreWithContext,
    this.workspace = false,
    this.alignToDesign = false,
    this.recommendationsInDiscovery = false,
  });
  final ValueChanged<String> onNavigate;
  final VoidCallback onPlayer;
  final void Function(Song, List<Song>) onPlay;
  final ValueChanged<Song> onMore;
  final void Function(BuildContext, Song)? onMoreWithContext;
  final bool workspace;
  final bool alignToDesign;
  final bool recommendationsInDiscovery;
  @override
  ConsumerState<IkHomePage> createState() => _IkHomePageState();
}

class _IkHomePageState extends ConsumerState<IkHomePage> {
  @override
  void initState() {
    super.initState();
    ref.listenManual(authProvider.select((state) => state.loggedUsers), (_, _) {
      Future.microtask(() {
        if (mounted) {
          ref.read(recommendationsProvider.notifier).loadRecommendations();
        }
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(recommendationsProvider.notifier).loadRecommendations();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final aligned = widget.workspace && widget.alignToDesign;
    final publicRecommendations = aligned && widget.recommendationsInDiscovery;
    final player = ref.watch(playerProvider);
    final auth = ref.watch(authProvider);
    final recommendations = ref.watch(recommendationsProvider);
    final allPlatforms = {
      ...recommendations.songsByPlatform.keys,
      ...recommendations.errorsByPlatform.keys,
    };
    final platforms = publicRecommendations
        ? allPlatforms.where((platform) {
            final source = recommendations.sourceForPlatform(platform);
            return source?.platform == platform &&
                (source?.kind == RecommendationKind.fallbackToplist ||
                    source?.kind == RecommendationKind.fallbackHomepage);
          }).toSet()
        : allPlatforms;
    return RefreshIndicator(
      onRefresh: ref.read(recommendationsProvider.notifier).loadRecommendations,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: aligned ? 24 : 20,
                vertical: 20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (aligned)
                    _DiscoveryHeading(onNavigate: widget.onNavigate)
                  else ...[
                    Text(
                      widget.workspace
                          ? IkWorkspaceStrings.discoveryTitle
                          : IkStrings.home,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(IkStrings.discoveryHint),
                  ],
                  SizedBox(height: aligned ? 16 : 20),
                  if (widget.workspace) ...[
                    if (aligned)
                      _DiscoveryHero(
                        onExplore: () => widget.onNavigate('/new-songs'),
                      )
                    else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(26),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: LinearGradient(
                            colors: [
                              Theme.of(context).colorScheme.primary
                                  .withValues(alpha: .12),
                              Theme.of(context).colorScheme.primary
                                  .withValues(alpha: .22),
                            ],
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              IkWorkspaceStrings.discoveryFeature,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: 10),
                            const Text(IkWorkspaceStrings.discoveryFeatureHint),
                            const SizedBox(height: 18),
                            FilledButton.icon(
                              onPressed: () => widget.onNavigate('/new-songs'),
                              icon: const Icon(
                                Icons.play_arrow_rounded,
                                size: 18,
                              ),
                              label: const Text(IkWorkspaceStrings.explore),
                            ),
                          ],
                        ),
                      ),
                    SizedBox(height: aligned ? 12 : 20),
                  ],
                  if (player.currentSong case final song?)
                    if (aligned)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: _ContinueCard(
                          song: song,
                          playing: player.isPlaying,
                          onOpen: widget.onPlayer,
                          onToggle: ref
                              .read(playerProvider.notifier)
                              .togglePlay,
                        ),
                      )
                    else
                      Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: VideoCover(url: song.coverUrl, size: 56),
                          title: const Text(IkStrings.continuePlaying),
                          subtitle: Text('${song.name} · ${song.artistNames}'),
                          trailing: IconButton(
                            tooltip: player.isPlaying
                                ? VideoStrings.pause
                                : VideoStrings.play,
                            icon: Icon(
                              player.isPlaying ? Icons.pause : Icons.play_arrow,
                            ),
                            onPressed: ref
                                .read(playerProvider.notifier)
                                .togglePlay,
                          ),
                          onTap: widget.onPlayer,
                        ),
                      ),
                  if (!aligned)
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final entry in [
                          (
                            IkStrings.recommendations,
                            '/recommendations',
                            Icons.favorite_outline,
                          ),
                          (
                            IkStrings.toplists,
                            '/toplists',
                            Icons.leaderboard_outlined,
                          ),
                          (
                            IkStrings.newSongs,
                            '/new-songs',
                            Icons.new_releases_outlined,
                          ),
                        ])
                          FilledButton.tonalIcon(
                            onPressed: () => widget.onNavigate(entry.$2),
                            icon: Icon(entry.$3),
                            label: Text(entry.$1),
                          ),
                      ],
                    ),
                  SizedBox(height: aligned ? 0 : 24),
                  if (!publicRecommendations ||
                      platforms.isNotEmpty ||
                      recommendations.isLoading)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            aligned
                                ? IkDiscoveryRevisionStrings.recommendations
                                : IkStrings.recommendations,
                            style: aligned
                                ? const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                  )
                                : Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        if (aligned && !publicRecommendations)
                          TextButton(
                            onPressed: () =>
                                widget.onNavigate('/recommendations'),
                            child: const Text(IkStrings.browse),
                          ),
                        IconButton(
                          tooltip: VideoStrings.retry,
                          onPressed: recommendations.isLoading
                              ? null
                              : ref
                                    .read(recommendationsProvider.notifier)
                                    .loadRecommendations,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                  if (recommendations.isLoading)
                    const LinearProgressIndicator(),
                  if (!publicRecommendations &&
                      recommendations.error != null &&
                      platforms.isEmpty)
                    Text(recommendations.error!),
                  if (!publicRecommendations &&
                      !recommendations.isLoading &&
                      platforms.isEmpty) ...[
                    if (recommendations.error == null)
                      const Text(IkStrings.noRecommendations),
                    if (!aligned)
                      TextButton(
                        onPressed: () => widget.onNavigate('/recommendations'),
                        child: const Text(IkStrings.browse),
                      ),
                  ],
                ],
              ),
            ),
          ),
          for (final platform in platforms) ...[
            SliverToBoxAdapter(
              child: ListTile(
                contentPadding: aligned
                    ? const EdgeInsets.symmetric(horizontal: 24)
                    : null,
                title: Text(
                  videoPlatformLabel(platform),
                  style: aligned
                      ? const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        )
                      : null,
                ),
                subtitleTextStyle: aligned
                    ? Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        height: 1.6,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      )
                    : null,
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      aligned
                          ? IkDiscoveryRevisionStrings.sourceLabel(
                              recommendations.sourceForPlatform(platform),
                              platform: platform,
                              loggedIn: auth.isLoggedIn(platform),
                            )
                          : recommendations
                                    .sourceForPlatform(platform)
                                    ?.label ??
                                IkStrings.recommendations,
                    ),
                    if (widget.workspace &&
                        !publicRecommendations &&
                        recommendations.songsForPlatform(platform).length > 6)
                      Text(IkWorkspaceStrings.previewTracks(6)),
                    if ((aligned
                            ? IkDiscoveryRevisionStrings.sourceNote(
                                recommendations.sourceForPlatform(platform),
                                platform: platform,
                              )
                            : recommendations.sourceForPlatform(platform)?.note)
                        case final String note)
                      Text(note),
                  ],
                ),
              ),
            ),
            if (recommendations.errorsByPlatform[platform] case final error?)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: aligned ? 24 : 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        error,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: recommendations.isLoading
                                ? null
                                : () {
                                    final notifier = ref.read(
                                      recommendationsProvider.notifier,
                                    );
                                    unawaited(
                                      notifier is IkRecommendationsNotifier
                                          ? notifier.retryLatestPlatform(
                                              platform,
                                            )
                                          : notifier.loadRecommendations(),
                                    );
                                  },
                            child: const Text(VideoStrings.retry),
                          ),
                          if (!auth.isLoggedIn(platform))
                            TextButton(
                              onPressed: () =>
                                  widget.onNavigate('/login/${platform.name}'),
                              child: Text(
                                VideoStrings.loginPlatform(
                                  videoPlatformLabel(platform),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (!recommendations.isLoading &&
                !recommendations.errorsByPlatform.containsKey(platform) &&
                recommendations.songsForPlatform(platform).isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: aligned ? 24 : 20),
                  child: const Text(IkStrings.noRecommendations),
                ),
              ),
            if (aligned &&
                recommendations.songsForPlatform(platform).isNotEmpty)
              _DiscoverySongGrid(
                songs: recommendations.songsForPlatform(platform),
                fullList: publicRecommendations,
                onPlay: widget.onPlay,
                onMore: widget.onMore,
                onMoreWithContext: widget.onMoreWithContext,
              )
            else if (!aligned)
              SliverList.builder(
                itemCount: recommendations
                    .songsForPlatform(platform)
                    .length
                    .clamp(0, 6),
                itemBuilder: (context, index) {
                  final songs = recommendations.songsForPlatform(platform);
                  return IkSongTile(
                    song: songs[index],
                    onTap: () => widget.onPlay(songs[index], songs),
                    onMore: () => widget.onMore(songs[index]),
                  );
                },
              ),
            if (!publicRecommendations &&
                recommendations.songsForPlatform(platform).isNotEmpty)
              SliverToBoxAdapter(
                child: TextButton(
                  onPressed: () => widget.onNavigate('/recommendations'),
                  child: Text(
                    '${IkStrings.browse} · ${IkStrings.results(recommendations.songsForPlatform(platform).length, null)}',
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _DiscoveryHeading extends StatelessWidget {
  const _DiscoveryHeading({required this.onNavigate});
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          IkAlignmentShellStrings.discoveryEyebrow,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.primary,
          ),
        ),
        const SizedBox(height: 7),
        const Text(
          IkWorkspaceStrings.discoveryTitle,
          style: TextStyle(
            fontSize: 29,
            height: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
    final actions = Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        FilledButton.tonalIcon(
          key: const Key('ik-personal-daily-entry'),
          onPressed: () => onNavigate('/daily'),
          icon: const Icon(Icons.wb_sunny_outlined, size: 17),
          label: const Text(IkPersonalDailyStrings.title),
        ),
        OutlinedButton.icon(
          onPressed: () => onNavigate('/new-songs'),
          icon: const Icon(Icons.new_releases_outlined, size: 17),
          label: const Text(IkStrings.newSongs),
        ),
        OutlinedButton.icon(
          onPressed: () => onNavigate('/toplists'),
          icon: const Icon(Icons.leaderboard_outlined, size: 17),
          label: const Text(IkStrings.toplists),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        return constraints.maxWidth >= 650 * scale
            ? Row(
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 20),
                  actions,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [title, const SizedBox(height: 12), actions],
              );
      },
    );
  }
}

class _DiscoveryHero extends StatelessWidget {
  const _DiscoveryHero({required this.onExplore});
  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final roomy = constraints.maxWidth >= 650;
        final explore = FilledButton.icon(
          onPressed: onExplore,
          icon: const Icon(Icons.play_arrow_rounded, size: 18),
          label: const Text(IkWorkspaceStrings.explore),
        );
        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(roomy ? 22 : 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            gradient: LinearGradient(
              colors: [
                colors.primary.withValues(alpha: .09),
                colors.primary.withValues(alpha: .21),
              ],
            ),
          ),
          child: !roomy
              ? Row(
                  children: [
                    Expanded(
                      child: Text(
                        IkAlignmentShellStrings.compactHeroTitle,
                        style: TextStyle(
                          fontSize: 20,
                          height: 1.3,
                          fontWeight: FontWeight.w500,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    explore,
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            IkAlignmentShellStrings.heroTitle,
                            style: TextStyle(
                              fontSize: 26,
                              height: 1.3,
                              fontWeight: FontWeight.w500,
                              color: colors.onSurface,
                            ),
                          ),
                          const SizedBox(height: 9),
                          Text(
                            IkWorkspaceStrings.discoveryFeatureHint,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.65,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          explore,
                        ],
                      ),
                    ),
                    if (roomy) ...[
                      const SizedBox(width: 28),
                      ExcludeSemantics(
                        child: Icon(
                          Icons.graphic_eq_rounded,
                          size: 112,
                          color: colors.primary.withValues(alpha: .28),
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.song,
    required this.playing,
    required this.onOpen,
    required this.onToggle,
  });
  final Song song;
  final bool playing;
  final VoidCallback onOpen;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(11),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              VideoCover(url: song.coverUrl, size: 48, radius: 8),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      IkStrings.continuePlaying,
                      style: TextStyle(fontSize: 12, color: colors.primary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      song.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      song.artistNames,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: playing ? VideoStrings.pause : VideoStrings.play,
                onPressed: onToggle,
                icon: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiscoverySongGrid extends StatelessWidget {
  const _DiscoverySongGrid({
    required this.songs,
    required this.onPlay,
    required this.onMore,
    this.onMoreWithContext,
    this.fullList = false,
  });
  final List<Song> songs;
  final void Function(Song, List<Song>) onPlay;
  final ValueChanged<Song> onMore;
  final void Function(BuildContext, Song)? onMoreWithContext;
  final bool fullList;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          const gap = 20.0;
          final columns =
              ((constraints.crossAxisExtent + gap) / (164 * scale + gap))
                  .floor()
                  .clamp(1, 4);
          final width =
              (constraints.crossAxisExtent - gap * (columns - 1)) / columns;
          final coverHeight = width / 1.15;
          return SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: gap,
              mainAxisSpacing: 20,
              mainAxisExtent: coverHeight + 66 * scale + 22,
            ),
            itemCount: fullList ? songs.length : songs.length.clamp(0, 6),
            itemBuilder: (context, index) {
              final song = songs[index];
              final identity = '${song.platform.name}-$index';
              final colors = Theme.of(context).colorScheme;
              return Material(
                key: ValueKey('ik-discovery-song-$identity'),
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(11),
                child: InkWell(
                  borderRadius: BorderRadius.circular(11),
                  onTap: () => onPlay(song, songs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        key: ValueKey('ik-discovery-cover-$identity'),
                        width: width,
                        height: coverHeight,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(11),
                          child: FittedBox(
                            fit: BoxFit.cover,
                            child: VideoCover(
                              url: song.coverUrl,
                              size: width,
                              radius: 0,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  song.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    height: 1.4,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  song.artistNames,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.5,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Builder(
                            builder: (buttonContext) => IconButton(
                              key: ValueKey('ik-discovery-more-$identity'),
                              tooltip: IkStrings.more,
                              onPressed: () => onMoreWithContext == null
                                  ? onMore(song)
                                  : onMoreWithContext!(buttonContext, song),
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 40,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 8,
                              ),
                              icon: const Icon(
                                Icons.more_horiz_rounded,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

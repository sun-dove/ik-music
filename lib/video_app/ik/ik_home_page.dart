import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/discovery/presentation/providers/recommendations_provider.dart';
import '../../features/player/presentation/providers/player_provider.dart';
import '../../l10n/ik_strings.dart';
import '../../l10n/video_strings.dart';
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
  });
  final ValueChanged<String> onNavigate;
  final VoidCallback onPlayer;
  final void Function(Song, List<Song>) onPlay;
  final ValueChanged<Song> onMore;
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
    final player = ref.watch(playerProvider);
    final auth = ref.watch(authProvider);
    final recommendations = ref.watch(recommendationsProvider);
    final platforms = {
      ...recommendations.songsByPlatform.keys,
      ...recommendations.errorsByPlatform.keys,
    };
    return RefreshIndicator(
      onRefresh: ref.read(recommendationsProvider.notifier).loadRecommendations,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    IkStrings.home,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(IkStrings.discoveryHint),
                  const SizedBox(height: 20),
                  if (player.currentSong case final song?)
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
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          IkStrings.recommendations,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
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
                  if (recommendations.error != null && platforms.isEmpty)
                    Text(recommendations.error!),
                  if (!recommendations.isLoading && platforms.isEmpty) ...[
                    if (recommendations.error == null)
                      const Text(IkStrings.noRecommendations),
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
                title: Text(videoPlatformLabel(platform)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recommendations.sourceForPlatform(platform)?.label ??
                          IkStrings.recommendations,
                    ),
                    if (recommendations.sourceForPlatform(platform)?.note
                        case final String note)
                      Text(note),
                  ],
                ),
              ),
            ),
            if (recommendations.errorsByPlatform[platform] case final error?)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
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
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Text(IkStrings.noRecommendations),
                ),
              ),
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
            if (recommendations.songsForPlatform(platform).isNotEmpty)
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

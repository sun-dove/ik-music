import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/share/song_actions.dart';
import '../../core/widgets/app_scrollbar.dart';
import '../../features/library/presentation/providers/likes_provider.dart';
import '../../features/player/presentation/providers/player_provider.dart';
import '../../l10n/ik_personal_daily_strings.dart';
import '../../models/personal_daily_result.dart';
import '../../models/platform_type.dart';
import '../../models/song.dart';
import '../data/personal_daily_provider.dart';
import 'ik_like_action.dart';
import 'ik_song_table.dart';

class IkPersonalDailyPage extends ConsumerStatefulWidget {
  const IkPersonalDailyPage({
    super.key,
    this.initialPlatform = PlatformType.netease,
  });

  final PlatformType initialPlatform;

  @override
  ConsumerState<IkPersonalDailyPage> createState() =>
      _IkPersonalDailyPageState();
}

class _IkPersonalDailyPageState extends ConsumerState<IkPersonalDailyPage> {
  late PlatformType _selected = widget.initialPlatform;
  String? _verificationIssue;

  @override
  void didUpdateWidget(covariant IkPersonalDailyPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPlatform != widget.initialPlatform) {
      _selected = widget.initialPlatform;
      _verificationIssue = null;
    }
  }

  Future<void> _verify() async {
    final platform = _selected;
    final url = switch (platform) {
      PlatformType.netease => 'https://music.163.com/',
      PlatformType.qq => 'https://y.qq.com/',
      PlatformType.kugou => 'https://www.kugou.com/',
      PlatformType.local => null,
    };
    if (url == null) return;
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!mounted || _selected != platform) return;
    setState(() {
      _verificationIssue = opened
          ? null
          : IkPersonalDailyStrings.verificationOpenFailed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final platform = _selected;
    final state = ref.watch(personalDailyProvider(platform));
    final currentSong = ref.watch(
      playerProvider.select((state) => state.currentSong),
    );
    final likedKeys = ref.watch(
      likesProvider.select(
        (state) => state.songs.map((s) => '${s.platform.name}:${s.id}').toSet(),
      ),
    );
    final likeAction = ref.watch(ikLikeActionProvider);
    return IkPersonalDailyWorkspace(
      platform: platform,
      state: state,
      currentSong: currentSong,
      likedKeys: likedKeys,
      likeBusy: likeAction.busy,
      actionIssue: _verificationIssue ?? likeAction.issue,
      onPlatform: (next) => setState(() {
        _selected = next;
        _verificationIssue = null;
      }),
      onRetry: () =>
          unawaited(ref.read(personalDailyProvider(platform).notifier).load()),
      onAccount: () => context.push('/login/${platform.name}'),
      onVerification: () => unawaited(_verify()),
      onPlay: (song, songs) => unawaited(
        ref
            .read(playerProvider.notifier)
            .playPlaylist(
              songs,
              startIndex: songs.indexWhere(
                (s) => s.id == song.id && s.platform == song.platform,
              ),
            ),
      ),
      onLike: (song) =>
          unawaited(ref.read(ikLikeActionProvider.notifier).toggle(song)),
      onMore: (buttonContext, song) => unawaited(
        showSongActionsMenu(
          buttonContext,
          ref,
          song: song,
          isLiked: likedKeys.contains('${song.platform.name}:${song.id}'),
        ),
      ),
    );
  }
}

/// 独立个人日推页，沿用工作区歌曲行和锚定菜单。
class IkPersonalDailyWorkspace extends StatelessWidget {
  const IkPersonalDailyWorkspace({
    super.key,
    required this.platform,
    required this.state,
    required this.onPlatform,
    required this.onRetry,
    required this.onAccount,
    required this.onVerification,
    required this.onPlay,
    required this.onLike,
    required this.onMore,
    this.currentSong,
    this.likedKeys = const {},
    this.likeBusy = false,
    this.actionIssue,
  });

  final PlatformType platform;
  final PersonalDailyState state;
  final ValueChanged<PlatformType> onPlatform;
  final VoidCallback onRetry, onAccount, onVerification;
  final void Function(Song, List<Song>) onPlay;
  final ValueChanged<Song> onLike;
  final void Function(BuildContext, Song) onMore;
  final Song? currentSong;
  final Set<String> likedKeys;
  final bool likeBusy;
  final String? actionIssue;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final result = state.result?.platform == platform ? state.result : null;
    final songs =
        !state.isLoading && result?.status == PersonalDailyStatus.success
        ? result!.songs
        : const <Song>[];
    final canRefresh =
        !state.isLoading &&
        (result == null ||
            result.retryable ||
            result.status == PersonalDailyStatus.success ||
            result.status == PersonalDailyStatus.empty ||
            result.status == PersonalDailyStatus.sessionChanged);
    return Scaffold(
      appBar: AppBar(
        title: const Text(IkPersonalDailyStrings.title),
        actions: [
          IconButton(
            tooltip: IkPersonalDailyStrings.refresh,
            onPressed: canRefresh ? onRetry : null,
            icon: const Icon(Icons.refresh_rounded),
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
                runSpacing: 6,
                children: [
                  for (final source in PlatformType.musicServices)
                    ChoiceChip(
                      key: ValueKey('ik-daily-platform-${source.name}'),
                      label: Text(IkPersonalDailyStrings.platformLabel(source)),
                      selected: platform == source,
                      onSelected: (selected) {
                        if (selected) onPlatform(source);
                      },
                    ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: AppScrollbar(
              key: ValueKey('ik-daily-scroll-${platform.name}'),
              builder: (controller) => CustomScrollView(
                controller: controller,
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: colors.outlineVariant),
                          gradient: LinearGradient(
                            colors: [
                              colors.primary.withValues(alpha: .07),
                              colors.surface,
                            ],
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              IkPersonalDailyStrings.heading,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            const Text(IkPersonalDailyStrings.hint),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 14,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                FilledButton.icon(
                                  key: const Key('ik-daily-play-all'),
                                  onPressed: songs.isEmpty
                                      ? null
                                      : () => onPlay(songs.first, songs),
                                  icon: const Icon(Icons.play_arrow_rounded),
                                  label: const Text(
                                    IkPersonalDailyStrings.playAll,
                                  ),
                                ),
                                if (!state.isLoading &&
                                    (songs.isNotEmpty ||
                                        result?.status ==
                                            PersonalDailyStatus.empty))
                                  Text(
                                    IkPersonalDailyStrings.count(songs.length),
                                  ),
                              ],
                            ),
                            if (!state.isLoading &&
                                (songs.isNotEmpty ||
                                    result?.status ==
                                        PersonalDailyStatus.empty)) ...[
                              const SizedBox(height: 12),
                              if (result!.sourceDate case final sourceDate?)
                                Text(
                                  IkPersonalDailyStrings.sourceDate(sourceDate),
                                ),
                              Text(
                                IkPersonalDailyStrings.acquired(
                                  result.fetchedAt,
                                ),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              if (result.validCount > songs.length)
                                Text(
                                  IkPersonalDailyStrings.fullCount(
                                    result.validCount,
                                    songs.length,
                                  ),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                            if (actionIssue case final issue?) ...[
                              const SizedBox(height: 12),
                              Text(
                                issue,
                                style: TextStyle(color: colors.error),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (state.isLoading)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: LinearProgressIndicator(
                          key: Key('ik-daily-progress'),
                        ),
                      ),
                    )
                  else if (songs.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: _DailyStatusCard(
                          platform: platform,
                          result: result,
                          onAccount: onAccount,
                          onRetry: onRetry,
                          onVerification: onVerification,
                        ),
                      ),
                    )
                  else ...[
                    const SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverToBoxAdapter(child: IkSongTableHeader()),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList.builder(
                        itemCount: songs.length,
                        itemBuilder: (context, index) {
                          final song = songs[index];
                          return IkSongTableRow(
                            key: ValueKey('ik-daily-song-${song.id}'),
                            song: song,
                            index: index,
                            playing:
                                currentSong?.id == song.id &&
                                currentSong?.platform == song.platform,
                            liked: likedKeys.contains(
                              '${song.platform.name}:${song.id}',
                            ),
                            onPlay: () => onPlay(song, songs),
                            onLike: () {
                              if (!likeBusy) onLike(song);
                            },
                            onMore: () => onMore(context, song),
                            onMoreWithContext: (buttonContext) =>
                                onMore(buttonContext, song),
                          );
                        },
                      ),
                    ),
                  ],
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyStatusCard extends StatelessWidget {
  const _DailyStatusCard({
    required this.platform,
    required this.result,
    required this.onAccount,
    required this.onRetry,
    required this.onVerification,
  });

  final PlatformType platform;
  final PersonalDailyResult? result;
  final VoidCallback onAccount, onRetry, onVerification;

  @override
  Widget build(BuildContext context) {
    final action = IkPersonalDailyStrings.actionLabel(result);
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            IkPersonalDailyStrings.stateTitle(result),
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(IkPersonalDailyStrings.stateHint(platform, result)),
          if (action != null) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton(
                  key: const Key('ik-daily-state-action'),
                  onPressed: switch (result?.status) {
                    PersonalDailyStatus.signedOut ||
                    PersonalDailyStatus.identityIncomplete ||
                    PersonalDailyStatus.sessionExpired => onAccount,
                    PersonalDailyStatus.verificationRequired => onVerification,
                    _ => onRetry,
                  },
                  child: Text(action),
                ),
                if (result?.status == PersonalDailyStatus.verificationRequired)
                  OutlinedButton(
                    key: const Key('ik-daily-verification-retry'),
                    onPressed: onRetry,
                    child: const Text(IkPersonalDailyStrings.verificationRetry),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

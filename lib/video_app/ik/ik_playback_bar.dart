import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/floating_lyrics/presentation/providers/floating_lyrics_provider.dart';
import '../../features/library/presentation/providers/likes_provider.dart';
import '../../features/player/presentation/providers/player_provider.dart';
import '../../l10n/ik_contextual_error_strings.dart';
import '../../l10n/ik_playback_notice_strings.dart';
import '../../l10n/ik_strings.dart';
import '../../l10n/ik_runtime_strings.dart';
import '../../l10n/ik_workspace_strings.dart';
import '../../l10n/video_strings.dart';
import '../ui/video_shell.dart';
import '../multi_source/multi_source_player.dart';
import 'ik_floating_lyrics.dart';
import 'ik_lyrics_action.dart';
import 'ik_like_action.dart';
import 'ik_playback_lyrics.dart';
import 'ik_playback_notice.dart';
import 'ik_queue_sheet.dart';
import 'ik_user_gain.dart';
import 'ik_runtime.dart';

Future<void> showIkQueue(BuildContext context) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: IkStrings.close,
  barrierColor: Colors.black.withValues(alpha: .12),
  transitionDuration: const Duration(milliseconds: 160),
  pageBuilder: (context, _, _) => Align(
    alignment: Alignment.centerRight,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 360,
        height: MediaQuery.sizeOf(context).height - 120,
        child: Material(
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: IkStrings.close,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ),
              const Expanded(child: IkQueuePanel()),
            ],
          ),
        ),
      ),
    ),
  ),
);

class IkPlaybackBar extends ConsumerWidget {
  const IkPlaybackBar({
    super.key,
    required this.onOpen,
    required this.onAudio,
    this.inlineLyrics = false,
    this.balancedLayout = false,
  })
    : _stableSeekSemantics = false,
      contextualErrors = false;
  const IkPlaybackBar.aligned({
    super.key,
    required this.onOpen,
    required this.onAudio,
    this.contextualErrors = false,
    this.inlineLyrics = false,
    this.balancedLayout = false,
  }) : _stableSeekSemantics = true;
  final VoidCallback? onOpen;
  final VoidCallback onAudio;
  final bool _stableSeekSemantics;
  final bool contextualErrors;
  final bool inlineLyrics;
  final bool balancedLayout;
  Widget _seekSemantics(Slider slider) =>
      _stableSeekSemantics ? Semantics(container: true, child: slider) : slider;
  String _time(Duration value) =>
      '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    final notifier = ref.read(playerProvider.notifier);
    final song = player.currentSong;
    final lyrics = ref.watch(floatingLyricsProvider).enabled;
    final busy = ref.watch(ikLyricsActionProvider);
    final failed = ref.watch(ikFloatingFailureProvider);
    final lyricsCapability = ref.watch(ikLyricsCapabilityProvider);
    final lyricsIssue = ref.watch(ikLyricsIssueProvider);
    final likes = ref.watch(likesProvider);
    final likeAction = ref.watch(ikLikeActionProvider);
    final gain = ref.watch(ikUserGainProvider);
    final source = balancedLayout && contextualErrors
        ? ref.watch(sourcePlaybackViewProvider)
        : null;
    final showCompactFailure = source != null &&
        (player.error?.isNotEmpty ?? false) &&
        !player.isPlaying &&
        !player.isTransitioning &&
        !source.busy;
    final reset = player.error == IkContextualErrorStrings.playerResetReason;
    final canContinue = !reset &&
        source?.canContinue == true &&
        notifier is MultiSourceVideoPlayerNotifier;
    final compactNotice = !showCompactFailure
        ? null
        : IkPlaybackNotice(
            key: ValueKey(
              'ik-notice-${song?.platform.name}-${song?.id}-${player.error}',
            ),
            title: reset
                ? IkContextualErrorStrings.playbackRecoveryIncomplete
                : canContinue
                ? IkPlaybackNoticeStrings.pending
                : IkPlaybackNoticeStrings.failed,
            reason: player.error!,
            details: source!.details,
            actionLabel: canContinue
                ? IkPlaybackNoticeStrings.continueTrying
                : reset
                ? IkContextualErrorStrings.replay
                : IkRuntimeStrings.retry,
            onAction: canContinue
                ? () => (notifier as MultiSourceVideoPlayerNotifier)
                    .continueSources()
                : song == null
                ? null
                : () => notifier.playSong(song),
          );
    final liked =
        song != null &&
        likes.songs.any(
          (entry) => entry.id == song.id && entry.platform == song.platform,
        );
    final scheme = Theme.of(context).colorScheme;
    final songInformation = InkWell(
            onTap: song == null ? null : onOpen,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  VideoCover(url: song?.coverUrl, size: 44, radius: 8),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          song?.name ?? IkWorkspaceStrings.noTrack,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (song != null)
                          Text(
                            song.artistNames,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
    final likeButton = song == null
        ? null
        : IconButton(
            tooltip: liked ? VideoStrings.unlike : VideoStrings.like,
            onPressed: likeAction.busy
                ? null
                : () => ref.read(ikLikeActionProvider.notifier).toggle(song),
            icon: Icon(
              liked ? Icons.favorite : Icons.favorite_border,
              size: 19,
              color: liked ? scheme.primary : null,
            ),
          );
    final title = Row(
      children: [
        Expanded(child: songInformation),
        if (likeButton != null) likeButton,
      ],
    );
    Widget wideTitle() => !inlineLyrics || song == null
        ? title
        : LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
              // 大字或紧凑宽度时保留原歌曲信息，不挤占播放控制。
              if (constraints.maxWidth < 400 * scale) return title;
              return Row(
                children: [
                  SizedBox(
                    width: (constraints.maxWidth * .3)
                        .clamp(180.0, 208.0).toDouble(),
                    child: songInformation,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: IkPlaybackLyrics(
                      key: ValueKey('ik-bar-lyrics-${song.platform.name}-${song.id}'),
                      position: player.position,
                      isPlaying: player.isPlaying,
                      isTransitioning: player.isTransitioning,
                      onOpen: onOpen,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (likeButton != null) likeButton,
                ],
              );
            },
          );
    final transportButtons = <Widget>[
            IconButton(
              tooltip: VideoStrings.shuffle,
              onPressed: notifier.toggleShuffle,
              color: player.isShuffle ? scheme.primary : null,
              icon: const Icon(Icons.shuffle_rounded, size: 18),
            ),
            IconButton(
              tooltip: VideoStrings.previousSong,
              onPressed: song == null ? null : notifier.skipToPrevious,
              icon: const Icon(Icons.skip_previous_rounded),
            ),
            IconButton.filled(
              tooltip: player.isPlaying
                  ? VideoStrings.pause
                  : VideoStrings.play,
              onPressed: song == null || player.isTransitioning
                  ? null
                  : notifier.togglePlay,
              icon: player.isTransitioning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      player.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
            ),
            IconButton(
              tooltip: VideoStrings.nextSong,
              onPressed: song == null ? null : notifier.skipToNext,
              icon: const Icon(Icons.skip_next_rounded),
            ),
            IconButton(
              tooltip: VideoStrings.repeatAll,
              onPressed: notifier.cycleRepeatMode,
              icon: Icon(
                player.repeatMode == RepeatMode.one
                    ? Icons.repeat_one_rounded
                    : Icons.repeat_rounded,
                size: 18,
              ),
              color: player.repeatMode == RepeatMode.off
                  ? null
                  : scheme.primary,
            ),
          ];
    final transport = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: transportButtons,
    );
    final progress = Row(
          children: [
            Text(_time(player.position), style: const TextStyle(fontSize: 12)),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 4,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 10,
                  ),
                ),
                child: _seekSemantics(
                  Slider(
                    key: const ValueKey('ik-bar-seek'),
                    value: player.position.inMilliseconds.toDouble().clamp(
                      0,
                      player.duration.inMilliseconds.toDouble().clamp(
                        1,
                        double.infinity,
                      ),
                    ),
                    max: player.duration.inMilliseconds.toDouble().clamp(
                      1,
                      double.infinity,
                    ),
                    onChanged:
                        song == null ||
                            player.isTransitioning ||
                            player.duration <= Duration.zero
                        ? null
                        : (value) => notifier.seek(
                            Duration(milliseconds: value.round()),
                          ),
                  ),
                ),
              ),
            ),
            Text(_time(player.duration), style: const TextStyle(fontSize: 12)),
          ],
        );
    final controls = Column(
      mainAxisSize: MainAxisSize.min,
      children: [transport, progress],
    );
    Widget volumeControl({double width = 104}) => SizedBox(
      width: width,
      child: Row(
        children: [
          IconButton(
            tooltip:
                '${IkWorkspaceStrings.volume} ${(gain.gain * 100).round()}%',
            onPressed: () => ref.read(ikUserGainProvider.notifier).toggleMute(),
            icon: Icon(
              gain.gain == 0
                  ? Icons.volume_off_outlined
                  : Icons.volume_up_outlined,
              size: 20,
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
              ),
              child: Slider(
                key: const ValueKey('ik-bar-volume'),
                value: gain.gain,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                semanticFormatterCallback: (value) =>
                    '${(value * 100).round()}%',
                onChanged: (value) =>
                    ref.read(ikUserGainProvider.notifier).setGain(value),
              ),
            ),
          ),
        ],
      ),
    );
    final volume = volumeControl();
    final toolButtons = <Widget>[
        Tooltip(
          message: !lyricsCapability.supported
              ? lyricsCapability.message
              : lyricsIssue ??
                    (failed
                        ? IkRuntimeStrings.floatingFailed
                        : IkStrings.floating),
          child: TextButton(
            key: const ValueKey('ik-bar-lyrics'),
            onPressed: busy || !lyricsCapability.supported
                ? null
                : () => ref
                      .read(ikLyricsActionProvider.notifier)
                      .setEnabled(!lyrics),
            style: TextButton.styleFrom(
              minimumSize: const Size(44, 44),
              foregroundColor: failed
                  ? scheme.error
                  : lyrics
                  ? scheme.primary
                  : scheme.onSurfaceVariant,
            ),
            child: const Text(IkWorkspaceStrings.lyricsShort),
          ),
        ),
        IconButton(
          tooltip: IkWorkspaceStrings.audio,
          onPressed: onAudio,
          icon: const Icon(Icons.tune_rounded, size: 21),
        ),
        IconButton(
          key: const ValueKey('ik-bar-queue'),
          tooltip: IkStrings.nextUp,
          onPressed: () => balancedLayout
              ? showIkQueueRefined(context)
              : showIkQueue(context),
          icon: const Icon(Icons.queue_music_rounded, size: 23),
        ),
      ];
    final tools = Row(
      mainAxisSize: MainAxisSize.min,
      children: toolButtons,
    );
    final toolTextSize = MediaQuery.textScalerOf(context).scale(14);
    final toolButtonWidth = (toolTextSize + 32).clamp(48.0, 100.0).toDouble();
    final toolButtonHeight = (toolTextSize * 1.5 + 20).clamp(48.0, 100.0).toDouble();
    final roomyToolsWidth = 144 + toolButtons.length * toolButtonWidth +
        toolButtons.length * 12;
    Widget roomyTools() {
      return Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 4,
        children: [
          volumeControl(width: 144),
          for (final button in toolButtons)
            SizedBox(width: toolButtonWidth, height: toolButtonHeight, child: button),
        ],
      );
    }
    Widget leftSongAndLyrics({Widget? playbackNotice}) {
      final currentSong = song;
      return LayoutBuilder(
        builder: (context, size) {
          final textScaler = MediaQuery.textScalerOf(context);
          final scale = textScaler.scale(13) / 13;
          double measure(String text, TextStyle style) {
            var effectiveStyle = DefaultTextStyle.of(context).style.merge(style);
            if (MediaQuery.boldTextOf(context)) {
              effectiveStyle = effectiveStyle.copyWith(fontWeight: FontWeight.bold);
            }
            final painter = TextPainter(
              text: TextSpan(text: text, style: effectiveStyle),
              textDirection: Directionality.of(context),
              textScaler: textScaler,
              locale: Localizations.maybeLocaleOf(context),
              maxLines: 1,
            )..layout();
            final width = painter.width;
            painter.dispose();
            return width;
          }
          final nameWidth = measure(
            currentSong?.name ?? IkWorkspaceStrings.noTrack,
            const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          );
          final artistWidth = currentSong == null
              ? 0.0
              : measure(currentSong.artistNames, const TextStyle(fontSize: 12));
          final textWidth = nameWidth > artistWidth ? nameWidth : artistWidth;
          final heartWidth = likeButton == null ? 0.0 : 40.0;
          final heartGap = likeButton == null ? 0.0 : 6.0;
          final naturalSongWidth = 64 + textWidth.ceilToDouble();
          final maximumSongWidth = (size.maxWidth - heartWidth - heartGap)
              .clamp(64.0, 64 + 148 * scale).toDouble();
          final songWidth = naturalSongWidth < maximumSongWidth
              ? naturalSongWidth : maximumSongWidth;
          final songGroup = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: songWidth, child: songInformation),
              if (likeButton != null) ...[
                SizedBox(width: heartGap),
                SizedBox(width: heartWidth, height: 40, child: likeButton),
              ],
            ],
          );
          final Widget? supplement = playbackNotice ??
              (inlineLyrics && currentSong != null
                  ? IkPlaybackLyrics(
                      key: ValueKey('ik-bar-lyrics-${currentSong.platform.name}-${currentSong.id}'),
                      position: player.position,
                      isPlaying: player.isPlaying,
                      isTransitioning: player.isTransitioning,
                      compact: true,
                      onOpen: onOpen,
                    )
                  : null);
          if (supplement == null) {
            return Align(alignment: Alignment.centerLeft, child: songGroup);
          }
          final supplementLimit = 260 * scale.clamp(1.0, 1.35);
          final availableSupplement = size.maxWidth - songWidth - heartWidth - heartGap - 12;
          final supplementMinimum = (playbackNotice == null ? 120 : 160) * scale;
          if (availableSupplement >= supplementMinimum) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                songGroup,
                const SizedBox(width: 12),
                SizedBox(
                  width: availableSupplement < supplementLimit
                      ? availableSupplement : supplementLimit.toDouble(),
                  child: supplement,
                ),
              ],
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              songGroup,
              const SizedBox(height: 4),
              SizedBox(
                width: size.maxWidth < supplementLimit
                    ? size.maxWidth : supplementLimit.toDouble(),
                child: supplement,
              ),
            ],
          );
        },
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(
            top: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: .55),
            ),
          ),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: constraints.maxWidth < 360 ? 12 : 20,
          vertical: 10,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (gain.error != null)
              Text(
                gain.error!,
                style: TextStyle(fontSize: 12, color: scheme.error),
              ),
            if (likeAction.issue != null)
              Text(
                likeAction.issue!,
                style: TextStyle(fontSize: 12, color: scheme.error),
              ),
            if (contextualErrors && !balancedLayout &&
                (player.error?.isNotEmpty ?? false))
              _errorNotice(context, player, notifier)
            else if (!contextualErrors && player.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  player.error!,
                  style: TextStyle(fontSize: 12, color: scheme.error),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            LayoutBuilder(
              builder: (context, size) {
                final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                if (balancedLayout) {
                  final sideMinimum = roomyToolsWidth + 24;
                  final centerWidth = (size.maxWidth - 48 - sideMinimum * 2)
                      .clamp(0.0, 680.0).toDouble();
                  if (centerWidth >= 360) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: leftSongAndLyrics(playbackNotice: compactNotice)),
                        const SizedBox(width: 24),
                        SizedBox(
                          key: const ValueKey('ik-bar-centered-controls'),
                          width: centerWidth,
                          child: controls,
                        ),
                        const SizedBox(width: 24),
                        Expanded(child: roomyTools()),
                      ],
                    );
                  }
                  final sideBySide = size.maxWidth >=
                      roomyToolsWidth + 20 + 280 * scale;
                  final responsiveControls = size.maxWidth >= 240
                      ? controls
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: transportButtons,
                            ),
                            progress,
                          ],
                        );
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (sideBySide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(child: leftSongAndLyrics(playbackNotice: compactNotice)),
                            const SizedBox(width: 20),
                            SizedBox(width: roomyToolsWidth, child: roomyTools()),
                          ],
                        )
                      else ...[
                        leftSongAndLyrics(playbackNotice: compactNotice),
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerRight,
                          child: roomyTools(),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.center,
                        child: ConstrainedBox(
                          key: const ValueKey('ik-bar-centered-controls'),
                          constraints: const BoxConstraints(maxWidth: 680),
                          child: SizedBox(width: double.infinity, child: responsiveControls),
                        ),
                      ),
                    ],
                  );
                }
                return size.maxWidth >= 850
                  ? Row(
                      children: [
                        Expanded(flex: 10, child: balancedLayout ? title : wideTitle()),
                        const SizedBox(width: 24),
                        Expanded(flex: 12, child: controls),
                        const SizedBox(width: 24),
                        volume,
                        tools,
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(child: title),
                            if (size.maxWidth >= 470) tools,
                          ],
                        ),
                        controls,
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [volume, if (size.maxWidth < 470) tools],
                        ),
                      ],
                    );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorNotice(
    BuildContext context,
    PlayerState player,
    PlayerNotifier notifier,
    {bool canContinue = false}
  ) {
    final colors = Theme.of(context).colorScheme;
    final reset = player.error == IkContextualErrorStrings.playerResetReason;
    final song = player.currentSong;
    return Container(
      key: const ValueKey('ik-playback-error'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  reset
                      ? IkContextualErrorStrings.playbackRecoveryIncomplete
                      : IkContextualErrorStrings.playbackNotice,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.error,
                  ),
                ),
              ),
              if (reset && song != null) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: player.isTransitioning
                      ? null
                      : () => notifier.playSong(song),
                  child: const Text(IkContextualErrorStrings.replay),
                ),
              ],
              if (canContinue && notifier is MultiSourceVideoPlayerNotifier)
                TextButton(
                  onPressed: player.isTransitioning ? null : notifier.continueSources,
                  child: const Text('继续尝试'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 96),
            child: SingleChildScrollView(
              key: const ValueKey('ik-playback-error-reason-scroll'),
              primary: false,
              child: Text(
                player.error!,
                key: const ValueKey('ik-playback-error-reason'),
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

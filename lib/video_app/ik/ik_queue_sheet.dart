import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/share/song_actions.dart';
import '../../features/library/presentation/providers/likes_provider.dart';
import '../../features/player/presentation/providers/player_provider.dart';
import '../../l10n/ik_strings.dart';
import '../../l10n/ik_workspace_strings.dart';
import '../../models/platform_type.dart';
import '../ui/video_shell.dart';

Future<void> showIkQueueRefined(
  BuildContext context,
) => showGeneralDialog<void>(
  context: context,
  useRootNavigator: true,
  barrierDismissible: true,
  barrierLabel: IkStrings.close,
  barrierColor: Colors.black.withValues(alpha: .06),
  transitionDuration: const Duration(milliseconds: 180),
  transitionBuilder: (context, animation, _, child) => FadeTransition(
    opacity: animation,
    child: SlideTransition(
      position: Tween(
        begin: const Offset(.04, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  ),
  pageBuilder: (context, _, _) => SafeArea(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final bottom = constraints.maxHeight > 500 ? 104.0 : 12.0;
        final width = math.min(420.0, math.max(0.0, constraints.maxWidth - 32));
        final height = math.min(
          720.0,
          math.max(0.0, constraints.maxHeight - bottom - 16),
        );
        final colors = Theme.of(context).colorScheme;
        return Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, bottom),
            child: SizedBox(
              width: width,
              height: height,
              child: Material(
                color: colors.surface,
                surfaceTintColor: Colors.transparent,
                elevation: 12,
                shadowColor: Colors.black.withValues(alpha: .16),
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: colors.outlineVariant.withValues(alpha: .4),
                  ),
                ),
                child: const _QueueContent(),
              ),
            ),
          ),
        );
      },
    ),
  ),
);

class _QueueContent extends ConsumerStatefulWidget {
  const _QueueContent();

  @override
  ConsumerState<_QueueContent> createState() => _QueueContentState();
}

class _QueueContentState extends ConsumerState<_QueueContent> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playerProvider);
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  IkStrings.nextUp,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                IkWorkspaceStrings.tracks(player.playlist.length),
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
              const SizedBox(width: 10),
              IconButton(
                tooltip: IkStrings.close,
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: colors.outlineVariant.withValues(alpha: .4)),
        Expanded(
          child: player.playlist.isEmpty
              ? const Center(child: Text(IkStrings.emptyQueue))
              : Scrollbar(
                  controller: _scroll,
                  radius: const Radius.circular(4),
                  thickness: 4,
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
                    itemCount: player.playlist.length,
                    itemBuilder: (context, index) {
                      final song = player.playlist[index];
                      final current = index == player.currentIndex;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Material(
                          color: current
                              ? colors.primary.withValues(alpha: .08)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          clipBehavior: Clip.antiAlias,
                          child: GestureDetector(
                            onSecondaryTapDown: (event) => unawaited(
                              showSongActionsMenuAt(
                                context,
                                ref,
                                song: song,
                                position: event.globalPosition,
                                isLocal: song.platform == PlatformType.local,
                                isLiked: ref
                                    .read(likesProvider)
                                    .songs
                                    .contains(song),
                              ),
                            ),
                            child: InkWell(
                              onTap: () => ref
                                  .read(playerProvider.notifier)
                                  .playPlaylist(
                                    player.playlist,
                                    startIndex: index,
                                  ),
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Row(
                                  children: [
                                    VideoCover(
                                      url: song.coverUrl,
                                      size: 42,
                                      radius: 9,
                                      neteaseImageCompatibility:
                                          song.platform == PlatformType.netease,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            song.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: current
                                                  ? FontWeight.w600
                                                  : FontWeight.w500,
                                              color: current
                                                  ? colors.primary
                                                  : colors.onSurface,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
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
                                    const SizedBox(width: 10),
                                    if (current)
                                      Icon(
                                        player.isPlaying
                                            ? Icons.graphic_eq_rounded
                                            : Icons.pause_rounded,
                                        size: 18,
                                        color: colors.primary,
                                      )
                                    else
                                      Text(
                                        '${song.duration.inMinutes}:${(song.duration.inSeconds % 60).toString().padLeft(2, '0')}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: colors.onSurfaceVariant,
                                        ),
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
                ),
        ),
      ],
    );
  }
}

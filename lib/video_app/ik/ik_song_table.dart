import 'package:flutter/material.dart';

import '../../l10n/ik_alignment_strings.dart';
import '../../l10n/ik_strings.dart';
import '../../l10n/video_strings.dart';
import '../../models/song.dart';
import '../ui/catalog_pages.dart';
import '../ui/video_shell.dart';

/// 新工作区的响应式歌曲列；原 IkSongTile 契约与默认布局保持。
class IkSongTableHeader extends StatelessWidget {
  const IkSongTableHeader({super.key});
  @override
  Widget build(BuildContext context) => _SongColumns(
    builder: (layout) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: DefaultTextStyle(
        style: Theme.of(context).textTheme.bodySmall!,
        child: Row(
          children: [
            if (layout.number) const SizedBox(width: 30, child: Text('#')),
            const Expanded(flex: 5, child: Text(IkAlignmentStrings.song)),
            if (layout.album)
              const Expanded(flex: 3, child: Text(IkAlignmentStrings.album)),
            if (layout.source)
              SizedBox(
                width: layout.sourceWidth,
                child: const Text(IkAlignmentStrings.source),
              ),
            if (layout.duration)
              SizedBox(
                width: layout.durationWidth,
                child: const Text(IkAlignmentStrings.duration),
              ),
            SizedBox(
              width: layout.actionWidth,
              child: const Center(child: Text(IkAlignmentStrings.actions)),
            ),
          ],
        ),
      ),
    ),
  );
}

class IkSongTableRow extends StatelessWidget {
  const IkSongTableRow({
    super.key,
    required this.song,
    required this.index,
    required this.onPlay,
    required this.onMore,
    this.onMoreWithContext,
    this.onLike,
    this.playing = false,
    this.liked = false,
    this.detail,
    this.cover,
  });
  final Song song;
  final int index;
  final VoidCallback onPlay, onMore;
  final ValueChanged<BuildContext>? onMoreWithContext;
  final VoidCallback? onLike;
  final bool playing, liked;
  final String? detail;
  final Widget? cover;

  @override
  Widget build(BuildContext context) => _SongColumns(
    builder: (layout) {
      final colors = Theme.of(context).colorScheme;
      final seconds = song.duration.inSeconds;
      final duration = seconds <= 0
          ? IkAlignmentStrings.unknownDuration
          : '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
      final subtitle = song.artistNames;
      return Material(
        color: playing
            ? colors.primary.withValues(alpha: .07)
            : Colors.transparent,
        child: InkWell(
          onTap: onPlay,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: .7),
                ),
              ),
            ),
            child: Row(
              children: [
                if (layout.number)
                  SizedBox(
                    width: 30,
                    child: Text(
                      '${index + 1}'.padLeft(2, '0'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                Expanded(
                  flex: 5,
                  child: Row(
                    children: [
                      cover ??
                          VideoCover(url: song.coverUrl, size: 40, radius: 7),
                      SizedBox(width: layout.compact ? 8 : 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              song.name,
                              maxLines: layout.compact ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: playing ? colors.primary : null,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (!layout.source)
                              Text(
                                videoPlatformLabel(song.platform),
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            if (detail != null)
                              Text(
                                detail!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                      SizedBox(width: layout.compact ? 8 : 12),
                    ],
                  ),
                ),
                if (layout.album)
                  Expanded(
                    flex: 3,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text(
                        song.album?.name ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                if (layout.source)
                  SizedBox(
                    width: layout.sourceWidth,
                    child: Text(
                      videoPlatformLabel(song.platform),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (layout.duration)
                  SizedBox(
                    width: layout.durationWidth,
                    child: Text(
                      duration,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                SizedBox(
                  width: layout.actionWidth,
                  child: Row(
                    children: [
                      if (onLike != null)
                        IconButton(
                          style: layout.actionStyle,
                          tooltip: liked
                              ? VideoStrings.unlike
                              : VideoStrings.like,
                          onPressed: onLike,
                          icon: Icon(
                            liked
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            size: 19,
                          ),
                        )
                      else
                        IconButton(
                          style: layout.actionStyle,
                          tooltip: VideoStrings.play,
                          onPressed: onPlay,
                          icon: Icon(
                            playing
                                ? Icons.graphic_eq_rounded
                                : Icons.play_arrow_rounded,
                            size: 21,
                          ),
                        ),
                      Builder(
                        builder: (buttonContext) => IconButton(
                          style: layout.actionStyle,
                          tooltip: IkStrings.more,
                          onPressed: onMoreWithContext == null
                              ? onMore
                              : () => onMoreWithContext!(buttonContext),
                          icon: const Icon(Icons.more_horiz, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _SongColumns extends StatelessWidget {
  const _SongColumns({required this.builder});
  final Widget Function(_ColumnLayout) builder;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) => builder(
      _ColumnLayout(
        size.maxWidth,
        MediaQuery.textScalerOf(context).scale(14) / 14,
      ),
    ),
  );
}

class _ColumnLayout {
  _ColumnLayout(double width, this.scale) : available = width / scale;
  final double available, scale;
  bool get compact => available < 420;
  bool get number => available >= 420;
  bool get duration => available >= 460;
  bool get album => available >= 650;
  bool get source => available >= 820;
  double get sourceWidth => 80 * scale;
  double get durationWidth => 64 * scale;
  double get actionWidth => compact ? 80 : 96;
  ButtonStyle? get actionStyle => compact
      ? IconButton.styleFrom(
          minimumSize: const Size.square(40),
          maximumSize: const Size.square(40),
          padding: const EdgeInsets.all(8),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        )
      : null;
}

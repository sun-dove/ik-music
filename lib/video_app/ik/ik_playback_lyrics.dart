import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/player/presentation/providers/lyrics_provider.dart';
import '../../l10n/ik_playback_lyrics_strings.dart';
import '../../l10n/video_strings.dart';
import '../../lyrics/models/lyrics_line.dart';

/// 复用当前歌曲歌词；只在播放栏有足够剩余宽度时挂载。
class IkPlaybackLyrics extends ConsumerWidget {
  const IkPlaybackLyrics({
    super.key,
    required this.position,
    required this.isPlaying,
    required this.isTransitioning,
    this.compact = false,
    this.onOpen,
  });

  final Duration position;
  final bool isPlaying, isTransitioning;
  final bool compact;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lyrics = ref.watch(lyricsProvider);
    var text = VideoStrings.noLyrics;
    var hasLine = false;
    // AsyncValue在重新加载时可能携带旧data，不能把它当成当前歌曲歌词。
    if (isTransitioning || lyrics.isLoading) {
      text = VideoStrings.loadingLyrics;
    } else if (lyrics.hasError) {
      text = IkPlaybackLyricsStrings.unavailable;
    } else {
      final document = lyrics.valueOrNull;
      if (document != null && document.lines.isNotEmpty) {
        final index = document.format == LyricsFormat.unknown
            ? 0
            : document.lines.lastIndexWhere(
                (line) => line.timestamp <= position,
              );
        if (index < 0) {
          text = IkPlaybackLyricsStrings.intro;
        } else {
          text = document.lines[index].text.trim();
          hasLine = text.isNotEmpty;
          if (!hasLine) text = VideoStrings.noLyrics;
        }
      }
    }
    final colors = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodySmall!.copyWith(
      fontSize: compact ? 14 : 13,
      height: 1.5,
      color: hasLine
          ? colors.onSurfaceVariant
          : colors.onSurfaceVariant.withValues(alpha: .65),
    );
    return Semantics(
      key: const ValueKey('ik-bar-current-lyrics'),
      container: true,
      label: hasLine ? '${IkPlaybackLyricsStrings.currentLine}：$text' : text,
      button: onOpen != null,
      onTap: onOpen,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 4,
              vertical: compact ? 2 : 12,
            ),
            child: Row(
              children: [
                if (compact) ...[
                  Icon(Icons.lyrics_outlined, size: 16, color: colors.primary),
                  const SizedBox(width: 7),
                ],
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final direction = Directionality.of(context);
                      final painter = TextPainter(
                        text: TextSpan(text: text, style: style),
                        maxLines: 1,
                        textDirection: direction,
                        textScaler: MediaQuery.textScalerOf(context),
                      )..layout();
                      final textWidth = painter.width;
                      final textHeight = painter.height;
                      painter.dispose();
                      final overflow = textWidth - constraints.maxWidth;
                      if (!hasLine || overflow <= 1) {
                        return Text(
                          text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: style,
                        );
                      }
                      return _RollingPlaybackLine(
                        key: ValueKey(text),
                        text: text,
                        style: style,
                        textWidth: textWidth,
                        textHeight: textHeight,
                        overflow: overflow,
                        direction: direction,
                        playing: isPlaying && !isTransitioning,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RollingPlaybackLine extends StatefulWidget {
  const _RollingPlaybackLine({
    super.key,
    required this.text,
    required this.style,
    required this.textWidth,
    required this.textHeight,
    required this.overflow,
    required this.direction,
    required this.playing,
  });
  final String text;
  final TextStyle style;
  final double textWidth, textHeight, overflow;
  final TextDirection direction;
  final bool playing;

  @override
  State<_RollingPlaybackLine> createState() => _RollingPlaybackLineState();
}

class _RollingPlaybackLineState extends State<_RollingPlaybackLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion;
  bool _forward = true;
  bool _motionAllowed = false;

  Duration get _travelTime => Duration(
    milliseconds: math.max(4000, (widget.overflow / 18 * 1000).round()),
  );

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(vsync: this, duration: _travelTime)
      ..addStatusListener(_directionChanged);
  }

  void _directionChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _forward = false;
    } else if (status == AnimationStatus.dismissed) {
      _forward = true;
    } else {
      return;
    }
    _syncMotion();
  }

  void _syncMotion() {
    if (!widget.playing || !_motionAllowed) {
      _motion.stop();
    } else if (!_motion.isAnimating) {
      if (_forward) {
        _motion.forward();
      } else {
        _motion.reverse();
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motionAllowed =
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    _syncMotion();
  }

  @override
  void didUpdateWidget(_RollingPlaybackLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.overflow != widget.overflow ||
        oldWidget.direction != widget.direction) {
      _motion.stop();
      _motion.duration = _travelTime;
      _forward = true;
      _motion.value = 0;
    }
    _syncMotion();
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rtl = widget.direction == TextDirection.rtl;
    return RepaintBoundary(
      child: ClipRect(
        child: SizedBox(
          height: widget.textHeight,
          child: OverflowBox(
            alignment: rtl ? Alignment.centerRight : Alignment.centerLeft,
            minWidth: widget.textWidth,
            maxWidth: widget.textWidth,
            child: AnimatedBuilder(
              animation: _motion,
              builder: (context, child) => Transform.translate(
                offset: Offset(
                  widget.overflow *
                      Curves.easeInOut.transform(_motion.value) *
                      (rtl ? 1 : -1),
                  0,
                ),
                child: child,
              ),
              child: Text(
                widget.text,
                maxLines: 1,
                softWrap: false,
                style: widget.style,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

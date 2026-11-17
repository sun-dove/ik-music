import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../l10n/video_strings.dart';
import '../../l10n/windows_music_strings.dart';
import '../../lyrics/models/lyrics_line.dart';
import '../../models/platform_type.dart';
import '../../models/song.dart';
import '../ui/catalog_pages.dart';
import '../ui/player_page.dart';
import '../ui/video_shell.dart';
import '../ui/video_theme.dart';
import 'windows_platform_icon.dart';

class WindowsPlayerPage extends StatefulWidget {
  const WindowsPlayerPage({
    super.key,
    required this.song,
    required this.position,
    required this.duration,
    required this.isPlaying,
    required this.onToggle,
    required this.onPrevious,
    required this.onNext,
    required this.onSeek,
    required this.onQueue,
    required this.onMode,
    this.isLoading = false,
    this.error,
    this.qualityLabel,
    this.isPreview = false,
    this.lyrics = const [],
    this.timedLyrics = true,
    this.lyricsLoading = false,
    this.lyricsError,
    this.onLyricsRetry,
    this.modeLabel = VideoStrings.sequential,
    this.onQuality,
    this.sourceStatus,
  });
  final Song song;
  final Duration position, duration;
  final bool isPlaying, isLoading, isPreview, lyricsLoading, timedLyrics;
  final String? error, qualityLabel, lyricsError;
  final List<LyricsLine> lyrics;
  final String modeLabel;
  final VoidCallback onToggle, onPrevious, onNext, onQueue, onMode;
  final ValueChanged<Duration> onSeek;
  final VoidCallback? onQuality, onLyricsRetry;
  final Widget? sourceStatus;
  @override
  State<WindowsPlayerPage> createState() => _WindowsPlayerPageState();
}

class _WindowsPlayerPageState extends State<WindowsPlayerPage> {
  final _scroll = ScrollController();
  final _lyricsFocus = FocusNode();
  List<GlobalKey> _lineKeys = [];
  bool _following = true;
  Size _lastSize = Size.zero;
  double _lastFontSize = 0;
  int _revision = 0;
  int get _active => widget.timedLyrics
      ? widget.lyrics.lastIndexWhere(
          (line) => line.timestamp <= widget.position,
        )
      : -1;
  @override
  void initState() {
    super.initState();
    _resetKeys();
  }

  void _resetKeys() {
    _lineKeys = List.generate(widget.lyrics.length, (_) => GlobalKey());
    _revision++;
  }

  @override
  void didUpdateWidget(WindowsPlayerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changedSong = widget.song.dedupeKey != oldWidget.song.dedupeKey;
    if (changedSong || widget.lyrics != oldWidget.lyrics) _resetKeys();
    if (changedSong) _following = true;
    if (changedSong ||
        widget.lyrics != oldWidget.lyrics ||
        _active !=
            oldWidget.lyrics.lastIndexWhere(
              (line) => line.timestamp <= oldWidget.position,
            )) {
      _follow();
    }
  }

  void _follow() {
    final revision = _revision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_following ||
          revision != _revision ||
          !widget.timedLyrics) {
        return;
      }
      if (_active < 0) {
        if (_scroll.hasClients) _scroll.jumpTo(0);
        return;
      }
      final line = _lineKeys[_active].currentContext;
      if (line != null) {
        Scrollable.ensureVisible(
          line,
          alignment: .38,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _pauseFollow() {
    if (!_following) return;
    setState(() => _following = false);
  }

  KeyEventResult _keyboard(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !_scroll.hasClients) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final position = _scroll.position;
    final amount = key == LogicalKeyboardKey.arrowDown
        ? 48.0
        : key == LogicalKeyboardKey.arrowUp
        ? -48.0
        : key == LogicalKeyboardKey.pageDown
        ? position.viewportDimension * .8
        : key == LogicalKeyboardKey.pageUp
        ? -position.viewportDimension * .8
        : null;
    if (amount == null &&
        key != LogicalKeyboardKey.home &&
        key != LogicalKeyboardKey.end) {
      return KeyEventResult.ignored;
    }
    _pauseFollow();
    final target = key == LogicalKeyboardKey.home
        ? 0.0
        : key == LogicalKeyboardKey.end
        ? position.maxScrollExtent
        : (_scroll.offset + amount!).clamp(0.0, position.maxScrollExtent);
    _scroll.jumpTo(target);
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _revision++;
    _scroll.dispose();
    _lyricsFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: VideoTheme.canvas(context),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                label: const Text(WindowsMusicStrings.back),
              ),
            ),
            if (widget.sourceStatus != null)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: math.min(
                    96,
                    MediaQuery.sizeOf(context).height * .18,
                  ),
                ),
                child: SingleChildScrollView(child: widget.sourceStatus!),
              ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final fontSize = MediaQuery.textScalerOf(context).scale(22);
                  if (_lastSize != constraints.biggest ||
                      _lastFontSize != fontSize) {
                    _lastSize = constraints.biggest;
                    _lastFontSize = fontSize;
                    _follow();
                  }
                  final wide = constraints.maxWidth >= 840;
                  return wide
                      ? Row(
                          key: const ValueKey('windows-player-wide'),
                          children: [
                            SizedBox(
                              width: constraints.maxWidth * .40,
                              child: _cover(
                                context,
                                constraints.maxWidth * .31,
                              ),
                            ),
                            const SizedBox(width: 36),
                            Expanded(child: _lyrics(context)),
                          ],
                        )
                      : Column(
                          key: const ValueKey('windows-player-narrow'),
                          children: [
                            if (constraints.maxHeight >= 120)
                              SizedBox(
                                height: constraints.maxHeight < 220 ? 80 : 105,
                                child: _compactCover(
                                  context,
                                  constraints.maxHeight < 220 ? 56 : 84,
                                ),
                              ),
                            const SizedBox(height: 8),
                            Expanded(child: _lyrics(context)),
                          ],
                        );
                },
              ),
            ),
            if (widget.isLoading || widget.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  widget.error ?? VideoStrings.preparingAudio,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: widget.error == null
                        ? VideoTheme.secondaryText(context)
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            TextButton(
              onPressed: widget.song.platform == PlatformType.local
                  ? null
                  : widget.onQuality,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  WindowsPlatformIcon(platform: widget.song.platform, size: 18),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '${videoPlatformLabel(widget.song.platform)} · ${widget.qualityLabel ?? VideoStrings.qualityUnknown}${widget.isPreview ? VideoStrings.previewSuffix : ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(trackHeight: 3),
              child: Slider(
                value: widget.position.inMilliseconds.toDouble().clamp(
                  0,
                  math.max(1, widget.duration.inMilliseconds).toDouble(),
                ),
                max: math.max(1, widget.duration.inMilliseconds).toDouble(),
                onChanged: widget.isLoading || widget.duration <= Duration.zero
                    ? null
                    : (value) =>
                          widget.onSeek(Duration(milliseconds: value.round())),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  videoTime(widget.position),
                  style: const TextStyle(fontSize: 11),
                ),
                Text(
                  videoTime(widget.duration),
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              children: [
                IconButton(
                  tooltip: widget.modeLabel,
                  onPressed: widget.onMode,
                  icon: Icon(
                    widget.modeLabel == VideoStrings.shuffle
                        ? Icons.shuffle_rounded
                        : widget.modeLabel == VideoStrings.repeatOne
                        ? Icons.repeat_one_rounded
                        : Icons.repeat_rounded,
                  ),
                ),
                IconButton(
                  tooltip: VideoStrings.previousSong,
                  onPressed: widget.onPrevious,
                  icon: const Icon(Icons.skip_previous_rounded, size: 30),
                ),
                IconButton.filled(
                  tooltip: widget.isPlaying && !widget.isLoading
                      ? VideoStrings.pause
                      : VideoStrings.play,
                  onPressed: widget.isLoading ? null : widget.onToggle,
                  style: IconButton.styleFrom(fixedSize: const Size(54, 54)),
                  icon: widget.isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          widget.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 32,
                        ),
                ),
                IconButton(
                  tooltip: VideoStrings.nextSong,
                  onPressed: widget.onNext,
                  icon: const Icon(Icons.skip_next_rounded, size: 30),
                ),
                IconButton(
                  tooltip: VideoStrings.playQueue,
                  onPressed: widget.onQueue,
                  icon: const Icon(Icons.queue_music_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _cover(BuildContext context, double size) => SingleChildScrollView(
    child: Column(
      children: [
        VideoCover(
          url: widget.song.coverUrl,
          size: size.clamp(120, 350),
          radius: 24,
        ),
        const SizedBox(height: 24),
        Text(
          widget.song.name,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          widget.song.artistNames,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: VideoTheme.secondaryText(context),
          ),
        ),
      ],
    ),
  );
  Widget _compactCover(BuildContext context, double coverSize) => Row(
    children: [
      VideoCover(url: widget.song.coverUrl, size: coverSize, radius: 14),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.song.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
            ),
            Text(
              widget.song.artistNames,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    ],
  );
  Widget _lyrics(BuildContext context) {
    if (widget.lyrics.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.lyricsLoading
                  ? VideoStrings.loadingLyrics
                  : widget.lyricsError ?? VideoStrings.noLyrics,
            ),
            if (widget.lyricsError != null && widget.onLyricsRetry != null)
              TextButton(
                onPressed: widget.onLyricsRetry,
                child: const Text(VideoStrings.retry),
              ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.timedLyrics)
          const Text(
            WindowsMusicStrings.plainLyrics,
            style: TextStyle(fontSize: 12),
          ),
        Expanded(
          child: Focus(
            key: const ValueKey('windows-lyrics-focus'),
            focusNode: _lyricsFocus,
            onKeyEvent: _keyboard,
            child: Listener(
              onPointerDown: (_) => _lyricsFocus.requestFocus(),
              onPointerSignal: (_) => _pauseFollow(),
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is UserScrollNotification &&
                      notification.direction != ScrollDirection.idle) {
                    _pauseFollow();
                  }
                  if (notification is ScrollUpdateNotification &&
                      notification.dragDetails != null) {
                    _pauseFollow();
                  }
                  return false;
                },
                child: Scrollbar(
                  controller: _scroll,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    key: const ValueKey('windows-lyrics-scroll'),
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 30, 18, 110),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < widget.lyrics.length; i++)
                          InkWell(
                            key: _lineKeys[i],
                            borderRadius: BorderRadius.circular(12),
                            onTap: widget.timedLyrics
                                ? () {
                                    widget.onSeek(widget.lyrics[i].timestamp);
                                  }
                                : null,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 13,
                                horizontal: 6,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.lyrics[i].text,
                                    style: TextStyle(
                                      fontSize: 22,
                                      height: 1.6,
                                      fontWeight: i == _active
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: i == _active
                                          ? VideoTheme.primary
                                          : Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withValues(alpha: .62),
                                    ),
                                  ),
                                  if (widget.lyrics[i].hasTranslation)
                                    Text(
                                      widget.lyrics[i].translation!,
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 1.6,
                                        color: VideoTheme.secondaryText(
                                          context,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (!_following && widget.timedLyrics)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                setState(() => _following = true);
                _follow();
              },
              icon: const Icon(Icons.my_location_outlined, size: 16),
              label: const Text(WindowsMusicStrings.returnToLyrics),
            ),
          ),
      ],
    );
  }
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../l10n/ik_player_alignment_strings.dart';
import '../../l10n/ik_strings.dart';
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

class WindowsSourceDetails {
  const WindowsSourceDetails({
    this.sourceName,
    this.format,
    this.bitrate,
    this.note,
  });
  final String? sourceName, format, note;
  final int? bitrate;
}

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
    this.sourceDetails,
    this.playbackBar,
    this.onDesktopLyrics,
    this.desktopLyricsEnabled = false,
    this.alignToDesign = false,
    this.compactLayout = false,
    this.lyricsAutoResumeDelay,
    this.onArtist,
    this.onAlbum,
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
  final WindowsSourceDetails? sourceDetails;
  final Widget? playbackBar;
  final VoidCallback? onDesktopLyrics;
  final bool desktopLyricsEnabled;
  final bool alignToDesign;

  /// 独立播放详情的紧凑排版；缺省保留既有页面布局。
  final bool compactLayout;

  /// 手动浏览结束后的恢复延时；缺省保持手动返回歌词的原行为。
  final Duration? lyricsAutoResumeDelay;
  final VoidCallback? onArtist, onAlbum;
  @override
  State<WindowsPlayerPage> createState() => _WindowsPlayerPageState();
}

class _WindowsPlayerPageState extends State<WindowsPlayerPage> {
  final _scroll = ScrollController();
  final _informationScroll = ScrollController();
  final _lyricsFocus = FocusNode();
  List<GlobalKey> _lineKeys = [];
  bool _following = true;
  bool _showTranslation = true;
  bool _sourceExpanded = false;
  double _lyricsFontSize = 22;
  Size _lastSize = Size.zero;
  Size? _compactPageSize;
  double _lastFontSize = 0;
  int _revision = 0;
  Timer? _autoResumeTimer;
  final Set<int> _lyricsPointers = {};
  bool _manualScrollActive = false;
  bool _lyricsVisible = true;
  bool get _canAutoResume =>
      widget.lyricsAutoResumeDelay != null &&
      widget.timedLyrics &&
      widget.lyrics.isNotEmpty &&
      !widget.lyricsLoading &&
      !widget.isLoading &&
      widget.duration > Duration.zero;
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true);
    if (_lyricsVisible == visible) return;
    _lyricsVisible = visible;
    if (widget.lyricsAutoResumeDelay == null) return;
    _cancelAutoResume();
    if (!visible) {
      _lyricsPointers.clear();
      _manualScrollActive = false;
    } else if (_following) {
      _follow();
    } else {
      _scheduleAutoResume();
    }
  }

  @override
  void didUpdateWidget(WindowsPlayerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changedSong = widget.alignToDesign
        ? widget.song.id != oldWidget.song.id ||
              widget.song.platform != oldWidget.song.platform
        : widget.song.dedupeKey != oldWidget.song.dedupeKey;
    final changedLyrics = widget.lyrics != oldWidget.lyrics;
    if (changedSong || changedLyrics) _resetKeys();
    if (changedSong) {
      _cancelAutoResume();
      _lyricsPointers.clear();
      _manualScrollActive = false;
      _following = true;
      _sourceExpanded = false;
    }
    if (widget.lyricsAutoResumeDelay != oldWidget.lyricsAutoResumeDelay ||
        changedLyrics ||
        !_canAutoResume) {
      _cancelAutoResume();
    }
    if (widget.lyricsAutoResumeDelay != null && widget.lyrics.isEmpty) {
      _lyricsPointers.clear();
      _manualScrollActive = false;
    }
    final becameReady =
        _canAutoResume &&
        (oldWidget.lyrics.isEmpty ||
            !oldWidget.timedLyrics ||
            oldWidget.lyricsLoading ||
            oldWidget.isLoading ||
            oldWidget.duration <= Duration.zero);
    if (becameReady) {
      _following = true;
      _manualScrollActive = false;
    } else if (changedLyrics ||
        widget.lyricsAutoResumeDelay != oldWidget.lyricsAutoResumeDelay) {
      _scheduleAutoResume();
    }
    if (changedSong ||
        changedLyrics ||
        becameReady ||
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
          !widget.timedLyrics ||
          (widget.lyricsAutoResumeDelay != null &&
              (!_lyricsVisible ||
                  _lyricsPointers.isNotEmpty ||
                  _manualScrollActive))) {
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
    if (_following) setState(() => _following = false);
    _scheduleAutoResume();
  }

  void _cancelAutoResume() {
    _autoResumeTimer?.cancel();
    _autoResumeTimer = null;
  }

  void _scheduleAutoResume() {
    _cancelAutoResume();
    if (_following ||
        !_canAutoResume ||
        !_lyricsVisible ||
        _manualScrollActive ||
        _lyricsPointers.isNotEmpty) {
      return;
    }
    final revision = _revision;
    _autoResumeTimer = Timer(widget.lyricsAutoResumeDelay!, () {
      _autoResumeTimer = null;
      if (!mounted ||
          !_canAutoResume ||
          !_lyricsVisible ||
          revision != _revision ||
          _manualScrollActive ||
          _lyricsPointers.isNotEmpty) {
        return;
      }
      _resumeFollow();
    });
  }

  void _resumeFollow() {
    _cancelAutoResume();
    _manualScrollActive = false;
    setState(() => _following = true);
    _follow();
  }

  void _lyricsPointerStart(int pointer) {
    _lyricsPointers.add(pointer);
    _cancelAutoResume();
  }

  void _lyricsPointerEnd(int pointer) {
    _lyricsPointers.remove(pointer);
    if (_following) {
      _follow();
    } else {
      _scheduleAutoResume();
    }
  }

  KeyEventResult _keyboard(FocusNode node, KeyEvent event) {
    if ((event is! KeyDownEvent &&
            (widget.lyricsAutoResumeDelay == null ||
                event is! KeyRepeatEvent)) ||
        !_scroll.hasClients) {
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
    _cancelAutoResume();
    _revision++;
    _scroll.dispose();
    _informationScroll.dispose();
    _lyricsFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.alignToDesign
        ? (widget.compactLayout ? _compactAlignedPage : _alignedPage)
        : _page;
    if (Theme.of(context).extension<IkThemeColors>() == null) {
      return page(context);
    }
    final cover = widget.song.coverUrl;
    return IkCoverTheme(
      cover: cover == null || cover.isEmpty ? null : NetworkImage(cover),
      child: Builder(builder: page),
    );
  }

  Widget _compactAlignedPage(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if ((ModalRoute.isCurrentOf(context) ?? true) ||
          _compactPageSize == null) {
        _compactPageSize = constraints.biggest;
      }
      final size = _compactPageSize!;
      // 主壳先恢复时，退场页按原尺寸布局，并整体适配收缩后的正文。
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Overlay.wrap(
            clipBehavior: Clip.none,
            child: _compactAlignedContent(context),
          ),
        ),
      );
    },
  );

  Widget _compactAlignedContent(BuildContext context) => Scaffold(
    backgroundColor: VideoTheme.canvas(context),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => Navigator.maybePop(context),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                        label: const Text(WindowsMusicStrings.back),
                      ),
                      const Spacer(),
                      if (widget.onDesktopLyrics != null)
                        TextButton.icon(
                          onPressed: widget.onDesktopLyrics,
                          icon: Icon(
                            Icons.subtitles_outlined,
                            size: 20,
                            color: widget.desktopLyricsEnabled
                                ? VideoTheme.accent(context)
                                : null,
                          ),
                          label: const Text(IkStrings.floating),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1240),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final fontSize = MediaQuery.textScalerOf(context)
                                .scale(_lyricsFontSize);
                            if (_lastSize != constraints.biggest ||
                                _lastFontSize != fontSize) {
                              _lastSize = constraints.biggest;
                              _lastFontSize = fontSize;
                              _follow();
                            }
                            final wide = constraints.maxWidth >= 800;
                            final gap = (constraints.maxWidth * .03).clamp(
                              24.0,
                              40.0,
                            );
                            final informationWidth = wide
                                ? (constraints.maxWidth - gap) * .4
                                : constraints.maxWidth;
                            final coverSize = wide
                                ? math.min(
                                    math.min(420.0, informationWidth * .92),
                                    math.max(
                                      160.0,
                                      constraints.maxHeight - 210,
                                    ),
                                  )
                                : 68.0;
                            final information = Scrollbar(
                              key: const ValueKey(
                                'ik-player-information-scrollbar',
                              ),
                              controller: _informationScroll,
                              thumbVisibility: true,
                              thickness: 3,
                              child: SingleChildScrollView(
                                key: const ValueKey('ik-player-information'),
                                controller: _informationScroll,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minHeight: wide ? constraints.maxHeight : 0,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      if (wide) ...[
                                        Center(
                                          child: VideoCover(
                                            url: widget.song.coverUrl,
                                            size: coverSize,
                                            radius: 18,
                                          ),
                                        ),
                                        const SizedBox(height: 14),
                                        _alignedMetadata(
                                          context,
                                          centered: true,
                                        ),
                                      ] else
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            VideoCover(
                                              url: widget.song.coverUrl,
                                              size: coverSize,
                                              radius: 10,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: _alignedMetadata(context),
                                            ),
                                          ],
                                        ),
                                      const SizedBox(height: 10),
                                      _compactSourceInfo(context),
                                    ],
                                  ),
                                ),
                              ),
                            );
                            final lyrics = _alignedLyricsPane(
                              context,
                              compact: true,
                            );
                            return wide
                                ? Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      SizedBox(
                                        width: informationWidth,
                                        child: information,
                                      ),
                                      SizedBox(width: gap),
                                      Expanded(child: lyrics),
                                    ],
                                  )
                                : Column(
                                    children: [
                                      SizedBox(
                                        height: math.min(
                                          300,
                                          constraints.maxHeight * .43,
                                        ),
                                        child: information,
                                      ),
                                      const SizedBox(height: 14),
                                      Expanded(child: lyrics),
                                    ],
                                  );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          widget.playbackBar ?? _alignedTransport(context),
        ],
      ),
    ),
  );

  Widget _alignedPage(BuildContext context) => Scaffold(
    backgroundColor: VideoTheme.canvas(context),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => Navigator.maybePop(context),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                        label: const Text(WindowsMusicStrings.back),
                      ),
                      const Spacer(),
                      if (widget.onDesktopLyrics != null)
                        TextButton.icon(
                          onPressed: widget.onDesktopLyrics,
                          icon: Icon(
                            Icons.subtitles_outlined,
                            size: 20,
                            color: widget.desktopLyricsEnabled
                                ? VideoTheme.accent(context)
                                : null,
                          ),
                          label: const Text(IkStrings.floating),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1160),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final fontSize = MediaQuery.textScalerOf(context)
                                .scale(_lyricsFontSize);
                            if (_lastSize != constraints.biggest ||
                                _lastFontSize != fontSize) {
                              _lastSize = constraints.biggest;
                              _lastFontSize = fontSize;
                              _follow();
                            }
                            final wide = constraints.maxWidth >= 840;
                            final coverSize = (constraints.maxHeight - 320)
                                .clamp(160.0, 330.0);
                            final information = Scrollbar(
                              key: const ValueKey(
                                'ik-player-information-scrollbar',
                              ),
                              controller: _informationScroll,
                              thumbVisibility: true,
                              thickness: 3,
                              child: SingleChildScrollView(
                                key: const ValueKey('ik-player-information'),
                                controller: _informationScroll,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (wide) ...[
                                      Center(
                                        child: VideoCover(
                                          url: widget.song.coverUrl,
                                          size: coverSize,
                                          radius: 18,
                                        ),
                                      ),
                                      const SizedBox(height: 20),
                                      _alignedMetadata(context, centered: true),
                                    ] else
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          VideoCover(
                                            url: widget.song.coverUrl,
                                            size: 68,
                                            radius: 10,
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: _alignedMetadata(context),
                                          ),
                                        ],
                                      ),
                                    const SizedBox(height: 18),
                                    _alignedSourceInfo(context),
                                  ],
                                ),
                              ),
                            );
                            return wide
                                ? Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      SizedBox(
                                        width: math.min(
                                          390,
                                          constraints.maxWidth * .36,
                                        ),
                                        child: information,
                                      ),
                                      VerticalDivider(
                                        key: const ValueKey(
                                          'ik-player-divider',
                                        ),
                                        width: 44,
                                        thickness: 1,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outlineVariant
                                            .withValues(alpha: .6),
                                      ),
                                      Expanded(
                                        child: _alignedLyricsPane(context),
                                      ),
                                    ],
                                  )
                                : Column(
                                    children: [
                                      SizedBox(
                                        height: math.min(
                                          260,
                                          constraints.maxHeight * .42,
                                        ),
                                        child: information,
                                      ),
                                      const SizedBox(height: 16),
                                      Expanded(
                                        child: _alignedLyricsPane(context),
                                      ),
                                    ],
                                  );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          widget.playbackBar ?? _alignedTransport(context),
        ],
      ),
    ),
  );

  Widget _alignedMetadata(BuildContext context, {bool centered = false}) {
    final song = widget.song;
    final local = song.platform == PlatformType.local;
    final artistId =
        song.artistId?.trim().isNotEmpty == true ||
        song.artists.any((artist) => artist.id.trim().isNotEmpty);
    final albumId =
        song.albumId?.trim().isNotEmpty == true ||
        song.album?.id.trim().isNotEmpty == true;
    final artist = song.artistNames.isEmpty
        ? VideoStrings.unknownArtist
        : song.artistNames;
    final album = song.album?.name;
    final albumLabel = album == null || album.isEmpty
        ? (albumId ? IkStrings.album : null)
        : album;
    return Column(
      key: const ValueKey('ik-player-metadata'),
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Tooltip(
          message: song.name,
          child: Text(
            song.name,
            textAlign: centered ? TextAlign.center : TextAlign.start,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 23,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 8),
        _metadataEntry(
          context,
          text: artist,
          tooltip: IkStrings.artist,
          key: const ValueKey('ik-player-artist'),
          onTap: !local && artistId ? widget.onArtist : null,
          centered: centered,
        ),
        if (albumLabel != null) ...[
          const SizedBox(height: 4),
          _metadataEntry(
            context,
            text: albumLabel,
            tooltip: IkStrings.album,
            key: const ValueKey('ik-player-album'),
            onTap: !local && albumId ? widget.onAlbum : null,
            centered: centered,
          ),
        ],
      ],
    );
  }

  Widget _metadataEntry(
    BuildContext context, {
    required String text,
    required String tooltip,
    required Key key,
    VoidCallback? onTap,
    bool centered = false,
  }) {
    final label = Text(
      text,
      textAlign: centered ? TextAlign.center : TextAlign.start,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 13,
        color: onTap == null
            ? VideoTheme.secondaryText(context)
            : VideoTheme.accent(context),
      ),
    );
    if (onTap == null) return label;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: label,
        ),
      ),
    );
  }

  Widget _alignedSourceInfo(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final details = widget.sourceDetails;
    final source = details?.sourceName?.trim();
    final format = details?.format?.trim();
    final formatParts = [
      if (format != null && format.isNotEmpty) format.toUpperCase(),
      if (details?.bitrate != null && details!.bitrate! > 0)
        '${(details.bitrate! / 1000).round()} kbps',
    ];
    return Container(
      key: const ValueKey('ik-player-source-inline'),
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
      decoration: BoxDecoration(
        color: VideoTheme.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  IkStrings.sourceDetails,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                key: const ValueKey('ik-player-source-expand'),
                tooltip: _sourceExpanded
                    ? IkPlayerAlignmentStrings.collapseSource
                    : IkPlayerAlignmentStrings.expandSource,
                onPressed: () =>
                    setState(() => _sourceExpanded = !_sourceExpanded),
                icon: Icon(
                  _sourceExpanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 20,
                ),
              ),
            ],
          ),
          _sourceValue(
            context,
            IkPlayerAlignmentStrings.songSource,
            '${widget.song.platform == PlatformType.local ? VideoStrings.localAudio : videoPlatformLabel(widget.song.platform)}${widget.isPreview ? VideoStrings.previewSuffix : ''}',
          ),
          const SizedBox(height: 8),
          _sourceValue(
            context,
            IkStrings.sourceName,
            source == null || source.isEmpty ? IkStrings.sourceUnknown : source,
          ),
          const SizedBox(height: 8),
          _sourceValue(
            context,
            IkPlayerAlignmentStrings.audioFormat,
            formatParts.isEmpty
                ? IkStrings.sourceUnknown
                : formatParts.join(' · '),
          ),
          if (_sourceExpanded) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1),
            ),
            if (widget.sourceStatus != null)
              widget.sourceStatus!
            else if (details?.note case final note?)
              Text(note, style: const TextStyle(fontSize: 12)),
            if (widget.song.platform != PlatformType.local &&
                widget.onQuality != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: widget.onQuality,
                  child: const Text(IkStrings.changeQuality),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _sourceValue(BuildContext context, String label, String value) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        flex: 4,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: VideoTheme.secondaryText(context),
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        flex: 6,
        child: Text(value, style: const TextStyle(fontSize: 12)),
      ),
    ],
  );

  Widget _compactSourceInfo(BuildContext context) {
    final details = widget.sourceDetails;
    final source = details?.sourceName?.trim();
    final format = details?.format?.trim();
    final formatParts = [
      if (format != null && format.isNotEmpty) format.toUpperCase(),
      if (details?.bitrate != null && details!.bitrate! > 0)
        '${(details.bitrate! / 1000).round()} kbps',
    ];
    final platform =
        '${widget.song.platform == PlatformType.local ? VideoStrings.localAudio : videoPlatformLabel(widget.song.platform)}${widget.isPreview ? VideoStrings.previewSuffix : ''}';
    return Column(
      key: const ValueKey('ik-player-source-inline'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(color: Theme.of(context).colorScheme.outlineVariant),
        Tooltip(
          message: _sourceExpanded
              ? IkPlayerAlignmentStrings.collapseSource
              : IkPlayerAlignmentStrings.expandSource,
          child: TextButton(
            key: const ValueKey('ik-player-source-expand'),
            onPressed: () => setState(() => _sourceExpanded = !_sourceExpanded),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$platform · ${source == null || source.isEmpty ? IkStrings.sourceUnknown : source}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  _sourceExpanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
        if (_sourceExpanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sourceValue(
                  context,
                  IkPlayerAlignmentStrings.songSource,
                  platform,
                ),
                const SizedBox(height: 8),
                _sourceValue(
                  context,
                  IkStrings.sourceName,
                  source == null || source.isEmpty
                      ? IkStrings.sourceUnknown
                      : source,
                ),
                const SizedBox(height: 8),
                _sourceValue(
                  context,
                  IkPlayerAlignmentStrings.audioFormat,
                  formatParts.isEmpty
                      ? IkStrings.sourceUnknown
                      : formatParts.join(' · '),
                ),
                const SizedBox(height: 12),
                if (widget.sourceStatus != null)
                  widget.sourceStatus!
                else if (details?.note case final note?)
                  Text(note, style: const TextStyle(fontSize: 12)),
                if (widget.song.platform != PlatformType.local &&
                    widget.onQuality != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: widget.onQuality,
                      child: const Text(IkStrings.changeQuality),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _alignedLyricsPane(BuildContext context, {bool compact = false}) =>
      Column(
        key: const ValueKey('ik-player-lyrics-pane'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!compact)
            Row(
              children: [
                const Text(
                  IkPlayerAlignmentStrings.lyrics,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 12),
                if (widget.lyrics.isNotEmpty && widget.timedLyrics)
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        _following
                            ? IkPlayerAlignmentStrings.following
                            : IkPlayerAlignmentStrings.browsing,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 12,
                          color: VideoTheme.secondaryText(context),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          if (!compact) const SizedBox(height: 4),
          if (compact)
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 12,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    IkPlayerAlignmentStrings.lyrics,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  _translationControl(context),
                  SizedBox(
                    width: math.min(190, constraints.maxWidth),
                    child: _lyricsSizeControl(context),
                  ),
                  if (widget.lyrics.isNotEmpty && widget.timedLyrics)
                    Text(
                      _following
                          ? IkPlayerAlignmentStrings.following
                          : IkPlayerAlignmentStrings.browsing,
                      style: TextStyle(
                        fontSize: 12,
                        color: VideoTheme.secondaryText(context),
                      ),
                    ),
                ],
              ),
            )
          else
            Row(
              children: [
                _translationControl(context),
                const SizedBox(width: 12),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 270),
                      child: _lyricsSizeControl(context),
                    ),
                  ),
                ),
              ],
            ),
          Expanded(child: _lyrics(context)),
        ],
      );

  Widget _translationControl(BuildContext context) => TextButton.icon(
    key: const ValueKey('ik-player-translation'),
    onPressed: widget.lyrics.any((line) => line.hasTranslation)
        ? () {
            setState(() => _showTranslation = !_showTranslation);
            if (!_following) _scheduleAutoResume();
            _follow();
          }
        : null,
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      foregroundColor: _showTranslation
          ? VideoTheme.accent(context)
          : VideoTheme.secondaryText(context),
    ),
    icon: Icon(
      _showTranslation ? Icons.check_rounded : Icons.translate_rounded,
      size: 17,
    ),
    label: const Text(
      IkPlayerAlignmentStrings.translation,
      style: TextStyle(fontSize: 12),
    ),
  );

  Widget _lyricsSizeControl(BuildContext context) => Row(
    children: [
      const Icon(Icons.text_fields_rounded, size: 19),
      Expanded(
        child: Tooltip(
          message: IkPlayerAlignmentStrings.lyricsSize,
          child: Listener(
            onPointerDown: widget.lyricsAutoResumeDelay == null
                ? null
                : (event) => _lyricsPointerStart(event.pointer),
            onPointerUp: widget.lyricsAutoResumeDelay == null
                ? null
                : (event) => _lyricsPointerEnd(event.pointer),
            onPointerCancel: widget.lyricsAutoResumeDelay == null
                ? null
                : (event) => _lyricsPointerEnd(event.pointer),
            child: Semantics(
              container: true,
              child: Slider(
                key: const ValueKey('ik-player-lyrics-size'),
                value: _lyricsFontSize,
                min: 16,
                max: 30,
                divisions: 7,
                label: '${_lyricsFontSize.round()}',
                semanticFormatterCallback: (value) =>
                    '${IkPlayerAlignmentStrings.lyricsSize} ${value.round()}',
                onChanged: widget.lyrics.isEmpty
                    ? null
                    : (value) {
                        setState(() => _lyricsFontSize = value);
                        if (!_following) _scheduleAutoResume();
                        _follow();
                      },
              ),
            ),
          ),
        ),
      ),
      Text('${_lyricsFontSize.round()}', style: const TextStyle(fontSize: 12)),
    ],
  );

  Widget _alignedTransport(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    child: Column(
      children: [
        if (widget.error != null || widget.isLoading)
          Text(
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
        Slider(
          value: widget.position.inMilliseconds.toDouble().clamp(
            0,
            math.max(1, widget.duration.inMilliseconds).toDouble(),
          ),
          max: math.max(1, widget.duration.inMilliseconds).toDouble(),
          onChanged: widget.isLoading || widget.duration <= Duration.zero
              ? null
              : (value) => widget.onSeek(Duration(milliseconds: value.round())),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(videoTime(widget.position)),
            Text(videoTime(widget.duration)),
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
              icon: const Icon(Icons.skip_previous_rounded),
            ),
            IconButton.filled(
              tooltip: widget.isPlaying
                  ? VideoStrings.pause
                  : VideoStrings.play,
              onPressed: widget.isLoading ? null : widget.onToggle,
              icon: widget.isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(widget.isPlaying ? Icons.pause : Icons.play_arrow),
            ),
            IconButton(
              tooltip: VideoStrings.nextSong,
              onPressed: widget.onNext,
              icon: const Icon(Icons.skip_next_rounded),
            ),
            IconButton(
              tooltip: IkStrings.nextUp,
              onPressed: widget.onQueue,
              icon: const Icon(Icons.queue_music_rounded),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _page(BuildContext context) => Scaffold(
    backgroundColor: VideoTheme.canvas(context),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
        child: Column(
          children: [
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  label: const Text(WindowsMusicStrings.back),
                ),
                const Spacer(),
                if (widget.onDesktopLyrics != null)
                  TextButton.icon(
                    onPressed: widget.onDesktopLyrics,
                    icon: Icon(
                      Icons.subtitles_outlined,
                      size: 20,
                      color: widget.desktopLyricsEnabled
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    label: const Text(IkStrings.floating),
                  ),
              ],
            ),
            if (widget.sourceStatus != null &&
                Theme.of(context).extension<IkThemeColors>() == null)
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
            if (Theme.of(context).extension<IkThemeColors>() != null)
              _sourceCard(context)
            else
              TextButton(
                onPressed: widget.song.platform == PlatformType.local
                    ? null
                    : widget.onQuality,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    WindowsPlatformIcon(
                      platform: widget.song.platform,
                      size: 18,
                    ),
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
            if (widget.playbackBar == null) ...[
              SliderTheme(
                data: SliderTheme.of(context).copyWith(trackHeight: 3),
                child: Slider(
                  value: widget.position.inMilliseconds.toDouble().clamp(
                    0,
                    math.max(1, widget.duration.inMilliseconds).toDouble(),
                  ),
                  max: math.max(1, widget.duration.inMilliseconds).toDouble(),
                  onChanged:
                      widget.isLoading || widget.duration <= Duration.zero
                      ? null
                      : (value) => widget.onSeek(
                          Duration(milliseconds: value.round()),
                        ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    videoTime(widget.position),
                    style: TextStyle(
                      fontSize:
                          Theme.of(context).extension<IkThemeColors>() == null
                          ? 11
                          : 12,
                    ),
                  ),
                  Text(
                    videoTime(widget.duration),
                    style: TextStyle(
                      fontSize:
                          Theme.of(context).extension<IkThemeColors>() == null
                          ? 11
                          : 12,
                    ),
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
            ] else
              widget.playbackBar!,
          ],
        ),
      ),
    ),
  );

  Widget _sourceCard(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Material(
      color: VideoTheme.surface(context),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('ik-source-card'),
        onTap: () => _showSourceDetails(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              WindowsPlatformIcon(platform: widget.song.platform, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      IkStrings.sourceDetails,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${widget.sourceDetails == null ? videoPlatformLabel(widget.song.platform) : widget.sourceDetails!.sourceName ?? IkStrings.sourceUnknown} · ${widget.qualityLabel ?? VideoStrings.qualityUnknown}${widget.isPreview ? VideoStrings.previewSuffix : ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: VideoTheme.secondaryText(context),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 20),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _showSourceDetails(BuildContext context) => showDialog<void>(
    context: context,
    builder: (dialog) {
      final details = widget.sourceDetails;
      return AlertDialog(
        title: const Text(IkStrings.sourceDetails),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${videoPlatformLabel(widget.song.platform)} · ${widget.qualityLabel ?? VideoStrings.qualityUnknown}',
              ),
              if (details != null) ...[
                const SizedBox(height: 16),
                Text(
                  '${IkStrings.sourceName}：${details.sourceName ?? IkStrings.sourceUnknown}',
                ),
                Text(
                  '${IkStrings.sourceFormat}：${details.format?.toUpperCase() ?? IkStrings.sourceUnknown}',
                ),
                Text(
                  '${IkStrings.sourceBitrate}：${details.bitrate != null && details.bitrate! > 0 ? '${(details.bitrate! / 1000).round()} kbps' : IkStrings.sourceUnknown}',
                ),
                if (details.note case final note?) ...[
                  const SizedBox(height: 12),
                  Text(note),
                ],
              ],
              if (widget.sourceStatus != null) ...[
                const SizedBox(height: 16),
                widget.sourceStatus!,
              ],
            ],
          ),
        ),
        actions: [
          if (widget.song.platform != PlatformType.local &&
              widget.onQuality != null)
            TextButton(
              onPressed: () {
                Navigator.pop(dialog);
                widget.onQuality!();
              },
              child: const Text(IkStrings.changeQuality),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text(IkStrings.close),
          ),
        ],
      );
    },
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
      final empty = Column(
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
      );
      return Center(
        child: widget.alignToDesign
            ? SingleChildScrollView(child: empty)
            : empty,
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
              onPointerDown: (event) {
                _lyricsFocus.requestFocus();
                if (widget.lyricsAutoResumeDelay != null) {
                  _lyricsPointerStart(event.pointer);
                }
              },
              onPointerUp: widget.lyricsAutoResumeDelay == null
                  ? null
                  : (event) => _lyricsPointerEnd(event.pointer),
              onPointerCancel: widget.lyricsAutoResumeDelay == null
                  ? null
                  : (event) => _lyricsPointerEnd(event.pointer),
              onPointerSignal: (event) {
                if (widget.lyricsAutoResumeDelay == null ||
                    event is PointerScrollEvent) {
                  _pauseFollow();
                }
              },
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if ((notification is UserScrollNotification &&
                          notification.direction != ScrollDirection.idle) ||
                      (notification is ScrollUpdateNotification &&
                          notification.dragDetails != null) ||
                      (widget.lyricsAutoResumeDelay != null &&
                          notification is ScrollStartNotification &&
                          notification.dragDetails != null)) {
                    if (widget.lyricsAutoResumeDelay != null) {
                      _manualScrollActive = true;
                    }
                    _pauseFollow();
                  } else if (notification is ScrollEndNotification &&
                      _manualScrollActive) {
                    _manualScrollActive = false;
                    _scheduleAutoResume();
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
                            onTap:
                                widget.timedLyrics &&
                                    (!widget.alignToDesign ||
                                        (!widget.isLoading &&
                                            !widget.lyricsLoading &&
                                            widget.duration > Duration.zero))
                                ? () {
                                    if (widget.alignToDesign) {
                                      _cancelAutoResume();
                                      _manualScrollActive = false;
                                      setState(() => _following = true);
                                    }
                                    widget.onSeek(widget.lyrics[i].timestamp);
                                    if (widget.alignToDesign) _follow();
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
                                      fontSize: widget.alignToDesign
                                          ? _lyricsFontSize *
                                                (!widget.timedLyrics ||
                                                        i == _active
                                                    ? 1
                                                    : 18 / 22)
                                          : 22,
                                      height: 1.6,
                                      fontWeight: i == _active
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: i == _active
                                          ? VideoTheme.accent(context)
                                          : Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withValues(alpha: .62),
                                    ),
                                  ),
                                  if (widget.lyrics[i].hasTranslation &&
                                      (!widget.alignToDesign ||
                                          _showTranslation))
                                    Text(
                                      widget.lyrics[i].translation!,
                                      style: TextStyle(
                                        fontSize: widget.alignToDesign
                                            ? _lyricsFontSize * 13 / 22
                                            : 13,
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
              onPressed: _resumeFollow,
              icon: const Icon(Icons.my_location_outlined, size: 16),
              label: const Text(WindowsMusicStrings.returnToLyrics),
            ),
          ),
      ],
    );
  }
}

/// 从已缓存封面取色，仅用于新版播放器；失败时保留基础主题。
class IkCoverTheme extends StatefulWidget {
  const IkCoverTheme({super.key, required this.cover, required this.child});
  final ImageProvider? cover;
  final Widget child;

  @override
  State<IkCoverTheme> createState() => _IkCoverThemeState();
}

class _IkCoverThemeState extends State<IkCoverTheme> {
  ColorScheme? _scheme;
  Brightness? _brightness;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (_brightness != brightness) {
      _brightness = brightness;
      unawaited(_load());
    }
  }

  @override
  void didUpdateWidget(IkCoverTheme oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cover != widget.cover) unawaited(_load());
  }

  Future<void> _load() async {
    final generation = ++_generation;
    _scheme = null;
    final cover = widget.cover;
    if (cover == null) return;
    ColorScheme? scheme;
    try {
      scheme = await ColorScheme.fromImageProvider(
        provider: cover,
        brightness: _brightness!,
      );
    } catch (_) {
      // 封面不可读不阻断播放，也不保留上一首的颜色。
    }
    if (!mounted || generation != _generation) return;
    setState(() => _scheme = scheme);
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final scheme = _scheme;
    final palette = base.extension<IkThemeColors>();
    if (scheme == null || palette == null) return widget.child;
    return Theme(
      data: base.copyWith(
        colorScheme: scheme,
        extensions: [
          ...base.extensions.values.where((value) => value is! IkThemeColors),
          palette.copyWith(
            background: scheme.surface,
            surface: scheme.surfaceContainerLow,
          ),
        ],
      ),
      child: widget.child,
    );
  }
}

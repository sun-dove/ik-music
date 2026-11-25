import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/lyrics/models/lyrics_line.dart';
import 'package:mconnect/l10n/video_strings.dart';
import 'package:mconnect/models/album.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/video_app/ik/ik_workspace_theme.dart';
import 'package:mconnect/video_app/ui/video_shell.dart';
import 'package:mconnect/video_app/ui/video_theme.dart';
import 'package:mconnect/video_app/windows/windows_player_page.dart';

const _baseline = bool.fromEnvironment('IK_PLAYER_ALIGNMENT_BASELINE');
const _song = Song(
  id: 'alignment-player',
  platform: PlatformType.qq,
  name: '需要完整显示但不能撑乱页面的很长很长歌曲标题与现场录音说明',
  artists: [Artist(id: 'real-artist', name: '真实歌手')],
  album: Album(id: 'real-album', name: '真实专辑'),
);
const _lines = [
  LyricsLine(
    timestamp: Duration.zero,
    text: '第一句歌词',
    translation: 'First line',
  ),
  LyricsLine(
    timestamp: Duration(seconds: 10),
    text: '当前句歌词',
    translation: 'Current line',
  ),
  LyricsLine(timestamp: Duration(seconds: 20), text: '最后一句歌词'),
];

Widget _player({
  bool aligned = true,
  Song song = _song,
  bool loading = false,
  String? qualityLabel,
  bool preview = false,
  Duration duration = const Duration(minutes: 4),
  Duration position = const Duration(seconds: 12),
  List<LyricsLine> lines = _lines,
  bool timed = true,
  bool lyricsLoading = false,
  String? lyricsError,
  String? playbackError,
  bool sharedPlaybackBar = true,
  VoidCallback? retryLyrics,
  VoidCallback? artist,
  VoidCallback? album,
  VoidCallback? desktopLyrics,
  ValueChanged<Duration>? seek,
  WindowsSourceDetails? details = const WindowsSourceDetails(
    sourceName: '真实备用源',
    format: 'flac',
    bitrate: 900000,
    note: '当前使用备用音源',
  ),
  Widget? sourceStatus,
}) => WindowsPlayerPage(
  song: song,
  position: position,
  duration: duration,
  isPlaying: !loading,
  isLoading: loading,
  qualityLabel: qualityLabel,
  isPreview: preview,
  error: playbackError,
  lyrics: lines,
  timedLyrics: timed,
  lyricsLoading: lyricsLoading,
  lyricsError: lyricsError,
  onLyricsRetry: retryLyrics,
  onToggle: () {},
  onPrevious: () {},
  onNext: () {},
  onSeek: seek ?? (_) {},
  onQueue: () {},
  onMode: () {},
  onQuality: () {},
  sourceDetails: details,
  sourceStatus: sourceStatus ?? const Text('完整尝试记录'),
  playbackBar: sharedPlaybackBar
      ? SizedBox(
          key: const ValueKey('alignment-shared-playback'),
          height: 90,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (playbackError != null) Text(playbackError),
              const Text('统一播放栏'),
            ],
          ),
        )
      : null,
  alignToDesign: aligned && !_baseline,
  onArtist: artist,
  onAlbum: album,
  onDesktopLyrics: desktopLyrics,
);

Future<void> _mount(
  WidgetTester tester,
  Widget player, {
  Size size = const Size(1200, 800),
  double scale = 1,
  bool dark = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    MaterialApp(
      theme: IkWorkspaceTheme.from(dark ? VideoTheme.dark : VideoTheme.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: player,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('A04 截图收口：来源不重复格式码率，试听和本地身份保留', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mount(
      tester,
      _player(qualityLabel: 'FLAC · 900 kbps', preview: true),
    );
    expect(find.textContaining('FLAC · 900 kbps'), findsOneWidget);
    expect(find.text('QQ 音乐${VideoStrings.previewSuffix}'), findsOneWidget);
    await _mount(
      tester,
      _player(
        song: const Song(
          id: 'local',
          platform: PlatformType.local,
          name: '本地',
          artists: [],
        ),
        qualityLabel: VideoStrings.localAudio,
      ),
    );
    expect(find.text(VideoStrings.localAudio), findsOneWidget);
  });

  testWidgets('A04 截图收口：歌词字号工具靠右且滑杆不超过240宽', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mount(tester, _player());
    final slider = find.byKey(const ValueKey('ik-player-lyrics-size'));
    final translation = find.byKey(const ValueKey('ik-player-translation'));
    final pane = find.byKey(const ValueKey('ik-player-lyrics-pane'));
    expect(tester.getSize(slider).width, lessThanOrEqualTo(240));
    expect(
      tester.getRect(slider).right,
      greaterThan(tester.getRect(pane).right - 50),
    );
    expect(
      tester.getRect(slider).left - tester.getRect(translation).right,
      greaterThan(200),
    );
    await _mount(tester, _player(), size: const Size(320, 800), scale: 1.5);
    expect(slider.hitTestable(), findsOneWidget);
    expect(tester.getSize(slider).width, greaterThan(60));
    expect(tester.takeException(), isNull);
  });

  testWidgets('A04 原稿视觉：宽版信息与封面居中，淡竖线分区，窄版保持左对齐', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const song = Song(
      id: 'centered-song',
      platform: PlatformType.qq,
      name: '短歌名',
      artists: [Artist(id: 'real-artist', name: '真实歌手')],
      album: Album(id: 'real-album', name: '真实专辑'),
    );
    await _mount(tester, _player(song: song, artist: () {}, album: () {}));
    final center = tester.getCenter(find.byType(VideoCover)).dx;
    for (final text in ['短歌名', '真实歌手', '真实专辑']) {
      expect(tester.getCenter(find.text(text)).dx, closeTo(center, .5));
      expect(tester.widget<Text>(find.text(text)).textAlign, TextAlign.center);
    }
    final dividerFinder = find.byKey(const ValueKey('ik-player-divider'));
    expect(dividerFinder, findsOneWidget);
    final divider = tester.widget<VerticalDivider>(dividerFinder);
    expect(divider.thickness, lessThanOrEqualTo(1));
    expect(divider.color!.a, inExclusiveRange(0, 1));
    expect(
      tester.getCenter(dividerFinder).dx,
      greaterThan(
        tester
            .getRect(find.byKey(const ValueKey('ik-player-source-inline')))
            .right,
      ),
    );
    expect(
      tester.getCenter(dividerFinder).dx,
      lessThan(
        tester
            .getRect(find.byKey(const ValueKey('ik-player-lyrics-pane')))
            .left,
      ),
    );
    await _mount(tester, _player(song: song), size: const Size(320, 800));
    expect(dividerFinder, findsNothing);
    expect(
      tester.widget<Text>(find.text(song.name)).textAlign,
      TextAlign.start,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('A04 原稿视觉：当前歌词突出，其他行和译文随字号同比缩放', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mount(tester, _player());
    double? font(String text) =>
        tester.widget<Text>(find.text(text)).style?.fontSize;
    expect(font('当前句歌词'), 22);
    expect(font('第一句歌词'), 18);
    expect(font('最后一句歌词'), 18);
    expect(font('Current line'), 13);
    tester
        .widget<Slider>(find.byKey(const ValueKey('ik-player-lyrics-size')))
        .onChanged!(26);
    await tester.pumpAndSettle();
    expect(font('当前句歌词'), 26);
    expect(font('第一句歌词'), closeTo(26 * 18 / 22, .001));
    expect(font('Current line'), closeTo(26 * 13 / 22, .001));
    await _mount(tester, _player(position: const Duration(seconds: 20)));
    expect(font('最后一句歌词'), 26);
    expect(font('当前句歌词'), closeTo(26 * 18 / 22, .001));
    await _mount(tester, _player(timed: false));
    expect(font('第一句歌词'), 26);
    expect(font('当前句歌词'), 26);
    await _mount(tester, _player(aligned: false));
    expect(font('第一句歌词'), 22);
    expect(font('当前句歌词'), 22);
    expect(font('Current line'), 13);
  });

  testWidgets('A04 来源信息位于封面下，原位展开不弹窗，旧缺省仍用原弹窗', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mount(tester, _player());
    final metadata = find.byKey(const ValueKey('ik-player-metadata'));
    final source = find.byKey(const ValueKey('ik-player-source-inline'));
    final lyricPane = find.byKey(const ValueKey('ik-player-lyrics-pane'));
    expect(metadata, findsOneWidget);
    expect(source, findsOneWidget);
    expect(
      tester.getTopLeft(source).dy,
      greaterThan(tester.getBottomLeft(metadata).dy),
    );
    expect(
      tester.getRect(source).right,
      lessThan(tester.getRect(lyricPane).left),
    );
    expect(find.text('真实备用源'), findsOneWidget);
    expect(find.text('FLAC · 900 kbps'), findsOneWidget);
    expect(find.text('完整尝试记录'), findsNothing);
    await tester.ensureVisible(
      find.byKey(const ValueKey('ik-player-source-expand')),
    );
    await tester.tap(find.byKey(const ValueKey('ik-player-source-expand')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('完整尝试记录'), findsOneWidget);
    expect(find.text('当前使用备用音源'), findsNothing);
    expect(
      find.byKey(const ValueKey('alignment-shared-playback')),
      findsOneWidget,
    );
    await _mount(tester, _player(aligned: false));
    expect(find.byKey(const ValueKey('ik-player-source-inline')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('ik-source-card')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('A04 歌手专辑只按真实ID与回调启用，长标题最多两行', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var artists = 0;
    var albums = 0;
    await _mount(
      tester,
      _player(artist: () => artists++, album: () => albums++),
    );
    expect(tester.widget<Text>(find.text(_song.name)).maxLines, 2);
    await tester.tap(find.byKey(const ValueKey('ik-player-artist')));
    await tester.tap(find.byKey(const ValueKey('ik-player-album')));
    expect([artists, albums], [1, 1]);
    await _mount(
      tester,
      _player(
        song: const Song(
          id: 'local-detail',
          platform: PlatformType.local,
          name: '本地曲目',
          artists: [Artist(id: 'tag-only', name: '标签歌手')],
          album: Album(id: 'tag-only', name: '标签专辑'),
        ),
        artist: () => artists++,
        album: () => albums++,
      ),
    );
    expect(find.byKey(const ValueKey('ik-player-artist')), findsNothing);
    expect(find.byKey(const ValueKey('ik-player-album')), findsNothing);
    expect([artists, albums], [1, 1]);
    await _mount(
      tester,
      _player(
        song: const Song(
          id: 'missing-detail',
          platform: PlatformType.qq,
          name: '缺标识',
          artists: [Artist(id: '', name: '同名歌手')],
          album: Album(id: '', name: '同名专辑'),
        ),
        artist: () => artists++,
        album: () => albums++,
      ),
    );
    expect(find.byKey(const ValueKey('ik-player-artist')), findsNothing);
    expect(find.byKey(const ValueKey('ik-player-album')), findsNothing);
    expect(find.text('同名歌手'), findsOneWidget);
    expect(find.text('同名专辑'), findsOneWidget);
    expect([artists, albums], [1, 1]);
  });

  testWidgets('A04 歌词字号和翻译即时生效，点击定位恢复跟随，切歌中禁止定位', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final seeks = <Duration>[];
    await _mount(tester, _player(seek: seeks.add));
    expect(find.text('Current line'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ik-player-translation')));
    await tester.pumpAndSettle();
    expect(find.text('Current line'), findsNothing);
    final sizeControl = tester.widget<Slider>(
      find.byKey(const ValueKey('ik-player-lyrics-size')),
    );
    sizeControl.onChanged!(26);
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.text('当前句歌词')).style?.fontSize, 26);
    final focus = tester.widget<Focus>(
      find.byKey(const ValueKey('windows-lyrics-focus')),
    );
    focus.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    expect(find.text('正在浏览歌词'), findsOneWidget);
    await tester.ensureVisible(find.text('最后一句歌词'));
    await tester.tap(find.text('最后一句歌词'));
    await tester.pumpAndSettle();
    expect(seeks, [const Duration(seconds: 20)]);
    expect(find.text('跟随播放'), findsOneWidget);
    await _mount(tester, _player(loading: true, seek: seeks.add));
    await tester.tap(find.text('当前句歌词'));
    expect(seeks, [const Duration(seconds: 20)]);
    await _mount(tester, _player(duration: Duration.zero, seek: seeks.add));
    await tester.tap(find.text('当前句歌词'));
    expect(seeks, [const Duration(seconds: 20)]);
    await _mount(tester, _player(lyricsLoading: true, seek: seeks.add));
    await tester.tap(find.text('当前句歌词'));
    expect(seeks, [const Duration(seconds: 20)]);
    await _mount(tester, _player(timed: false, seek: seeks.add));
    await tester.tap(find.text('当前句歌词'));
    expect(seeks, [const Duration(seconds: 20)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A04 来源未知不推断格式，错误和重试保持真实，歌词空态有明确区别', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var retries = 0;
    await _mount(
      tester,
      _player(details: const WindowsSourceDetails(), playbackError: '网络已断开'),
    );
    expect(find.text('尚未确认'), findsNWidgets(2));
    expect(find.text('网络已断开'), findsOneWidget);
    expect(find.textContaining('kbps'), findsNothing);
    await _mount(
      tester,
      _player(sharedPlaybackBar: false, playbackError: '独立播放失败'),
    );
    expect(find.text('独立播放失败'), findsOneWidget);
    expect(find.byTooltip('暂停').hitTestable(), findsOneWidget);
    await _mount(tester, _player(lines: const [], lyricsLoading: true));
    expect(find.text('正在加载歌词…'), findsOneWidget);
    await _mount(tester, _player(lines: const []));
    expect(find.text('暂无歌词'), findsOneWidget);
    await _mount(
      tester,
      _player(
        lines: const [],
        lyricsError: '歌词加载失败',
        retryLyrics: () => retries++,
      ),
    );
    expect(find.text('歌词加载失败'), findsOneWidget);
    await tester.tap(find.text('重试'));
    expect(retries, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A04 同名不同ID切歌重新跟随，歌词迟到和长句滚动保持定位', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final longLines = List.generate(
      40,
      (index) => LyricsLine(
        timestamp: Duration(seconds: 5 + index * 10),
        text: '第$index句：这一句很长，需要依据真实换行后的布局定位歌词，不能依赖固定行高。',
      ),
    );
    await _mount(
      tester,
      _player(position: const Duration(seconds: 205), lines: longLines),
    );
    final scroller = find.byKey(const ValueKey('windows-lyrics-scroll'));
    expect(
      tester
          .getRect(scroller)
          .contains(tester.getCenter(find.text(longLines[20].text))),
      isTrue,
    );
    await tester.drag(scroller, const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(find.text('正在浏览歌词'), findsOneWidget);
    await _mount(
      tester,
      _player(
        song: Song(
          id: 'same-name-new-id',
          platform: PlatformType.qq,
          name: _song.name,
          artists: _song.artists,
        ),
        position: Duration.zero,
        lines: longLines,
      ),
    );
    expect(find.text('跟随播放'), findsOneWidget);
    expect(
      tester
          .getRect(scroller)
          .contains(tester.getCenter(find.text(longLines.first.text))),
      isTrue,
    );
    await _mount(tester, _player(lines: const [], lyricsLoading: true));
    await _mount(
      tester,
      _player(position: const Duration(seconds: 205), lines: longLines),
    );
    expect(
      tester
          .getRect(scroller)
          .contains(tester.getCenter(find.text(longLines[20].text))),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('A07 播放详情两主题六宽三字号完整36布局组合', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var combinations = 0;
    for (final dark in [false, true]) {
      for (final width in [320.0, 390.0, 720.0, 900.0, 1200.0, 1440.0]) {
        for (final scale in [1.0, 1.25, 1.5]) {
          await _mount(
            tester,
            _player(desktopLyrics: () {}),
            size: Size(width, width == 900 ? 600 : 800),
            scale: scale,
            dark: dark,
          );
          expect(tester.takeException(), isNull, reason: '$dark/$width/$scale');
          expect(
            find.byKey(const ValueKey('ik-player-lyrics-pane')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('ik-player-source-inline')),
            findsOneWidget,
          );
          expect(find.text('统一播放栏').hitTestable(), findsOneWidget);
          expect(find.text('桌面歌词').hitTestable(), findsOneWidget);
          expect(
            find.byKey(const ValueKey('ik-player-translation')).hitTestable(),
            findsOneWidget,
          );
          combinations++;
        }
      }
    }
    expect(combinations, 36);
  });

  testWidgets('A07 320宽150%长来源行内展开可滚动，歌词与底栏不被挤出', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mount(
      tester,
      _player(
        desktopLyrics: () {},
        details: const WindowsSourceDetails(
          sourceName: '这是很长的音源名称用于检验窄窗口和大字体',
          format: 'flac',
          bitrate: 900000,
        ),
        sourceStatus: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(
            12,
            (index) => Text('第$index次尝试：当前音源暂不可用，保留真实失败原因供查看。'),
          ),
        ),
      ),
      size: const Size(320, 600),
      scale: 1.5,
    );
    final expand = find.byKey(const ValueKey('ik-player-source-expand'));
    final scrollHint = find.byKey(
      const ValueKey('ik-player-information-scrollbar'),
    );
    expect(scrollHint, findsOneWidget);
    expect(tester.widget<Scrollbar>(scrollHint).thumbVisibility, isTrue);
    expect(
      tester.widget<Scrollbar>(scrollHint).controller!.position.maxScrollExtent,
      greaterThan(0),
    );
    await tester.ensureVisible(expand);
    await tester.tap(expand);
    await tester.pumpAndSettle();
    final lastAttempt = find.text('第11次尝试：当前音源暂不可用，保留真实失败原因供查看。');
    await tester.ensureVisible(lastAttempt);
    await tester.pumpAndSettle();
    expect(lastAttempt.hitTestable(), findsOneWidget);
    expect(find.text('统一播放栏').hitTestable(), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ik-player-translation')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

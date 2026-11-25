import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/lyrics/models/lyrics_line.dart';
import 'package:mconnect/models/album.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/video_app/ik/ik_workspace_theme.dart';
import 'package:mconnect/video_app/ui/video_shell.dart';
import 'package:mconnect/video_app/ui/video_theme.dart';
import 'package:mconnect/video_app/windows/windows_player_page.dart';

const _song = Song(
  id: 'compact-player',
  platform: PlatformType.qq,
  name: '需要完整显示但不能撑乱页面的很长歌曲标题与现场录音说明',
  artists: [Artist(id: 'artist-id', name: '真实歌手')],
  album: Album(id: 'album-id', name: '真实专辑'),
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
  bool compact = true,
  bool aligned = true,
  List<LyricsLine> lyrics = _lines,
  Duration position = const Duration(seconds: 12),
  bool lyricsLoading = false,
  String? lyricsError,
  VoidCallback? lyricsRetry,
  VoidCallback? artist,
  VoidCallback? album,
  VoidCallback? desktop,
  VoidCallback? quality,
  ValueChanged<Duration>? seek,
  WindowsSourceDetails? details = const WindowsSourceDetails(
    sourceName: '真实备用源',
    format: 'flac',
    bitrate: 900000,
  ),
  Widget? sourceStatus,
}) => WindowsPlayerPage(
  alignToDesign: aligned,
  compactLayout: compact,
  lyricsAutoResumeDelay: const Duration(seconds: 3),
  song: _song,
  position: position,
  duration: const Duration(minutes: 4),
  isPlaying: true,
  lyrics: lyrics,
  lyricsLoading: lyricsLoading,
  lyricsError: lyricsError,
  onLyricsRetry: lyricsRetry,
  onToggle: () {},
  onPrevious: () {},
  onNext: () {},
  onSeek: seek ?? (_) {},
  onQueue: () {},
  onMode: () {},
  onArtist: artist,
  onAlbum: album,
  onDesktopLyrics: desktop,
  onQuality: quality,
  sourceDetails: details,
  sourceStatus: sourceStatus ?? const Text('完整尝试记录'),
  playbackBar: const SizedBox(
    key: ValueKey('compact-shared-playback'),
    height: 80,
    child: Center(child: Text('统一播放栏')),
  ),
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
  testWidgets('E06 1920独立详情封面放大且歌词靠近，内容不过度拉散', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mount(tester, _player(), size: const Size(1920, 1080));
    final cover = tester.getRect(find.byType(VideoCover));
    final lyrics = tester.getRect(
      find.byKey(const ValueKey('ik-player-lyrics-pane')),
    );
    expect(cover.width, closeTo(420, .001));
    expect(lyrics.left - cover.right, inInclusiveRange(24, 80));
    expect(lyrics.right - cover.left, lessThanOrEqualTo(1240));
    expect(find.byKey(const ValueKey('ik-player-divider')), findsNothing);
    final translation = tester.getRect(
      find.byKey(const ValueKey('ik-player-translation')),
    );
    final size = tester.getRect(
      find.byKey(const ValueKey('ik-player-lyrics-size')),
    );
    expect((translation.center.dy - size.center.dy).abs(), lessThan(2));
    expect(size.left - translation.right, inInclusiveRange(0, 40));
    expect(find.text('统一播放栏').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('E06 旧缺省仍保留原封面和竖分隔，未对齐入口不启用紧凑排版', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mount(tester, _player(compact: false), size: const Size(1920, 1080));
    expect(tester.getSize(find.byType(VideoCover)).width, 330);
    expect(find.byKey(const ValueKey('ik-player-divider')), findsOneWidget);
    await _mount(tester, _player(aligned: false));
    expect(find.byKey(const ValueKey('windows-player-wide')), findsOneWidget);
    expect(find.byKey(const ValueKey('ik-player-lyrics-pane')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('E06 来源收为简明一行，展开保留真实来源与未知音质及操作', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var quality = 0;
    await _mount(
      tester,
      _player(
        quality: () => quality++,
        details: const WindowsSourceDetails(sourceName: '真实备用源'),
      ),
    );
    final source = find.byKey(const ValueKey('ik-player-source-inline'));
    expect(tester.getSize(source).height, lessThanOrEqualTo(76));
    expect(find.textContaining('真实备用源'), findsOneWidget);
    expect(find.text('完整尝试记录'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('ik-player-source-expand')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('完整尝试记录'), findsOneWidget);
    expect(find.text('尚未确认'), findsOneWidget);
    expect(find.textContaining('kbps'), findsNothing);
    await tester.ensureVisible(find.text('调整音质'));
    await tester.tap(find.text('调整音质'));
    expect(quality, 1);
    expect(find.text('统一播放栏').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('E06 歌手专辑、桌面歌词、翻译字号与歌词定位继续可用', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var artists = 0;
    var albums = 0;
    var desktops = 0;
    final seeks = <Duration>[];
    await _mount(
      tester,
      _player(
        artist: () => artists++,
        album: () => albums++,
        desktop: () => desktops++,
        seek: seeks.add,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('ik-player-artist')));
    await tester.tap(find.byKey(const ValueKey('ik-player-album')));
    await tester.tap(find.text('桌面歌词'));
    expect([artists, albums, desktops], [1, 1, 1]);
    await tester.tap(find.byKey(const ValueKey('ik-player-translation')));
    await tester.pumpAndSettle();
    expect(find.text('Current line'), findsNothing);
    tester
        .widget<Slider>(find.byKey(const ValueKey('ik-player-lyrics-size')))
        .onChanged!(26);
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.text('当前句歌词')).style?.fontSize, 26);
    await tester.tap(find.text('最后一句歌词'));
    expect(seeks, [const Duration(seconds: 20)]);
    expect(tester.widget<Text>(find.text(_song.name)).maxLines, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('E06 紧凑歌词真实滚轮浏览三秒回最新行且不改变播放进度', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final lyrics = List.generate(
      60,
      (i) => LyricsLine(
        timestamp: Duration(seconds: i * 10),
        text: '第$i句很长的歌词，按真实换行位置定位当前播放内容。',
      ),
    );
    final seeks = <Duration>[];
    await _mount(
      tester,
      _player(
        lyrics: lyrics,
        position: const Duration(seconds: 205),
        seek: seeks.add,
      ),
    );
    final scroll = find.byKey(const ValueKey('windows-lyrics-scroll'));
    await tester.sendEventToBinding(
      PointerScrollEvent(
        kind: PointerDeviceKind.mouse,
        position: tester.getCenter(scroll),
        scrollDelta: const Offset(0, -500),
      ),
    );
    await tester.pump();
    expect(find.text('正在浏览歌词'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2900));
    expect(find.text('正在浏览歌词'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('跟随播放'), findsOneWidget);
    expect(
      tester
          .getRect(scroll)
          .contains(tester.getCenter(find.text(lyrics[20].text))),
      isTrue,
    );
    expect(seeks, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('E06 紧凑歌词加载空态及失败重试保持可见', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mount(tester, _player(lyrics: const [], lyricsLoading: true));
    expect(find.text('正在加载歌词…').hitTestable(), findsOneWidget);
    await _mount(tester, _player(lyrics: const []));
    expect(find.text('暂无歌词').hitTestable(), findsOneWidget);
    var retries = 0;
    await _mount(
      tester,
      _player(
        lyrics: const [],
        lyricsError: '歌词加载失败',
        lyricsRetry: () => retries++,
      ),
      size: const Size(320, 600),
      scale: 1.5,
    );
    expect(find.text('歌词加载失败').hitTestable(), findsOneWidget);
    await tester.tap(find.text('重试'));
    expect(retries, 1);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    for (final width in [320.0, 390.0, 720.0, 900.0, 1200.0, 1440.0, 1920.0]) {
      for (final scale in [1.0, 1.25, 1.5]) {
        testWidgets('E08 紧凑播放器${dark ? '深' : '浅'}色${width.toInt()}宽$scale字号', (
          tester,
        ) async {
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await _mount(
            tester,
            _player(desktop: () {}),
            size: Size(width, width == 900 ? 600 : 800),
            scale: scale,
            dark: dark,
          );
          expect(tester.takeException(), isNull);
          expect(find.text('统一播放栏').hitTestable(), findsOneWidget);
          expect(find.text('桌面歌词').hitTestable(), findsOneWidget);
          expect(find.text(_song.name).hitTestable(), findsOneWidget);
          expect(
            find.byKey(const ValueKey('ik-player-translation')).hitTestable(),
            findsOneWidget,
          );
          final pane = tester.getRect(
            find.byKey(const ValueKey('ik-player-lyrics-pane')),
          );
          expect(pane.height, greaterThan(150));
          expect(pane.left, greaterThanOrEqualTo(0));
          expect(pane.right, lessThanOrEqualTo(width));
          expect(
            find.byKey(const ValueKey('compact-shared-playback')),
            findsOneWidget,
          );
        });
      }
    }
  }

  testWidgets('E08 窄窗大字号展开长音源记录仍可读完且不挤走歌词和底栏', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mount(
      tester,
      _player(
        desktop: () {},
        sourceStatus: Column(
          children: List.generate(12, (i) => Text('第$i次尝试：当前音源暂不可用，保留真实失败原因。')),
        ),
        details: const WindowsSourceDetails(sourceName: '这是很长的音源名称用于检验窄窗口和大字体'),
      ),
      size: const Size(320, 600),
      scale: 1.5,
    );
    final expand = find.byKey(const ValueKey('ik-player-source-expand'));
    await tester.ensureVisible(expand);
    await tester.tap(expand);
    await tester.pumpAndSettle();
    final last = find.text('第11次尝试：当前音源暂不可用，保留真实失败原因。');
    await tester.ensureVisible(last);
    await tester.pumpAndSettle();
    expect(last.hitTestable(), findsOneWidget);
    expect(find.text('统一播放栏').hitTestable(), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ik-player-translation')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

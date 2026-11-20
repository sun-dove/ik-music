import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/lyrics/models/lyrics_line.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/video_app/ui/my_page.dart';
import 'package:mconnect/video_app/ui/player_page.dart';
import 'package:mconnect/video_app/ui/video_theme.dart';
import 'package:mconnect/video_app/windows/windows_my_page.dart';
import 'package:mconnect/video_app/windows/windows_player_page.dart';
import 'package:flutter/services.dart';

const baseline = bool.fromEnvironment('LEYIN_BASELINE');

const song = Song(
  id: 'windows-gate',
  platform: PlatformType.qq,
  name: '桌面验收曲目',
  artists: [Artist(id: 'artist', name: '验收歌手')],
);
const lines = [
  LyricsLine(timestamp: Duration(seconds: 5), text: '第一句歌词'),
  LyricsLine(timestamp: Duration(seconds: 10), text: '当前句歌词'),
  LyricsLine(timestamp: Duration(seconds: 20), text: '下一句歌词'),
];

Widget settingsPage({VoidCallback? play, VoidCallback? download}) {
  final legacy = VideoMyPage(
    platforms: const [
      PlatformType.qq,
      PlatformType.netease,
      PlatformType.kugou,
    ],
    accounts: const {},
    cacheLabel: '0 MB',
    downloadLabel: '0 项',
    themeLabel: '浅色',
    onAccount: (_) {},
    onQuality: (_, isDownload) => (isDownload ? download : play)?.call(),
    onCache: () {},
    onDownloads: () {},
    onDirectory: () {},
    onTheme: () {},
    onLocal: () {},
  );
  return baseline
      ? legacy
      : WindowsMyPage(
          settings: legacy,
          playQuality: '沿用原设置',
          downloadQuality: '标准',
          onQuality: (isDownload) => (isDownload ? download : play)?.call(),
        );
}

Widget playerPage({
  Song selectedSong = song,
  ValueChanged<Duration>? seek,
  Duration position = const Duration(seconds: 12),
  List<LyricsLine> lyrics = lines,
  bool timed = true,
  String? lyricsError,
  bool loadingLyrics = false,
}) => baseline
    ? VideoPlayerPage(
        song: selectedSong,
        position: position,
        duration: const Duration(minutes: 4),
        isPlaying: true,
        lyrics: lyrics,
        onToggle: () {},
        onPrevious: () {},
        onNext: () {},
        onSeek: seek ?? (_) {},
        onQueue: () {},
        onMode: () {},
      )
    : WindowsPlayerPage(
        song: selectedSong,
        position: position,
        duration: const Duration(minutes: 4),
        isPlaying: true,
        lyrics: lyrics,
        timedLyrics: timed,
        lyricsError: lyricsError,
        lyricsLoading: loadingLyrics,
        onToggle: () {},
        onPrevious: () {},
        onNext: () {},
        onSeek: seek ?? (_) {},
        onQueue: () {},
        onMode: () {},
      );

Future<void> mount(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(1200, 800),
  double scale = 1,
  double deviceScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = deviceScale;
  await tester.pumpWidget(
    MaterialApp(
      theme: VideoTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(body: child),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Windows「我的」页显示 DJ Music 与新图标', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester, settingsPage());
    expect(find.text('DJ Music'), findsOneWidget);
    expect(
      find.image(
        const AssetImage(
          'assets/branding/dj-music/source/windows/yangyin-256.png',
        ),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('W01/W03：桌面只有播放和下载两项，分别可点', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var plays = 0;
    var downloads = 0;
    await mount(
      tester,
      settingsPage(play: () => plays++, download: () => downloads++),
    );
    expect(find.text('播放音质'), findsOneWidget);
    expect(find.text('QQ 音乐音质'), findsNothing);
    await tester.ensureVisible(find.text('播放音质'));
    await tester.tap(find.text('播放音质'));
    await tester.scrollUntilVisible(find.text('下载音质'), 160);
    expect(find.text('下载音质'), findsOneWidget);
    await tester.tap(find.text('下载音质'));
    expect([plays, downloads], [1, 1]);
  });
  testWidgets('W07：宽屏直接看到完整歌词，点击时间行定位', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final seeks = <Duration>[];
    await mount(tester, playerPage(seek: seeks.add));
    expect(find.text('第一句歌词'), findsOneWidget);
    expect(find.text('下一句歌词'), findsOneWidget);
    await tester.tap(find.text('下一句歌词'));
    expect(seeks, [const Duration(seconds: 20)]);
  });
  for (final size in [
    const Size(900, 600),
    const Size(1200, 800),
    const Size(720, 600),
    const Size(320, 700),
  ]) {
    for (final scale in [1.0, 1.25, 1.5]) {
      testWidgets('W09：${size.width}×${size.height}，字号缩放$scale，控件无溢出', (
        tester,
      ) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await mount(
          tester,
          playerPage(),
          size: size,
          scale: scale,
          deviceScale: scale,
        );
        expect(tester.takeException(), isNull);
        expect(find.byTooltip('暂停').hitTestable(), findsOneWidget);
        expect(find.byTooltip('播放队列').hitTestable(), findsOneWidget);
        expect(find.text('当前句歌词'), findsOneWidget);
        expect(find.text('第一句歌词'), findsOneWidget);
      });
    }
  }
  testWidgets('W07：首句前、边界、末句后按时间高亮，纯文本不假同步', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final entry in <int, int>{0: -1, 5: 0, 10: 1, 20: 2, 200: 2}.entries) {
      await mount(tester, playerPage(position: Duration(seconds: entry.key)));
      for (var i = 0; i < lines.length; i++) {
        final text = tester.widget<Text>(find.text(lines[i].text));
        expect(text.style?.color == VideoTheme.primary, i == entry.value);
      }
    }
    final seeks = <Duration>[];
    await mount(tester, playerPage(timed: false, seek: seeks.add));
    expect(find.text('纯文本歌词'), findsOneWidget);
    await tester.tap(find.text('第一句歌词'));
    expect(seeks, isEmpty);
  });
  testWidgets('W08：多行歌词使用真实位置，手动浏览暂停，恢复和键盘滚动', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final longLines = List.generate(
      40,
      (i) => LyricsLine(
        timestamp: Duration(seconds: i * 10),
        text: '第$i句：这是一段会自动换行的歌词，用实际布局定位当前句，不依赖固定行高。',
      ),
    );
    await mount(
      tester,
      playerPage(position: const Duration(seconds: 250), lyrics: longLines),
    );
    final scroller = find.byKey(const ValueKey('windows-lyrics-scroll'));
    final bounds = tester.getRect(scroller);
    expect(
      bounds.contains(tester.getCenter(find.text(longLines[25].text))),
      isTrue,
    );
    await tester.drag(scroller, const Offset(0, 160));
    await tester.pumpAndSettle();
    expect(find.text('回到当前歌词').hitTestable(), findsOneWidget);
    await mount(
      tester,
      playerPage(position: const Duration(seconds: 300), lyrics: longLines),
    );
    await tester.tap(find.text('回到当前歌词'));
    await tester.pumpAndSettle();
    expect(
      bounds.contains(tester.getCenter(find.text(longLines[30].text))),
      isTrue,
    );
    final focus = tester.widget<Focus>(
      find.byKey(const ValueKey('windows-lyrics-focus')),
    );
    focus.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.pumpAndSettle();
    expect(find.text('回到当前歌词').hitTestable(), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('W07：加载、没有歌词、加载失败显示不同状态', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester, playerPage(lyrics: const [], loadingLyrics: true));
    expect(find.text('正在加载歌词…'), findsOneWidget);
    await mount(tester, playerPage(lyrics: const []));
    expect(find.text('暂无歌词'), findsOneWidget);
    await mount(tester, playerPage(lyrics: const [], lyricsError: '歌词加载失败'));
    expect(find.text('歌词加载失败'), findsOneWidget);
  });
  testWidgets('W07：切歌到首句前回到顶部，歌词迟到与窗口变矮仍跟随当前句', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final longLines = List.generate(
      40,
      (i) => LyricsLine(
        timestamp: Duration(seconds: 5 + i * 10),
        text: '第$i句桌面跟随歌词',
      ),
    );
    await mount(
      tester,
      playerPage(position: const Duration(seconds: 205), lyrics: longLines),
    );
    await mount(
      tester,
      playerPage(
        selectedSong: const Song(
          id: 'next-gate',
          platform: PlatformType.qq,
          name: '下一首验收',
          artists: [],
        ),
        position: Duration.zero,
        lyrics: longLines,
      ),
    );
    final scroller = find.byKey(const ValueKey('windows-lyrics-scroll'));
    expect(
      tester
          .getRect(scroller)
          .contains(tester.getCenter(find.text(longLines.first.text))),
      isTrue,
    );
    await mount(tester, playerPage(lyrics: const [], loadingLyrics: true));
    await mount(
      tester,
      playerPage(position: const Duration(seconds: 205), lyrics: longLines),
    );
    expect(
      tester
          .getRect(scroller)
          .contains(tester.getCenter(find.text(longLines[20].text))),
      isTrue,
    );
    await mount(
      tester,
      playerPage(position: const Duration(seconds: 205), lyrics: longLines),
      size: const Size(1200, 400),
    );
    expect(
      tester
          .getRect(scroller)
          .contains(tester.getCenter(find.text(longLines[20].text))),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('W10：默认最小化说明清楚，原生不可用时禁用关闭与退出', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester, settingsPage());
    await tester.scrollUntilVisible(find.text('关闭主窗口时'), 300);
    expect(find.textContaining('最小化并继续播放'), findsWidgets);
    final close = tester.widget<ListTile>(
      find
          .ancestor(of: find.text('关闭主窗口时'), matching: find.byType(ListTile))
          .first,
    );
    expect(close.onTap, isNull);
    final exit = tester.widget<ListTile>(
      find
          .ancestor(of: find.text('退出应用'), matching: find.byType(ListTile))
          .first,
    );
    expect(exit.onTap, isNull);
  });
}

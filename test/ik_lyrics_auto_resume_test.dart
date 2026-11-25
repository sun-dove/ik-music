import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/lyrics/models/lyrics_line.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/video_app/ui/video_theme.dart';
import 'package:mconnect/video_app/windows/windows_player_page.dart';

const _song = Song(
  id: 'idle-lyrics',
  platform: PlatformType.qq,
  name: '歌词浏览验收',
  artists: [],
);
final _lines = List.generate(
  60,
  (index) => LyricsLine(
    timestamp: Duration(seconds: index * 10),
    text: '第$index句歌词：按真实换行的位置定位，回到此刻的播放进度。',
    translation: 'Translation of line $index',
  ),
);
final _scrollFinder = find.byKey(const ValueKey('windows-lyrics-scroll'));

ScrollController _controller(WidgetTester tester) =>
    tester.widget<SingleChildScrollView>(_scrollFinder).controller!;

Widget _page({
  Song song = _song,
  List<LyricsLine>? lines,
  Duration position = const Duration(seconds: 205),
  Duration? delay = const Duration(seconds: 3),
  Duration duration = const Duration(minutes: 10),
  bool playing = true,
  bool loading = false,
  bool lyricsLoading = false,
  bool timed = true,
  ValueChanged<Duration>? onSeek,
}) => WindowsPlayerPage(
  alignToDesign: true,
  lyricsAutoResumeDelay: delay,
  song: song,
  lyrics: lines ?? _lines,
  position: position,
  duration: duration,
  isPlaying: playing,
  isLoading: loading,
  lyricsLoading: lyricsLoading,
  timedLyrics: timed,
  onToggle: () {},
  onPrevious: () {},
  onNext: () {},
  onQueue: () {},
  onMode: () {},
  onSeek: onSeek ?? (_) {},
  playbackBar: const SizedBox(height: 70),
);

Future<void> _mount(
  WidgetTester tester,
  Widget page, {
  double width = 1200,
  double scale = 1,
  bool tickerEnabled = true,
  GlobalKey<NavigatorState>? navigatorKey,
  Duration settle = const Duration(milliseconds: 250),
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      theme: VideoTheme.light.copyWith(platform: TargetPlatform.windows),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: TickerMode(enabled: tickerEnabled, child: child!),
      ),
      home: page,
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump(settle);
  await tester.pump();
}

Future<void> _wheel(WidgetTester tester, {double delta = -400}) async {
  final position = tester.getCenter(_scrollFinder);
  await tester.sendEventToBinding(
    PointerScrollEvent(
      kind: PointerDeviceKind.mouse,
      position: position,
      scrollDelta: Offset(0, delta),
    ),
  );
  await tester.pump();
}

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  final focus = tester.widget<Focus>(
    find.byKey(const ValueKey('windows-lyrics-focus')),
  );
  focus.focusNode!.requestFocus();
  await tester.pump();
  await tester.sendKeyEvent(key);
  await tester.pump();
}

Future<void> _animation(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump();
}

void _expectCurrent(WidgetTester tester, int index, {List<LyricsLine>? lines}) {
  final bounds = tester.getRect(_scrollFinder);
  final current = find.text((lines ?? _lines)[index].text);
  expect(
    bounds.contains(tester.getCenter(current)),
    isTrue,
    reason: '当前行$index ${tester.getRect(current)} 应在歌词视口 $bounds 内',
  );
  expect(tester.widget<Text>(current).style?.fontWeight, FontWeight.w600);
}

void main() {
  testWidgets('E03 滚轮浏览2.9秒保持，3秒后主动回最新行且不seek', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final seeks = <Duration>[];
    await _mount(tester, _page(onSeek: seeks.add));
    await _wheel(tester);
    final browsed = _controller(tester).offset;
    expect(find.text('正在浏览歌词'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2900));
    expect(_controller(tester).offset, browsed);
    expect(find.text('正在浏览歌词'), findsOneWidget);
    await _mount(
      tester,
      _page(position: const Duration(seconds: 305), onSeek: seeks.add),
      settle: Duration.zero,
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('跟随播放'), findsOneWidget);
    await _animation(tester);
    _expectCurrent(tester, 30);
    expect(seeks, isEmpty);
  });

  testWidgets('E03 重复滚轮重置期限，hover和程序滚动不推迟回位', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mount(tester, _page());
    await _wheel(tester);
    await tester.pump(const Duration(seconds: 2));
    await _wheel(tester, delta: -120);
    final offset = _controller(tester).offset;
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('正在浏览歌词'), findsOneWidget);
    expect(_controller(tester).offset, offset);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(_scrollFinder));
    await mouse.moveTo(tester.getCenter(_scrollFinder) + const Offset(5, 5));
    await tester.pump(const Duration(milliseconds: 1900));
    expect(find.text('正在浏览歌词'), findsOneWidget);
    _controller(tester).jumpTo(_controller(tester).offset - 30);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('跟随播放'), findsOneWidget);
    await _animation(tester);
    _expectCurrent(tester, 20);
    await mouse.removePointer();
  });

  for (final key in [
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.pageUp,
    LogicalKeyboardKey.pageDown,
    LogicalKeyboardKey.home,
    LogicalKeyboardKey.end,
  ]) {
    testWidgets('E03 键盘${key.keyLabel}浏览停止三秒回位', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _mount(tester, _page());
      await _key(tester, key);
      expect(find.text('正在浏览歌词'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 2900));
      expect(find.text('正在浏览歌词'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('跟随播放'), findsOneWidget);
      await _animation(tester);
      _expectCurrent(tester, 20);
    });
  }

  testWidgets('E03 持续按键的重复事件重新计时，最后一次按键后才回位', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mount(tester, _page());
    final focus = tester.widget<Focus>(
      find.byKey(const ValueKey('windows-lyrics-focus')),
    );
    focus.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump(const Duration(milliseconds: 2900));
    expect(find.text('正在浏览歌词'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('跟随播放'), findsOneWidget);
    await _animation(tester);
    _expectCurrent(tester, 20);
  });

  testWidgets('E03 手指持续拖动及按住不抢回，松开后完整三秒', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mount(tester, _page());
    final drag = await tester.startGesture(tester.getCenter(_scrollFinder));
    await drag.moveBy(const Offset(0, 150));
    await tester.pump();
    expect(find.text('正在浏览歌词'), findsOneWidget);
    final held = _controller(tester).offset;
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('正在浏览歌词'), findsOneWidget);
    expect(_controller(tester).offset, held);
    await drag.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2900));
    expect(find.text('正在浏览歌词'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('跟随播放'), findsOneWidget);
    await _animation(tester);
    _expectCurrent(tester, 20);
  });

  testWidgets('E03 滚动条拖动后按住超过三秒，松开才开始倒计时', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mount(tester, _page());
    final paint = tester.widget<CustomPaint>(
      find
          .descendant(
            of: find.byKey(const ValueKey('windows-lyrics-focus')),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is CustomPaint &&
                  widget.foregroundPainter is ScrollbarPainter,
            ),
          )
          .first,
    );
    final rect = tester.getRect(_scrollFinder);
    final thumb = (paint.foregroundPainter! as ScrollbarPainter)
        .getThumbScrollOffset();
    final drag = await tester.startGesture(
      Offset(rect.right - 3, rect.top + thumb + 12),
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveBy(const Offset(0, 60));
    await tester.pump();
    expect(find.text('正在浏览歌词'), findsOneWidget);
    final held = _controller(tester).offset;
    await tester.pump(const Duration(seconds: 4));
    expect(_controller(tester).offset, held);
    expect(find.text('正在浏览歌词'), findsOneWidget);
    await drag.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2900));
    expect(find.text('正在浏览歌词'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('跟随播放'), findsOneWidget);
    await _animation(tester);
    _expectCurrent(tester, 20);
  });

  testWidgets('E03 惯性滚动结束后再等三秒，不能从松手提前计时', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mount(tester, _page());
    await tester.fling(_scrollFinder, const Offset(0, -250), 1800);
    await tester.pump();
    expect(_controller(tester).position.isScrollingNotifier.value, isTrue);
    var elapsed = Duration.zero;
    while (_controller(tester).position.isScrollingNotifier.value) {
      await tester.pump(const Duration(milliseconds: 20));
      elapsed += const Duration(milliseconds: 20);
      expect(elapsed, lessThan(const Duration(seconds: 8)));
      expect(find.text('正在浏览歌词'), findsOneWidget);
    }
    expect(elapsed, greaterThan(Duration.zero));
    await tester.pump(const Duration(milliseconds: 2900));
    expect(find.text('正在浏览歌词'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('跟随播放'), findsOneWidget);
    await _animation(tester);
    _expectCurrent(tester, 20);
  });

  testWidgets('E03 程序跟随和跳转不启动手动计时，暂停仍回当前位置', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final seeks = <Duration>[];
    await _mount(tester, _page());
    _controller(tester).jumpTo(0);
    await tester.pump();
    expect(find.text('跟随播放'), findsOneWidget);
    await _mount(tester, _page(position: const Duration(seconds: 305)));
    _expectCurrent(tester, 30);
    expect(find.text('跟随播放'), findsOneWidget);
    await _mount(tester, _page(playing: false, onSeek: seeks.add));
    await _wheel(tester);
    await tester.pump(const Duration(seconds: 3));
    await _animation(tester);
    _expectCurrent(tester, 20);
    expect(seeks, isEmpty);
    expect(
      tester
          .widget<WindowsPlayerPage>(find.byType(WindowsPlayerPage))
          .isPlaying,
      isFalse,
    );
  });

  testWidgets('E03 手动回位和点时间歌词立即恢复，旧计时不能提前结束新浏览', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final seeks = <Duration>[];
    await _mount(tester, _page(onSeek: seeks.add));
    await _wheel(tester);
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('回到当前歌词'));
    await _animation(tester);
    expect(find.text('跟随播放'), findsOneWidget);
    _expectCurrent(tester, 20);
    await _wheel(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('正在浏览歌词'), findsOneWidget);
    final visibleLine = find
        .byWidgetPredicate(
          (widget) =>
              widget is Text && _lines.any((line) => line.text == widget.data),
        )
        .hitTestable()
        .first;
    final text = tester.widget<Text>(visibleLine).data!;
    await tester.tap(visibleLine);
    await _animation(tester);
    expect(seeks, [_lines.firstWhere((line) => line.text == text).timestamp]);
    expect(find.text('跟随播放'), findsOneWidget);
    await _wheel(tester);
    await tester.pump(const Duration(milliseconds: 2900));
    expect(find.text('正在浏览歌词'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    await _animation(tester);
    expect(find.text('跟随播放'), findsOneWidget);
  });

  testWidgets('E03 切同名不同ID或不同平台取消旧计时，歌词迟到重按当前行定位', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mount(tester, _page());
    for (final song in [
      const Song(
        id: 'new-id',
        platform: PlatformType.qq,
        name: '歌词浏览验收',
        artists: [],
      ),
      const Song(
        id: 'new-id',
        platform: PlatformType.netease,
        name: '歌词浏览验收',
        artists: [],
      ),
    ]) {
      await _wheel(tester);
      await tester.pump(const Duration(seconds: 2));
      await _mount(
        tester,
        _page(song: song, position: const Duration(seconds: 305)),
      );
      expect(find.text('跟随播放'), findsOneWidget);
      _expectCurrent(tester, 30);
      await _wheel(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('正在浏览歌词'), findsOneWidget);
      await _mount(
        tester,
        _page(song: song, lines: const [], lyricsLoading: true),
      );
      expect(find.text('正在加载歌词…'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await _mount(
        tester,
        _page(song: song, position: const Duration(seconds: 405)),
      );
      expect(find.text('跟随播放'), findsOneWidget);
      _expectCurrent(tester, 40);
    }
  });

  testWidgets('E03 有效歌词替换取消旧期限，继续浏览按新文档重新计时', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mount(tester, _page());
    await _wheel(tester);
    await tester.pump(const Duration(seconds: 2));
    final refreshed = [for (final line in _lines) line.withTranslation('新译文')];
    await _mount(tester, _page(lines: refreshed));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('正在浏览歌词'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1750));
    expect(find.text('跟随播放'), findsOneWidget);
    await _animation(tester);
    _expectCurrent(tester, 20, lines: refreshed);
  });

  testWidgets('E03 无歌词、纯文本和加载中不自动定位，恢复有效歌词才跟随', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final seeks = <Duration>[];
    for (final options in [
      (timed: false, loading: false, lyricsLoading: false),
      (timed: true, loading: true, lyricsLoading: false),
      (timed: true, loading: false, lyricsLoading: true),
    ]) {
      await _mount(
        tester,
        _page(
          timed: options.timed,
          loading: options.loading,
          lyricsLoading: options.lyricsLoading,
          onSeek: seeks.add,
        ),
      );
      await _wheel(tester);
      final offset = _controller(tester).offset;
      await tester.pump(const Duration(seconds: 4));
      expect(_controller(tester).offset, offset);
      final visible = find
          .byWidgetPredicate(
            (widget) =>
                widget is Text &&
                _lines.any((line) => line.text == widget.data),
          )
          .hitTestable()
          .first;
      await tester.tap(visible);
      expect(seeks, isEmpty);
      await _mount(tester, _page());
      expect(find.text('跟随播放'), findsOneWidget);
      _expectCurrent(tester, 20);
    }
    await _mount(tester, _page(lines: const []));
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('暂无歌词'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('E03 旧缺省不自动恢复，可选延时关闭也取消已有计时', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mount(tester, _page(delay: null));
    await _wheel(tester);
    final offset = _controller(tester).offset;
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('正在浏览歌词'), findsOneWidget);
    expect(_controller(tester).offset, offset);
    await _mount(tester, _page());
    await _wheel(tester);
    await tester.pump(const Duration(seconds: 2));
    await _mount(tester, _page(delay: null));
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('正在浏览歌词'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('E03 长句、翻译和字号布局改变后按真实位置回位', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mount(tester, _page(), width: 900, scale: 1.5);
    await _wheel(tester);
    await tester.tap(find.byKey(const ValueKey('ik-player-translation')));
    tester
        .widget<Slider>(find.byKey(const ValueKey('ik-player-lyrics-size')))
        .onChanged!(30);
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await _animation(tester);
    _expectCurrent(tester, 20);
    expect(find.text('Translation of line 20'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('E03 浏览时翻译重置三秒，字号拖动按住不抢回且结束后重新计时', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mount(tester, _page());
    await _wheel(tester);
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byKey(const ValueKey('ik-player-translation')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2900));
    expect(find.text('正在浏览歌词'), findsOneWidget);
    final slider = find.byKey(const ValueKey('ik-player-lyrics-size'));
    final drag = await tester.startGesture(tester.getCenter(slider));
    await drag.moveBy(const Offset(15, 0));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('正在浏览歌词'), findsOneWidget);
    await drag.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(tester.widget<Slider>(slider).value, isNot(22));
    final offset = _controller(tester).offset;
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('正在浏览歌词'), findsOneWidget);
    expect(_controller(tester).offset, offset);
    await drag.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2900));
    expect(find.text('正在浏览歌词'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('跟随播放'), findsOneWidget);
    await _animation(tester);
    _expectCurrent(tester, 20);
    await tester.tap(find.byKey(const ValueKey('ik-player-translation')));
    await tester.drag(slider, const Offset(10, 0));
    await _animation(tester);
    expect(find.text('跟随播放'), findsOneWidget);
    _expectCurrent(tester, 20);
  });

  testWidgets('E03 隐藏页面暂停计时，恢复前台重新等三秒，销毁取消回调', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mount(tester, _page());
    await _wheel(tester);
    await tester.pump(const Duration(seconds: 2));
    await _mount(tester, _page(), tickerEnabled: false);
    final offset = _controller(tester).offset;
    await tester.pump(const Duration(seconds: 4));
    expect(_controller(tester).offset, offset);
    expect(find.text('正在浏览歌词'), findsOneWidget);
    await _mount(tester, _page());
    await tester.pump(const Duration(milliseconds: 2650));
    expect(find.text('正在浏览歌词'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('跟随播放'), findsOneWidget);
    await _animation(tester);
    _expectCurrent(tester, 20);
    await _wheel(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('E03 其他路由覆盖播放详情不在后台回位，返回后重新计时', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final navigator = GlobalKey<NavigatorState>();
    await _mount(tester, _page(), navigatorKey: navigator);
    await _wheel(tester);
    final controller = _controller(tester);
    final offset = controller.offset;
    unawaited(
      navigator.currentState!.push<void>(
        MaterialPageRoute(builder: (_) => const Scaffold(body: Text('其他页面'))),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    expect(controller.offset, offset);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('正在浏览歌词'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await _animation(tester);
    expect(find.text('跟随播放'), findsOneWidget);
    _expectCurrent(tester, 20);
  });
}

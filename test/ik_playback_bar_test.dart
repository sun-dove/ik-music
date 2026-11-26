import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/core/database/app_database.dart';
import 'package:mconnect/core/platform/platform_utils.dart';
import 'package:mconnect/features/floating_lyrics/presentation/providers/floating_lyrics_provider.dart';
import 'package:mconnect/features/library/presentation/providers/likes_provider.dart';
import 'package:mconnect/features/player/data/playback_keep_alive_service.dart';
import 'package:mconnect/features/player/data/playback_notification_service.dart';
import 'package:mconnect/features/player/presentation/providers/lyrics_provider.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/l10n/ik_lyrics_action_strings.dart';
import 'package:mconnect/l10n/ik_playback_notice_strings.dart';
import 'package:mconnect/l10n/ik_runtime_strings.dart';
import 'package:mconnect/l10n/ik_strings.dart';
import 'package:mconnect/l10n/ik_workspace_strings.dart';
import 'package:mconnect/l10n/video_strings.dart';
import 'package:mconnect/lyrics/models/lyrics_line.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/video_app/ik/ik_like_action.dart';
import 'package:mconnect/video_app/ik/ik_lyrics_action.dart';
import 'package:mconnect/video_app/ik/ik_playback_bar.dart';
import 'package:mconnect/video_app/ik/ik_theme.dart';
import 'package:mconnect/video_app/ik/ik_workspace.dart';
import 'package:mconnect/video_app/ui/video_theme.dart';

import 'support/content_page_fakes.dart';

const _track = Song(
  id: 'bar-song',
  name: '播放栏验收曲目',
  platform: PlatformType.qq,
  artists: [],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.mconnect.mconnect/floating_lyrics');
  late Directory scratch;
  late AppDatabase database;
  late List<String> nativeCalls;
  Completer<bool>? pendingShow;

  setUpAll(() async {
    scratch = await Directory.systemTemp.createTemp('ik-bar-formal-');
    Hive.init(scratch.path);
    await Hive.openBox('settings');
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.customSelect('SELECT 1').get();
  });
  setUp(() async {
    await database.delete(database.userLikes).go();
    pendingShow = null;
    nativeCalls = [];
    PlatformUtils.setDebugOverride(AppPlatform.windows);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          nativeCalls.add(call.method);
          return call.method == 'show' && pendingShow != null
              ? pendingShow!.future
              : true;
        });
  });
  tearDown(() {
    PlatformUtils.setDebugOverride(null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  tearDownAll(() async {
    await database.close();
    await Hive.close();
    final target = scratch.absolute.path;
    if (!target.startsWith(
          '${Directory.systemTemp.absolute.path}${Platform.pathSeparator}',
        ) ||
        !scratch.path
            .split(Platform.pathSeparator)
            .last
            .startsWith('ik-bar-formal-')) {
      throw StateError('拒绝删除未知目录');
    }
    if (await scratch.exists()) await scratch.delete(recursive: true);
  });

  Future<({ProviderContainer container, _BarPlayer player, _Likes likes})>
  mount(
    WidgetTester tester, {
    double width = 1200,
    double scale = 1,
    bool balancedLayout = false,
    bool contentAdaptive = false,
    bool inlineLyrics = false,
    bool contextualErrors = false,
    bool workspaceRoot = false,
    LyricsDocument? document,
    IkPlaybackBar? playbackBar,
    VoidCallback? onOpen,
    VoidCallback? onAudio,
  }) async {
    tester.view.physicalSize = Size(width, workspaceRoot ? 1032 : 400);
    tester.view.devicePixelRatio = 1;
    final player = _BarPlayer();
    final likes = _Likes(database);
    await tester.runAsync(likes.loadAllLikes);
    final container = ProviderContainer(
      overrides: [
        playerProvider.overrideWith((ref) => player),
        lyricsProvider.overrideWith((ref) async => document),
        likesProvider.overrideWith((ref) => likes),
        floatingLyricsProvider.overrideWith(
          (ref) => IkStrictFloatingLyricsNotifier(save: (_) async {}),
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: workspaceRoot
              ? IkDesktopWorkspace(
                  index: 0,
                  alignToDesign: true,
                  onSelect: (_) {},
                  onAccount: () {},
                  pages: const [
                    SizedBox(),
                    SizedBox(),
                    SizedBox(),
                    SizedBox(),
                    SizedBox(),
                  ],
                  playbackBar: playbackBar!,
                )
              : Scaffold(
                  body: Align(
                    alignment: Alignment.bottomCenter,
                    child:
                        playbackBar ??
                        (balancedLayout
                            ? IkPlaybackBar.aligned(
                                onOpen: onOpen,
                                onAudio: onAudio ?? () {},
                                balancedLayout: true,
                                contentAdaptive: contentAdaptive,
                                inlineLyrics: inlineLyrics,
                                contextualErrors: contextualErrors,
                              )
                            : IkPlaybackBar(onOpen: () {}, onAudio: () {})),
                  ),
                ),
        ),
      ),
    );
    await tester.pump();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await tester.pump();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    return (container: container, player: player, likes: likes);
  }

  IconButton likeButton(WidgetTester tester) => tester.widget<IconButton>(
    find.widgetWithIcon(IconButton, Icons.favorite_border),
  );
  TextButton lyricsButton(WidgetTester tester) =>
      tester.widget<TextButton>(find.byKey(const ValueKey('ik-bar-lyrics')));
  Slider seekSlider(WidgetTester tester) =>
      tester.widget<Slider>(find.byKey(const ValueKey('ik-bar-seek')));

  final centerControls = find.byKey(const ValueKey('ik-bar-centered-controls'));
  final currentLyrics = find.byKey(const ValueKey('ik-bar-current-lyrics'));
  final heartTarget = find.byTooltip(VideoStrings.like);
  final volumeSlider = find.byKey(const ValueKey('ik-bar-volume'));
  final queueTarget = find.byKey(const ValueKey('ik-bar-queue'));

  testWidgets('1920 全屏工作区：封面和队列靠近窗口边缘，播放键仍在屏幕正中', (tester) async {
    await mount(
      tester,
      width: 1920,
      workspaceRoot: true,
      playbackBar: IkPlaybackBar.aligned(
        onOpen: () {},
        onAudio: () {},
        balancedLayout: true,
        contentAdaptive: true,
        windowEdges: true,
        inlineLyrics: true,
      ),
    );
    final root = tester.getRect(find.byType(Scaffold).first);
    final song = find.ancestor(
      of: find.text(_track.name),
      matching: find.byType(InkWell),
    );
    expect(tester.getRect(song).left - root.left, inInclusiveRange(0, 16));
    expect(
      root.right - tester.getRect(queueTarget).right,
      inInclusiveRange(0, 16),
    );
    expect(
      tester.getCenter(find.byTooltip(VideoStrings.play)).dx,
      closeTo(root.center.dx, 1),
    );
    expect(tester.getSize(centerControls).width, 680);
    for (final target in [
      song,
      heartTarget,
      currentLyrics,
      volumeSlider,
      queueTarget,
    ]) {
      expect(target.hitTestable(), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('内容变更：旧调用缺省仍保留宽屏布局且详情不重复歌词', (tester) async {
    final legacy = IkPlaybackBar.aligned(
      onOpen: null,
      onAudio: () {},
      balancedLayout: true,
    );
    expect(legacy.contentAdaptive, isFalse);
    await mount(tester, width: 1920, playbackBar: legacy);
    final center = tester.getRect(centerControls);
    expect(center.left - tester.getRect(heartTarget).right, greaterThan(180));
    expect(currentLyrics, findsNothing);
    expect(heartTarget.hitTestable(), findsOneWidget);
    expect(volumeSlider.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('内容变更：主栏逐句滚动歌词不推移收藏、中央及右侧工具；长歌名按预算显示', (tester) async {
    const firstLine = '起风了';
    const nextLine = '窗外的风穿过长街，远方的歌声仍在回响，一行很长的歌词正在唱，直到夜色将灯光点亮';
    var detailOpens = 0;
    final h = await mount(
      tester,
      width: 1920,
      balancedLayout: true,
      contentAdaptive: true,
      inlineLyrics: true,
      onOpen: () => detailOpens++,
      document: const LyricsDocument(
        format: LyricsFormat.lrc,
        lines: [
          LyricsLine(timestamp: Duration.zero, text: firstLine),
          LyricsLine(timestamp: Duration(seconds: 3), text: nextLine),
        ],
      ),
    );
    final areas = [
      currentLyrics,
      heartTarget,
      centerControls,
      volumeSlider,
      queueTarget,
    ];
    final before = areas.map(tester.getRect).toList();
    expect(find.text(firstLine), findsOneWidget);
    await tester.tap(currentLyrics);
    expect(detailOpens, 1);
    expect(
      tester.getRect(centerControls).left - tester.getRect(currentLyrics).right,
      closeTo(28, 1),
    );
    h.player.publish(
      const PlayerState(
        currentSong: _track,
        isPlaying: true,
        position: Duration(seconds: 4),
        duration: Duration(minutes: 3),
      ),
    );
    await tester.pump();
    expect(find.text(firstLine), findsNothing);
    final longLine = find.text(nextLine);
    expect(longLine, findsOneWidget);
    final textStart = tester.getTopLeft(longLine).dx;
    await tester.pump(const Duration(seconds: 2));
    expect(tester.getTopLeft(longLine).dx, lessThan(textStart));
    expect(areas.map(tester.getRect).toList(), before);

    Finder songInfo(String name) =>
        find.ancestor(of: find.text(name), matching: find.byType(InkWell));
    final shortSong = tester.getRect(songInfo(_track.name));
    const longSong = Song(
      id: 'long-title',
      name: '特别长的一首歌的名字测试歌名增长时可用空间的使用情况',
      artists: [],
      platform: PlatformType.qq,
    );
    h.player.publish(
      const PlayerState(currentSong: longSong, duration: Duration(minutes: 3)),
    );
    await tester.pump();
    final longerSong = tester.getRect(songInfo(longSong.name));
    expect(longerSong.width, greaterThan(shortSong.width));
    expect(
      tester.widget<Text>(find.text(longSong.name)).overflow,
      TextOverflow.ellipsis,
    );
    expect(
      tester.getRect(heartTarget).left - longerSong.right,
      inInclusiveRange(0, 12),
    );
    expect(tester.getRect(centerControls), before[2]);
    expect(tester.takeException(), isNull);
  });

  for (final width in [1920.0, 1024.0]) {
    testWidgets('内容变更：长歌名播放失败 $width 可查看原因并重试当前歌曲', (tester) async {
      const longSong = Song(
        id: 'failed-title',
        name: '这是一首很长很长一直延伸到右边但不能遮盖按钮的长歌名',
        artists: [],
        platform: PlatformType.qq,
      );
      const cause = '音源没有返回可播放的地址';
      final h = await mount(
        tester,
        width: width,
        balancedLayout: true,
        contentAdaptive: true,
        contextualErrors: true,
        inlineLyrics: true,
      );
      h.player.publish(
        const PlayerState(
          currentSong: longSong,
          error: cause,
          duration: Duration(minutes: 3),
        ),
      );
      await tester.pump();
      expect(currentLyrics, findsNothing);
      final details = find.widgetWithText(
        TextButton,
        IkPlaybackNoticeStrings.details,
      );
      final retry = find.widgetWithText(TextButton, IkRuntimeStrings.retry);
      expect(find.text(IkPlaybackNoticeStrings.failed), findsOneWidget);
      expect(find.text(cause), findsNothing);
      expect(details.hitTestable(), findsOneWidget);
      expect(retry.hitTestable(), findsOneWidget);
      final center = tester.getRect(centerControls);
      if (width == 1920) {
        expect(center.left - tester.getRect(details).right, closeTo(28, 1));
      } else {
        expect(
          tester.getRect(details).top,
          greaterThanOrEqualTo(tester.getRect(heartTarget).bottom),
        );
        expect(tester.getRect(details).right, lessThan(center.left));
      }
      await tester.tap(details);
      await tester.pumpAndSettle();
      expect(find.text(cause).hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip(IkStrings.close));
      await tester.pumpAndSettle();
      expect(find.text(cause), findsNothing);
      await tester.tap(retry);
      expect(h.player.retried, [same(longSong)]);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (width, centerWidth, gap) in <(double, double, double)>[
    (1920, 680, 28),
    (1440, 680, 17),
    (1280, 560, 16),
    (1024, 304, 16),
  ]) {
    testWidgets('内容自适应：详情 $width 的可见控件贴近中央控制区', (tester) async {
      await mount(
        tester,
        width: width,
        balancedLayout: true,
        contentAdaptive: true,
      );
      final center = tester.getRect(
        find.byKey(const ValueKey('ik-bar-centered-controls')),
      );
      final heart = tester.getRect(find.byTooltip(VideoStrings.like));
      final volume = tester.getRect(
        find.widgetWithIcon(IconButton, Icons.volume_up_outlined),
      );
      expect(center.center.dx, closeTo(width / 2, 1));
      expect(center.width, closeTo(centerWidth, 1));
      expect(center.left - heart.right, closeTo(gap, 1), reason: '收藏命中盒与中区间距');
      expect(volume.left - center.right, closeTo(gap, 1), reason: '音量命中盒与中区间距');
      expect(heart.center.dy, closeTo(center.center.dy, 1));
      expect(volume.center.dy, closeTo(center.center.dy, 1));
      expect(tester.takeException(), isNull);
    });
  }

  for (final (width, scale, singleRow) in <(double, double, bool)>[
    (1024, 1, true),
    (800, 1, false),
    (1024, 1.5, false),
    (1920, 1, true),
  ]) {
    testWidgets('底栏自适应 $width / $scale 排列与操作', (tester) async {
      var audioOpens = 0;
      final mounted = await mount(
        tester,
        width: width,
        scale: scale,
        balancedLayout: true,
        onAudio: () => audioOpens++,
      );
      final song = find.ancestor(
        of: find.text(_track.name),
        matching: find.byType(InkWell),
      );
      final heart = find.byTooltip(VideoStrings.like);
      final controls = find.byKey(const ValueKey('ik-bar-centered-controls'));
      final play = find.byTooltip(VideoStrings.play);
      final seek = find.byKey(const ValueKey('ik-bar-seek'));
      final audio = find.byTooltip(IkWorkspaceStrings.audio);
      final queue = find.byKey(const ValueKey('ik-bar-queue'));

      expect(tester.takeException(), isNull);
      expect(tester.getCenter(play).dx, closeTo(width / 2, 1));
      expect(tester.getCenter(controls).dx, closeTo(width / 2, 1));
      expect(tester.getSize(controls).width, lessThanOrEqualTo(680));
      expect(tester.getCenter(seek).dy, greaterThan(tester.getCenter(play).dy));
      expect(
        tester.getRect(heart).left - tester.getRect(song).right,
        inInclusiveRange(0, 12),
      );
      if (singleRow) {
        final centerY = tester.getCenter(controls).dy;
        expect(tester.getCenter(song).dy, closeTo(centerY, 1));
        expect(tester.getCenter(audio).dy, closeTo(centerY, 1));
        expect(
          tester.getRect(heart).right,
          lessThan(tester.getRect(controls).left),
        );
      } else {
        expect(
          tester.getRect(song).bottom,
          lessThanOrEqualTo(tester.getRect(controls).top),
        );
        expect(
          tester.getRect(queue).bottom,
          lessThanOrEqualTo(tester.getRect(controls).top),
        );
      }
      if (width == 1024 && singleRow) {
        expect(tester.getSize(seek).width, lessThan(360));
      }
      if (width == 1920) {
        expect(tester.getRect(song).left, greaterThan(100));
        expect(width - tester.getRect(queue).right, greaterThan(100));
      }

      for (final target in [heart, play, seek, audio, queue]) {
        expect(target.hitTestable(), findsOneWidget);
      }
      await tester.tap(seek);
      expect(mounted.player.seeks, isNotEmpty);
      expect(mounted.player.seeks.last, greaterThan(Duration.zero));
      await tester.tap(audio);
      expect(audioOpens, 1);
      expect(tester.takeException(), isNull);
    });
  }

  Future<void> finishLike(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.runAsync(() async {
      if (!container.read(ikLikeActionProvider).busy) return;
      final done = Completer<void>();
      final subscription = container.listen(ikLikeActionProvider, (_, next) {
        if (!next.busy && !done.isCompleted) done.complete();
      });
      try {
        await done.future.timeout(const Duration(seconds: 5));
      } finally {
        subscription.close();
      }
    });
    await tester.pump();
  }

  for (final scale in [1.0, 1.5]) {
    testWidgets('内容变更：同一会话连续缩到 1024、800 再放大，字号 $scale 下控件仍可操作', (tester) async {
      var audioOpens = 0;
      final h = await mount(
        tester,
        width: 1920,
        scale: scale,
        balancedLayout: true,
        contentAdaptive: true,
        onAudio: () => audioOpens++,
      );
      final initialState = h.container.read(playerProvider);
      final play = find.byTooltip(VideoStrings.play);
      final seek = find.byKey(const ValueKey('ik-bar-seek'));
      final audio = find.byTooltip(IkWorkspaceStrings.audio);
      for (final width in [1920.0, 1024.0, 800.0, 1920.0]) {
        tester.view.physicalSize = Size(width, 400);
        await tester.pump();
        final center = tester.getRect(centerControls);
        expect(center.center.dx, closeTo(width / 2, 1));
        expect(tester.getCenter(play).dx, closeTo(width / 2, 1));
        if (width == 800 || (width == 1024 && scale > 1)) {
          expect(
            tester.getRect(heartTarget).bottom,
            lessThanOrEqualTo(center.top),
          );
          expect(
            tester.getRect(queueTarget).bottom,
            lessThanOrEqualTo(center.top),
          );
        } else {
          expect(
            tester.getCenter(heartTarget).dy,
            closeTo(center.center.dy, 1),
          );
          expect(
            tester.getCenter(queueTarget).dy,
            closeTo(center.center.dy, 1),
          );
        }
        for (final target in [
          heartTarget,
          play,
          seek,
          volumeSlider,
          audio,
          queueTarget,
        ]) {
          expect(target.hitTestable(), findsOneWidget);
        }
        if (width == 800) {
          await tester.tap(play);
          expect(h.player.toggles, 1);
          await tester.tap(seek);
          expect(h.player.seeks.single.inSeconds, inInclusiveRange(85, 95));
          await tester.tap(volumeSlider);
          await tester.pump();
          expect(tester.widget<Slider>(volumeSlider).value, closeTo(.5, .05));
          await tester.tap(audio);
          expect(audioOpens, 1);
          await tester.tap(queueTarget);
          await tester.pumpAndSettle();
          expect(find.text(IkStrings.emptyQueue).hitTestable(), findsOneWidget);
          await tester.tap(find.byTooltip(IkStrings.close));
          await tester.pumpAndSettle();
        }
        expect(h.container.read(playerProvider), same(initialState));
        expect(tester.takeException(), isNull);
      }
      await tester.tap(heartTarget);
      await finishLike(tester, h.container);
      expect(find.widgetWithIcon(IconButton, Icons.favorite), findsOneWidget);
      expect(tester.widget<Slider>(volumeSlider).value, closeTo(.5, .05));
      expect(tester.takeException(), isNull);
    });
  }

  // 正式长期门：使用真实播放栏验证键盘输入几何、命中与状态恢复。
  Future<
    ({ProviderContainer container, _BarPlayer player, List<String> queries})
  >
  mountKeyboard(
    WidgetTester tester, {
    required double width,
    required double scale,
    required bool withTrack,
    double height = 640,
    bool? keyboardLayout = true,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    final player = _BarPlayer();
    player.publish(
      withTrack
          ? const PlayerState(
              currentSong: _track,
              duration: Duration(minutes: 3),
              isPlaying: true,
            )
          : const PlayerState(),
    );
    final likes = _Likes(database);
    await tester.runAsync(likes.loadAllLikes);
    final queries = <String>[];
    final container = ProviderContainer(
      overrides: [
        playerProvider.overrideWith((ref) => player),
        likesProvider.overrideWith((ref) => likes),
        floatingLyricsProvider.overrideWith(
          (ref) => IkStrictFloatingLyricsNotifier(save: (_) async {}),
        ),
      ],
    );
    final defaultWorkspace = IkDesktopWorkspace(
      index: 1,
      onSelect: (_) {},
      onAccount: () {},
      alignToDesign: true,
      onSearch: queries.add,
      pages: [
        const Text('发现页'),
        ListView(
          key: const ValueKey('keyboard-results'),
          children: [for (var i = 0; i < 30; i++) Text('搜索结果 $i')],
        ),
        const Text('音乐库页'),
        const Text('最近播放页'),
        const Text('设置页'),
      ],
      playbackBar: IkPlaybackBar.aligned(onOpen: () {}, onAudio: () {}),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: IkTheme.from(VideoTheme.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: keyboardLayout == null
              ? defaultWorkspace
              : IkDesktopWorkspace(
                  index: defaultWorkspace.index,
                  onSelect: defaultWorkspace.onSelect,
                  onAccount: defaultWorkspace.onAccount,
                  alignToDesign: defaultWorkspace.alignToDesign,
                  mobileKeyboardLayout: keyboardLayout,
                  onSearch: defaultWorkspace.onSearch,
                  pages: defaultWorkspace.pages,
                  playbackBar: defaultWorkspace.playbackBar,
                ),
        ),
      ),
    );
    await tester.pump();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await tester.pump();
      tester.view.resetViewInsets();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    return (container: container, player: player, queries: queries);
  }

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 1.5]) {
      for (final withTrack in [false, true]) {
        final trackLabel = withTrack ? '有播放会话' : '空播放器';
        testWidgets('K01/K02 ${width}x640 $scale $trackLabel 输入可命中及关闭恢复', (
          tester,
        ) async {
          PlatformUtils.setDebugOverride(AppPlatform.android);
          final h = await mountKeyboard(
            tester,
            width: width,
            scale: scale,
            withTrack: withTrack,
          );
          final search = find.byKey(const ValueKey('ik-workspace-search'));
          final results = find.byKey(const ValueKey('keyboard-results'));
          final pageElement = tester.element(results);
          final playerState = h.container.read(playerProvider);
          await tester.tap(search);
          await tester.enterText(search, 'music');
          final controller = tester.widget<TextField>(search).controller!;
          for (final inset in [248.0, 320.0]) {
            await tester.tap(search);
            tester.view.viewInsets = FakeViewPadding(bottom: inset);
            await tester.pump();
            final inputRect = tester.getRect(search);
            expect(inputRect.top, greaterThanOrEqualTo(0));
            expect(inputRect.bottom, lessThanOrEqualTo(640 - inset));
            expect(search.hitTestable(), findsOneWidget);
            expect(
              search.hitTestable(at: const Alignment(0, .75)),
              findsOneWidget,
            );
            final visibleBar = find.byType(IkPlaybackBar);
            if (visibleBar.evaluate().isNotEmpty) {
              final barRect = tester.getRect(visibleBar);
              expect(
                inputRect.overlaps(barRect),
                isFalse,
                reason: '输入矩形$inputRect不可与播放栏$barRect相交',
              );
            }
            expect(find.byType(IkPlaybackBar).hitTestable(), findsNothing);
            expect(controller.text, 'music');
            expect(tester.element(results), same(pageElement));
            await tester.testTextInput.receiveAction(TextInputAction.search);
            expect(h.queries.last, 'music');
            tester.testTextInput.hide();
            tester.view.viewInsets = const FakeViewPadding();
            await tester.pump();
            expect(search.hitTestable(), findsOneWidget);
            expect(find.byType(IkPlaybackBar).hitTestable(), findsOneWidget);
            expect(
              find.byKey(const ValueKey('ik-workspace-nav-1')).hitTestable(),
              findsOneWidget,
            );
            expect(
              tester.widget<TextField>(search).controller,
              same(controller),
            );
            expect(controller.text, 'music');
            expect(tester.element(results), same(pageElement));
            expect(h.container.read(playerProvider), same(playerState));
          }
          expect(h.queries, ['music', 'music']);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  for (final config in <(double, bool?)>[
    (320, null),
    (320, false),
    (720, false),
    (720, true),
    (1200, false),
    (1200, true),
  ]) {
    testWidgets('K03 ${config.$1}x960 ${config.$2} 缺省和宽窗保留导航底栏', (
      tester,
    ) async {
      await mountKeyboard(
        tester,
        width: config.$1,
        height: 960,
        scale: 1,
        withTrack: false,
        keyboardLayout: config.$2,
      );
      final search = find.byKey(const ValueKey('ik-workspace-search'));
      final bar = find.byType(IkPlaybackBar);
      final before = tester.getRect(bar);
      await tester.tap(search);
      await tester.enterText(search, 'music');
      tester.view.viewInsets = const FakeViewPadding(bottom: 248);
      await tester.pump();
      final after = tester.getRect(bar);
      expect(bar.hitTestable(), findsOneWidget);
      expect(after.size, before.size);
      expect(after.top, before.top - 248);
      expect(
        find.byKey(const ValueKey('ik-workspace-nav-1')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(search).controller!.text, 'music');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('U03 播放栏收藏忙碌禁用，落盘失败显示错误并可重试', (tester) async {
    final h = await mount(tester);
    h.likes.pending = Completer<void>();
    h.likes.fail = true;
    await tester.tap(find.byTooltip(VideoStrings.like));
    await tester.runAsync(
      () => h.likes.entered.future.timeout(const Duration(seconds: 5)),
    );
    await tester.pump();
    expect(h.likes.calls, 1);
    expect(h.container.read(ikLikeActionProvider).busy, isTrue);
    expect(likeButton(tester).onPressed, isNull);
    h.likes.pending!.complete();
    await finishLike(tester, h.container);
    expect(find.text(IkWorkspaceStrings.likeFailed), findsOneWidget);
    expect(likeButton(tester).onPressed, isNotNull);
    expect(
      await tester.runAsync(() => h.likes.isLiked(_track.id, _track.platform)),
      isFalse,
    );
    h.likes.pending = null;
    h.likes.fail = false;
    await tester.tap(find.byTooltip(VideoStrings.like));
    await finishLike(tester, h.container);
    expect(
      await tester.runAsync(() => h.likes.isLiked(_track.id, _track.platform)),
      isTrue,
    );
    expect(find.text(IkWorkspaceStrings.likeFailed), findsNothing);
    expect(find.widgetWithIcon(IconButton, Icons.favorite), findsOneWidget);
  });

  testWidgets('U06 播放栏不支持歌词平台禁用并显示能力说明', (tester) async {
    PlatformUtils.setDebugOverride(AppPlatform.linux);
    await mount(tester);
    expect(lyricsButton(tester).onPressed, isNull);
    expect(find.byTooltip(IkLyricsActionStrings.unsupported), findsOneWidget);
    expect(nativeCalls, isEmpty);
  });

  testWidgets('U06 播放栏歌词等待原生时禁用，失败后保留关闭并可重试', (tester) async {
    final h = await mount(tester);
    pendingShow = Completer<bool>();
    await tester.tap(find.byKey(const ValueKey('ik-bar-lyrics')));
    await tester.pump();
    expect(h.container.read(ikLyricsActionProvider), isTrue);
    expect(lyricsButton(tester).onPressed, isNull);
    expect(h.container.read(floatingLyricsProvider).enabled, isFalse);
    pendingShow!.complete(false);
    await tester.pump();
    await tester.pump();
    expect(nativeCalls.where((call) => call == 'show'), hasLength(1));
    expect(lyricsButton(tester).onPressed, isNotNull);
    expect(find.byTooltip(IkLyricsActionStrings.showFailed), findsOneWidget);
    expect(h.container.read(floatingLyricsProvider).enabled, isFalse);
  });

  testWidgets('U03 播放栏无曲目、无时长或切歌时禁用拖动，完成后可精确定位', (tester) async {
    final h = await mount(tester);
    h.player.publish(const PlayerState());
    await tester.pump();
    expect(seekSlider(tester).onChanged, isNull);
    h.player.publish(const PlayerState(currentSong: _track));
    await tester.pump();
    expect(seekSlider(tester).onChanged, isNull);
    h.player.publish(
      const PlayerState(
        currentSong: _track,
        duration: Duration(minutes: 3),
        isTransitioning: true,
      ),
    );
    await tester.pump();
    expect(seekSlider(tester).onChanged, isNull);
    expect(h.player.seeks, isEmpty);
    h.player.publish(
      const PlayerState(
        currentSong: _track,
        duration: Duration(minutes: 3),
        isPlaying: true,
      ),
    );
    await tester.pump();
    final slider = seekSlider(tester);
    expect(slider.onChanged, isNotNull);
    slider.onChanged!(42000);
    expect(h.player.seeks, [const Duration(seconds: 42)]);
    expect(tester.takeException(), isNull);
  });
}

class _Likes extends LikesNotifier {
  _Likes(AppDatabase database) : super(database.likesDao, database.songsDao);
  bool fail = false;
  int calls = 0;
  final entered = Completer<void>();
  Completer<void>? pending;
  @override
  Future<bool> toggleLike(Song song) async {
    calls++;
    if (!entered.isCompleted) entered.complete();
    await pending?.future;
    return fail ? false : super.toggleLike(song);
  }
}

class _BarPlayer extends PlayerNotifier {
  _BarPlayer()
    : super(
        audioController: IdleAudioController(),
        audioControllerFactory: IdleAudioController.new,
        keepAliveController: const NoopPlaybackKeepAliveController(),
        notificationController: const NoopPlaybackNotificationController(),
        stuckWatchdogInterval: Duration.zero,
        playbackHealthCheckInterval: Duration.zero,
        playbackMemorySaveInterval: Duration.zero,
      ) {
    state = const PlayerState(
      currentSong: _track,
      duration: Duration(minutes: 3),
    );
  }
  final seeks = <Duration>[];
  final retried = <Song>[];
  int toggles = 0;
  void publish(PlayerState next) => state = next;
  @override
  Future<void> playSong(Song song) async => retried.add(song);
  @override
  Future<void> togglePlay() async => toggles++;
  @override
  Future<void> seek(Duration position) async => seeks.add(position);
}

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
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/l10n/ik_lyrics_action_strings.dart';
import 'package:mconnect/l10n/ik_workspace_strings.dart';
import 'package:mconnect/l10n/video_strings.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/video_app/ik/ik_like_action.dart';
import 'package:mconnect/video_app/ik/ik_lyrics_action.dart';
import 'package:mconnect/video_app/ik/ik_playback_bar.dart';

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
  mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 400);
    tester.view.devicePixelRatio = 1;
    final player = _BarPlayer();
    final likes = _Likes(database);
    await tester.runAsync(likes.loadAllLikes);
    final container = ProviderContainer(
      overrides: [
        playerProvider.overrideWith((ref) => player),
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
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: IkPlaybackBar(onOpen: () {}, onAudio: () {}),
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
  void publish(PlayerState next) => state = next;
  @override
  Future<void> seek(Duration position) async => seeks.add(position);
}

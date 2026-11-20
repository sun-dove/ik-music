import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/auth/presentation/providers/auth_provider.dart';
import 'package:mconnect/features/discovery/presentation/providers/recommendations_provider.dart';
import 'package:mconnect/features/player/data/playback_keep_alive_service.dart';
import 'package:mconnect/features/player/data/playback_notification_service.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/features/toplist/presentation/widgets/ranked_song_tile.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/recommendation_source.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/video_app/data/video_catalog.dart';
import 'package:mconnect/video_app/ik/ik_catalog_pages.dart';
import 'package:mconnect/video_app/ik/ik_home_page.dart';
import 'package:mconnect/video_app/ik/ik_search.dart';
import 'package:mconnect/video_app/ik/ik_theme.dart';
import 'package:mconnect/video_app/ui/video_theme.dart';
import 'package:mconnect/video_app/ui/video_shell.dart';

import 'support/content_page_fakes.dart';

Song song(PlatformType platform, String id, {String name = '同名歌曲'}) => Song(
  id: id,
  platform: platform,
  name: name,
  artists: const [Artist(id: 'artist', name: '歌手')],
);

Future<void> mount(
  WidgetTester tester,
  Widget child, {
  ThemeData? theme,
  double width = 900,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 950);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? IkTheme.from(VideoTheme.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(body: child),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('K08 共享排名小字在ik中可读且旧字号不变', (tester) async {
    for (final modern in [false, true]) {
      await mount(
        tester,
        const Column(
          children: [
            RankMovementBadge(rankChange: 2),
            RankMovementBadge(rankChange: null, isNew: true),
          ],
        ),
        theme: modern ? IkTheme.from(VideoTheme.light) : VideoTheme.light,
        width: 320,
        scale: 1.5,
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.text('2')).style?.fontSize,
        modern ? 12 : 11,
      );
      expect(
        tester.widget<Text>(find.text('新')).style?.fontSize,
        modern ? 12 : 10,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('K08 新主题进入共享画布，旧默认及自定义背景不变', (tester) async {
    for (final dark in [false, true]) {
      final base = dark ? VideoTheme.dark : VideoTheme.light;
      Color? canvas, surface;
      final probe = Builder(
        builder: (context) {
          canvas = VideoTheme.canvas(context);
          surface = VideoTheme.surface(context);
          return const SizedBox();
        },
      );
      await mount(tester, probe, theme: base);
      await tester.pumpAndSettle();
      expect(canvas, dark ? const Color(0xff17171c) : VideoTheme.background);
      expect(surface, dark ? const Color(0xff25242c) : VideoTheme.card);
      final modern = IkTheme.from(base);
      await mount(tester, probe, theme: modern);
      await tester.pumpAndSettle();
      expect(canvas, modern.extension<IkThemeColors>()!.background);
      expect(surface, modern.extension<IkThemeColors>()!.surface);
      final imageTheme = IkTheme.from(
        base.copyWith(
          extensions: [const WindowsAppearanceTheme(hasBackground: true)],
        ),
      );
      await mount(tester, probe, theme: imageTheme);
      await tester.pumpAndSettle();
      expect(canvas, Colors.transparent);
      expect(
        imageTheme.scaffoldBackgroundColor,
        Colors.transparent,
        reason: '详情壳和复用页必须透出用户背景',
      );
      expect(imageTheme.appBarTheme.backgroundColor, Colors.transparent);
      expect(imageTheme.navigationRailTheme.backgroundColor!.a, lessThan(1));
      expect(imageTheme.navigationBarTheme.backgroundColor!.a, lessThan(1));
      expect(
        surface,
        imageTheme.extension<IkThemeColors>()!.surface.withValues(alpha: .86),
      );
    }
  });

  testWidgets('K03 搜索逐来源加载、失败重试、分页和筛选不混用来源', (tester) async {
    final first = Completer<VideoPage>();
    final calls = <(PlatformType, int)>[];
    var failed = true;
    final qq = song(PlatformType.qq, 'one');
    final netease = song(PlatformType.netease, 'one');
    final search = IkSearchController(
      platforms: const [PlatformType.qq, PlatformType.netease],
      search: (platform, query, page) async {
        calls.add((platform, page));
        if (platform == PlatformType.qq && page == 1) return first.future;
        if (platform == PlatformType.netease && failed) {
          throw const VideoFailure(
            VideoFailureKind.network,
            '网络失败，可重试',
            canRetry: true,
          );
        }
        return VideoPage(
          songs: [
            platform == PlatformType.qq
                ? song(platform, 'two', name: '第二首')
                : netease,
          ],
          page: page,
          hasMore: false,
        );
      },
    );
    addTearDown(search.dispose);
    final played = <Song>[];
    await mount(
      tester,
      IkSearchPage(
        search: search,
        currentSong: qq,
        onPlay: (song, _) => played.add(song),
        onLike: (_) {},
        onMore: (_) {},
      ),
    );
    await tester.enterText(find.byType(TextField), '歌曲');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('网络失败，可重试'), findsOneWidget);
    first.complete(VideoPage(songs: [qq], page: 1, total: 2, hasMore: true));
    await tester.pump();
    expect(find.text('同名歌曲'), findsOneWidget);
    failed = false;
    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(find.text('同名歌曲'), findsNWidgets(2));
    final selected = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .where((tile) => tile.selected)
        .length;
    expect(selected, 1, reason: '同名歌曲只高亮实际正在播放的来源');
    await tester.tap(find.text('加载更多'));
    await tester.pump();
    expect(find.text('第二首'), findsOneWidget);
    final before = calls.length;
    await tester.tap(find.widgetWithText(ChoiceChip, '网易云'));
    await tester.pump();
    expect(calls.length, before);
    expect(find.text('第二首'), findsNothing);
    await tester.tap(find.text('同名歌曲'));
    expect(played.single.platform, PlatformType.netease);
    expect(calls, [
      (PlatformType.qq, 1),
      (PlatformType.netease, 1),
      (PlatformType.netease, 1),
      (PlatformType.qq, 2),
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('K04 未登录不显示旧账号收藏，登录/同步/本地收藏分别操作', (tester) async {
    final account = <PlatformType>[], sync = <PlatformType>[];
    final removed = <Song>[], played = <Song>[];
    final navigation = <String>[];
    final qq = song(PlatformType.qq, 'q', name: '平台收藏曲目');
    final local = song(PlatformType.netease, 'l', name: '本地收藏曲目');
    await mount(
      tester,
      IkLibraryPage(
        libraries: {
          PlatformType.qq: VideoLibrary(songs: [qq], total: 3),
          PlatformType.netease: VideoLibrary(
            songs: [song(PlatformType.netease, 'stale', name: '旧账号曲目')],
          ),
        },
        loggedIn: const {PlatformType.qq},
        syncing: const {},
        localLikes: [local],
        onAccount: account.add,
        onSync: sync.add,
        onLike: removed.add,
        onPlay: (song, _) => played.add(song),
        onMore: (_) {},
        onNavigate: navigation.add,
        onDownloads: () => navigation.add('/downloads'),
      ),
    );
    expect(find.text('旧账号曲目'), findsNothing);
    expect(find.textContaining('未完整同步'), findsOneWidget);
    await tester.tap(find.text('登录网易云'));
    expect(account, [PlatformType.netease]);
    await tester.tap(find.text('重新同步喜欢的歌曲'));
    expect(sync, [PlatformType.qq]);
    await tester.tap(find.byTooltip('取消收藏'));
    expect(removed, [qq]);
    await tester.tap(find.widgetWithText(ChoiceChip, '本地收藏'));
    await tester.pump();
    expect(find.text('平台收藏曲目'), findsNothing);
    expect(find.byTooltip('取消收藏'), findsNothing);
    await tester.tap(find.text('本地收藏曲目'));
    expect(played, [local]);
    for (final label in ['我的歌单', '本地音乐', '下载管理', '最近播放', '智能歌单']) {
      await tester.tap(find.widgetWithText(ActionChip, label));
    }
    expect(navigation, [
      '/platform-playlists',
      '/local-music',
      '/downloads',
      '/history',
      '/smart-playlists',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('K03 登录失效提供登录动作，不可重试错误不出现重试', (tester) async {
    final accounts = <PlatformType>[];
    final search = IkSearchController(
      platforms: const [PlatformType.netease],
      search: (_, _, _) async =>
          throw const VideoFailure(VideoFailureKind.sessionExpired, '登录已过期'),
    );
    addTearDown(search.dispose);
    await search.submit('歌曲');
    await mount(
      tester,
      IkSearchPage(
        search: search,
        onPlay: (_, _) {},
        onLike: (_) {},
        onMore: (_) {},
        onAccount: accounts.add,
      ),
    );
    expect(find.text('登录已过期'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
    await tester.tap(find.text('登录网易云'));
    expect(accounts, [PlatformType.netease]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('K04 同步失败保留已有收藏，同步中禁用操作并显示进度', (tester) async {
    final synced = <PlatformType>[];
    final qq = song(PlatformType.qq, 'q', name: '保留曲目');
    Widget library(Set<PlatformType> syncing) => IkLibraryPage(
      libraries: {
        PlatformType.qq: VideoLibrary(
          songs: [qq],
          total: 8,
          error: const VideoFailure(
            VideoFailureKind.network,
            '同步中断，可重新同步',
            canRetry: true,
          ),
        ),
      },
      loggedIn: const {PlatformType.qq},
      syncing: syncing,
      onAccount: (_) {},
      onSync: synced.add,
      onLike: (_) {},
      onPlay: (_, _) {},
      onMore: (_) {},
      onNavigate: (_) {},
      onDownloads: () {},
    );
    await mount(tester, library(const {}));
    expect(find.text('同步中断，可重新同步'), findsOneWidget);
    expect(find.text('保留曲目'), findsOneWidget);
    await tester.tap(find.text('重新同步喜欢的歌曲'));
    expect(synced, [PlatformType.qq]);
    await mount(tester, library(const {PlatformType.qq}));
    expect(find.text('正在同步喜欢的音乐…'), findsOneWidget);
    expect(find.text('重新同步喜欢的歌曲'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('保留曲目'), findsOneWidget);
  });

  testWidgets('K04 窄屏大字仍能读同步失败原因并点重试', (tester) async {
    const message = '网络暂时不可用，请检查连接后重新同步';
    var retried = false;
    await mount(
      tester,
      IkLibraryPage(
        libraries: const {
          PlatformType.qq: VideoLibrary(
            error: VideoFailure(
              VideoFailureKind.network,
              message,
              canRetry: true,
            ),
          ),
        },
        loggedIn: const {PlatformType.qq},
        syncing: const {},
        onAccount: (_) {},
        onSync: (_) => retried = true,
        onLike: (_) {},
        onPlay: (_, _) {},
        onMore: (_) {},
        onNavigate: (_) {},
        onDownloads: () {},
      ),
      width: 320,
      scale: 1.5,
    );
    await tester.ensureVisible(find.text(message));
    expect(tester.getSize(find.text(message)).width, greaterThan(100));
    await tester.ensureVisible(find.text('重新同步喜欢的歌曲'));
    await tester.tap(find.text('重新同步喜欢的歌曲'));
    expect(retried, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('K04 本地收藏加载/失败/重试状态不能误显示为空', (tester) async {
    var retries = 0;
    Widget library({bool loading = false, String? error}) => IkLibraryPage(
      libraries: const {},
      loggedIn: const {},
      syncing: const {},
      onAccount: (_) {},
      onSync: (_) {},
      onLike: (_) {},
      onPlay: (_, _) {},
      onMore: (_) {},
      onNavigate: (_) {},
      onDownloads: () {},
      localLoading: loading,
      localError: error,
      onRetryLocal: () => retries++,
    );
    await mount(tester, library(loading: true));
    await tester.tap(find.widgetWithText(ChoiceChip, '本地收藏'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('还没有收藏歌曲'), findsNothing);
    await mount(tester, library(error: '加载喜欢列表失败'));
    expect(find.text('加载喜欢列表失败'), findsOneWidget);
    expect(find.text('还没有收藏歌曲'), findsNothing);
    await tester.tap(find.text('重试'));
    expect(retries, 1);
    await mount(tester, library());
    expect(find.text('还没有收藏歌曲'), findsOneWidget);
  });

  testWidgets('K05 首页显示真实推荐出处、失败动作、完整列表和发现入口', (tester) async {
    final recommendations = _Recommendations(
      RecommendationsState(
        songsByPlatform: {
          PlatformType.qq: [
            for (var i = 0; i < 8; i++)
              song(PlatformType.qq, '$i', name: '推荐$i'),
          ],
        },
        errorsByPlatform: const {PlatformType.netease: '请登录后获取每日推荐'},
        sourceByPlatform: const {
          PlatformType.qq: RecommendationSource(
            platform: PlatformType.qq,
            kind: RecommendationKind.fallbackToplist,
            label: '榜单推荐',
            note: '当前内容来自新歌榜',
          ),
        },
      ),
    );
    final player = _Player();
    final navigation = <String>[];
    await mount(
      tester,
      ProviderScope(
        overrides: [
          recommendationsProvider.overrideWith((ref) => recommendations),
          playerProvider.overrideWith((ref) => player),
          authProvider.overrideWith((ref) => AuthNotifier()),
        ],
        child: IkHomePage(
          onNavigate: navigation.add,
          onPlayer: () {},
          onPlay: (_, _) {},
          onMore: (_) {},
        ),
      ),
      width: 1200,
    );
    expect(recommendations.loads, 1);
    expect(find.text('当前内容来自新歌榜'), findsOneWidget);
    await tester.tap(find.text('榜单'));
    await tester.tap(find.text('新歌速递'));
    await tester.scrollUntilVisible(find.text('浏览全部 · 8 首'), 200);
    await tester.tap(find.text('浏览全部 · 8 首'));
    await tester.scrollUntilVisible(find.text('登录网易云'), 200);
    await tester.tap(find.text('登录网易云'));
    expect(navigation, [
      '/toplists',
      '/new-songs',
      '/recommendations',
      '/login/netease',
    ]);
    await tester.tap(find.widgetWithText(TextButton, '重试').last);
    expect(recommendations.loads, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('K08 新迷你播放器小字至少12px，窄屏放大仍可控制', (tester) async {
    final actions = <String>[];
    await mount(
      tester,
      Align(
        alignment: Alignment.bottomCenter,
        child: VideoMiniPlayer(
          song: song(PlatformType.qq, 'mini', name: '非常长的曲目标题需要省略显示'),
          isPlaying: true,
          onOpen: () => actions.add('open'),
          onToggle: () => actions.add('toggle'),
          onQueue: () => actions.add('queue'),
        ),
      ),
      width: 320,
      scale: 1.5,
    );
    expect(
      tester.widget<Text>(find.text('歌手 · QQ 音乐')).style!.fontSize,
      greaterThanOrEqualTo(12),
    );
    await tester.tap(find.byTooltip('暂停'));
    await tester.tap(find.byTooltip('播放队列'));
    expect(actions, ['toggle', 'queue']);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 720.0, 900.0, 1200.0]) {
    for (final scale in [1.0, 1.25, 1.5]) {
      testWidgets('K04/K08 收藏页登录按钮可读可点 $width / $scale', (tester) async {
        await mount(
          tester,
          IkLibraryPage(
            libraries: const {},
            syncing: const {},
            loggedIn: const {},
            onAccount: (_) {},
            onSync: (_) {},
            onPlay: (_, _) {},
            onLike: (_) {},
            onMore: (_) {},
            onNavigate: (_) {},
            onDownloads: () {},
          ),
          width: width,
          scale: scale,
        );
        await tester.scrollUntilVisible(find.text('登录网易云'), 100);
        expect(find.text('登录网易云').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}

class _Recommendations extends RecommendationsNotifier {
  _Recommendations(RecommendationsState initial) {
    state = initial;
  }
  int loads = 0;
  @override
  Future<void> loadRecommendations() async {
    loads++;
  }
}

class _Player extends PlayerNotifier {
  _Player()
    : super(
        audioController: IdleAudioController(),
        audioControllerFactory: IdleAudioController.new,
        keepAliveController: const NoopPlaybackKeepAliveController(),
        notificationController: const NoopPlaybackNotificationController(),
        stuckWatchdogInterval: Duration.zero,
      );
}

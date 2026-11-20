import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/core/database/app_database.dart';
import 'package:mconnect/core/platform/platform_utils.dart';
import 'package:mconnect/core/share/share_links.dart';
import 'package:mconnect/features/album/presentation/pages/album_page.dart';
import 'package:mconnect/features/artist/presentation/pages/artist_page.dart';
import 'package:mconnect/features/auth/presentation/pages/login_page.dart';
import 'package:mconnect/features/auth/presentation/providers/auth_provider.dart';
import 'package:mconnect/features/backup/presentation/pages/backup_page.dart';
import 'package:mconnect/features/discovery/presentation/pages/recommendations_page.dart';
import 'package:mconnect/features/download/presentation/providers/download_provider.dart';
import 'package:mconnect/features/download/presentation/providers/download_quality_provider.dart';
import 'package:mconnect/features/download/presentation/screens/download_page.dart';
import 'package:mconnect/features/library/presentation/pages/history_page.dart';
import 'package:mconnect/features/library/presentation/pages/platform_playlists_page.dart';
import 'package:mconnect/features/library/data/my_playlists_repository.dart';
import 'package:mconnect/features/library/presentation/providers/my_playlists_provider.dart';
import 'package:mconnect/features/local_music/presentation/pages/local_music_page.dart';
import 'package:mconnect/features/new_songs/presentation/pages/new_songs_page.dart';
import 'package:mconnect/features/player/data/playback_keep_alive_service.dart';
import 'package:mconnect/features/player/data/playback_notification_service.dart';
import 'package:mconnect/features/player/presentation/pages/queue_page.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/features/settings/presentation/pages/settings_page.dart';
import 'package:mconnect/features/smart_playlists/presentation/pages/smart_playlist_editor_page.dart';
import 'package:mconnect/features/smart_playlists/presentation/pages/smart_playlists_page.dart';
import 'package:mconnect/features/stats/presentation/pages/listening_stats_page.dart';
import 'package:mconnect/features/toplist/presentation/pages/toplists_page.dart';
import 'package:mconnect/l10n/ik_strings.dart';
import 'package:mconnect/l10n/video_strings.dart';
import 'package:mconnect/l10n/windows_music_strings.dart';
import 'package:mconnect/models/album.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/models/toplist.dart';
import 'package:mconnect/models/user.dart';
import 'package:mconnect/platform/base/music_platform.dart';
import 'package:mconnect/platform/base/platform_registry.dart';
import 'package:mconnect/video_app/data/video_catalog.dart';
import 'package:mconnect/video_app/data/video_kugou_catalog.dart';
import 'package:mconnect/video_app/ik/ik_audio_page.dart';
import 'package:mconnect/video_app/ik/ik_catalog_pages.dart';
import 'package:mconnect/video_app/ik/ik_home_page.dart';
import 'package:mconnect/video_app/ik/ik_shell.dart';
import 'package:mconnect/video_app/multi_source/multi_source_player.dart';
import 'package:mconnect/video_app/playback/video_platforms.dart';
import 'package:mconnect/video_app/playback/video_stream_state.dart';
import 'package:mconnect/video_app/ui/video_shell.dart';
import 'package:mconnect/video_app/video_app.dart';
import 'package:mconnect/video_app/video_preferences.dart';
import 'package:mconnect/video_app/windows/windows_my_page.dart';
import 'package:mconnect/video_app/windows/windows_music_preferences.dart';
import 'package:mconnect/video_app/windows/windows_player_page.dart';

import 'support/content_page_fakes.dart';

// 正式装配门：真实 VideoMusicApp + Router + 内容/个人数据 providers。
// 仅音频设备、网络目录和账号认证替换为可控边界，数据库使用真实内存 SQLite。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory scratch;
  late AppDatabase db;
  late Box<dynamic> settings;
  late Zone ioZone;

  setUpAll(() async {
    ioZone = Zone.current;
    scratch = await Directory.systemTemp.createTemp('ik-app-integration-');
    Hive.init(scratch.path);
    settings = await Hive.openBox<dynamic>('settings');
    for (final box in ['local_music', 'listening_stats', 'smart_playlists']) {
      await Hive.openBox<dynamic>(box);
    }
    db = AppDatabase.forTesting(NativeDatabase.memory());
    initializeApplicationDatabase(db);
    await db.customSelect('SELECT 1').get();
  });

  setUp(() async {
    PlatformUtils.setDebugOverride(AppPlatform.linux);
    await settings.clear();
    await settings.put('video.cacheInitialized', true);
    for (final platform in PlatformType.musicServices) {
      PlatformRegistry.register(_Content(platform));
    }
  });

  tearDown(() {
    PlatformUtils.setDebugOverride(null);
  });

  tearDownAll(() async {
    await Hive.close();
    await db.close();
    final target = scratch.absolute.path;
    final parent = Directory.systemTemp.absolute.path;
    if (!target.startsWith('$parent${Platform.pathSeparator}') ||
        !scratch.uri.pathSegments
            .where((part) => part.isNotEmpty)
            .last
            .startsWith('ik-app-integration-')) {
      throw StateError('拒绝清理非本门创建的目录：$target');
    }
    if (await scratch.exists()) await scratch.delete(recursive: true);
  });

  Future<_Harness> mount(WidgetTester tester, {double width = 1200}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final catalog = _Catalog();
    final auth = _Auth();
    final preferences = VideoPreferences(settings);
    final unified = WindowsMusicPreferences(
      preferences,
      write: (values) => ioZone.run(() async {
        // Hive 的写锁 Future 不能跨已结束的 FakeAsync zone 传给下一条门。
        // 使用既有写入边界进入真实 IO，仍验证真实 Hive 持久化与发布顺序。
        await settings.putAll(values);
        await settings.flush();
      }),
    )..load();
    final player = PlayerNotifier(
      audioController: IdleAudioController(),
      audioControllerFactory: IdleAudioController.new,
      keepAliveController: const NoopPlaybackKeepAliveController(),
      notificationController: const NoopPlaybackNotificationController(),
      stuckWatchdogInterval: Duration.zero,
      playbackHealthCheckInterval: Duration.zero,
      playbackMemorySaveInterval: Duration.zero,
    );
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((ref) => auth),
        playerProvider.overrideWith((ref) => player),
        myPlaylistsProvider.overrideWith(
          (ref) => MyPlaylistsNotifier(
            repository: MyPlaylistsRepository(storageDirectory: scratch),
          ),
        ),
        downloadProvider.overrideWith(
          (ref) => DownloadNotifier(initialState: const DownloadState()),
        ),
        downloadQualityProvider.overrideWithValue(
          (platform) => unified.quality(platform, download: true),
        ),
      ],
    );
    final harness = _Harness(container, auth, catalog, unified);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      unified.dispose();
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: VideoMusicApp(
          redesign: true,
          expandedPlatforms: true,
          preferences: preferences,
          unifiedPreferences: unified,
          catalog: catalog,
        ),
      ),
    );
    await drain(tester);
    return harness;
  }

  Future<void> selectTab(WidgetTester tester, String label) async {
    final navigation = find.byWidgetPredicate(
      (widget) => widget is NavigationRail || widget is NavigationBar,
    );
    await tester.tap(
      find.descendant(of: navigation, matching: find.text(label)),
    );
    await drain(tester);
  }

  Future<void> tapText(WidgetTester tester, Finder owner, String text) async {
    final target = find.descendant(of: owner, matching: find.text(text));
    final scrollables = find.descendant(
      of: owner,
      matching: find.byType(Scrollable),
    );
    if (scrollables.evaluate().isNotEmpty) {
      final scrolling = tester.state<ScrollableState>(scrollables.first);
      for (
        var attempt = 0;
        target.evaluate().isEmpty && attempt < 20;
        attempt++
      ) {
        scrolling.position.jumpTo(
          (scrolling.position.pixels + 180).clamp(
            scrolling.position.minScrollExtent,
            scrolling.position.maxScrollExtent,
          ),
        );
        await tester.pump();
      }
    }
    expect(target, findsWidgets, reason: '必须存在可点击入口：$text');
    await Scrollable.ensureVisible(tester.element(target.first), alignment: .5);
    await tester.pump();
    await tester.tap(target.first);
    await drain(tester);
  }

  Future<void> back(WidgetTester tester) async {
    final playerBack = find
        .descendant(
          of: find.byType(WindowsPlayerPage),
          matching: find.text(WindowsMusicStrings.back),
        )
        .hitTestable();
    await tester.tap(
      playerBack.evaluate().isNotEmpty
          ? playerBack
          : find.byType(BackButton).hitTestable().last,
    );
    await drain(tester);
  }

  testWidgets('K02/K05 完整独立入口点击四导航、推荐、榜单详情和新歌', (tester) async {
    await mount(tester);
    expect(find.byType(IkShell), findsOneWidget);
    await selectTab(tester, VideoStrings.search);
    expect(find.byType(IkSearchPage).hitTestable(), findsOneWidget);
    await selectTab(tester, IkStrings.library);
    expect(find.byType(IkLibraryPage).hitTestable(), findsOneWidget);
    await selectTab(tester, VideoStrings.my);
    expect(find.byType(WindowsMyPage).hitTestable(), findsOneWidget);
    await selectTab(tester, IkStrings.home);

    await tapText(tester, find.byType(IkHomePage), IkStrings.recommendations);
    expect(find.byType(RecommendationsPage), findsOneWidget);
    expect(find.byType(VideoMiniPlayer).hitTestable(), findsOneWidget);
    await back(tester);
    await tapText(tester, find.byType(IkHomePage), IkStrings.toplists);
    expect(find.byType(ToplistsPage), findsOneWidget);
    await tapText(tester, find.byType(ToplistsPage), '验收热歌榜');
    expect(find.byType(ToplistDetailPage), findsOneWidget);
    expect(find.text('内容歌曲qq'), findsWidgets);
    await back(tester);
    await back(tester);
    await tapText(tester, find.byType(IkHomePage), IkStrings.newSongs);
    expect(find.byType(NewSongsPage), findsOneWidget);
    expect(find.text('内容歌曲qq'), findsWidgets);
    await back(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('K02/K04 曲库真实入口可打开歌单、本地音乐、历史与下载管理', (tester) async {
    await mount(tester);
    await selectTab(tester, IkStrings.library);
    for (final entry in <(String, Type)>[
      (IkStrings.playlists, PlatformPlaylistsPage),
      (VideoStrings.localMusic, LocalMusicPage),
      (IkStrings.history, HistoryPage),
    ]) {
      await tapText(tester, find.byType(IkLibraryPage), entry.$1);
      expect(find.byType(entry.$2), findsOneWidget, reason: entry.$1);
      expect(
        find.byType(VideoMiniPlayer).hitTestable(),
        findsOneWidget,
        reason: '${entry.$1}保留播放器',
      );
      await back(tester);
    }
    await tapText(
      tester,
      find.byType(IkLibraryPage),
      VideoStrings.downloadManagement,
    );
    expect(find.text(VideoStrings.downloadManagement), findsOneWidget);
    await back(tester);
    final router = GoRouter.of(tester.element(find.byType(IkShell)));
    unawaited(router.push<void>('/downloads'));
    await drain(tester);
    expect(find.byType(DownloadPage), findsOneWidget);
    expect(find.byType(VideoMiniPlayer).hitTestable(), findsOneWidget);
    await back(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('K01/K06 非桌面统一下载音质应用全部来源，隐藏无能力的背景字体', (tester) async {
    final app = await mount(tester);
    await selectTab(tester, VideoStrings.my);
    expect(find.text(WindowsMusicStrings.background), findsNothing);
    expect(find.text(WindowsMusicStrings.font), findsNothing);
    await tapText(
      tester,
      find.byType(WindowsMyPage),
      WindowsMusicStrings.downloadQuality,
    );
    await tester.tap(
      find.text(WindowsMusicPreferences.qualityName(AudioLevel.lossless)).last,
    );
    await drain(tester);
    for (final platform in PlatformType.musicServices) {
      expect(
        app.unified.quality(platform, download: true),
        AudioLevel.lossless,
      );
      expect(
        app.container.read(downloadQualityProvider)!(platform),
        AudioLevel.lossless,
      );
    }
    final reloaded = WindowsMusicPreferences(VideoPreferences(settings))
      ..load();
    for (final platform in PlatformType.musicServices) {
      expect(reloaded.quality(platform, download: true), AudioLevel.lossless);
    }
    reloaded.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('K02/K06 我的实际打开音效、悬浮歌词、统计、智能编辑器和备份', (tester) async {
    await mount(tester);
    await selectTab(tester, VideoStrings.my);
    for (final entry in <(String, Type)>[
      (IkStrings.audio, IkAudioPage),
      (IkStrings.floating, SettingsFloatingLyricsPage),
      (IkStrings.stats, ListeningStatsPage),
      (IkStrings.smart, SmartPlaylistsPage),
      (IkStrings.backup, BackupPage),
    ]) {
      await tapText(tester, find.byType(WindowsMyPage), entry.$1);
      expect(find.byType(entry.$2), findsOneWidget, reason: entry.$1);
      expect(
        find.byType(VideoMiniPlayer).hitTestable(),
        findsOneWidget,
        reason: entry.$1,
      );
      if (entry.$2 == SmartPlaylistsPage) {
        await tester.tap(find.byTooltip('新建规则'));
        await drain(tester);
        expect(find.byType(SmartPlaylistEditorPage), findsOneWidget);
        await back(tester);
      }
      await back(tester);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('K02/K03 搜索真实更多菜单进入专辑和歌手，播放后迷你播放器与队列可返回', (tester) async {
    final app = await mount(tester);
    await selectTab(tester, VideoStrings.search);
    await tester.enterText(
      find.descendant(
        of: find.byType(IkSearchPage),
        matching: find.byType(TextField),
      ),
      '验收搜索',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await drain(tester);
    expect(app.catalog.searches.map((call) => call.$1).toSet(), {
      PlatformType.qq,
      PlatformType.netease,
      PlatformType.kugou,
    });
    final tile = find.ancestor(
      of: find.text('搜索歌曲qq'),
      matching: find.byType(IkSongTile),
    );
    await tester.tap(
      find.descendant(of: tile, matching: find.byTooltip(IkStrings.more)),
    );
    await drain(tester);
    await tester.tap(find.text(IkStrings.album));
    await drain(tester);
    expect(find.byType(AlbumPage), findsOneWidget);
    expect(find.text('验收专辑'), findsWidgets);
    await back(tester);
    await tester.tap(
      find.descendant(of: tile, matching: find.byTooltip(IkStrings.more)),
    );
    await drain(tester);
    await tester.tap(find.text('${IkStrings.artist} · 验收歌手'));
    await drain(tester);
    expect(find.byType(ArtistPage), findsOneWidget);
    expect(find.text('验收歌手'), findsWidgets);
    await back(tester);
    await tester.tap(find.text('搜索歌曲qq').first);
    await drain(tester);
    expect(app.container.read(playerProvider).currentSong?.name, '搜索歌曲qq');
    expect(find.byType(WindowsPlayerPage), findsOneWidget);
    final songId = app.container.read(playerProvider).currentSong!.id;
    app.container.read(videoStreamInfoProvider.notifier).state = {
      'qq:$songId': VideoStreamInfo(
        platform: PlatformType.qq,
        songId: songId,
        requestedQuality: AudioLevel.lossless,
        actualFormat: 'flac',
        actualBitrate: 990000,
      ),
    };
    app.container.read(sourcePlaybackViewProvider.notifier).state =
        const SourcePlaybackView(message: '正在尝试备用源');
    await drain(tester);
    var playback = tester.widget<WindowsPlayerPage>(
      find.byType(WindowsPlayerPage),
    );
    expect(playback.sourceDetails?.format, isNull);
    expect(playback.sourceDetails?.bitrate, isNull);
    expect(playback.qualityLabel, isNot(contains('音质见上方')));
    expect(playback.qualityLabel, isNot(contains('FLAC')));
    app.container
        .read(sourcePlaybackViewProvider.notifier)
        .state = const SourcePlaybackView(
      message: '备用播放',
      sourceName: '实际备用',
      format: 'mp3',
      bitrate: 128000,
    );
    await drain(tester);
    playback = tester.widget<WindowsPlayerPage>(find.byType(WindowsPlayerPage));
    expect(playback.sourceDetails?.sourceName, '实际备用');
    expect(playback.sourceDetails?.format, 'mp3');
    expect(playback.sourceDetails?.bitrate, 128000);
    app.container.read(sourcePlaybackViewProvider.notifier).state =
        const SourcePlaybackView(message: '已暂停');
    await drain(tester);
    playback = tester.widget<WindowsPlayerPage>(find.byType(WindowsPlayerPage));
    expect(playback.sourceDetails?.format, isNull);
    expect(playback.sourceDetails?.bitrate, isNull);
    await back(tester);
    final mini = find.byType(VideoMiniPlayer).hitTestable();
    await tester.tap(find.descendant(of: mini, matching: find.text('搜索歌曲qq')));
    await drain(tester);
    expect(find.byType(WindowsPlayerPage), findsOneWidget);
    await back(tester);
    await tester.tap(
      find.descendant(
        of: mini,
        matching: find.byTooltip(VideoStrings.playQueue),
      ),
    );
    await drain(tester);
    expect(find.byType(QueuePage), findsOneWidget);
    await back(tester);
    expect(find.text('搜索歌曲qq'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('K02 非法详情返回首页后播放器仍可打开，不依赖旧Home State', (tester) async {
    final app = await mount(tester);
    await app.container.read(playerProvider.notifier).playPlaylist([
      _song(PlatformType.qq),
    ]);
    await drain(tester);
    final router = GoRouter.of(tester.element(find.byType(IkShell)));
    router.go('/album/not-a-platform/missing');
    await drain(tester);
    expect(find.text(IkStrings.pageMissing), findsOneWidget);
    await tester.tap(find.text(IkStrings.backHome));
    await drain(tester);
    expect(find.byType(IkShell), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(VideoMiniPlayer),
        matching: find.text('内容歌曲qq'),
      ),
    );
    await drain(tester);
    expect(find.byType(WindowsPlayerPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('K04 路由登录成功自动同步；换账号不展示旧收藏；退出清空来源', (tester) async {
    final app = await mount(tester);
    final router = GoRouter.of(tester.element(find.byType(IkShell)));
    unawaited(router.push<void>('/login/qq'));
    await drain(tester);
    expect(find.byType(LoginPage), findsOneWidget);
    app.auth.loginAs('account-a');
    await drain(tester);
    expect(find.byType(LoginPage), findsNothing);
    await selectTab(tester, IkStrings.library);
    expect(app.catalog.syncs, contains((PlatformType.qq, 'account-a')));
    expect(find.text('account-a的收藏'), findsOneWidget);
    app.auth.replaceUser('account-b');
    await drain(tester);
    expect(find.text('account-a的收藏'), findsNothing);
    expect(find.text('account-b的收藏'), findsOneWidget);
    app.auth.replaceUser(null);
    await drain(tester);
    expect(find.text('account-b的收藏'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('K02/K06 带路径冷启动分享先挂载首页，再交链接入口打开同一播放器', (tester) async {
    // Android 接受 mconnect scheme；现有解析器同样接受带 path 的歌曲链接。
    final link = Uri.parse(
      ShareLinks.songLink(_song(PlatformType.qq, name: '冷启动分享歌曲')),
    ).replace(path: '/play').toString();
    tester.binding.platformDispatcher.defaultRouteNameTestValue = link;
    final initial = Completer<String?>();
    const messages = MethodChannel('com.llfbandit.app_links/messages');
    const events = MethodChannel('com.llfbandit.app_links/events');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(messages, (call) async {
      return call.method == 'getInitialLink' ? initial.future : null;
    });
    messenger.setMockMethodCallHandler(events, (_) async => null);
    addTearDown(() {
      if (!initial.isCompleted) initial.complete(null);
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue();
      messenger.setMockMethodCallHandler(messages, null);
      messenger.setMockMethodCallHandler(events, null);
    });
    final app = await mount(tester);
    expect(find.byType(IkShell), findsOneWidget);
    expect(find.text(IkStrings.pageMissing), findsNothing);
    initial.complete(link);
    await drain(tester);
    expect(app.container.read(playerProvider).currentSong?.name, '冷启动分享歌曲');
    expect(find.byType(WindowsPlayerPage), findsOneWidget);
    await back(tester);
    expect(find.byType(IkShell), findsOneWidget);
    expect(find.text('冷启动分享歌曲'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('K08 320宽度实际应用四导航和工具页不溢出', (tester) async {
    await mount(tester, width: 320);
    for (final label in IkShell.labels) {
      await selectTab(tester, label);
      expect(tester.takeException(), isNull, reason: label);
    }
    await tapText(tester, find.byType(WindowsMyPage), IkStrings.audio);
    expect(find.byType(IkAudioPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> drain(WidgetTester tester) async {
  // SQLite/Hive 使用真实 IO；runAsync 让它们完成，再推进路由动画。
  // 数据页可能在动画结束后才挂载并开始 IO，交替推进两者；不对永久进度动画 settle。
  for (var turn = 0; turn < 3; turn++) {
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
  }
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Song _song(PlatformType platform, {String? name}) => Song(
  id: 'fixture-${platform.name}',
  platform: platform,
  name: name ?? '内容歌曲${platform.name}',
  artists: const [Artist(id: 'artist-a', name: '验收歌手')],
  album: const Album(id: 'album-a', name: '验收专辑'),
  albumId: 'album-a',
  duration: const Duration(seconds: 200),
);

class _Content extends FakeContentPlatform {
  _Content(PlatformType platform)
    : super(
        type: platform,
        toplists: const [Toplist(id: '26', name: '验收热歌榜', songCount: 1)],
        rankedSongs: {
          '26': [RankedSong(song: _song(platform), rank: 1)],
        },
        album: const Album(
          id: 'album-a',
          name: '验收专辑',
          artistId: 'artist-a',
          artistName: '验收歌手',
        ),
        albumSongs: [_song(platform)],
        artist: const Artist(id: 'artist-a', name: '验收歌手'),
        artistTopSongs: [_song(platform)],
        newSongs: [_song(platform)],
      );
  @override
  bool get supportsDailyRecommendations => true;
  @override
  Future<List<Song>> getDailyRecommendations() async => [_song(type)];
  @override
  Future<String?> getLyrics(String songId) async =>
      '[00:00.00]验收歌词\n[00:10.00]下一句';
}

class _Catalog extends ExpandedVideoCatalog {
  final searches = <(PlatformType, String, int)>[];
  final syncs = <(PlatformType, String)>[];
  @override
  Future<List<String>> hotSearch() async => const [];
  @override
  Future<VideoPage> search(
    PlatformType platform,
    String query, {
    int page = 1,
    int limit = 30,
  }) async {
    searches.add((platform, query, page));
    return VideoPage(
      songs: [_song(platform, name: '搜索歌曲${platform.name}')],
      page: page,
      hasMore: false,
      total: 1,
    );
  }

  @override
  Future<VideoLibrary> syncLikes(
    PlatformType platform, {
    required String userId,
    void Function(VideoLibrary)? onProgress,
  }) async {
    syncs.add((platform, userId));
    return VideoLibrary(
      songs: [_song(platform, name: '$userId的收藏')],
      total: 1,
      complete: true,
    );
  }
}

class _Auth extends AuthNotifier {
  final _qr = StreamController<QrLoginStatus>.broadcast();
  String _loginId = 'account-a';
  @override
  Future<void> init() async {}
  @override
  Future<QrLoginResult> getQrCodeWithVariant(
    PlatformType platform, {
    String? authVariant,
  }) async =>
      const QrLoginResult(key: 'fixture', qrUrl: 'https://example.test/login');
  @override
  Stream<QrLoginStatus> pollQrStatus(
    PlatformType platform,
    String key, {
    String? authVariant,
  }) => _qr.stream;
  @override
  Future<User?> onQrLoginSuccess(PlatformType platform) async {
    replaceUser(_loginId);
    return state.userFor(platform);
  }

  void loginAs(String id) {
    _loginId = id;
    _qr.add(QrLoginStatus.success);
  }

  void replaceUser(String? id) {
    state = state.copyWith(
      loggedUsers: {
        PlatformType.qq: id == null
            ? null
            : User(id: id, nickname: id, platform: PlatformType.qq),
      },
    );
  }

  @override
  void dispose() {
    unawaited(_qr.close());
    super.dispose();
  }
}

class _Harness {
  const _Harness(this.container, this.auth, this.catalog, this.unified);
  final ProviderContainer container;
  final _Auth auth;
  final _Catalog catalog;
  final WindowsMusicPreferences unified;
}

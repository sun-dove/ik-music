import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/core/database/app_database.dart';
import 'package:mconnect/core/network/api_exception.dart';
import 'package:mconnect/core/platform/platform_utils.dart';
import 'package:mconnect/core/share/share_links.dart';
import 'package:mconnect/core/widgets/song_actions_sheet.dart';
import 'package:mconnect/features/album/presentation/pages/album_page.dart';
import 'package:mconnect/features/artist/presentation/pages/artist_page.dart';
import 'package:mconnect/features/auth/presentation/pages/login_page.dart';
import 'package:mconnect/features/auth/presentation/providers/auth_provider.dart';
import 'package:mconnect/features/backup/presentation/pages/backup_page.dart';
import 'package:mconnect/features/discovery/presentation/pages/recommendations_page.dart';
import 'package:mconnect/features/download/presentation/providers/download_provider.dart';
import 'package:mconnect/features/download/data/download_directory_service.dart';
import 'package:mconnect/features/download/data/repositories/download_manager.dart';
import 'package:mconnect/features/download/domain/entities/download_task.dart';
import 'package:mconnect/features/download/domain/entities/download_failure.dart';
import 'package:mconnect/features/library/presentation/providers/likes_provider.dart';
import 'package:mconnect/features/download/presentation/providers/download_quality_provider.dart';
import 'package:mconnect/features/download/presentation/screens/download_page.dart';
import 'package:mconnect/features/library/presentation/pages/history_page.dart';
import 'package:mconnect/features/library/presentation/pages/platform_playlists_page.dart';
import 'package:mconnect/features/library/presentation/pages/playlist_detail_page.dart';
import 'package:mconnect/features/library/data/my_playlists_repository.dart';
import 'package:mconnect/features/library/presentation/providers/my_playlists_provider.dart';
import 'package:mconnect/features/local_music/presentation/pages/local_music_page.dart';
import 'package:mconnect/features/local_music/presentation/providers/local_music_provider.dart';
import 'package:mconnect/features/local_music/data/local_lyrics_store.dart';
import 'package:mconnect/features/local_music/data/local_scan_root_store.dart';
import 'package:mconnect/features/local_music/data/local_track_store.dart';
import 'package:mconnect/features/local_music/data/online_library_snapshot.dart';
import 'package:mconnect/features/local_music/data/track_ratings_store.dart';
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
import 'package:mconnect/l10n/ik_workspace_strings.dart';
import 'package:mconnect/l10n/video_strings.dart';
import 'package:mconnect/l10n/windows_music_strings.dart';
import 'package:mconnect/models/album.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/playlist.dart';
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
import 'package:mconnect/video_app/ik/ik_workspace.dart';
import 'package:mconnect/video_app/ik/ik_settings_workspace.dart';
import 'package:mconnect/video_app/ik/ik_playback_bar.dart';
import 'package:mconnect/video_app/ik/ik_controls.dart';
import 'package:mconnect/video_app/ik/ik_song_table.dart';
import 'package:mconnect/video_app/ik/ik_search_workspace.dart';
import 'package:mconnect/video_app/ik/ik_library_workspace.dart';
import 'package:mconnect/video_app/ik/ik_downloads_workspace.dart';
import 'package:mconnect/video_app/multi_source/multi_source_player.dart';
import 'package:mconnect/video_app/playback/video_platforms.dart';
import 'package:mconnect/video_app/playback/video_stream_state.dart';
import 'package:mconnect/video_app/ui/video_shell.dart';
import 'package:mconnect/video_app/video_app.dart';
import 'package:mconnect/video_app/video_preferences.dart';
import 'package:mconnect/video_app/windows/windows_appearance.dart';
import 'package:mconnect/video_app/windows/windows_my_page.dart';
import 'package:mconnect/video_app/windows/windows_music_preferences.dart';
import 'package:mconnect/video_app/windows/windows_player_page.dart';
import 'package:mconnect/video_app/windows/windows_window_controller.dart';

import 'support/content_page_fakes.dart';
import 'download_fakes.dart' show MemoryDownloadDirectoryStore;

// 正式装配门：真实 VideoMusicApp + Router + 内容/个人数据 providers。
// 仅音频设备、网络目录和账号认证替换为可控边界，数据库使用真实内存 SQLite。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory scratch;
  late AppDatabase db;
  late Box<dynamic> settings;
  late Zone ioZone;

  setUpAll(() async {
    // 本机审阅截图加载实际字体，不复制字体进发行包。
    final captureFont = Platform.environment['IK_CAPTURE_UI_FONT'];
    if (captureFont != null) {
      final data = ByteData.sublistView(await File(captureFont).readAsBytes());
      for (final family in [
        'sans-serif',
        'Roboto',
        'Microsoft YaHei UI',
        'Ahem',
      ]) {
        await (FontLoader(family)..addFont(Future.value(data))).load();
      }
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
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
    await MyPlaylistsRepository(storageDirectory: scratch)
        .restoreStorageSnapshot(null);
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

  Future<_Harness> mount(
    WidgetTester tester, {
    double width = 1200,
    bool desktopAppearance = false,
    bool workspace = false,
    bool alignToDesign = false,
    bool pageInteractionRefinements = false,
    DownloadState? downloads,
    double textScale = 1,
    PlayerAudioController? audioController,
    List<String> hotTerms = const [],
    bool hotFailure = false,
    LocalMusicNotifier? localNotifier,
    DownloadManager? downloadManager,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final catalog = _Catalog(hotTerms: hotTerms, hotFailure: hotFailure);
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
    final window = desktopAppearance ? _Window() : null;
    final appearance = window == null
        ? null
        : WindowsAppearance(
            preferences: unified,
            directory: Directory('${scratch.path}/appearance'),
            window: window,
          );
    if (appearance != null) {
      await tester.runAsync(() async {
        await unified.update(
          unified.value.copyWith(closeAction: WindowsCloseAction.exit),
        );
        await appearance.initialize();
      });
    }
    final player = PlayerNotifier(
      audioController: audioController ?? IdleAudioController(),
      audioControllerFactory: IdleAudioController.new,
      keepAliveController: const NoopPlaybackKeepAliveController(),
      notificationController: const NoopPlaybackNotificationController(),
      stuckWatchdogInterval: Duration.zero,
      playbackHealthCheckInterval: Duration.zero,
      playbackMemorySaveInterval: Duration.zero,
    );
    if (localNotifier != null) await localNotifier.initialize();
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((ref) => auth),
        playerProvider.overrideWith((ref) => player),
        if (localNotifier != null)
          localMusicProvider.overrideWith((ref) => localNotifier),
        myPlaylistsProvider.overrideWith(
          (ref) => MyPlaylistsNotifier(
            repository: _IoPlaylistsRepository(ioZone, scratch),
          ),
        ),
        downloadProvider.overrideWith(
          (ref) => DownloadNotifier(
            initialState: downloads ?? const DownloadState(),
            manager: downloadManager,
          ),
        ),
        downloadQualityProvider.overrideWithValue(
          (platform) => unified.quality(platform, download: true),
        ),
      ],
    );
    final harness = _Harness(
      container,
      auth,
      catalog,
      unified,
      appearance: appearance,
      window: window,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      appearance?.dispose();
      unified.dispose();
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(
          key: const ValueKey('ik-ui-capture'),
          child: VideoMusicApp(
            redesign: true,
            workspace: workspace,
            alignToDesign: alignToDesign,
            pageInteractionRefinements: pageInteractionRefinements,
            expandedPlatforms: true,
            preferences: preferences,
            unifiedPreferences: unified,
            windowsAppearance: appearance,
            catalog: catalog,
          ),
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

  testWidgets('A01/A04 原稿对齐真实共用搜索、来源和专辑歌手路由', (tester) async {
    final app = await mount(tester, workspace: true, alignToDesign: true);
    final shell = find.byType(IkDesktopWorkspace);
    final shellWidget = tester.widget<IkDesktopWorkspace>(shell);
    expect(shellWidget.alignToDesign, isTrue);
    expect(shellWidget.onSearch, isNotNull);
    shellWidget.onSearch!('对齐验收');
    await drain(tester);
    expect(app.catalog.searches.map((c) => c.$2).toSet(), {'对齐验收'});
    expect(find.byType(IkSearchWorkspace).hitTestable(), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(IkSearchWorkspace),
        matching: find.byType(TextField),
      ),
      findsNothing,
    );
    await tester.tap(find.text('搜索歌曲qq').first);
    await drain(tester);
    final player = tester.widget<WindowsPlayerPage>(
      find.byType(WindowsPlayerPage),
    );
    expect(player.alignToDesign, isTrue);
    expect(player.onArtist, isNotNull);
    expect(player.onAlbum, isNotNull);
    player.onAlbum!();
    await drain(tester);
    expect(find.byType(AlbumPage).hitTestable(), findsOneWidget);
    await back(tester);
    tester
        .widget<WindowsPlayerPage>(find.byType(WindowsPlayerPage))
        .onArtist!();
    await drain(tester);
    expect(find.byType(ArtistPage).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('E00 页面修订真实装配与原默认兼容', (tester) async {
    for (final enabled in [false, true]) {
      final app = await mount(
        tester,
        workspace: true,
        alignToDesign: true,
        pageInteractionRefinements: enabled,
      );
      await tester.tap(find.byKey(const ValueKey('ik-workspace-nav-1')));
      await drain(tester);
      expect(
        find.text('查看全部推荐').hitTestable(),
        enabled ? findsNothing : findsOneWidget,
      );
      expect(
        find.text('播放全部').hitTestable(),
        enabled ? findsOneWidget : findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('ik-workspace-nav-2')));
      await drain(tester);
      if (enabled) {
        final likes = find.text('喜欢的音乐').hitTestable();
        final before = tester.getTopLeft(likes).dy;
        await tester.tap(
          find.byKey(const ValueKey('ik-library-category-playlists')),
        );
        await drain(tester);
        expect(tester.getTopLeft(likes).dy, moreOrLessEquals(before));
      }
      await app.container
          .read(playerProvider.notifier)
          .playSong(_song(PlatformType.qq));
      await drain(tester);
      final router = GoRouter.of(
        tester.element(find.byType(IkDesktopWorkspace)),
      );
      unawaited(router.push<void>('/player'));
      await drain(tester);
      final playerPage = tester.widget<WindowsPlayerPage>(
        find.byType(WindowsPlayerPage),
      );
      expect(
        playerPage.lyricsAutoResumeDelay,
        enabled ? const Duration(seconds: 3) : null,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await drain(tester);
    }
  });

  testWidgets('A06 新下载路由与曲库入口共用新工作页和播放栏', (tester) async {
    await mount(tester, workspace: true, alignToDesign: true);
    final router = GoRouter.of(tester.element(find.byType(IkDesktopWorkspace)));
    unawaited(router.push<void>('/downloads'));
    await drain(tester);
    expect(find.byType(IkDownloadsWorkspace).hitTestable(), findsOneWidget);
    expect(find.byType(IkPlaybackBar).hitTestable(), findsOneWidget);
    expect(find.text(VideoStrings.downloadManagement), findsOneWidget);
    await back(tester);
    await tester.tap(find.byKey(const ValueKey('ik-workspace-nav-2')));
    await drain(tester);
    await tester.tap(find.text(VideoStrings.download).hitTestable());
    await drain(tester);
    expect(find.byType(IkDownloadsWorkspace).hitTestable(), findsOneWidget);
    expect(find.byType(IkPlaybackBar).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('R01 音乐库五分类在同壳切换，后四分类不跳旧路由', (tester) async {
    await mount(tester, workspace: true, alignToDesign: true);
    await tester.tap(find.byKey(const ValueKey('ik-workspace-nav-2')));
    await drain(tester);
    final library = find.byType(IkLibraryWorkspace);
    final router = GoRouter.of(tester.element(library));
    for (final entry in <(String, Type?, String)>[
      (IkStrings.playlists, PlatformPlaylistsPage, 'playlists'),
      (VideoStrings.localMusic, LocalMusicPage, 'local'),
      (VideoStrings.download, IkDownloadsWorkspace, 'downloads'),
      (IkStrings.smart, SmartPlaylistsPage, 'smart'),
      (IkWorkspaceStrings.likes, null, 'likes'),
    ]) {
      final tab = find
          .descendant(
            of: library,
            matching: find.byKey(ValueKey('ik-library-category-${entry.$3}')),
          )
          .hitTestable();
      expect(tab, findsOneWidget, reason: '五分类始终可见：${entry.$1}');
      await tester.tap(tab);
      await drain(tester);
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/',
        reason: '${entry.$1}应在音乐库同壳切换',
      );
      expect(find.byType(IkDesktopWorkspace).hitTestable(), findsOneWidget);
      expect(find.byType(IkPlaybackBar).hitTestable(), findsOneWidget);
      expect(
        find.descendant(
          of: library,
          matching: find.text(IkWorkspaceStrings.library),
        ),
        findsOneWidget,
      );
      if (entry.$2 != null) {
        expect(find.byType(entry.$2!), findsOneWidget);
      }
      expect(tab.hitTestable(), findsOneWidget, reason: '当前分类仍可点击：${entry.$1}');
      expect(tester.takeException(), isNull, reason: entry.$1);
    }
  });

  testWidgets('R05 搜索空态显示真实热词，点击使用原分来源搜索', (tester) async {
    final app = await mount(
      tester,
      workspace: true,
      alignToDesign: true,
      hotTerms: const ['真实热词一', '真实热词二'],
    );
    await tester.tap(find.byKey(const ValueKey('ik-workspace-nav-1')));
    await drain(tester);
    final search = find.byType(IkSearchWorkspace);
    expect(
      find.descendant(of: search, matching: find.text('真实热词一')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: search, matching: find.text('真实热词二')),
      findsOneWidget,
    );
    await tester.tap(find.text('真实热词二'));
    await drain(tester);
    expect(app.catalog.searches.map((call) => call.$2).toSet(), {'真实热词二'});
    expect(find.text('真实热词一'), findsNothing);
    expect(find.text('搜索歌曲qq'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('R05 热词失败原因和重试可见，推荐与手动搜索仍可用', (tester) async {
    final app = await mount(
      tester,
      workspace: true,
      alignToDesign: true,
      hotFailure: true,
    );
    await tester.tap(find.byKey(const ValueKey('ik-workspace-nav-1')));
    await drain(tester);
    final search = find.byType(IkSearchWorkspace);
    expect(
      find.descendant(of: search, matching: find.text('热搜暂时连接失败')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: search, matching: find.text(VideoStrings.retry)),
      findsWidgets,
    );
    expect(
      find.descendant(of: search, matching: find.textContaining('推荐精选')),
      findsWidgets,
    );
    app.catalog.hotFailure = false;
    app.catalog.hotTerms = ['重新取得的热词'];
    await tester.tap(
      find
          .descendant(of: search, matching: find.text(VideoStrings.retry))
          .first,
    );
    await drain(tester);
    expect(find.text('重新取得的热词'), findsOneWidget);
    expect(find.text('热搜暂时连接失败'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('R02 音乐库歌单和规则详情返回原分类，创建与筛选仍可用', (tester) async {
    final app = await mount(tester, workspace: true, alignToDesign: true);
    await tester.tap(find.byKey(const ValueKey('ik-workspace-nav-2')));
    await drain(tester);
    await tester.tap(
      find.byKey(const ValueKey('ik-library-category-playlists')),
    );
    await drain(tester);
    expect(find.byType(IkDesktopWorkspace).hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('新建歌单').hitTestable());
    await drain(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '同壳验收歌单',
    );
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('新建')),
    );
    await drain(tester);
    expect(app.container.read(myPlaylistsProvider).isSaving, isFalse);
    expect(app.container.read(myPlaylistsProvider).error, isNull);
    expect(find.text('同壳验收歌单'), findsOneWidget);
    await tester.tap(find.text('同壳验收歌单'));
    await drain(tester);
    expect(find.byType(PlaylistDetailPage).hitTestable(), findsOneWidget);
    await back(tester);
    expect(find.byType(PlatformPlaylistsPage).hitTestable(), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ik-library-category-smart')));
    await drain(tester);
    await tester.tap(find.byTooltip('新建规则').hitTestable());
    await drain(tester);
    expect(find.byType(SmartPlaylistEditorPage).hitTestable(), findsOneWidget);
    await back(tester);
    expect(find.byType(SmartPlaylistsPage), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ik-library-category-local')));
    await drain(tester);
    expect(
      find.byKey(const Key('local-music-search-field')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('local-music-merge-switch')).hitTestable(),
      findsOneWidget,
    );
    expect(
      app.container.read(myPlaylistsProvider).playlists.map((p) => p.name),
      contains('同壳验收歌单'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('R08 已登录账号使用居中窗口，取消不变更账号', (tester) async {
    final app = await mount(tester, workspace: true, alignToDesign: true);
    app.auth.replaceUser('菜单验收账号');
    await drain(tester);
    // 通过实际设置组件的既有入口执行，避免直接调用私有账号方法。
    await tester.tap(find.byKey(const ValueKey('ik-workspace-nav-4')));
    await drain(tester);
    await tester.tap(find.byKey(const ValueKey('ik-settings-accounts')));
    await drain(tester);
    final settingsPage = tester.widget<IkSettingsWorkspace>(
      find.byType(IkSettingsWorkspace),
    );
    settingsPage.onAccount(PlatformType.qq);
    await drain(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('菜单验收账号'), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await drain(tester);
    expect(
      app.container.read(authProvider).userFor(PlatformType.qq)?.id,
      '菜单验收账号',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('R02 本地分类沿用歌曲列与更多按钮，分组筛选和批量目标居中', (tester) async {
    final local = _localLibrary();
    final app = await mount(
      tester,
      workspace: true,
      alignToDesign: true,
      localNotifier: local,
    );
    final target = await tester.runAsync(
      () => app.container.read(myPlaylistsProvider.notifier).create('本地验收目标'),
    );
    expect(target, isNotNull);
    await drain(tester);
    await tester.tap(find.byKey(const ValueKey('ik-workspace-nav-2')));
    await drain(tester);
    await tester.tap(find.byKey(const ValueKey('ik-library-category-local')));
    await drain(tester);
    final localPage = find.byType(LocalMusicPage);
    expect(
      find.descendant(of: localPage, matching: find.byType(IkSongTableRow)),
      findsWidgets,
    );
    expect(
      find.descendant(of: localPage, matching: find.byType(IkSongTableHeader)),
      findsOneWidget,
      reason: '本地歌曲与喜欢的音乐使用相同列标题',
    );
    final more = find
        .descendant(of: localPage, matching: find.byTooltip(IkStrings.more))
        .first;
    await tester.ensureVisible(more);
    await tester.tap(more);
    await drain(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(PopupMenuItem<SongAction>), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await drain(tester);
    for (final view in [
      LocalLibraryView.albums,
      LocalLibraryView.artists,
      LocalLibraryView.folders,
    ]) {
      local.setView(view);
      await drain(tester);
      final group = find
          .descendant(of: localPage, matching: find.byType(ExpansionTile))
          .first;
      await tester.ensureVisible(group);
      await tester.tap(group);
      await drain(tester);
      final row = find.descendant(
        of: group,
        matching: find.byType(IkSongTableRow),
      );
      expect(row, findsOneWidget, reason: '${view.name}组内也沿用统一歌曲列');
      final groupMore = find.descendant(
        of: row,
        matching: find.byTooltip(IkStrings.more),
      );
      await tester.ensureVisible(groupMore);
      await tester.tap(groupMore);
      await drain(tester);
      expect(find.byType(BottomSheet), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await drain(tester);
    }
    local.setView(LocalLibraryView.songs);
    local.setKeyword('本地歌曲甲');
    await drain(tester);
    expect(local.state.visibleSongs.map((song) => song.name), ['本地歌曲甲']);
    local.clearQuery();
    await drain(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('local-music-select-toggle')),
      -180,
      scrollable: find
          .descendant(of: localPage, matching: find.byType(Scrollable))
          .first,
    );
    await tester.tap(find.byKey(const Key('local-music-select-toggle')));
    await drain(tester);
    await tester.ensureVisible(find.byKey(const Key('local-music-select-all')));
    await tester.tap(find.byKey(const Key('local-music-select-all')));
    await drain(tester);
    await tester.tap(find.byKey(const Key('local-music-batch-add')));
    await drain(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(Dialog), findsOneWidget);
    await tester.tap(find.text('本地验收目标').hitTestable());
    await drain(tester);
    final saved = await tester.runAsync(
      () =>
          app.container.read(myPlaylistsProvider.notifier).getSongs(target!.id),
    );
    expect(
      saved!.map((song) => song.id).toSet(),
      local.state.songs.map((song) => song.id).toSet(),
    );
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('R07 歌单导出及二维码居中，取消保留当前库分类', (tester) async {
    final app = await mount(tester, workspace: true, alignToDesign: true);
    await tester.runAsync(
      () => app.container.read(myPlaylistsProvider.notifier).create('导出验收歌单'),
    );
    await drain(tester);
    await tester.tap(find.byKey(const ValueKey('ik-workspace-nav-2')));
    await drain(tester);
    await tester.tap(
      find.byKey(const ValueKey('ik-library-category-playlists')),
    );
    await drain(tester);
    await tester.tap(find.byTooltip('歌单操作').hitTestable());
    await drain(tester);
    await tester.tap(find.text('导出歌单').hitTestable());
    await drain(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(Dialog), findsOneWidget);
    for (final label in [
      '分享链接',
      'M3U8 播放列表',
      '纯文本（歌名 - 歌手）',
      IkStrings.playlistJson,
      '二维码分享',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('二维码分享'));
    await drain(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.textContaining('扫码导入'), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await drain(tester);
    expect(find.byType(PlatformPlaylistsPage), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ik-library-category-playlists')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('R07 歌曲菜单打开后后台移除目标行，缩放与取消不访问失效锚点', (tester) async {
    final app = await mount(tester, workspace: true, alignToDesign: true);
    final likes = app.container.read(likesProvider.notifier);
    for (final existing in app.container.read(likesProvider).songs.toList()) {
      await tester.runAsync(() => likes.toggleLike(existing));
    }
    const song = Song(
      id: 'revision-menu-removed-anchor',
      platform: PlatformType.qq,
      name: '后台移除锚点验收歌曲',
      artists: [Artist(id: 'revision-anchor-artist', name: '验收歌手')],
    );
    expect(await tester.runAsync(() => likes.toggleLike(song)), isTrue);
    await drain(tester);
    await tester.tap(find.byKey(const ValueKey('ik-workspace-nav-2')));
    await drain(tester);
    final library = find.byType(IkLibraryWorkspace);
    final row = find.descendant(
      of: library,
      matching: find.byWidgetPredicate(
        (widget) => widget is IkSongTableRow && widget.song == song,
      ),
    );
    expect(row, findsOneWidget);
    final more = find.descendant(
      of: row,
      matching: find.byTooltip(IkStrings.more),
    );
    await tester.ensureVisible(more);
    await tester.tap(more);
    await drain(tester);
    expect(find.byType(PopupMenuItem<String>), findsWidgets);
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
    final downloads = app.container.read(downloadProvider).tasks.toList();

    expect(await tester.runAsync(() => likes.toggleLike(song)), isFalse);
    await drain(tester);
    expect(row, findsNothing, reason: '真实通知器已移除歌曲行和更多按钮');
    tester.view.physicalSize = const Size(900, 900);
    await drain(tester);
    expect(tester.takeException(), isNull, reason: '窗口重排不读取失效按钮上下文');
    expect(find.byType(PopupMenuItem<String>), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await drain(tester);
    expect(find.byType(PopupMenuItem<String>), findsNothing);
    expect(library.hitTestable(), findsOneWidget);
    expect(app.container.read(likesProvider).songs, isEmpty);
    expect(app.container.read(downloadProvider).tasks, downloads);
    expect(tester.takeException(), isNull);
  });

  testWidgets('R08 VIP下载音质居中，取消不重试，确认沿用统一保存与原重试', (tester) async {
    final song = _song(PlatformType.qq, name: 'VIP音质入口验收歌曲');
    final task = DownloadTask(
      id: DownloadTask.buildId(song, AudioLevel.high),
      song: song,
      quality: AudioLevel.high,
      status: DownloadStatus.failed,
      createdAt: DateTime(2026, 11, 22),
      error: '当前账号无此下载音质权限',
      failureKind: DownloadFailureKind.vip,
    );
    final app = await mount(
      tester,
      workspace: true,
      alignToDesign: true,
      desktopAppearance: true,
      downloads: DownloadState(tasks: [task]),
      downloadManager: DownloadManager(
        directoryService: _IoDownloadDirectoryService(ioZone, scratch),
      ),
    );
    final platform = _VipContent();
    PlatformRegistry.register(platform);
    await tester.tap(find.byKey(const ValueKey('ik-workspace-nav-2')));
    await drain(tester);
    await tester.tap(
      find.byKey(const ValueKey('ik-library-category-downloads')),
    );
    await drain(tester);
    await tester.tap(find.byKey(const ValueKey('ik-downloads-group-failed')));
    await drain(tester);
    final resolve = find.byKey(ValueKey('ik-download-resolve-${task.id}'));
    await tester.ensureVisible(resolve);
    await tester.tap(resolve);
    await drain(tester);
    expect(find.byType(BottomSheet), findsNothing);
    final dialog = find.byType(Dialog);
    expect(dialog, findsOneWidget);
    final surface = find
        .descendant(
          of: dialog,
          matching: find.byWidgetPredicate(
            (widget) => widget is Material && widget.type == MaterialType.card,
          ),
        )
        .first;
    final rect = tester.getRect(surface);
    expect(rect.center.dx, closeTo(600, 1));
    expect(rect.center.dy, closeTo(450, 1));
    for (final level in [
      AudioLevel.low,
      AudioLevel.high,
      AudioLevel.lossless,
      AudioLevel.hires,
      AudioLevel.master,
    ]) {
      expect(
        find.descendant(
          of: dialog,
          matching: find.text(WindowsMusicPreferences.qualityName(level)),
        ),
        findsOneWidget,
      );
    }
    final before = app.unified.value;
    final storedBefore = settings.get(WindowsMusicPreferences.key);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await drain(tester);
    expect(app.unified.value, same(before));
    expect(settings.get(WindowsMusicPreferences.key), storedBefore);
    expect(app.container.read(downloadProvider).tasks, [task]);
    expect(platform.qualities, isEmpty);
    expect(find.byType(IkLibraryWorkspace).hitTestable(), findsOneWidget);

    await tester.tap(resolve);
    await drain(tester);
    await tester.tap(
      find.descendant(
        of: dialog,
        matching: find.text(
          WindowsMusicPreferences.qualityName(AudioLevel.lossless),
        ),
      ),
    );
    await drain(tester);
    expect(dialog, findsNothing);
    final reloaded = WindowsMusicPreferences(VideoPreferences(settings))
      ..load();
    for (final platform in PlatformType.musicServices) {
      expect(
        app.unified.quality(platform, download: true),
        AudioLevel.lossless,
      );
      expect(reloaded.quality(platform, download: true), AudioLevel.lossless);
    }
    reloaded.dispose();
    final tasks = app.container.read(downloadProvider).tasks;
    expect(tasks.any((value) => value.id == task.id), isFalse);
    final retried = tasks.singleWhere(
      (value) => value.id == DownloadTask.buildId(song, AudioLevel.lossless),
    );
    expect(retried.song, song);
    expect(retried.quality, AudioLevel.lossless);
    expect(retried.failureKind, DownloadFailureKind.vip);
    expect(platform.qualities, isNotEmpty);
    expect(platform.qualities, everyElement(AudioLevel.lossless));
    expect(tester.takeException(), isNull);
  });

  testWidgets('U01/U03/U06 新工作区实际装配、七区、音质持久化与按需队列', (tester) async {
    final harness = await mount(tester, workspace: true);
    expect(find.byType(IkDesktopWorkspace), findsOneWidget);
    expect(find.byType(IkPlaybackBar), findsOneWidget);
    expect(find.text(IkStrings.nextUp), findsNothing);
    await tester.tap(find.byKey(const ValueKey('ik-workspace-nav-4')));
    await drain(tester);
    for (final section in [
      'audio',
      'appearance',
      'lyrics',
      'sources',
      'downloads',
      'accounts',
      'backup',
    ]) {
      await tester.tap(find.byKey(ValueKey('ik-settings-$section')));
      await drain(tester);
      expect(tester.takeException(), isNull, reason: section);
    }
    await tester.tap(find.byKey(const ValueKey('ik-settings-audio')));
    await drain(tester);
    final select = find
        .descendant(
          of: find.byType(IkSettingsWorkspace),
          matching: find.byType(IkSelect<String>),
        )
        .first;
    await tester.ensureVisible(select);
    await tester.tap(select);
    await drain(tester);
    await tester.tap(
      find.text(WindowsMusicPreferences.qualityName(AudioLevel.lossless)).last,
    );
    await drain(tester);
    expect(harness.unified.quality(PlatformType.qq), AudioLevel.lossless);
    final reloaded = WindowsMusicPreferences(VideoPreferences(settings))
      ..load();
    expect(reloaded.quality(PlatformType.kugou), AudioLevel.lossless);
    reloaded.dispose();
    await tester.tap(find.byKey(const ValueKey('ik-bar-queue')));
    await drain(tester);
    expect(find.text(IkStrings.nextUp), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await drain(tester);
    expect(find.text(IkStrings.nextUp), findsNothing);
    expect(tester.takeException(), isNull);
    await captureIkUi(tester, 'settings');
  });

  testWidgets('E02 根底栏音效从备份切到播放与音效并保留设置状态', (tester) async {
    const filePicker = MethodChannel('miguelruivo.flutter.plugins.filepicker');
    final messenger = tester.binding.defaultBinaryMessenger;
    final backupBytes = Uint8List.fromList(
      utf8.encode('{"manifest":{"version":1,"appVersion":"preview-fixture"}}'),
    );
    var selections = 0;
    messenger.setMockMethodCallHandler(filePicker, (call) async {
      expect(call.method, 'custom');
      selections++;
      return [
        {
          'name': 'preview.json',
          'size': backupBytes.length,
          'bytes': backupBytes,
        },
      ];
    });
    addTearDown(() => messenger.setMockMethodCallHandler(filePicker, null));
    await mount(tester, workspace: true, alignToDesign: true);
    await tester.tap(find.byKey(const ValueKey('ik-workspace-nav-4')));
    await drain(tester);
    final workspace = find.byType(IkSettingsWorkspace);
    final settingsState = tester.state(workspace);
    final route = ModalRoute.of(tester.element(workspace));
    expect(route, isNotNull);
    final backupTab = find.byKey(const ValueKey('ik-settings-backup'));
    final backupContent = find.text(IkWorkspaceStrings.backupExportHint);
    final preview = find.text(IkWorkspaceStrings.backupPreview);
    final audioContent = find.byKey(const ValueKey('ik-spatial-emphasis'));
    final bottomAudio = find.descendant(
      of: find.byType(IkPlaybackBar),
      matching: find.byTooltip(IkWorkspaceStrings.audio),
    );
    expect(audioContent.hitTestable(), findsOneWidget);
    for (var attempt = 0; attempt < 2; attempt++) {
      await tester.tap(backupTab);
      await drain(tester);
      expect(backupContent.hitTestable(), findsOneWidget);
      expect(audioContent, findsNothing);
      if (attempt == 0) {
        final selectBackup = find.widgetWithText(
          OutlinedButton,
          IkWorkspaceStrings.selectBackup,
        );
        await tester.ensureVisible(selectBackup);
        await tester.tap(selectBackup);
        await drain(tester);
      }
      expect(preview, findsOneWidget);
      expect(selections, 1);
      expect(bottomAudio.hitTestable(), findsOneWidget);
      await tester.tap(bottomAudio);
      await drain(tester);
      expect(audioContent.hitTestable(), findsOneWidget);
      expect(backupContent, findsNothing);
      expect(preview, findsNothing);
      expect(tester.state(workspace), same(settingsState));
      expect(ModalRoute.of(tester.element(workspace)), same(route));
      expect(tester.takeException(), isNull);
    }
    await tester.tap(backupTab);
    await drain(tester);
    expect(preview, findsOneWidget);
    expect(selections, 1);
  });

  testWidgets('E03 旧设置普通重建保留当前备份区', (tester) async {
    await mount(tester, workspace: true);
    final settingsNav = find.byKey(const ValueKey('ik-workspace-nav-4'));
    await tester.tap(settingsNav);
    await drain(tester);
    final workspace = find.byType(IkSettingsWorkspace);
    final settingsState = tester.state(workspace);
    await tester.tap(find.byKey(const ValueKey('ik-settings-backup')));
    await drain(tester);
    final backupContent = find.text(IkWorkspaceStrings.backupExportHint);
    expect(backupContent.hitTestable(), findsOneWidget);
    final before = tester.widget<IkSettingsWorkspace>(workspace);
    await tester.tap(settingsNav);
    await drain(tester);
    expect(tester.widget<IkSettingsWorkspace>(workspace), isNot(same(before)));
    expect(tester.state(workspace), same(settingsState));
    expect(backupContent.hitTestable(), findsOneWidget);
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

  testWidgets('U02/U05 新搜索下拉、锚定歌曲菜单、详情和完整播放器共用底栏', (tester) async {
    final app = await mount(tester, workspace: true);
    await tester.tap(find.byKey(const ValueKey('ik-workspace-nav-1')));
    await drain(tester);
    await tester.enterText(
      find.descendant(
        of: find.byType(IkSearchWorkspace),
        matching: find.byType(TextField),
      ),
      '验收搜索',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await drain(tester);
    final tile = find.ancestor(
      of: find.text('搜索歌曲qq'),
      matching: find.byType(IkSongTile),
    );
    await tester.tap(
      find.descendant(of: tile, matching: find.byTooltip(IkStrings.more)),
    );
    await drain(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(PopupMenuItem<String>), findsWidgets);
    await tester.tap(find.text(IkStrings.album));
    await drain(tester);
    expect(find.byType(AlbumPage), findsOneWidget);
    expect(find.byType(IkPlaybackBar).hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('播放与音效').hitTestable());
    await drain(tester);
    expect(find.byType(IkSettingsWorkspace).hitTestable(), findsOneWidget);
    expect(find.byType(BackButton).hitTestable(), findsOneWidget);
    await back(tester);
    expect(find.byType(AlbumPage).hitTestable(), findsOneWidget);
    await back(tester);
    await tester.tap(find.text('搜索歌曲qq').first);
    await drain(tester);
    expect(app.container.read(playerProvider).currentSong?.name, '搜索歌曲qq');
    expect(find.byType(WindowsPlayerPage), findsOneWidget);
    expect(find.byType(IkPlaybackBar).hitTestable(), findsOneWidget);
    expect(
      tester
          .widget<WindowsPlayerPage>(find.byType(WindowsPlayerPage))
          .onDesktopLyrics,
      isNull,
    );
    await captureIkUi(tester, 'player');
    await back(tester);
    expect(find.byType(IkSearchWorkspace).hitTestable(), findsOneWidget);
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

  testWidgets('K08 当前我的页更改关闭动作立即更新标签，不依赖离开路由', (tester) async {
    final app = await mount(tester, desktopAppearance: true);
    await selectTab(tester, VideoStrings.my);
    expect(
      tester.widget<WindowsMyPage>(find.byType(WindowsMyPage)).closeAction,
      WindowsCloseAction.exit,
    );
    await tapText(
      tester,
      find.byType(WindowsMyPage),
      WindowsMusicStrings.closeWindow,
    );
    await tester.tap(find.text(WindowsMusicStrings.minimize).last);
    await drain(tester);

    expect(app.window!.action, WindowsCloseAction.minimize);
    expect(app.unified.closeAction, WindowsCloseAction.minimize);
    expect(find.text(WindowsMusicStrings.applied), findsOneWidget);
    expect(
      tester.widget<WindowsMyPage>(find.byType(WindowsMyPage)).closeAction,
      WindowsCloseAction.minimize,
    );
    expect(
      find.text(
        '${WindowsMusicStrings.minimize}\n${WindowsMusicStrings.minimizeHint}',
      ),
      findsOneWidget,
    );
    await tester.runAsync(
      () => app.appearance!.setCloseAction(WindowsCloseAction.exit),
    );
    await drain(tester);
    expect(
      tester.widget<WindowsMyPage>(find.byType(WindowsMyPage)).closeAction,
      WindowsCloseAction.exit,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('K08 当前我的页字体变更与失效回退立即更新显示名和错误', (tester) async {
    final app = await mount(tester, desktopAppearance: true);
    final appearance = app.appearance!;
    await selectTab(tester, VideoStrings.my);
    await tester.runAsync(() => appearance.selectSystemFont('Noto Sans SC'));
    await drain(tester);
    expect(
      tester.widget<WindowsMyPage>(find.byType(WindowsMyPage)).fontLabel,
      'Noto Sans SC',
    );

    app.window!.fonts = ['Microsoft YaHei UI'];
    await appearance.refreshFonts();
    await drain(tester);
    var page = tester.widget<WindowsMyPage>(find.byType(WindowsMyPage));
    expect(page.fontLabel, WindowsMusicStrings.defaultFont);
    expect(
      page.errors,
      contains(WindowsMusicStrings.failure(DesktopFailure.fileMissing)),
    );
    await tapText(tester, find.byType(WindowsMyPage), WindowsMusicStrings.font);
    expect(
      find.text(WindowsMusicStrings.failure(DesktopFailure.fileMissing)),
      findsWidgets,
    );
    await tester.tap(find.text(WindowsMusicStrings.cancel));
    await drain(tester);

    await tester.runAsync(appearance.resetFont);
    await drain(tester);
    page = tester.widget<WindowsMyPage>(find.byType(WindowsMyPage));
    expect(page.fontLabel, WindowsMusicStrings.defaultFont);
    expect(page.errors, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('K08 当前我的页背景和原生控制错误恢复实时呈现', (tester) async {
    final app = await mount(tester, desktopAppearance: true);
    final appearance = app.appearance!;
    await selectTab(tester, VideoStrings.my);
    await tester.runAsync(() async {
      final draft = await appearance.prepareBackground(
        File('assets/platform-icons/qq-music.jpg'),
      );
      await appearance.applyBackground(draft);
      await precacheImage(
        FileImage(appearance.backgroundFile!),
        tester.element(find.byType(WindowsBackground)),
      );
    });
    await drain(tester);
    expect(
      tester.widget<WindowsMyPage>(find.byType(WindowsMyPage)).backgroundLabel,
      WindowsMusicStrings.savedBackground,
    );
    await tester.runAsync(appearance.resetBackground);
    await drain(tester);
    expect(
      tester.widget<WindowsMyPage>(find.byType(WindowsMyPage)).backgroundLabel,
      WindowsMusicStrings.defaultBackground,
    );

    app.window!.available = false;
    await expectLater(
      appearance.setCloseAction(WindowsCloseAction.minimize),
      throwsA(isA<DesktopConfigurationException>()),
    );
    await drain(tester);
    var page = tester.widget<WindowsMyPage>(find.byType(WindowsMyPage));
    expect(page.nativeAvailable, isFalse);
    expect(
      page.errors,
      contains(WindowsMusicStrings.failure(DesktopFailure.nativeUnavailable)),
    );
    final closeTile = find.ancestor(
      of: find.text(WindowsMusicStrings.closeWindow),
      matching: find.byType(ListTile),
    );
    await tapText(
      tester,
      find.byType(WindowsMyPage),
      WindowsMusicStrings.closeWindow,
    );
    expect(tester.widget<ListTile>(closeTile).onTap, isNull);
    expect(find.byType(BottomSheet), findsNothing);
    app.window!.available = true;
    await tester.runAsync(appearance.initialize);
    await drain(tester);
    page = tester.widget<WindowsMyPage>(find.byType(WindowsMyPage));
    expect(page.nativeAvailable, isTrue);
    expect(page.errors, isEmpty);
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

  for (final dark in [false, true]) {
    for (final width in [320.0, 390.0, 720.0, 900.0, 1200.0, 1440.0]) {
      for (final scale in [1.0, 1.25, 1.5]) {
        testWidgets(
          'R09 新音乐库和搜索全量布局 ${dark ? '深' : '浅'} ${width.toInt()}/$scale',
          (tester) async {
            await tester.runAsync(
              () => settings.put('video.theme', dark ? 'dark' : 'light'),
            );
            final local = _localLibrary();
            final app = await mount(
              tester,
              workspace: true,
              alignToDesign: true,
              width: width,
              textScale: scale,
              hotTerms: const ['热门曲目一', '热门歌手二', '热门专辑三'],
              localNotifier: local,
              downloads: DownloadState(
                tasks: [
                  for (final status in [
                    DownloadStatus.downloading,
                    DownloadStatus.completed,
                    DownloadStatus.failed,
                  ])
                    DownloadTask(
                      id: 'revision-${status.name}',
                      song: _song(PlatformType.qq, name: '布局验收${status.name}'),
                      quality: AudioLevel.high,
                      status: status,
                      createdAt: DateTime(2026, 11, 22),
                      progress: .4,
                      error: status == DownloadStatus.failed ? '来源连接失败' : null,
                      failureKind: status == DownloadStatus.failed
                          ? DownloadFailureKind.network
                          : null,
                    ),
                ],
              ),
            );
            await tester.runAsync(
              () => app.container
                  .read(myPlaylistsProvider.notifier)
                  .create('布局验收歌单'),
            );
            await drain(tester);
            final suffix = '${dark ? 'dark' : 'light'}-${width.toInt()}-$scale';
            Future<void> check(String scene) async {
              expect(tester.takeException(), isNull, reason: '$scene $suffix');
              expect(
                find.byType(Dialog).evaluate().isEmpty
                    ? find.byType(IkPlaybackBar).hitTestable()
                    : find.byType(IkPlaybackBar),
                findsOneWidget,
                reason: '底栏保留；模态窗口关闭后恢复操作：$scene $suffix',
              );
              await captureIkUi(tester, 'revision-$scene-$suffix');
            }

            await tester.tap(find.byKey(const ValueKey('ik-workspace-nav-1')));
            await drain(tester);
            await check('search-empty');
            expect(find.text('热门曲目一').hitTestable(), findsOneWidget);
            await tester.tap(find.byKey(const ValueKey('ik-workspace-nav-2')));
            await drain(tester);
            for (final category in [
              'likes',
              'playlists',
              'local',
              'downloads',
              'smart',
            ]) {
              final tab = find.byKey(ValueKey('ik-library-category-$category'));
              await tester.ensureVisible(tab);
              await tester.pump();
              expect(tab.hitTestable(), findsOneWidget);
              await tester.tap(tab);
              await drain(tester);
              await check('library-$category');
              if (category == 'downloads') {
                for (final group in ['completed', 'failed']) {
                  final downloadTab = find.byKey(
                    ValueKey('ik-downloads-group-$group'),
                  );
                  await tester.ensureVisible(downloadTab);
                  await tester.tap(downloadTab);
                  await drain(tester);
                  await check('downloads-$group');
                }
              }
              if (category == 'playlists') {
                await tester.tap(find.byTooltip('歌单操作').hitTestable());
                await drain(tester);
                await tester.tap(find.text('导出歌单').hitTestable());
                await drain(tester);
                expect(find.byType(BottomSheet), findsNothing);
                await check('export');
                await tester.ensureVisible(find.text('二维码分享'));
                await tester.tap(find.text('二维码分享'));
                await drain(tester);
                expect(find.byType(BottomSheet), findsNothing);
                await check('qr');
                await tester.sendKeyEvent(LogicalKeyboardKey.escape);
                await drain(tester);
              }
              if (category == 'local') {
                for (final view in [
                  LocalLibraryView.albums,
                  LocalLibraryView.artists,
                  LocalLibraryView.folders,
                ]) {
                  local.setView(view);
                  await drain(tester);
                  final group = switch (view) {
                    LocalLibraryView.albums => find.byKey(
                      Key('album-group-${local.state.albumGroups.first.id}'),
                    ),
                    LocalLibraryView.artists => find.byKey(
                      Key('artist-group-${local.state.artistGroups.first.id}'),
                    ),
                    LocalLibraryView.folders => find.byKey(
                      Key('folder-group-${local.state.folderGroups.first.id}'),
                    ),
                    LocalLibraryView.songs => throw StateError('分组门不能使用歌曲视图'),
                  };
                  await tester.scrollUntilVisible(
                    group,
                    180,
                    scrollable: find
                        .descendant(
                          of: find.byType(LocalMusicPage),
                          matching: find.byType(Scrollable),
                        )
                        .first,
                  );
                  final groupHeader = find
                      .descendant(of: group, matching: find.byType(ListTile))
                      .first;
                  await Scrollable.ensureVisible(
                    tester.element(groupHeader),
                    alignment: .2,
                  );
                  await tester.pump();
                  expect(groupHeader.hitTestable(), findsOneWidget);
                  await tester.tap(groupHeader);
                  await drain(tester);
                  expect(
                    find.descendant(
                      of: group,
                      matching: find.byType(IkSongTableRow),
                    ),
                    findsWidgets,
                    reason: '${view.name}必须实际展开歌曲，不能以未命中点击代替场景',
                  );
                  await check('local-${view.name}');
                }
                local.setView(LocalLibraryView.songs);
                await drain(tester);
                final localScroll = tester.state<ScrollableState>(
                  find
                      .descendant(
                        of: find.byType(LocalMusicPage),
                        matching: find.byType(Scrollable),
                      )
                      .first,
                );
                localScroll.position.jumpTo(
                  localScroll.position.minScrollExtent,
                );
                await tester.pump();
                await tester.ensureVisible(
                  find.byKey(const Key('local-music-select-toggle')),
                );
                await tester.tap(
                  find.byKey(const Key('local-music-select-toggle')),
                );
                await drain(tester);
                await tester.ensureVisible(
                  find.byKey(const Key('local-music-select-all')),
                );
                await tester.tap(
                  find.byKey(const Key('local-music-select-all')),
                );
                await drain(tester);
                await check('local-selection');
                await tester.ensureVisible(
                  find.byKey(const Key('local-music-batch-add')),
                );
                await tester.tap(
                  find.byKey(const Key('local-music-batch-add')),
                );
                await drain(tester);
                expect(find.byType(BottomSheet), findsNothing);
                await check('local-batch-target');
                await tester.sendKeyEvent(LogicalKeyboardKey.escape);
                await drain(tester);
                local.setSelectionMode(false);
                await drain(tester);
              }
            }
          },
        );
      }
    }
  }

  for (final width in [320.0, 390.0, 720.0, 900.0, 1200.0, 1440.0]) {
    testWidgets('U11 工作区五页与播放栏真实装配 ${width.toInt()} / 150%', (tester) async {
      final app = await mount(
        tester,
        workspace: true,
        width: width,
        textScale: 1.5,
      );
      for (var index = 0; index < 5; index++) {
        await tester.tap(find.byKey(ValueKey('ik-workspace-nav-$index')));
        await drain(tester);
        expect(
          tester.takeException(),
          isNull,
          reason: 'page=$index,width=$width',
        );
        if (width == 1200) await captureIkUi(tester, 'page-$index');
      }
      await app.container
          .read(playerProvider.notifier)
          .playSong(_song(PlatformType.qq));
      await drain(tester);
      final router = GoRouter.of(
        tester.element(find.byType(IkDesktopWorkspace)),
      );
      unawaited(router.push<void>('/player'));
      await drain(tester);
      expect(find.byType(WindowsPlayerPage), findsOneWidget);
      final page = tester.widget<WindowsPlayerPage>(
        find.byType(WindowsPlayerPage),
      );
      expect(page.onDesktopLyrics, isNull, reason: 'Linux 原生歌词不可用');
      expect(tester.takeException(), isNull, reason: 'player width=$width');
      if (width == 320) await captureIkUi(tester, 'player-narrow');
    });
  }

  for (final dark in [false, true]) {
    for (final width in [320.0, 390.0, 720.0, 900.0, 1200.0, 1440.0]) {
      for (final scale in [1.0, 1.25, 1.5]) {
        testWidgets('A07 对齐版实际装配 ${dark ? '深' : '浅'} ${width.toInt()}/$scale', (
          tester,
        ) async {
          await tester.runAsync(
            () => settings.put('video.theme', dark ? 'dark' : 'light'),
          );
          final app = await mount(
            tester,
            workspace: true,
            alignToDesign: true,
            width: width,
            textScale: scale,
            downloads: DownloadState(
              tasks: [
                for (final status in [
                  DownloadStatus.downloading,
                  DownloadStatus.completed,
                  DownloadStatus.failed,
                ])
                  DownloadTask(
                    id: 'capture-${status.name}',
                    song: _song(PlatformType.qq, name: '验收${status.name}歌曲'),
                    quality: AudioLevel.high,
                    status: status,
                    createdAt: DateTime(2026, 11, 21),
                    progress: .42,
                    downloadedBytes: 4200000,
                    totalBytes: 10000000,
                    filePath: status == DownloadStatus.completed
                        ? 'D:/音乐/验收歌曲.mp3'
                        : null,
                    error: status == DownloadStatus.failed
                        ? '该来源连接失败，请稍后重试'
                        : null,
                    failureKind: status == DownloadStatus.failed
                        ? DownloadFailureKind.network
                        : null,
                  ),
              ],
            ),
          );
          final suffix = '${dark ? 'dark' : 'light'}-${width.toInt()}-$scale';
          Future<void> check(String page) async {
            expect(tester.takeException(), isNull, reason: '$page $suffix');
            if ((width == 1200 && scale == 1) ||
                (width == 390 && scale == 1.5)) {
              await captureIkUi(tester, 'aligned-$page-$suffix');
            }
          }

          await check('home');
          await tester.enterText(
            find.byKey(const ValueKey('ik-workspace-search')),
            '验收搜索',
          );
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await drain(tester);
          await check('search');
          await tester.runAsync(
            () => app.container
                .read(likesProvider.notifier)
                .toggleLike(_song(PlatformType.qq)),
          );
          await tester.tap(find.byKey(const ValueKey('ik-workspace-nav-2')));
          await drain(tester);
          await check('library');
          await tester.tap(find.byKey(const ValueKey('ik-workspace-nav-3')));
          await drain(tester);
          await check('recent');
          await tester.tap(find.byKey(const ValueKey('ik-workspace-nav-4')));
          await drain(tester);
          await check('audio');
          await tester.tap(
            find.byKey(const ValueKey('ik-settings-appearance')),
          );
          await drain(tester);
          await check('appearance');
          final router = GoRouter.of(
            tester.element(find.byType(IkDesktopWorkspace)),
          );
          unawaited(router.push<void>('/downloads'));
          await drain(tester);
          await check('downloads');
          for (final group in ['completed', 'failed']) {
            final tab = find.byKey(ValueKey('ik-downloads-group-$group'));
            await tester.ensureVisible(tab);
            await tester.pump();
            await tester.tap(tab);
            await drain(tester);
            await check('downloads-$group');
          }
          await back(tester);
          await app.container
              .read(playerProvider.notifier)
              .playSong(_song(PlatformType.qq));
          await drain(tester);
          app.container
              .read(sourcePlaybackViewProvider.notifier)
              .state = const SourcePlaybackView(
            message: '当前音源已返回音频',
            details: '主来源已连接\n备用来源未请求\n实际格式与码率由响应确认',
            sourceName: '验收来源',
            format: 'mp3',
            bitrate: 320000,
          );
          unawaited(router.push<void>('/player'));
          await drain(tester);
          await check('player');
          final expand = find.byKey(const ValueKey('ik-player-source-expand'));
          await tester.ensureVisible(expand);
          await tester.pump();
          await tester.tap(expand);
          await drain(tester);
          expect(
            find.byKey(const ValueKey('ik-inline-source-status')),
            findsOneWidget,
          );
          expect(find.byType(AlertDialog), findsNothing);
          await check('player-source');
        });
      }
    }
  }

  testWidgets('U05 切歌装载中禁止拖动进度，装载完成后恢复', (tester) async {
    final audio = _LoadingAudio();
    final app = await mount(tester, workspace: true, audioController: audio);
    addTearDown(() {
      if (!audio.ready.isCompleted) audio.ready.complete();
    });
    final play = app.container
        .read(playerProvider.notifier)
        .playSong(_song(PlatformType.qq));
    await drain(tester);
    expect(app.container.read(playerProvider).isTransitioning, isTrue);
    final seek = find.byKey(const ValueKey('ik-bar-seek'));
    expect(tester.widget<Slider>(seek).onChanged, isNull);
    audio.ready.complete();
    await play;
    await drain(tester);
    expect(app.container.read(playerProvider).isTransitioning, isFalse);
    expect(tester.widget<Slider>(seek).onChanged, isNotNull);
    await tester.pump(const Duration(seconds: 3));
    await drain(tester);
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

Future<void> captureIkUi(WidgetTester tester, String name) async {
  final directory = Platform.environment['IK_CAPTURE_UI_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('ik-ui-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final folder = Directory(directory);
      await folder.create(recursive: true);
      await File('${folder.path}/ik-flutter-$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
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

LocalMusicNotifier _localLibrary() => LocalMusicNotifier(
  trackStore: MemoryLocalTrackStore(const [
    LocalTrackEntry(
      path: '/受控曲库/专辑甲/本地歌曲甲.mp3',
      mtime: 1,
      size: 1000,
      title: '本地歌曲甲',
      artistName: '本地歌手甲',
      albumName: '本地专辑甲',
      durationMs: 180000,
    ),
    LocalTrackEntry(
      path: '/受控曲库/专辑乙/本地歌曲乙.mp3',
      mtime: 1,
      size: 2000,
      title: '本地歌曲乙',
      artistName: '本地歌手乙',
      albumName: '本地专辑乙',
      durationMs: 240000,
    ),
  ]),
  lyricsStore: MemoryLocalLyricsStore(),
  rootStore: MemoryLocalScanRootStore(),
  onlineSnapshot: MemoryOnlineLibrarySnapshot(),
  ratingsStore: MemoryTrackRatingsStore(),
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

class _VipContent extends _Content {
  _VipContent() : super(PlatformType.qq);
  final qualities = <AudioLevel>[];
  @override
  Future<String> getSongUrl(
    String songId, {
    AudioLevel quality = AudioLevel.low,
  }) {
    qualities.add(quality);
    throw NoVipMembershipException('QQ音乐');
  }
}

class _IoDownloadDirectoryService extends DownloadDirectoryService {
  _IoDownloadDirectoryService(this.ioZone, Directory directory)
    : super(
        store: MemoryDownloadDirectoryStore(),
        defaultRootProvider: () async =>
            Directory('${directory.path}/vip-download'),
      );
  final Zone ioZone;
  @override
  Future<DownloadDestination> resolveDownloadDestination(
    PlatformType platformType,
    AudioLevel quality, {
    bool create = true,
  }) => ioZone.run(
    () =>
        super.resolveDownloadDestination(platformType, quality, create: create),
  );
}

// 保留真实文件格式和原仓库逻辑；IO 操作完整进入真实 Zone，避免 flush
// 的 Future 被测试 FakeAsync 持住，留下尚未完成的零字节 .tmp 文件。
class _IoPlaylistsRepository extends MyPlaylistsRepository {
  const _IoPlaylistsRepository(this.ioZone, Directory directory)
    : super(storageDirectory: directory);
  final Zone ioZone;

  @override
  Future<List<Playlist>> getPlaylists() => ioZone.run(super.getPlaylists);
  @override
  Future<Playlist> createPlaylist(String name) =>
      ioZone.run(() => super.createPlaylist(name));
  @override
  Future<List<Song>> getSongs(String id) =>
      ioZone.run(() => super.getSongs(id));
  @override
  Future<String?> exportPlaylistLink(String id) =>
      ioZone.run(() => super.exportPlaylistLink(id));
  @override
  Future<bool> addSong(String id, Song song) =>
      ioZone.run(() => super.addSong(id, song));
}

class _Catalog extends ExpandedVideoCatalog {
  _Catalog({this.hotTerms = const [], this.hotFailure = false});
  List<String> hotTerms;
  bool hotFailure;
  final searches = <(PlatformType, String, int)>[];
  final syncs = <(PlatformType, String)>[];
  @override
  Future<List<String>> hotSearch() async {
    if (hotFailure) {
      throw const VideoFailure(VideoFailureKind.network, '热搜暂时连接失败');
    }
    return hotTerms;
  }

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
  const _Harness(
    this.container,
    this.auth,
    this.catalog,
    this.unified, {
    this.appearance,
    this.window,
  });
  final ProviderContainer container;
  final _Auth auth;
  final _Catalog catalog;
  final WindowsMusicPreferences unified;
  final WindowsAppearance? appearance;
  final _Window? window;
}

class _Window extends WindowsWindowController {
  WindowsCloseAction action = WindowsCloseAction.minimize;
  bool available = true;
  List<String> fonts = ['Microsoft YaHei UI', 'Noto Sans SC'];

  @override
  Future<void> setCloseAction(WindowsCloseAction value) async {
    if (!available) {
      throw const DesktopConfigurationException(
        DesktopFailure.nativeUnavailable,
      );
    }
    action = value;
  }

  @override
  Future<List<String>> listFonts() async => fonts;
}

class _LoadingAudio extends IdleAudioController {
  final ready = Completer<void>();
  @override
  Future<void> setUrl(String url) => ready.future;
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:ui' show Tristate;

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/core/database/app_database.dart';
import 'package:mconnect/core/network/api_exception.dart';
import 'package:mconnect/core/platform/platform_utils.dart';
import 'package:mconnect/core/widgets/song_actions_sheet.dart';
import 'package:mconnect/features/album/presentation/pages/album_page.dart';
import 'package:mconnect/features/audio_effects/presentation/providers/audio_effects_provider.dart';
import 'package:mconnect/features/auth/presentation/providers/auth_provider.dart';
import 'package:mconnect/features/discovery/presentation/pages/recommendations_page.dart';
import 'package:mconnect/features/discovery/presentation/providers/recommendations_provider.dart';
import 'package:mconnect/features/download/data/download_directory_service.dart';
import 'package:mconnect/features/download/data/repositories/download_manager.dart';
import 'package:mconnect/features/download/presentation/providers/download_provider.dart';
import 'package:mconnect/features/download/presentation/providers/download_quality_provider.dart';
import 'package:mconnect/features/floating_lyrics/data/floating_lyrics_models.dart';
import 'package:mconnect/features/floating_lyrics/presentation/providers/floating_lyrics_provider.dart';
import 'package:mconnect/features/library/data/my_playlists_repository.dart';
import 'package:mconnect/features/library/presentation/pages/platform_playlists_page.dart';
import 'package:mconnect/features/library/presentation/providers/history_provider.dart';
import 'package:mconnect/features/library/presentation/providers/likes_provider.dart';
import 'package:mconnect/features/library/presentation/providers/my_playlists_provider.dart';
import 'package:mconnect/features/local_music/presentation/pages/local_music_page.dart';
import 'package:mconnect/features/local_music/presentation/providers/local_music_provider.dart';
import 'package:mconnect/features/local_music/data/local_lyrics_store.dart';
import 'package:mconnect/features/local_music/data/local_scan_root_store.dart';
import 'package:mconnect/features/local_music/data/local_track_store.dart';
import 'package:mconnect/features/local_music/data/online_library_snapshot.dart';
import 'package:mconnect/features/local_music/data/track_ratings_store.dart';
import 'package:mconnect/features/new_songs/presentation/pages/new_songs_page.dart';
import 'package:mconnect/features/new_songs/presentation/providers/new_songs_provider.dart';
import 'package:mconnect/features/player/data/playback_keep_alive_service.dart';
import 'package:mconnect/features/player/data/playback_notification_service.dart';
import 'package:mconnect/features/player/presentation/pages/queue_page.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/features/smart_playlists/presentation/pages/smart_playlists_page.dart';
import 'package:mconnect/features/toplist/presentation/pages/toplists_page.dart';
import 'package:mconnect/features/toplist/presentation/providers/toplists_provider.dart';
import 'package:mconnect/l10n/ik_discovery_revision_strings.dart';
import 'package:mconnect/l10n/ik_library_revision_strings.dart';
import 'package:mconnect/l10n/ik_player_alignment_strings.dart';
import 'package:mconnect/l10n/ik_source_catalog_strings.dart';
import 'package:mconnect/l10n/ik_strings.dart';
import 'package:mconnect/l10n/expanded_strings.dart';
import 'package:mconnect/l10n/source_strings.dart';
import 'package:mconnect/l10n/video_strings.dart';
import 'package:mconnect/l10n/windows_music_strings.dart';
import 'package:mconnect/models/album.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/playlist.dart';
import 'package:mconnect/models/recommendation_source.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/models/toplist.dart';
import 'package:mconnect/platform/base/music_platform.dart';
import 'package:mconnect/platform/base/platform_registry.dart';
import 'package:mconnect/video_app/data/video_catalog.dart';
import 'package:mconnect/video_app/data/video_kugou_catalog.dart';
import 'package:mconnect/video_app/built_in/catalog.dart';
import 'package:mconnect/video_app/built_in/catalog_coordinator.dart';
import 'package:mconnect/video_app/built_in/fixed_importer.dart';
import 'package:mconnect/video_app/built_in/managed_settings.dart';
import 'package:mconnect/video_app/ik/ik_downloads_workspace.dart';
import 'package:mconnect/video_app/ik/ik_home_page.dart';
import 'package:mconnect/video_app/ik/ik_library_workspace.dart';
import 'package:mconnect/video_app/ik/ik_lyrics_action.dart';
import 'package:mconnect/video_app/ik/ik_playback_bar.dart';
import 'package:mconnect/video_app/ik/ik_recent_page.dart';
import 'package:mconnect/video_app/ik/ik_runtime.dart';
import 'package:mconnect/video_app/ik/ik_theme.dart';
import 'package:mconnect/video_app/ik/ik_workspace.dart';
import 'package:mconnect/video_app/ik/ik_workspace_navigation.dart';
import 'package:mconnect/video_app/ik/ik_controls.dart';
import 'package:mconnect/video_app/ik/ik_search_workspace.dart';
import 'package:mconnect/video_app/ik/ik_song_table.dart';
import 'package:mconnect/video_app/ik/ik_settings_workspace.dart';
import 'package:mconnect/video_app/ik/ik_spatial_runtime.dart';
import 'package:mconnect/video_app/ik/ik_strict_settings.dart';
import 'package:mconnect/video_app/lx_source/lx_source.dart';
import 'package:mconnect/video_app/multi_source/multi_source_player.dart';
import 'package:mconnect/video_app/ui/source_manager_page.dart';
import 'package:mconnect/video_app/ui/video_shell.dart';
import 'package:mconnect/video_app/video_app.dart';
import 'package:mconnect/video_app/video_preferences.dart';
import 'package:mconnect/video_app/windows/windows_appearance.dart';
import 'package:mconnect/video_app/windows/windows_music_preferences.dart';
import 'package:mconnect/video_app/windows/windows_player_page.dart';
import 'package:mconnect/video_app/windows/windows_window_controller.dart';
import 'package:mconnect/video_app/ui/catalog_pages.dart'
    show videoPlatformLabel, videoSongKey;
import 'package:mconnect/video_app/ui/video_theme.dart';

import 'support/content_page_fakes.dart';

const _track = Song(
  id: 'semantics-track',
  name: '语义验收曲目',
  platform: PlatformType.qq,
  artists: [Artist(id: 'semantics-artist', name: '语义验收歌手')],
  album: Album(id: 'semantics-album', name: '语义验收专辑'),
  albumId: 'semantics-album',
);

void main() {
  final binding = _SemanticsBinding();
  late Directory scratch;
  late AppDatabase suiteDb;
  late Box<dynamic> settings;
  late Zone ioZone;
  final lyricsCalls = <MethodCall>[];

  setUpAll(() async {
    ioZone = Zone.current;
    scratch = await Directory.systemTemp.createTemp('ik-a11y-gate-');
    debugPrint('IK_SEMANTICS 临时存储目录：${scratch.path}');
    Hive.init(scratch.path);
    settings = await Hive.openBox<dynamic>('settings');
    for (final name in ['local_music', 'listening_stats', 'smart_playlists']) {
      await Hive.openBox<dynamic>(name);
    }
    suiteDb = AppDatabase.forTesting(NativeDatabase.memory());
    initializeApplicationDatabase(suiteDb);
    await suiteDb.customSelect('SELECT 1').get();
    final messenger = binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('sun-dove.yueyin/ik-desktop'),
      (call) async => switch (call.method) {
        'initialize' => true,
        'capabilities' => {'tray': true, 'media': true, 'windowMemory': true},
        _ => null,
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.mconnect.mconnect/floating_lyrics'),
      (call) async {
        lyricsCalls.add(call);
        return true;
      },
    );
  });

  setUp(() async {
    binding.trace.clear();
    lyricsCalls.clear();
    await settings.clear();
    for (final name in ['local_music', 'listening_stats', 'smart_playlists']) {
      await Hive.box<dynamic>(name).clear();
    }
    // 数据库单例仅初始化一次；每个场景清空本门真实内存SQLite的全部表。
    await suiteDb.transaction(() async {
      for (final table in suiteDb.allTables.toList().reversed) {
        await suiteDb.delete(table).go();
      }
    });
    await settings.put('video.cacheInitialized', true);
    for (final platform in PlatformType.musicServices) {
      PlatformRegistry.register(_Content(platform));
    }
  });
  tearDownAll(() async {
    for (final channel in [
      'sun-dove.yueyin/ik-desktop',
      'com.mconnect.mconnect/floating_lyrics',
    ]) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(channel),
        null,
      );
    }
    await Hive.close();
    await suiteDb.close();
    if (!await scratch.exists()) return;
    final target = await scratch.resolveSymbolicLinks();
    final parent = await Directory.systemTemp.resolveSymbolicLinks();
    if (!target.startsWith('$parent${Platform.pathSeparator}') ||
        !scratch.uri.pathSegments
            .lastWhere((part) => part.isNotEmpty)
            .startsWith('ik-a11y-gate-')) {
      throw StateError('拒绝清理非本门创建的目录：$target');
    }
    await scratch.delete(recursive: true);
    debugPrint('IK_SEMANTICS 已清理本门临时存储：$target');
  });

  test('W-A11Y-06 Windows AX重挂必须初始化被销毁的后代', () {
    final trace = _TreeTrace();
    var completed = false;
    try {
      trace.commit([
        _axGoldenNode(0, [1, 2]),
        _axGoldenNode(1, [3]),
        _axGoldenNode(2, []),
        _axGoldenNode(3, [4]),
        _axGoldenNode(4, []),
      ]);
      expect(trace.issues, isEmpty);
      trace.step = '黄金场景：3从1移到2，后代4未收到初始化';
      trace.commit([
        _axGoldenNode(1, []),
        _axGoldenNode(2, [3]),
        _axGoldenNode(3, [4]),
      ]);
      // 最终缓存图0→2→3→4完整，AX却已在第一阶段销毁3与4。
      expect(trace.nodes[3]!.traversal, [4]);
      expect(trace.nodes.containsKey(4), isTrue);
      expect(
        trace.issues,
        contains(contains('AX待初始化节点4')),
        reason: '重挂后不能使用上批缓存替代原生已销毁后代的初始化',
      );
      completed = true;
    } finally {
      trace.finishDiagnostics(completed: completed);
    }
  });

  test('W-A11Y-06 Windows AX完整重挂全部24种原始提交顺序均有效', () {
    var orders = 0;
    for (final batch in _axNodeOrders([
      _axGoldenNode(1, []),
      _axGoldenNode(2, [3]),
      _axGoldenNode(3, [4]),
      _axGoldenNode(4, []),
    ])) {
      final trace = _TreeTrace();
      var completed = false;
      try {
        trace.commit([
          _axGoldenNode(0, [1, 2]),
          _axGoldenNode(1, [3]),
          _axGoldenNode(2, []),
          _axGoldenNode(3, [4]),
          _axGoldenNode(4, []),
        ]);
        trace.step = '完整初始化重挂顺序$orders';
        trace.commit(batch);
        expect(trace.issues, isEmpty, reason: trace.step);
        expect(trace.ax.deleted, unorderedEquals([3, 4]));
        expect(trace.ax.pendingInitialization, isEmpty);
        expect(trace.ax.nodes[3]!.parent, 2);
        expect(trace.ax.nodes[4]!.parent, 3);
        // 单独更新现有后代不应要求整个树重新初始化。
        trace.commit([_axGoldenNode(4, [])]);
        expect(trace.issues, isEmpty);
        expect(trace.ax.deleted, isEmpty);
        // 普通移除不重挂，也不应要求被销毁的后代继续提交。
        trace.commit([_axGoldenNode(2, [])]);
        expect(trace.issues, isEmpty);
        expect(trace.ax.nodes.keys, unorderedEquals([0, 1, 2]));
        orders++;
        completed = true;
      } finally {
        trace.finishDiagnostics(completed: completed);
      }
    }
    expect(orders, 24);
    debugPrint('IK_SEMANTICS AX黄金门完整检查24种提交排列、属性更新与普通移除');
  });

  Future<_RootHarness> mountRoot(
    WidgetTester tester, {
    required bool hasSong,
    bool recommendationsLoading = true,
    PlayerState? restoredState,
    Size? viewport,
    Future<void> Function(Map<String, dynamic>)? audioWrite,
    _Catalog? catalogOverride,
    _Recommendations? recommendationsOverride,
    bool realDiscovery = false,
    bool interactionIo = false,
    bool pageInteractionRefinements = false,
    bool workspacePageRefinements = false,
    bool withSourceManager = false,
  }) async {
    await _size(tester);
    if (viewport != null) tester.view.physicalSize = viewport;
    final db = suiteDb;
    final preferences = VideoPreferences(settings);
    final sourceSettings = withSourceManager
        ? (IkManagedSourceSettings(preferences)..load())
        : null;
    final unified = WindowsMusicPreferences(
      preferences,
      write: (values) => ioZone.run(() async {
        await settings.putAll(values);
        await settings.flush();
      }),
    )..load();
    final appearance = WindowsAppearance(
      preferences: unified,
      directory: Directory('${scratch.path}/appearance'),
      window: const _Window(),
    );
    await tester.runAsync(appearance.initialize);
    final recommendations =
        recommendationsOverride ?? _Recommendations(realLoading: realDiscovery);
    if (!recommendationsLoading) {
      recommendations.show(
        RecommendationsState(
          songsByPlatform: {
            PlatformType.qq: [_track],
          },
        ),
      );
    }
    final catalog = catalogOverride ?? _Catalog();
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => _Auth()),
        if (sourceSettings != null)
          ikSourceCatalogProvider.overrideWith((ref) {
            final coordinator = IkSourceCatalogCoordinator(
              catalog: IkSourceCatalog.fromJson(
                jsonDecode(
                  File('assets/source-catalog/pdone-v1.json')
                      .readAsStringSync(),
                ) as Map<String, dynamic>,
              ),
              settings: sourceSettings,
              runtimeId: 'windows-lx3',
              importer: IkFixedSourceImporter(engine: _UnusedSourceEngine()),
            );
            ref.onDispose(() {
              coordinator.dispose();
              sourceSettings.dispose();
            });
            return coordinator;
          }),
        playerProvider.overrideWith(
          (_) => _Player(
            hasSong: hasSong,
            verifiedAudio: true,
            initialState: restoredState,
          ),
        ),
        audioEffectsSettingsStoreProvider.overrideWithValue(
          MemoryAudioEffectsSettingsStore(),
        ),
        if (audioWrite != null)
          audioEffectsSettingsProvider.overrideWith(
            (_) => IkStrictAudioSettings(write: audioWrite),
          ),
        ikSpatialRuntimeProvider.overrideWith((ref) {
          final player = ref.read(playerProvider.notifier);
          final coordinator = IkSpatialCoordinator(
            capability: () => player.spatialAudioCapability,
            initial: SpatialSettings.fromMap(settings.get('ik.spatial.v1')),
            save: (value) =>
                ioZone.run(() => settings.put('ik.spatial.v1', value.toMap())),
          );
          unawaited(Future<void>.microtask(coordinator.initialize));
          return coordinator;
        }),
        recommendationsProvider.overrideWith((_) => recommendations),
        if (realDiscovery)
          newSongsProvider.overrideWith(
            (_) => NewSongsNotifier(supportedTypes: PlatformType.musicServices),
          ),
        if (realDiscovery)
          toplistsProvider.overrideWith(
            (_) => ToplistsNotifier(supportedTypes: PlatformType.musicServices),
          ),
        if (interactionIo)
          floatingLyricsProvider.overrideWith(
            (_) => IkStrictFloatingLyricsNotifier(
              save: (value) => ioZone.run(
                () => settings.put('floating_lyrics_settings', value.toJson()),
              ),
            ),
          ),
        if (interactionIo)
          localMusicProvider.overrideWith((_) {
            final notifier = LocalMusicNotifier(
              trackStore: MemoryLocalTrackStore(),
              lyricsStore: MemoryLocalLyricsStore(),
              rootStore: MemoryLocalScanRootStore(),
              onlineSnapshot: MemoryOnlineLibrarySnapshot(),
              ratingsStore: MemoryTrackRatingsStore(),
            );
            unawaited(notifier.loadFromIndex());
            return notifier;
          }),
        myPlaylistsProvider.overrideWith(
          (_) => MyPlaylistsNotifier(
            repository: interactionIo
                ? _IoPlaylistsRepository(
                    Directory('${scratch.path}/r10-playlists'),
                    ioZone,
                  )
                : MyPlaylistsRepository(storageDirectory: scratch),
          ),
        ),
        downloadProvider.overrideWith(
          (_) => DownloadNotifier(
            initialState: const DownloadState(),
            manager: DownloadManager(
              directoryService: DownloadDirectoryService(
                defaultRootProvider: () async => scratch,
              ),
            ),
          ),
        ),
        downloadQualityProvider.overrideWithValue(
          (platform) => unified.quality(platform, download: true),
        ),
      ],
    );
    ioZone.run(() => container.read(historyProvider));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: VideoMusicApp(
          redesign: true,
          workspace: true,
          alignToDesign: true,
          pageInteractionRefinements: pageInteractionRefinements,
          workspacePageRefinements: workspacePageRefinements,
          sourceSettings: sourceSettings,
          sourceEngine: withSourceManager ? _UnusedSourceEngine() : null,
          expandedPlatforms: true,
          preferences: preferences,
          unifiedPreferences: unified,
          windowsAppearance: appearance,
          catalog: catalog,
        ),
      ),
    );
    await _rootDrain(tester, binding.trace);
    return _RootHarness(
      container,
      recommendations,
      catalog,
      unified,
      appearance,
      db,
    );
  }

  for (final hasSong in [false, true]) {
    _testWindows('W-A11Y-02 真实播放栏${hasSong ? '已有歌曲' : '空PlayerState'} '
        '迟启语义后完整悬停播放控制及工具提示', (tester) async {
      await _size(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerProvider.overrideWith((_) => _Player(hasSong: hasSong)),
            likesProvider.overrideWith((_) => _Likes()),
          ],
          child: MaterialApp(
            theme: IkTheme.from(VideoTheme.light),
            home: Scaffold(
              body: const SizedBox.expand(),
              bottomNavigationBar: IkPlaybackBar(onOpen: () {}, onAudio: () {}),
            ),
          ),
        ),
      );
      await tester.pump();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1190, 1));
      addTearDown(mouse.removePointer);
      await _hover(
        tester,
        mouse,
        find.byTooltip(VideoStrings.shuffle),
        binding.trace,
      );
      expect(binding.renderViews.single.owner!.semanticsOwner, isNull);
      binding.trace.step = '播放栏${hasSong ? '有歌' : '空状态'}随机提示已显示后迟启语义';
      final handle = tester.ensureSemantics();
      try {
        await _pumpAndCheck(tester, binding.trace);
        for (final message in [
          VideoStrings.shuffle,
          VideoStrings.previousSong,
          VideoStrings.play,
          VideoStrings.nextSong,
          VideoStrings.repeatAll,
        ]) {
          binding.trace.step = '播放栏${hasSong ? '有歌' : '空状态'}悬停$message';
          await _hover(tester, mouse, find.byTooltip(message), binding.trace);
          await _leave(tester, mouse, binding.trace);
        }
        final tooltips = find.byType(Tooltip).hitTestable();
        final count = tooltips.evaluate().length;
        for (var index = 0; index < count; index++) {
          final current = find.byType(Tooltip).hitTestable().at(index);
          binding.trace.step = '播放栏${hasSong ? '有歌' : '空状态'}全部提示$index';
          await _hover(tester, mouse, current, binding.trace);
          await _leave(tester, mouse, binding.trace);
        }
        binding.trace.expectValid();
      } finally {
        handle.dispose();
      }
    });
  }

  for (final config in [
    (align: true, workspace: true, hasSong: false),
    (align: true, workspace: true, hasSong: true),
    (align: false, workspace: true, hasSong: true),
    (align: false, workspace: false, hasSong: true),
  ]) {
    _testWindows('W-A11Y-01/03 真实工作区、发现、播放栏与四个列表替身迟启语义 '
        '对齐${config.align}/首页工作区${config.workspace}/有歌${config.hasSong}', (
      tester,
    ) async {
      await _size(tester);
      final recommendations = _Recommendations();
      final queries = <String>[];
      var index = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            recommendationsProvider.overrideWith((_) => recommendations),
            playerProvider.overrideWith(
              (_) => _Player(hasSong: config.hasSong),
            ),
            authProvider.overrideWith((_) => AuthNotifier()),
            likesProvider.overrideWith((_) => _Likes()),
          ],
          child: MaterialApp(
            theme: IkTheme.from(VideoTheme.light),
            home: StatefulBuilder(
              builder: (context, update) => IkDesktopWorkspace(
                index: index,
                onSelect: (next) => update(() => index = next),
                onAccount: () {},
                alignToDesign: config.align,
                onSearch: (query) {
                  queries.add(query);
                  update(() => index = 1);
                },
                pages: [
                  IkHomePage(
                    workspace: config.workspace,
                    alignToDesign: config.align,
                    onNavigate: (_) {},
                    onPlayer: () {},
                    onPlay: (_, _) {},
                    onMore: (_) {},
                  ),
                  for (var page = 1; page < 5; page++)
                    ListView(
                      children: [
                        Text('主区$page', key: ValueKey('a11y-page-$page')),
                        for (var row = 0; row < 18; row++)
                          ListTile(
                            title: Text('主区$page项目$row'),
                            trailing: IconButton(
                              tooltip: '主区$page操作$row',
                              onPressed: () {},
                              icon: const Icon(Icons.more_horiz),
                            ),
                          ),
                      ],
                    ),
                ],
                playbackBar: IkPlaybackBar(onOpen: () {}, onAudio: () {}),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1190, 1));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('ik-workspace-nav-0'))),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(binding.renderViews.single.owner!.semanticsOwner, isNull);

      binding.trace.step = '发现已启动、导航提示显示后迟启语义';
      final handle = tester.ensureSemantics();
      try {
        await _pumpAndCheck(tester, binding.trace);

        for (var page = 0; page < 5; page++) {
          final nav = find.byKey(ValueKey('ik-workspace-nav-$page'));
          binding.trace.step = '悬停导航$page';
          await _hover(tester, mouse, nav, binding.trace);
          binding.trace.step = '离开导航$page';
          await _leave(tester, mouse, binding.trace);
          binding.trace.step = '切到主区$page';
          await tester.tap(nav);
          await _pumpAndCheck(tester, binding.trace);
          expect(index, page);
          final data = tester.getSemantics(nav).getSemanticsData();
          expect(data.label, contains(IkDesktopWorkspace.labels[page]));
          expect(data.flagsCollection.isButton, isTrue);
          expect(data.hasAction(SemanticsAction.tap), isTrue);

          if (page == 0) {
            binding.trace.step = '加载推荐替换发现语义节点';
            recommendations.show(
              RecommendationsState(
                songsByPlatform: {
                  PlatformType.qq: [
                    for (var i = 0; i < 8; i++)
                      Song(
                        id: 'recommended-$i',
                        name: '推荐语义曲目$i',
                        platform: PlatformType.qq,
                        artists: const [],
                      ),
                  ],
                },
              ),
            );
            await _pumpAndCheck(tester, binding.trace);
          }
          final scroll = find
              .descendant(
                of: find.byType(IndexedStack),
                matching: find.byType(Scrollable),
              )
              .hitTestable();
          expect(scroll, findsOneWidget);
          binding.trace.step = '主区$page滚动及所有当前Tooltip悬停';
          await tester.drag(scroll, const Offset(0, -260));
          await _pumpAndCheck(
            tester,
            binding.trace,
            const Duration(seconds: 1),
          );
          final tooltipCount = find
              .byType(Tooltip)
              .hitTestable()
              .evaluate()
              .length;
          for (var tip = 0; tip < tooltipCount; tip++) {
            binding.trace.step = '主区$page Tooltip$tip';
            await _hover(
              tester,
              mouse,
              find.byType(Tooltip).hitTestable().at(tip),
              binding.trace,
            );
            await _leave(tester, mouse, binding.trace);
          }
        }
        if (config.align) {
          binding.trace.step = '共用搜索真实提交';
          await tester.enterText(
            find.byKey(const ValueKey('ik-workspace-search')),
            '无障碍查询',
          );
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await _pumpAndCheck(tester, binding.trace);
          expect(queries, ['无障碍查询']);
          expect(index, 1);
        } else {
          expect(
            find.byKey(const ValueKey('ik-workspace-search')),
            findsNothing,
          );
        }
        binding.trace.expectValid();
      } finally {
        handle.dispose();
      }
    });
  }

  for (final hasSong in [true, false]) {
    for (final anchor in ['搜索导航', '无悬停', '导航', '播放栏上一首']) {
      _testWindows('W-A11Y-01/02 正式VideoMusicApp根五页、路由与浮层 '
          '迟启于$anchor/有歌$hasSong', (tester) async {
        binding.trace.step = '实际应用根初启：$anchor/有歌$hasSong';
        final app = await mountRoot(
          tester,
          hasSong: hasSong,
          recommendationsLoading: anchor != '搜索导航',
        );
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(1190, 1));
        final initialTarget = switch (anchor) {
          '导航' => find.byKey(const ValueKey('ik-workspace-nav-0')),
          '搜索导航' => find.byKey(const ValueKey('ik-workspace-nav-1')),
          '播放栏上一首' => find.byTooltip(VideoStrings.previousSong),
          _ => null,
        };
        if (initialTarget != null) {
          await _hover(tester, mouse, initialTarget, binding.trace);
        }
        expect(binding.renderViews.single.owner!.semanticsOwner, isNull);
        binding.trace.onIssue = () => _dumpMarkers(tester, binding.trace);
        final handle = tester.ensureSemantics();
        try {
          binding.trace.step = '实际应用根迟启语义：$anchor/有歌$hasSong';
          await _rootDrain(tester, binding.trace);
          // 初批树已非法时原生Unserialize没有整体回滚，后续图不可冒充有效旧AX树。
          binding.trace.expectValid();
          final pageElements = <int, Element>{
            for (var page = 0; page < 5; page++)
              page: find
                  .byKey(
                    ValueKey('ik-workspace-page-overlay-$page'),
                    skipOffstage: false,
                  )
                  .evaluate()
                  .single,
          };
          await _walkPage(
            tester,
            mouse,
            binding.trace,
            anchor == '搜索导航' ? '发现推荐初始已加载' : '发现加载中',
          );
          app.recommendations.show(
            RecommendationsState(
              songsByPlatform: {
                PlatformType.qq: [_track],
              },
            ),
          );
          await _rootDrain(tester, binding.trace);
          await _walkPage(tester, mouse, binding.trace, '发现推荐加载后');

          for (var page = 0; page < 5; page++) {
            binding.trace.step = '实际应用根切换主区$page';
            final nav = find.byKey(ValueKey('ik-workspace-nav-$page'));
            await tester.tap(nav);
            await _rootDrain(tester, binding.trace);
            for (var key = 0; key < 5; key++) {
              expect(
                find
                    .byKey(
                      ValueKey('ik-workspace-page-overlay-$key'),
                      skipOffstage: false,
                    )
                    .evaluate()
                    .single,
                same(pageElements[key]),
                reason: '切页后第$key页Overlay element必须保留',
              );
            }
            final semantics = tester.getSemantics(nav).getSemanticsData();
            expect(semantics.label, contains(IkDesktopWorkspace.labels[page]));
            expect(semantics.flagsCollection.isButton, isTrue);
            expect(semantics.hasAction(SemanticsAction.tap), isTrue);
            if (page == 1) {
              await tester.enterText(
                find.byKey(const ValueKey('ik-workspace-search')),
                '实际语义搜索',
              );
              await tester.testTextInput.receiveAction(TextInputAction.search);
              await _rootDrain(tester, binding.trace);
              expect(find.byType(IkSearchWorkspace), findsOneWidget);
              await _walkPage(tester, mouse, binding.trace, '实际搜索成功歌曲表');
              final searchPage = find.byType(IkSearchWorkspace);
              final searchState = tester.state(searchPage);
              final search = tester
                  .widget<IkSearchWorkspace>(searchPage)
                  .search;
              final scroll = _verticalScrolls(searchPage).single;
              final scrollState = tester.state<ScrollableState>(scroll);
              final scrollPosition = scrollState.position;
              final savedPixels = scrollPosition.maxScrollExtent.clamp(
                0.0,
                120.0,
              );
              scrollPosition.jumpTo(savedPixels);
              await _rootDrain(tester, binding.trace);
              binding.trace.step = '搜索切回发现再返回：保留结果、controller、State与滚动位置';
              await tester.tap(
                find.byKey(const ValueKey('ik-workspace-nav-0')),
              );
              await _rootDrain(tester, binding.trace);
              await tester.tap(
                find.byKey(const ValueKey('ik-workspace-nav-1')),
              );
              await _rootDrain(tester, binding.trace);
              expect(tester.state(searchPage), same(searchState));
              expect(
                tester.widget<IkSearchWorkspace>(searchPage).search,
                same(search),
              );
              expect(
                tester.state<ScrollableState>(
                  _verticalScrolls(searchPage).single,
                ),
                same(scrollState),
              );
              expect(scrollPosition.pixels, closeTo(savedPixels, .001));
              expect(search.query, '实际语义搜索');
              scrollPosition.jumpTo(scrollPosition.minScrollExtent);
              await _rootDrain(tester, binding.trace);
              final source = find.descendant(
                of: find.byType(IkSearchWorkspace),
                matching: find.byType(IkSelect<String>),
              );
              binding.trace.step = '实际搜索来源菜单展开';
              await tester.tap(source);
              await _rootDrain(tester, binding.trace);
              expect(find.byType(MenuItemButton).hitTestable(), findsWidgets);
              await _allTooltips(tester, mouse, binding.trace, '实际来源菜单');
              await tester.tap(find.byType(MenuItemButton).hitTestable().first);
              await _rootDrain(tester, binding.trace);
              app.catalog.fail = true;
              await tester.enterText(
                find.byKey(const ValueKey('ik-workspace-search')),
                '实际语义失败搜索',
              );
              await tester.testTextInput.receiveAction(TextInputAction.search);
              await _rootDrain(tester, binding.trace);
              await _walkPage(tester, mouse, binding.trace, '实际搜索各来源错误');
              expect(find.text('语义验收来源网络失败'), findsWidgets);
              app.catalog.fail = false;
            }
            if (page == 2) {
              await tester.runAsync(
                () => app.container
                    .read(likesProvider.notifier)
                    .toggleLike(_track),
              );
              await _rootDrain(tester, binding.trace);
            }
            if (page == 3) {
              await tester.runAsync(
                () => app.container
                    .read(historyProvider.notifier)
                    .recordListen(_track),
              );
              await _rootDrain(tester, binding.trace);
            }
            await _walkPage(tester, mouse, binding.trace, '实际主区$page');
            if (page == 4) {
              for (final section in [
                'appearance',
                'lyrics',
                'sources',
                'downloads',
                'accounts',
                'backup',
                'audio',
              ]) {
                final control = find.byKey(ValueKey('ik-settings-$section'));
                await tester.ensureVisible(control);
                await _pumpAndCheck(tester, binding.trace);
                await tester.tap(control);
                await _rootDrain(tester, binding.trace);
                expect(find.byType(IkSettingsWorkspace), findsOneWidget);
                await _walkPage(tester, mouse, binding.trace, '实际设置$section');
                if (section == 'appearance') {
                  final settingsState = tester.state(
                    find.byType(IkSettingsWorkspace),
                  );
                  final selectedColor = tester
                      .widget<TextButton>(control)
                      .style!
                      .backgroundColor!
                      .resolve({});
                  binding.trace.step = '设置切回发现再返回：保留设置State与选中的外观区';
                  await tester.tap(
                    find.byKey(const ValueKey('ik-workspace-nav-0')),
                  );
                  await _rootDrain(tester, binding.trace);
                  await tester.tap(
                    find.byKey(const ValueKey('ik-workspace-nav-4')),
                  );
                  await _rootDrain(tester, binding.trace);
                  expect(
                    tester.state(find.byType(IkSettingsWorkspace)),
                    same(settingsState),
                  );
                  expect(
                    tester
                        .widget<TextButton>(control)
                        .style!
                        .backgroundColor!
                        .resolve({}),
                    selectedColor,
                  );
                }
                if (section == 'audio') {
                  await _operateSettingsSliders(
                    tester,
                    mouse,
                    binding.trace,
                    app,
                  );
                }
              }
            }
          }

          binding.trace.step = '准备实际播放曲目以打开详情路由';
          await app.container.read(playerProvider.notifier).playSong(_track);
          await _rootDrain(tester, binding.trace);
          app.container
              .read(sourcePlaybackViewProvider.notifier)
              .state = const SourcePlaybackView(
            message: '语义验收当前来源',
            details: '语义验收当前来源已连接\n备用来源尚未请求',
            sourceName: '语义验收来源',
            format: 'mp3',
            bitrate: 320000,
          );
          final router = GoRouter.of(
            tester.element(find.byType(IkDesktopWorkspace)),
          );
          binding.trace.step = '实际路由/player进入过渡：新播放栏与歌词字号Slider';
          unawaited(router.push<void>('/player'));
          await _rootDrain(tester, binding.trace);
          binding.trace.expectValid();
          expect(find.byType(WindowsPlayerPage), findsOneWidget);
          await _walkPage(
            tester,
            mouse,
            binding.trace,
            '实际播放详情',
            owner: find.byType(WindowsPlayerPage),
          );
          await _operateLyricsSlider(tester, mouse, binding.trace);
          final expand = find.byKey(const ValueKey('ik-player-source-expand'));
          await tester.ensureVisible(expand);
          await _pumpAndCheck(tester, binding.trace);
          await tester.tap(expand);
          await _rootDrain(tester, binding.trace);
          await _allTooltips(tester, mouse, binding.trace, '实际播放详情来源展开');
          binding.trace.step = '实际路由/player返回工作区过渡';
          router.pop();
          await _rootDrain(tester, binding.trace);
          for (final section in ['audio', 'lyrics']) {
            binding.trace.step = '实际路由/settings/$section进入过渡';
            unawaited(router.push<void>('/settings/$section'));
            await _rootDrain(tester, binding.trace);
            binding.trace.expectValid();
            await _walkPage(
              tester,
              mouse,
              binding.trace,
              '实际设置详情路由$section',
              owner: find.byType(IkSettingsWorkspace),
            );
            binding.trace.step = '实际路由/settings/$section返回工作区';
            router.pop();
            await _rootDrain(tester, binding.trace);
          }

          binding.trace.step = '实际待播放浮层展开';
          await tester.tap(find.byKey(const ValueKey('ik-bar-queue')));
          await _rootDrain(tester, binding.trace);
          await _allTooltips(tester, mouse, binding.trace, '实际待播放浮层');
          await tester.tap(find.byTooltip(IkStrings.close).hitTestable());
          await _rootDrain(tester, binding.trace);
          binding.trace.expectValid();
        } finally {
          handle.dispose();
          await mouse.removePointer();
          await tester.pumpWidget(const SizedBox.shrink());
          app.container.dispose();
          app.appearance.dispose();
          app.unified.dispose();
          await tester.pump();
        }
      });
    }
  }

  _testWindows('W-A11Y-06 正式根恢复暂停长歌词经最近播放进入详情', (tester) async {
    final longLyrics = [
      '[00:00.00]语义验收前奏',
      '[00:03.00]语义验收歌词',
      for (var line = 2; line < 60; line++)
        '[${(line * 3 ~/ 60).toString().padLeft(2, '0')}:'
            '${(line * 3 % 60).toString().padLeft(2, '0')}.00]'
            '语义验收长歌词第$line句',
    ].join('\n');
    for (final platform in PlatformType.musicServices) {
      PlatformRegistry.register(_Content(platform, lyrics: longLyrics));
    }
    final app = await mountRoot(
      tester,
      hasSong: true,
      recommendationsLoading: false,
      restoredState: const PlayerState(
        currentSong: _track,
        duration: Duration(minutes: 3),
        position: Duration(seconds: 3),
        playlist: [_track],
      ),
      viewport: const Size(1186, 793),
    );
    await tester.runAsync(
      () => app.container.read(historyProvider.notifier).recordListen(_track),
    );
    app.container
        .read(sourcePlaybackViewProvider.notifier)
        .state = const SourcePlaybackView(
      message: '语义验收恢复曲目，音频格式待确认',
      sourceName: '语义验收来源',
    );
    await _rootDrain(tester, binding.trace);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1180, 1));
    binding.trace.onIssue = () => _dumpMarkers(tester, binding.trace);
    final handle = tester.ensureSemantics();
    try {
      binding.trace.step = '恢复暂停曲目根启用无障碍';
      await _rootDrain(tester, binding.trace);
      binding.trace.expectValid();
      binding.trace.step = '恢复暂停曲目切入最近播放';
      await tester.tap(find.byKey(const ValueKey('ik-workspace-nav-3')));
      await _rootDrain(tester, binding.trace);
      final before = app.container.read(playerProvider);
      expect(before.isPlaying, isFalse);
      expect(before.position, const Duration(seconds: 3));
      final title = find
          .descendant(
            of: find.byType(IkPlaybackBar),
            matching: find.text(_track.name),
          )
          .hitTestable();
      expect(title, findsOneWidget);
      binding.trace.step = '恢复暂停长歌词/player进入：来源格式未知、实际窗口尺寸';
      await tester.tap(title);
      await _rootDrain(tester, binding.trace);
      binding.trace.expectValid();
      final page = find.byType(WindowsPlayerPage);
      expect(page, findsOneWidget);
      final playerPage = tester.widget<WindowsPlayerPage>(page);
      expect(playerPage.position, const Duration(seconds: 3));
      expect(playerPage.isPlaying, isFalse);
      expect(playerPage.lyrics, hasLength(60));
      expect(playerPage.sourceDetails!.format, isNull);
      await _walkPage(tester, mouse, binding.trace, '恢复暂停长歌词播放详情', owner: page);
      await _operateLyricsSlider(tester, mouse, binding.trace);
      binding.trace.step = '恢复暂停详情来源信息展开';
      await tester.tap(find.byKey(const ValueKey('ik-player-source-expand')));
      await _rootDrain(tester, binding.trace);
      await _allTooltips(tester, mouse, binding.trace, '恢复暂停详情来源信息展开后');
      binding.trace.step = '恢复暂停播放详情返回最近播放';
      GoRouter.of(tester.element(page)).pop();
      await _rootDrain(tester, binding.trace);
      expect(find.byType(IkDesktopWorkspace), findsOneWidget);
      final after = app.container.read(playerProvider);
      expect(after.currentSong, before.currentSong);
      expect(after.position, before.position);
      expect(after.isPlaying, isFalse);
      binding.trace.expectValid();
    } finally {
      handle.dispose();
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      app.container.dispose();
      app.appearance.dispose();
      app.unified.dispose();
      await tester.pump();
    }
  });

  _testWindows('W-A11Y-07 正式根七个音效滑块禁用启用和保存期间稳定语义', (tester) async {
    final saveGate = _AudioSaveGate(
      (values) =>
          ioZone.run(() => settings.put('audio_effects_settings', values)),
    );
    final app = await mountRoot(
      tester,
      hasSong: true,
      recommendationsLoading: false,
      audioWrite: saveGate.write,
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1190, 1));
    binding.trace.onIssue = () => _dumpMarkers(tester, binding.trace);
    final handle = tester.ensureSemantics();
    try {
      binding.trace.step = '音效状态门正式根启用无障碍';
      await _rootDrain(tester, binding.trace);
      await tester.tap(find.byKey(const ValueKey('ik-workspace-nav-4')));
      await _rootDrain(tester, binding.trace);
      final page = find.byType(IkSettingsWorkspace);
      final sliders = find.descendant(of: page, matching: find.byType(Slider));
      expect(sliders, findsNWidgets(7));
      expect(tester.widget<Slider>(sliders.at(0)).onChanged, isNull);
      for (var band = 2; band < 7; band++) {
        expect(tester.widget<Slider>(sliders.at(band)).onChanged, isNull);
      }
      await _walkPage(tester, mouse, binding.trace, '音效状态门全部原始滚动位置');
      await _operateSettingsSliders(tester, mouse, binding.trace, app);
      binding.trace.step = '音效状态门真实写队列挂起：保存时六个effects滑块暂时禁用';
      await tester.ensureVisible(sliders.at(1));
      await _pumpAndCheck(tester, binding.trace);
      saveGate.hold();
      await tester.drag(sliders.at(1), const Offset(30, 0));
      await _rootDrain(tester, binding.trace);
      expect(saveGate.waiting, isTrue);
      for (var index = 1; index < 7; index++) {
        expect(tester.widget<Slider>(sliders.at(index)).onChanged, isNull);
        expect(
          _sliderSemantics(
            tester,
            sliders.at(index),
          ).getSemanticsData().hasAction(SemanticsAction.increase),
          isFalse,
        );
      }
      binding.trace.step = '音效状态门实际写入完成：六个effects滑块恢复可用';
      saveGate.release();
      await _rootDrain(tester, binding.trace);
      for (var index = 1; index < 7; index++) {
        expect(tester.widget<Slider>(sliders.at(index)).onChanged, isNotNull);
      }
      expect(
        AudioEffectsSettings.fromJson(settings.get('audio_effects_settings'))
            .fadeDuration,
        app.container.read(audioEffectsSettingsProvider).fadeDuration,
      );
      binding.trace.step = '音效状态门关闭3D：空间强度恢复禁用';
      final spatial = find.descendant(
        of: find.byKey(const ValueKey('ik-spatial-emphasis')),
        matching: find.byType(Switch),
      );
      await tester.ensureVisible(spatial);
      await _pumpAndCheck(tester, binding.trace);
      await tester.tap(spatial);
      await _rootDrain(tester, binding.trace);
      expect(tester.widget<Slider>(sliders.at(0)).onChanged, isNull);
      binding.trace.step = '音效状态门关闭均衡器：五个频段全部恢复禁用';
      final equalizer = find.descendant(
        of: find.byWidgetPredicate(
          (widget) =>
              widget is IkSettingRow && widget.title == IkStrings.equalizer,
        ),
        matching: find.byType(Switch),
      );
      await tester.ensureVisible(equalizer);
      await _pumpAndCheck(tester, binding.trace);
      await tester.tap(equalizer);
      await _rootDrain(tester, binding.trace);
      for (var band = 2; band < 7; band++) {
        expect(tester.widget<Slider>(sliders.at(band)).onChanged, isNull);
      }
      binding.trace.expectValid();
    } finally {
      handle.dispose();
      saveGate.release();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      app.container.dispose();
      app.appearance.dispose();
      app.unified.dispose();
      await tester.pump();
    }
  });

  _testWindows('W-A11Y-08 正式根播放准备与时长到达时进度保持有效语义', (tester) async {
    final app = await mountRoot(
      tester,
      hasSong: true,
      recommendationsLoading: false,
    );
    binding.trace.onIssue = () => _dumpMarkers(tester, binding.trace);
    final handle = tester.ensureSemantics();
    try {
      binding.trace.step = '进度状态门已有歌曲启用无障碍';
      await _rootDrain(tester, binding.trace);
      final progress = find.byKey(const ValueKey('ik-bar-seek'));
      expect(tester.widget<Slider>(progress).onChanged, isNotNull);
      final player = app.container.read(playerProvider.notifier) as _Player;
      binding.trace.step = '进度状态门新播放准备：暂未收到时长，进度必须禁用';
      await player.playSong(_track);
      await _rootDrain(tester, binding.trace);
      expect(tester.widget<Slider>(progress).onChanged, isNull);
      expect(
        _sliderSemantics(
          tester,
          progress,
        ).getSemanticsData().hasAction(SemanticsAction.increase),
        isFalse,
      );
      binding.trace.step = '进度状态门音频时长到达：进度恢复增加和减少动作';
      player.reportDuration(const Duration(minutes: 3));
      await _rootDrain(tester, binding.trace);
      expect(tester.widget<Slider>(progress).onChanged, isNotNull);
      final data = _sliderSemantics(tester, progress).getSemanticsData();
      expect(data.hasAction(SemanticsAction.increase), isTrue);
      expect(data.hasAction(SemanticsAction.decrease), isTrue);
      expect(tester.widget<Slider>(progress).max, 180000);
      binding.trace.expectValid();
    } finally {
      handle.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      app.container.dispose();
      app.appearance.dispose();
      app.unified.dispose();
      await tester.pump();
    }
  });

  _testWindows('E09 新交互开启真实根搜索分类与歌词自动恢复连续AX', (tester) async {
    final longLyrics = [
      for (var line = 0; line < 60; line++)
        '[${(line * 3 ~/ 60).toString().padLeft(2, '0')}:'
            '${(line * 3 % 60).toString().padLeft(2, '0')}.00]'
            'E09歌词第$line句',
    ].join('\n');
    for (final platform in PlatformType.musicServices) {
      PlatformRegistry.register(_Content(platform, lyrics: longLyrics));
    }
    final app = await mountRoot(
      tester,
      hasSong: true,
      recommendationsLoading: false,
      interactionIo: true,
      pageInteractionRefinements: true,
      restoredState: const PlayerState(
        currentSong: _track,
        duration: Duration(minutes: 3),
        position: Duration(seconds: 90),
        playlist: [_track],
      ),
      viewport: const Size(1186, 793),
    );
    app.recommendations.show(
      RecommendationsState(
        songsByPlatform: {
          for (final platform in PlatformType.musicServices)
            platform: [
              for (var index = 1; index <= 31; index++)
                Song(
                  id: 'e09-${platform.name}-$index',
                  name:
                      'AX${platform.name}推荐${index.toString().padLeft(2, '0')}',
                  platform: platform,
                  artists: _track.artists,
                  duration: const Duration(minutes: 3),
                ),
            ],
        },
        sourceByPlatform: {
          for (final platform in PlatformType.musicServices)
            platform: _R10Content(platform).source,
        },
      ),
    );
    final trace = binding.trace;
    await _rootDrain(tester, trace);
    expect(binding.renderViews.single.owner!.semanticsOwner, isNull);
    trace.onIssue = () => _dumpMarkers(tester, trace);
    trace.step = 'E09真实根已加载三平台完整推荐后迟启语义';
    final handle = tester.ensureSemantics();
    Future<void> tap(Finder target, String stage) =>
        _r10Tap(tester, trace, target, stage);
    Future<void> pump([Duration duration = Duration.zero]) =>
        _pumpAndCheck(tester, trace, duration);
    try {
      await _rootDrain(tester, trace);
      trace.expectValid();
      await tap(
        find.byKey(const ValueKey('ik-workspace-nav-1')),
        'E09进入新版完整推荐',
      );
      final searchPage = find.byType(IkSearchWorkspace);
      expect(
        tester.widget<IkSearchWorkspace>(searchPage).fullRecommendations,
        isTrue,
      );
      expect(find.text('查看全部推荐'), findsNothing);
      final selector = find.descendant(
        of: searchPage,
        matching: find.byWidgetPredicate(
          (widget) => widget is IkSelect<PlatformType>,
        ),
      );
      for (final platform in PlatformType.musicServices) {
        trace.step = 'E09返回推荐平台选择器';
        await tester.scrollUntilVisible(
          selector,
          -400,
          scrollable: _verticalScrolls(searchPage).single,
        );
        await _rootDrain(tester, trace);
        await tap(selector, 'E09打开推荐平台菜单');
        await tap(
          find.widgetWithText(MenuItemButton, videoPlatformLabel(platform)),
          'E09切换${platform.name}',
        );
        expect(find.text('共 31 首'), findsOneWidget);
        expect(find.text('播放全部').hitTestable(), findsOneWidget);
        trace.step = 'E09${platform.name}完整推荐滚动至31首';
        final lastSong = find.descendant(
          of: searchPage,
          matching: find.text('AX${platform.name}推荐31'),
        );
        await tester.scrollUntilVisible(
          lastSong,
          400,
          scrollable: _verticalScrolls(searchPage).single,
        );
        await _rootDrain(tester, trace);
        expect(lastSong.hitTestable(), findsOneWidget);
      }
      for (final query in ['E09查询', '']) {
        trace.step = query.isEmpty ? 'E09清空查询恢复完整推荐' : 'E09提交查询重建结果列表';
        await tester.enterText(
          find.byKey(const ValueKey('ik-workspace-search')),
          query,
        );
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await _rootDrain(tester, trace);
        final search = tester.widget<IkSearchWorkspace>(searchPage).search;
        expect(search.query, query);
        if (query.isEmpty) {
          expect(search.groups, isEmpty);
          expect(find.text('AXkugou推荐31').hitTestable(), findsOneWidget);
        } else {
          for (final platform in PlatformType.musicServices) {
            expect(search.groups[platform]!.songs, hasLength(3));
          }
        }
      }
      await tap(find.byKey(const ValueKey('ik-workspace-nav-2')), 'E09进入固定分类');
      expect(
        tester
            .widget<IkLibraryWorkspace>(find.byType(IkLibraryWorkspace))
            .stableCategoryTabs,
        isTrue,
      );
      for (final category in [
        'likes',
        'playlists',
        'local',
        'downloads',
        'smart',
        'likes',
      ]) {
        final tab = find.byKey(ValueKey('ik-library-category-$category'));
        await tap(tab, 'E09分类$category');
        expect(
          tester.getSemantics(tab).flagsCollection.isSelected,
          Tristate.isTrue,
        );
      }
      await tap(
        find
            .descendant(
              of: find.byType(IkPlaybackBar),
              matching: find.text(_track.name),
            )
            .hitTestable(),
        'E09进入三秒跟随详情',
      );
      final playerPage = find.byType(WindowsPlayerPage);
      final page = tester.widget<WindowsPlayerPage>(playerPage);
      expect(page.lyricsAutoResumeDelay, const Duration(seconds: 3));
      expect(page.lyrics, hasLength(60));
      final before = app.container.read(playerProvider);
      final lyricsScroll = find.byKey(const ValueKey('windows-lyrics-scroll'));
      final lyricsController = tester
          .widget<SingleChildScrollView>(lyricsScroll)
          .controller!;
      final currentLine = find.descendant(
        of: lyricsScroll,
        matching: find.text('E09歌词第30句'),
      );
      expect(
        tester.getRect(lyricsScroll).contains(tester.getCenter(currentLine)),
        isTrue,
      );
      trace.step = 'E09实际滚轮浏览歌词并记录三秒恢复语义';
      await tester.sendEventToBinding(
        PointerScrollEvent(
          kind: PointerDeviceKind.mouse,
          position: tester.getCenter(lyricsScroll),
          scrollDelta: const Offset(0, -600),
        ),
      );
      await pump();
      final browsedOffset = lyricsController.offset;
      expect(find.text(IkPlayerAlignmentStrings.browsing), findsOneWidget);
      await pump(const Duration(milliseconds: 2900));
      expect(lyricsController.offset, closeTo(browsedOffset, .001));
      expect(find.text(IkPlayerAlignmentStrings.browsing), findsOneWidget);
      await pump(const Duration(milliseconds: 100));
      expect(find.text(IkPlayerAlignmentStrings.following), findsOneWidget);
      // 三秒回位在帧尾启动动画；先建立动画首帧，再推进其250毫秒时长。
      await pump();
      await pump();
      await pump(const Duration(milliseconds: 250));
      await pump();
      expect(find.text(IkPlayerAlignmentStrings.following), findsOneWidget);
      expect(
        tester.getRect(lyricsScroll).contains(tester.getCenter(currentLine)),
        isTrue,
      );
      expect(lyricsController.offset, greaterThan(browsedOffset + 200));
      await tap(
        find.descendant(
          of: playerPage,
          matching: find.text(WindowsMusicStrings.back),
        ),
        'E09歌词自动恢复后返回音乐库',
      );
      expect(find.byType(WindowsPlayerPage), findsNothing);
      expect(find.byType(IkDesktopWorkspace), findsOneWidget);
      final after = app.container.read(playerProvider);
      expect(after.currentSong, before.currentSong);
      expect(after.position, before.position);
      expect(after.isPlaying, before.isPlaying);
      trace.expectValid();
    } finally {
      handle.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      app.container.dispose();
      app.appearance.dispose();
      app.unified.dispose();
      await tester.pump();
    }
  });

  for (final hasSong in [true, false]) {
    for (final anchor in ['搜索导航', '无悬停', '导航', '播放栏上一首']) {
      _testWindows('E23 新正文框架真实鼠标迟启于$anchor/有歌$hasSong', (tester) async {
        final app = await mountRoot(
          tester,
          hasSong: hasSong,
          recommendationsLoading: false,
          pageInteractionRefinements: true,
          workspacePageRefinements: true,
          viewport: const Size(1920, 1032),
          catalogOverride: _Catalog(
            hotTerms: [for (var i = 0; i < 30; i++) 'E23热词$i'],
          ),
        );
        final trace = binding.trace;
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(1918, 1));
        final initialTarget = switch (anchor) {
          '搜索导航' => find.byKey(const ValueKey('ik-workspace-nav-1')),
          '导航' => find.byKey(const ValueKey('ik-workspace-nav-0')),
          '播放栏上一首' => find.byTooltip(VideoStrings.previousSong),
          _ => null,
        };
        if (initialTarget != null) {
          await _hover(tester, mouse, initialTarget, trace);
        }
        expect(binding.renderViews.single.owner!.semanticsOwner, isNull);
        trace.onIssue = () => _dumpMarkers(tester, trace);
        trace.step = 'E23新正文框架鼠标停于$anchor后迟启语义';
        final handle = tester.ensureSemantics();
        Future<void> frames(String stage, int count) async {
          trace.step = stage;
          for (var frame = 0; frame < count; frame++) {
            await _pumpAndCheck(
              tester,
              trace,
              const Duration(milliseconds: 16),
            );
          }
        }

        Future<void> mouseClick(Finder target, String stage) async {
          expect(target.hitTestable(), findsOneWidget);
          final point = tester.getCenter(target.hitTestable());
          await mouse.moveTo(point);
          await frames('$stage 鼠标移入并显示提示', 70);
          await mouse.down(point);
          await frames('$stage 鼠标按下', 1);
          await mouse.up();
          await frames('$stage 鼠标释放与页面切换', 24);
          await mouse.moveTo(const Offset(1918, 1));
          await frames('$stage 鼠标离开与提示退场', 40);
          trace.expectValid();
        }

        try {
          await frames('E23迟启语义初始逐帧', 4);
          trace.expectValid();
          for (final page in [1, 0, 2]) {
            await mouseClick(
              find.byKey(ValueKey('ik-workspace-nav-$page')),
              'E23真实鼠标切主区$page',
            );
          }
          await mouseClick(
            find.byKey(const ValueKey('ik-library-category-playlists')),
            'E23真实鼠标进入我的歌单',
          );
          final source = find.descendant(
            of: find.byType(PlatformPlaylistsPage),
            matching: find.byType(IkSelect<PlatformType>),
          );
          await mouseClick(source, 'E23实际歌单来源菜单展开');
          expect(find.byType(MenuItemButton).hitTestable(), findsWidgets);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await frames('E23歌单来源菜单单次Esc退出', 40);
          expect(find.byType(MenuItemButton), findsNothing);
          trace.expectValid();
        } finally {
          handle.dispose();
          await mouse.removePointer();
          await tester.pumpWidget(const SizedBox.shrink());
          app.container.dispose();
          app.appearance.dispose();
          app.unified.dispose();
          await tester.pump();
        }
      });
    }
  }

  _testWindows('E24 真实30热词展开后鼠标跨主区内嵌下载和独立播放器', (tester) async {
    final terms = [for (var i = 0; i < 30; i++) 'E24热词$i'];
    final app = await mountRoot(
      tester,
      hasSong: true,
      recommendationsLoading: false,
      pageInteractionRefinements: true,
      workspacePageRefinements: true,
      viewport: const Size(1920, 1032),
      catalogOverride: _Catalog(hotTerms: terms),
    );
    final trace = binding.trace;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1918, 1));
    trace.onIssue = () => _dumpMarkers(tester, trace);
    trace.step = 'E24真实根迟启语义';
    final handle = tester.ensureSemantics();
    Future<void> hover(Finder target, String stage) =>
        _axMouseHover(tester, mouse, trace, target, stage);
    Future<void> click(Finder target, String stage, {bool leave = true}) =>
        _axMouseClick(tester, mouse, trace, target, stage, leave: leave);
    final search = find.byType(IkSearchWorkspace);
    final searchNav = find.byKey(const ValueKey('ik-workspace-nav-1'));
    final seek = find.byKey(const ValueKey('ik-bar-seek'));
    void expectAllTerms() {
      expect(
        find.descendant(of: search, matching: find.byType(ActionChip)),
        findsNWidgets(30),
      );
      for (final term in terms) {
        expect(
          find.descendant(of: search, matching: find.text(term)).hitTestable(),
          findsOneWidget,
          reason: 'E24全部30项必须实际显示，不能抽样',
        );
      }
    }

    try {
      await _axFrames(tester, trace, 'E24迟启初始逐帧', 4);
      await click(searchNav, 'E24鼠标进入搜索');
      expect(
        find.descendant(of: search, matching: find.byType(ActionChip)),
        findsNWidgets(10),
      );
      await click(
        find.text(IkLibraryRevisionStrings.expandHotSearch),
        'E24实际展开全部热词',
      );
      expectAllTerms();
      await hover(find.text(terms.last), 'E24第30项热词悬停');
      await hover(
        find.byKey(const ValueKey('ik-workspace-search')),
        'E24共享搜索输入悬停',
      );
      await hover(searchNav, 'E24搜索导航提示显示后切主区');
      await click(
        find.byKey(const ValueKey('ik-workspace-nav-0')),
        'E24鼠标离开展开搜索进入发现',
        leave: false,
      );
      await click(searchNav, 'E24鼠标回到展开搜索', leave: false);
      expectAllTerms();
      final router = GoRouter.of(tester.element(search));
      await hover(seek, 'E24进度滑块悬停后进入内嵌正文');
      trace.step = 'E24保持滑块悬停push内嵌下载';
      unawaited(router.push<void>('/downloads'));
      await _axFrames(tester, trace, 'E24下载正文逐帧', 40);
      expect(find.byType(IkDownloadsWorkspace).hitTestable(), findsOneWidget);
      await hover(seek, 'E24内嵌下载进度滑块悬停');
      await click(
        find.descendant(
          of: find.byType(IkPlaybackBar),
          matching: find.text(_track.name),
        ),
        'E24真实鼠标从内嵌下载打开独立播放器',
        leave: false,
      );
      expect(find.byType(WindowsPlayerPage).hitTestable(), findsOneWidget);
      expect(
        tester
            .widget<IkDesktopWorkspace>(find.byType(IkDesktopWorkspace))
            .fullPage,
        isTrue,
      );
      await hover(
        find.byKey(const ValueKey('ik-bar-volume')),
        'E24独立播放器音量滑块悬停',
      );
      await hover(seek, 'E24独立播放器进度滑块悬停');
      trace.step = 'E24保持进度滑块悬停push内嵌queue';
      unawaited(router.push<void>('/queue'));
      await _axFrames(tester, trace, 'E24queue正文逐帧', 40);
      expect(find.byType(QueuePage).hitTestable(), findsOneWidget);
      await click(find.byType(BackButton).hitTestable(), 'E24鼠标返回独立播放器');
      expect(find.byType(WindowsPlayerPage).hitTestable(), findsOneWidget);
      await click(
        find.descendant(
          of: find.byType(WindowsPlayerPage),
          matching: find.text(WindowsMusicStrings.back),
        ),
        'E24鼠标返回内嵌下载',
      );
      expect(find.byType(IkDownloadsWorkspace).hitTestable(), findsOneWidget);
      await click(find.byType(BackButton).hitTestable(), 'E24鼠标返回已展开搜索');
      expectAllTerms();
      trace.expectValid();
    } finally {
      handle.dispose();
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      app.container.dispose();
      app.appearance.dispose();
      app.unified.dispose();
      await tester.pump();
    }
  });

  _testWindows('E25 语义完全关闭重启后鼠标继续操作新正文', (tester) async {
    final app = await mountRoot(
      tester,
      hasSong: true,
      recommendationsLoading: false,
      pageInteractionRefinements: true,
      workspacePageRefinements: true,
      viewport: const Size(1920, 1032),
      catalogOverride: _Catalog(
        hotTerms: [for (var i = 0; i < 30; i++) 'E25热词$i'],
      ),
    );
    final trace = binding.trace;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1918, 1));
    trace.onIssue = () => _dumpMarkers(tester, trace);
    trace.step = 'E25第一代迟启语义';
    SemanticsHandle? handle = tester.ensureSemantics();
    Future<void> click(Finder target, String stage) =>
        _axMouseClick(tester, mouse, trace, target, stage);
    try {
      await _axFrames(tester, trace, 'E25第一代初始逐帧', 4);
      await click(
        find.byKey(const ValueKey('ik-workspace-nav-1')),
        'E25第一代进入搜索',
      );
      await click(
        find.text(IkLibraryRevisionStrings.expandHotSearch),
        'E25第一代实际展开30热词',
      );
      for (final anchor in ['搜索导航', '进度滑块']) {
        final target = find.byKey(
          ValueKey(anchor == '搜索导航' ? 'ik-workspace-nav-1' : 'ik-bar-seek'),
        );
        await _axMouseHover(tester, mouse, trace, target, 'E25关闭前鼠标停于$anchor');
        trace.expectValid();
        final oldOwner = binding.renderViews.single.owner!.semanticsOwner;
        expect(oldOwner, isNotNull);
        expect(binding.debugOutstandingSemanticsHandles, 1);
        final oldBatchCount = trace.batches.length;
        trace.step = 'E25$anchor释放唯一handle并等待语义所有者销毁';
        handle!.dispose();
        handle = null;
        await _axFrames(tester, trace, 'E25$anchor关闭期间逐帧', 4);
        expect(binding.debugOutstandingSemanticsHandles, 0);
        expect(binding.semanticsEnabled, isFalse);
        expect(binding.renderViews.single.owner!.semanticsOwner, isNull);
        expect(trace.batches.length, oldBatchCount, reason: '语义关闭后不得产生新批次');
        trace.expectValid();
        trace.finishDiagnostics(completed: true);
        // 当前Windows view在false时销毁bridge，true时新建bridge。
        // 仅在旧代完整有效且owner确已销毁之后重置；不清除活动树问题。
        trace.clear();
        trace.onIssue = () => _dumpMarkers(tester, trace);
        trace.step = 'E25$anchor重建语义bridge对应的新代';
        handle = tester.ensureSemantics();
        await _axFrames(tester, trace, 'E25$anchor重启初始完整批次', 4);
        expect(binding.debugOutstandingSemanticsHandles, 1);
        expect(binding.semanticsEnabled, isTrue);
        expect(
          binding.renderViews.single.owner!.semanticsOwner,
          isNot(same(oldOwner)),
        );
        expect(trace.batches, isNotEmpty);
        expect(
          trace.batches.first.any((node) => node.id == 0),
          isTrue,
          reason: 'bridge重建后首批必须初始化根0',
        );
        trace.expectValid();
        await click(
          find.byKey(const ValueKey('ik-workspace-nav-0')),
          'E25$anchor重启后鼠标进入发现',
        );
        await click(
          find.byKey(const ValueKey('ik-workspace-nav-1')),
          'E25$anchor重启后鼠标返回搜索',
        );
        expect(
          find.descendant(
            of: find.byType(IkSearchWorkspace),
            matching: find.byType(ActionChip),
          ),
          findsNWidgets(30),
        );
      }
      await click(
        find.byKey(const ValueKey('ik-workspace-nav-2')),
        'E25重启后鼠标进入音乐库',
      );
      await click(
        find.byKey(const ValueKey('ik-library-category-playlists')),
        'E25重启后鼠标进入我的歌单',
      );
      await click(
        find.descendant(
          of: find.byType(PlatformPlaylistsPage),
          matching: find.byType(IkSelect<PlatformType>),
        ),
        'E25重启后鼠标打开来源菜单',
      );
      expect(find.byType(MenuItemButton).hitTestable(), findsWidgets);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _axFrames(tester, trace, 'E25重启后来源菜单Esc退场', 40);
      expect(find.byType(MenuItemButton), findsNothing);
      trace.expectValid();
    } finally {
      handle?.dispose();
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      app.container.dispose();
      app.appearance.dispose();
      app.unified.dispose();
      await tester.pump();
    }
  });

  for (final route in ['/downloads', '/player']) {
    _testWindows('E26 主区隐藏于$route时真实热词推荐迟返', (tester) async {
      final terms = [for (var i = 0; i < 30; i++) 'E26热词$i'];
      final catalog = _PendingCatalog(hotTerms: terms);
      final platforms = {
        for (final platform in PlatformType.musicServices)
          platform: _PendingContent(platform),
      };
      for (final platform in platforms.values) {
        PlatformRegistry.register(platform);
      }
      final app = await mountRoot(
        tester,
        hasSong: true,
        pageInteractionRefinements: true,
        workspacePageRefinements: true,
        viewport: const Size(1920, 1032),
        catalogOverride: catalog,
        recommendationsOverride: _PendingRecommendations(),
      );
      final trace = binding.trace;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1918, 1));
      trace.onIssue = () => _dumpMarkers(tester, trace);
      trace.step = 'E26$route两类真实加载等待期间迟启语义';
      final handle = tester.ensureSemantics();
      Future<void> click(Finder target, String stage) =>
          _axMouseClick(tester, mouse, trace, target, stage);
      try {
        await _axFrames(tester, trace, 'E26$route初始逐帧', 4);
        expect(catalog.hotLoads, 1);
        expect(app.container.read(recommendationsProvider).isLoading, isTrue);
        for (final platform in platforms.values) {
          expect(platform.recommendationLoads, 1);
        }
        await click(
          find.byKey(const ValueKey('ik-workspace-nav-1')),
          'E26$route等待期间鼠标进入搜索',
        );
        final search = find.byType(IkSearchWorkspace);
        expect(tester.widget<IkSearchWorkspace>(search).hotLoading, isTrue);
        expect(tester.widget<IkSearchWorkspace>(search).hotTerms, isEmpty);
        await _axMouseHover(
          tester,
          mouse,
          trace,
          find.byKey(const ValueKey('ik-workspace-nav-1')),
          'E26$route隐藏主区前搜索导航悬停',
        );
        final router = GoRouter.of(tester.element(search));
        trace.step = 'E26$route真实请求未完成时隐藏主区';
        unawaited(router.push<void>(route));
        await _axFrames(tester, trace, 'E26$route进入逐帧', 40);
        final body = route == '/player'
            ? find.byType(WindowsPlayerPage)
            : find.byType(IkDownloadsWorkspace);
        expect(body.hitTestable(), findsOneWidget);
        expect(search.hitTestable(), findsNothing);
        await _axMouseHover(
          tester,
          mouse,
          trace,
          find.byKey(const ValueKey('ik-bar-seek')),
          'E26$route返回前进度滑块悬停',
        );
        expect(app.container.read(recommendationsProvider).isLoading, isTrue);
        trace.step = 'E26$route主区隐藏时热词Future真实返回';
        catalog.release();
        await _axFrames(tester, trace, 'E26$route热词返回逐帧', 4);
        final hiddenSearch = find.byType(
          IkSearchWorkspace,
          skipOffstage: false,
        );
        expect(tester.widget<IkSearchWorkspace>(hiddenSearch).hotTerms, terms);
        expect(
          tester.widget<IkSearchWorkspace>(hiddenSearch).hotLoading,
          isFalse,
        );
        for (final entry in platforms.entries) {
          trace.step = 'E26$route主区隐藏时${entry.key.name}推荐Future真实返回';
          entry.value.release();
          await _axFrames(tester, trace, 'E26$route${entry.key.name}推荐返回逐帧', 4);
          final state = app.container.read(recommendationsProvider);
          expect(state.songsForPlatform(entry.key), [
            entry.value.recommendedSong,
          ]);
          expect(
            state.sourceForPlatform(entry.key)?.kind,
            entry.value.source.kind,
          );
          expect(body.hitTestable(), findsOneWidget);
          expect(
            trace.nodes.values.any(
              (node) => node.label.contains(entry.value.recommendedSong.name),
            ),
            isFalse,
            reason: '隐藏发现页迟到推荐不得泄漏到当前可见AX树',
          );
        }
        expect(app.container.read(recommendationsProvider).isLoading, isFalse);
        expect(app.container.read(recommendationsProvider).totalCount, 3);
        for (final term in terms) {
          expect(
            trace.nodes.values.any((node) => node.label == term),
            isFalse,
            reason: '隐藏搜索页迟到热词不得泄漏到当前可见AX树',
          );
        }
        await click(
          route == '/player'
              ? find.descendant(
                  of: body,
                  matching: find.text(WindowsMusicStrings.back),
                )
              : find.byType(BackButton).hitTestable(),
          'E26$route鼠标返回迟到热词已加载的搜索',
        );
        expect(search.hitTestable(), findsOneWidget);
        expect(tester.widget<IkSearchWorkspace>(search).hotLoading, isFalse);
        await click(
          find.text(IkLibraryRevisionStrings.expandHotSearch),
          'E26$route返回后实际展开全部30热词',
        );
        expect(
          find.descendant(of: search, matching: find.byType(ActionChip)),
          findsNWidgets(30),
        );
        for (final term in terms) {
          expect(
            find
                .descendant(of: search, matching: find.text(term))
                .hitTestable(),
            findsOneWidget,
          );
        }
        await click(
          find.byKey(const ValueKey('ik-workspace-nav-0')),
          'E26$route鼠标返回迟到推荐已加载的发现',
        );
        final home = find.byType(IkHomePage);
        for (final platform in [PlatformType.qq, PlatformType.kugou]) {
          final song = find.descendant(
            of: home,
            matching: find.text(platforms[platform]!.recommendedSong.name),
          );
          await tester.scrollUntilVisible(
            song,
            240,
            scrollable: _verticalScrolls(home).single,
          );
          await _axFrames(tester, trace, 'E26$route${platform.name}推荐显示', 4);
          expect(song.hitTestable(), findsOneWidget);
        }
        expect(
          find.descendant(
            of: home,
            matching: find.text(
              platforms[PlatformType.netease]!.recommendedSong.name,
            ),
          ),
          findsNothing,
          reason: '个性每日推荐不会重回公共发现列表',
        );
        trace.expectValid();
      } finally {
        handle.dispose();
        catalog.release();
        for (final platform in platforms.values) {
          platform.release();
        }
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox.shrink());
        app.container.dispose();
        app.appearance.dispose();
        app.unified.dispose();
        await tester.pump();
      }
    });
  }

  for (final viewport in [const Size(1920, 1032), const Size(390, 844)]) {
    for (final newWorkspace in [false, true]) {
      for (final trigger in ['无提示push', '提示可见push', '提示退场鼠标点击']) {
        _testWindows(
          'E27 ${viewport.width.toInt()}宽新正文$newWorkspace所有加载完成后$trigger进入独立播放器',
          (tester) async {
            final app = await mountRoot(
              tester,
              hasSong: true,
              recommendationsLoading: false,
              pageInteractionRefinements: true,
              workspacePageRefinements: newWorkspace,
              viewport: viewport,
            );
            final trace = binding.trace;
            final mouse = await tester.createGesture(
              kind: PointerDeviceKind.mouse,
            );
            await mouse.addPointer(location: const Offset(1918, 1));
            trace.onIssue = () => _dumpMarkers(tester, trace);
            trace.step = 'E27所有加载完成后迟启语义';
            final handle = tester.ensureSemantics();
            try {
              await _axFrames(tester, trace, 'E27初始逐帧', 4);
              final searchNav = find.byKey(
                const ValueKey('ik-workspace-nav-1'),
              );
              await _axMouseClick(
                tester,
                mouse,
                trace,
                searchNav,
                'E27实际鼠标进入搜索后离开',
              );
              if (trigger != '无提示push') {
                await _axMouseHover(
                  tester,
                  mouse,
                  trace,
                  searchNav,
                  'E27搜索导航悬停直至提示显示',
                );
              }
              trace.step = 'E27新正文$newWorkspace通过$trigger进入独立播放器';
              if (trigger == '提示退场鼠标点击') {
                final song = find
                    .descendant(
                      of: find.byType(IkPlaybackBar),
                      matching: find.text(_track.name),
                    )
                    .hitTestable();
                expect(song, findsOneWidget);
                final point = tester.getCenter(song);
                await mouse.moveTo(point);
                await _axFrames(tester, trace, 'E27鼠标离开导航提示尚在退场', 1);
                await mouse.down(point);
                await _axFrames(tester, trace, 'E27真实鼠标按下歌曲', 1);
                await mouse.up();
              } else {
                final router = GoRouter.of(
                  tester.element(find.byType(IkSearchWorkspace)),
                );
                unawaited(router.push<void>('/player'));
              }
              await _axFrames(
                tester,
                trace,
                'E27新正文$newWorkspace$trigger播放器进入逐帧',
                40,
              );
              expect(
                find.byType(WindowsPlayerPage).hitTestable(),
                findsOneWidget,
              );
              trace.expectValid();
            } finally {
              handle.dispose();
              await mouse.removePointer();
              await tester.pumpWidget(const SizedBox.shrink());
              app.container.dispose();
              app.appearance.dispose();
              app.unified.dispose();
              await tester.pump();
            }
          },
        );
      }
    }
  }

  _testWindows('E16 全开真实根五主区、连续内嵌路由、独立播放器与音源草稿完整AX', (tester) async {
    PlatformRegistry.register(_E16Content());
    final app = await mountRoot(
      tester,
      hasSong: true,
      recommendationsLoading: false,
      interactionIo: true,
      pageInteractionRefinements: true,
      workspacePageRefinements: true,
      withSourceManager: true,
      viewport: const Size(1186, 793),
      catalogOverride: _Catalog(hotTerms: const ['E16热门搜索']),
      restoredState: const PlayerState(
        currentSong: _track,
        duration: Duration(minutes: 3),
        position: Duration(seconds: 30),
        playlist: [_track],
      ),
    );
    final counts = {
      PlatformType.netease: 2,
      PlatformType.qq: 9,
      PlatformType.kugou: 3,
    };
    app.recommendations.show(
      RecommendationsState(
        songsByPlatform: {
          for (final entry in counts.entries)
            entry.key: [
              for (var index = 0; index < entry.value; index++)
                Song(
                  id: 'e16-${entry.key.name}-$index',
                  name: 'E16${entry.key.name}推荐$index',
                  platform: entry.key,
                  artists: _track.artists,
                ),
            ],
        },
        sourceByPlatform: {
          for (final platform in counts.keys)
            platform: _R10Content(platform).source,
        },
      ),
    );
    await tester.runAsync(() async {
      await app.container.read(likesProvider.notifier).toggleLike(_track);
      await app.container.read(historyProvider.notifier).recordListen(_track);
    });
    final trace = binding.trace;
    await _rootDrain(tester, trace);
    expect(binding.renderViews.single.owner!.semanticsOwner, isNull);
    trace.onIssue = () => _dumpMarkers(tester, trace);
    trace.step = 'E16实际新页面已装配，迟启语义后连续记录全部原始批次';
    final handle = tester.ensureSemantics();
    Future<void> tap(Finder target, String stage) =>
        _r10Tap(tester, trace, target, stage);
    final workspace = find.byType(IkDesktopWorkspace);
    final search = find.byType(IkSearchWorkspace);
    final home = find.byType(IkHomePage);
    final manager = find.byType(SourceManagerPage);
    void expectFrame({bool player = false}) {
      expect(workspace, findsOneWidget);
      expect(tester.widget<IkDesktopWorkspace>(workspace).fullPage, player);
      expect(
        find.text('IK Music').hitTestable(),
        player ? findsNothing : findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('ik-workspace-search')).hitTestable(),
        player ? findsNothing : findsOneWidget,
      );
      expect(find.byType(IkPlaybackBar).hitTestable(), findsOneWidget);
    }

    try {
      await _rootDrain(tester, trace);
      trace.expectValid();
      final root = tester.widget<VideoMusicApp>(find.byType(VideoMusicApp));
      expect(root.workspacePageRefinements, isTrue);
      expect(root.pageInteractionRefinements, isTrue);
      final retained = {
        for (var page = 0; page < 5; page++)
          page: find
              .byKey(
                ValueKey('ik-workspace-page-overlay-$page'),
                skipOffstage: false,
              )
              .evaluate()
              .single,
      };
      final mainPages = [
        IkHomePage,
        IkSearchWorkspace,
        IkLibraryWorkspace,
        IkRecentPage,
        IkSettingsWorkspace,
      ];
      for (var page = 0; page < mainPages.length; page++) {
        final nav = find.byKey(ValueKey('ik-workspace-nav-$page'));
        await tap(nav, 'E16五主区逐一进入$page');
        expectFrame();
        expect(find.byType(mainPages[page]).hitTestable(), findsOneWidget);
        expect(
          tester.getSemantics(nav).flagsCollection.isSelected,
          Tristate.isTrue,
        );
        for (final entry in retained.entries) {
          expect(
            find
                .byKey(
                  ValueKey('ik-workspace-page-overlay-${entry.key}'),
                  skipOffstage: false,
                )
                .evaluate()
                .single,
            same(entry.value),
            reason: 'E16主区${entry.key}在新正文导航中仍须保留Element',
          );
        }
        if (page == 0) {
          expect(
            tester.widget<IkHomePage>(home).recommendationsInDiscovery,
            isTrue,
          );
          expect(
            find.byKey(const Key('ik-personal-daily-entry')).hitTestable(),
            findsOneWidget,
          );
          // SliverLayoutBuilder仅布局抵达的网格；逐首实际滚动后核验各平台，
          // 不能把首屏未构造的酷狗网格当作缺失，也不能只检查首屏QQ样本。
          final renderedCounts = <PlatformType, int?>{};
          final inspectedRows = <String>{};
          for (final platform in [PlatformType.qq, PlatformType.kugou]) {
            for (var index = 0; index < counts[platform]!; index++) {
              trace.step = 'E16逐首可见核验${platform.name}公共推荐$index';
              final row = find.byKey(
                ValueKey('ik-discovery-song-${platform.name}-$index'),
              );
              await tester.scrollUntilVisible(
                row,
                300,
                scrollable: _verticalScrolls(home).single,
              );
              await _rootDrain(tester, trace);
              expect(row.hitTestable(), findsOneWidget);
              final grid = tester.widget<SliverGrid>(
                find.ancestor(of: row, matching: find.byType(SliverGrid)),
              );
              expect(
                grid.delegate.estimatedChildCount,
                counts[platform],
                reason: '${platform.name}实际网格必须完整呈现该平台全部公共推荐',
              );
              renderedCounts[platform] = grid.delegate.estimatedChildCount;
              expect(
                find.descendant(
                  of: row,
                  matching: find.text('E16${platform.name}推荐$index'),
                ),
                findsOneWidget,
              );
              inspectedRows.add('${platform.name}-$index');
              for (
                var personal = 0;
                personal < counts[PlatformType.netease]!;
                personal++
              ) {
                expect(find.text('E16netease推荐$personal'), findsNothing);
              }
            }
          }
          expect(renderedCounts, {PlatformType.qq: 9, PlatformType.kugou: 3});
          expect(
            inspectedRows,
            unorderedEquals([
              for (final platform in [PlatformType.qq, PlatformType.kugou])
                for (var index = 0; index < counts[platform]!; index++)
                  '${platform.name}-$index',
            ]),
            reason: '两平台全部12首均须在滚动后实际可见，不允许截断或抽样',
          );
          trace.step = 'E16发现完整遍历后回到顶部';
          final position = tester
              .state<ScrollableState>(_verticalScrolls(home).single)
              .position;
          position.jumpTo(position.minScrollExtent);
          await _rootDrain(tester, trace);
        } else if (page == 1) {
          expect(
            tester.widget<IkSearchWorkspace>(search).recommendationsInDiscovery,
            isTrue,
          );
          expect(
            find.byKey(const ValueKey('ik-search-hot-terms')).hitTestable(),
            findsOneWidget,
          );
          expect(find.text('E16热门搜索').hitTestable(), findsOneWidget);
          expect(
            find.byKey(const ValueKey('ik-search-recommendations')),
            findsNothing,
          );
          expect(find.textContaining('E16qq推荐'), findsNothing);
          expect(find.text('查看全部推荐'), findsNothing);
        } else if (page == 2) {
          expect(
            tester
                .widget<IkLibraryWorkspace>(find.byType(IkLibraryWorkspace))
                .stableCategoryTabs,
            isTrue,
          );
          expect(
            find
                .byKey(const ValueKey('ik-library-content-likes'))
                .hitTestable(),
            findsOneWidget,
          );
        }
        trace.expectValid();
      }

      await tap(
        find.byKey(const ValueKey('ik-workspace-nav-1')),
        'E16准备搜索状态，随后连续跨正文与独立页',
      );
      trace.step = 'E16实际提交共享搜索框';
      await tester.enterText(
        find.byKey(const ValueKey('ik-workspace-search')),
        'E16连续导航',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await _rootDrain(tester, trace);
      final searchState = tester.state(search);
      final beforePlayer = app.container.read(playerProvider);
      final router = GoRouter.of(tester.element(workspace));
      trace.step = 'E16普通下载正文进入：保留侧栏、搜索和播放栏';
      unawaited(router.push<void>('/downloads'));
      await _rootDrain(tester, trace);
      expect(find.byType(IkDownloadsWorkspace).hitTestable(), findsOneWidget);
      expectFrame();
      await tap(
        find.descendant(
          of: find.byType(IkPlaybackBar),
          matching: find.text(_track.name),
        ),
        'E16由正文播放栏实际进入独立紧凑播放器',
      );
      expectFrame(player: true);
      final playerPage = find.byType(WindowsPlayerPage);
      expect(
        tester.widget<WindowsPlayerPage>(playerPage).compactLayout,
        isTrue,
      );
      expect(find.byKey(const ValueKey('ik-player-divider')), findsNothing);
      final information = find.byKey(const ValueKey('ik-player-information'));
      final lyricsPane = find.byKey(const ValueKey('ik-player-lyrics-pane'));
      expect(information.hitTestable(), findsOneWidget);
      expect(lyricsPane.hitTestable(), findsOneWidget);
      final informationRect = tester.getRect(information);
      final lyricsRect = tester.getRect(lyricsPane);
      expect(lyricsRect.left - informationRect.right, inInclusiveRange(24, 40));
      expect(informationRect.top, closeTo(lyricsRect.top, .01));
      expect(
        tester
            .widget<VideoCover>(
              find.descendant(
                of: information,
                matching: find.byType(VideoCover),
              ),
            )
            .size,
        greaterThan(330),
        reason: '实际紧凑宽屏封面需使用新布局空间，不能只有compact参数为真',
      );
      await tap(find.byKey(const ValueKey('ik-bar-queue')), 'E16播放器实际待播放浮层展开');
      expect(find.byType(IkQueuePanel).hitTestable(), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(
        find.descendant(
          of: find.byType(IkQueuePanel),
          matching: find.text(_track.name),
        ),
        findsOneWidget,
      );
      await tap(find.byTooltip(IkStrings.close).hitTestable(), 'E16播放器待播放浮层关闭');
      expect(find.byType(IkQueuePanel), findsNothing);
      expectFrame(player: true);
      trace.step = 'E16播放器之上继续进入内嵌queue路由';
      unawaited(router.push<void>('/queue'));
      await _rootDrain(tester, trace);
      expect(find.byType(QueuePage).hitTestable(), findsOneWidget);
      expectFrame();
      trace.step = 'E16queue之上继续进入真实专辑正文';
      unawaited(router.push<void>('/album/qq/semantics-album'));
      await _rootDrain(tester, trace);
      final album = find.byType(AlbumPage);
      expect(album.hitTestable(), findsOneWidget);
      expect(
        find.descendant(of: album, matching: find.text(_track.name)),
        findsOneWidget,
      );
      expectFrame();
      for (final back in [
        (leaving: AlbumPage, arriving: QueuePage, player: false),
        (leaving: QueuePage, arriving: WindowsPlayerPage, player: true),
        (
          leaving: WindowsPlayerPage,
          arriving: IkDownloadsWorkspace,
          player: false,
        ),
        (
          leaving: IkDownloadsWorkspace,
          arriving: IkSearchWorkspace,
          player: false,
        ),
      ]) {
        final target = back.leaving == WindowsPlayerPage
            ? find.descendant(
                of: find.byType(WindowsPlayerPage),
                matching: find.text(WindowsMusicStrings.back),
              )
            : find.byType(BackButton).hitTestable();
        await tap(target, 'E16连续返回${back.leaving}→${back.arriving}');
        expect(find.byType(back.arriving).hitTestable(), findsOneWidget);
        expectFrame(player: back.player);
        trace.expectValid();
      }
      expect(tester.state(search), same(searchState));
      expect(tester.widget<IkSearchWorkspace>(search).search.query, 'E16连续导航');

      await tap(find.byKey(const ValueKey('ik-workspace-nav-4')), 'E16进入实际设置');
      await tap(
        find.byKey(const ValueKey('ik-settings-sources')),
        'E16进入音源设置区',
      );
      await tap(
        find.descendant(
          of: find.byType(IkSettingsWorkspace),
          matching: find.text(IkSourceCatalogStrings.manage),
        ),
        'E16实际进入音源管理正文',
      );
      expect(manager.hitTestable(), findsOneWidget);
      expect(
        tester.widget<SourceManagerPage>(manager).modernPolicyMenu,
        isTrue,
      );
      expect(IkWorkspaceNavigation.maybeOf(tester.element(manager)), isNotNull);
      expectFrame();
      expect(
        find.descendant(of: manager, matching: find.byType(ExpansionTile)),
        findsNothing,
      );
      final sourceSettings = app.container
          .read(ikSourceCatalogProvider)!
          .settings;
      final savedPolicy = sourceSettings.value.toJson();
      final managerState = tester.state(manager);
      final trigger = find.byKey(const ValueKey('manager-policy-trigger'));
      final option = find.byKey(const ValueKey('manager-policy-option-false'));
      trace.step = 'E16策略菜单展开前定位新触发框';
      await tester.ensureVisible(trigger);
      await _pumpAndCheck(tester, trace);
      final listRect = tester.getRect(
        find.byKey(const ValueKey('manager-search')),
      );
      trace.step = 'E16实际新下拉展开并检查可见尺寸与不透明背景';
      await tester.tap(trigger.hitTestable());
      await _rootDrain(tester, trace);
      expect(find.byType(MenuItemButton).hitTestable(), findsNWidgets(2));
      final anchor = tester.widget<MenuAnchor>(
        find.descendant(of: manager, matching: find.byType(MenuAnchor)),
      );
      final menu = find
          .ancestor(of: option, matching: find.byType(Material))
          .first;
      expect(anchor.crossAxisUnconstrained, isFalse);
      expect(anchor.style!.backgroundColor!.resolve({})!.a, 1);
      expect(
        tester.getSize(menu).width,
        closeTo(tester.getSize(trigger).width, 1),
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('manager-search'))),
        listRect,
      );
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      trace.step = 'E16音源新菜单Esc关闭，仍停在正文';
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _rootDrain(tester, trace);
      expect(find.byType(MenuItemButton), findsNothing);
      expect(manager.hitTestable(), findsOneWidget);
      await tap(trigger, 'E16音源新菜单再次展开');
      await tap(
        find.byKey(const ValueKey('manager-policy-option-true')),
        'E16选择备用音源优先，形成真实未保存草稿',
      );
      expect(find.byType(MenuItemButton), findsNothing);
      final auto = find.byKey(const ValueKey('manager-auto-switch'));
      await tap(auto, 'E16修改独立自动切换策略');
      expect(tester.widget<SwitchListTile>(auto).value, isTrue);
      expect(sourceSettings.value.toJson(), savedPolicy);
      await tap(
        find.byKey(const ValueKey('ik-workspace-nav-1')),
        'E16草稿主导航离开弹出保护提示',
      );
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.widgetWithText(AlertDialog, ExpandedStrings.dirty),
        findsOneWidget,
      );
      await tap(find.text(ExpandedStrings.keepEditing), 'E16取消离开保留策略草稿');
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.state(manager), same(managerState));
      expect(
        find.descendant(
          of: trigger,
          matching: find.text(SourceStrings.customFirst),
        ),
        findsOneWidget,
      );
      expect(tester.widget<SwitchListTile>(auto).value, isTrue);
      expectFrame();
      await tap(
        find.byKey(const ValueKey('ik-workspace-nav-1')),
        'E16再次请求离开音源草稿',
      );
      await tap(find.text(ExpandedStrings.discard), 'E16放弃草稿返回原搜索状态');
      expect(manager, findsNothing);
      expect(search.hitTestable(), findsOneWidget);
      expect(tester.state(search), same(searchState));
      expect(tester.widget<IkSearchWorkspace>(search).search.query, 'E16连续导航');
      expect(sourceSettings.value.toJson(), savedPolicy);
      await tap(
        find.byKey(const ValueKey('ik-workspace-nav-4')),
        'E16返回保留的音源设置区',
      );
      await tap(
        find.descendant(
          of: find.byType(IkSettingsWorkspace),
          matching: find.text(IkSourceCatalogStrings.manage),
        ),
        'E16重开音源正文确认放弃未落盘',
      );
      expect(tester.widget<SwitchListTile>(auto).value, isFalse);
      expect(
        find.descendant(
          of: trigger,
          matching: find.text(ExpandedStrings.officialFirst),
        ),
        findsOneWidget,
      );
      await tap(
        find.descendant(of: manager, matching: find.byType(BackButton)),
        'E16无草稿页内返回设置，连续AX收尾',
      );
      expect(find.byType(IkSettingsWorkspace).hitTestable(), findsOneWidget);
      expect(manager, findsNothing);
      expectFrame();
      final afterPlayer = app.container.read(playerProvider);
      expect(afterPlayer.currentSong, beforePlayer.currentSong);
      expect(afterPlayer.position, beforePlayer.position);
      expect(afterPlayer.isPlaying, beforePlayer.isPlaying);
      expect(afterPlayer.playlist, beforePlayer.playlist);
      trace.expectValid();
    } finally {
      handle.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      app.container.dispose();
      app.appearance.dispose();
      app.unified.dispose();
      await tester.pump();
    }
  });

  _testWindows('R10 新界面真实根五分类、发现三平台、搜索菜单、播放详情与桌面歌词连续AX回归', (tester) async {
    final content = {
      for (final platform in PlatformType.musicServices)
        platform: _R10Content(
          platform,
          unsupportedRegions: platform == PlatformType.netease
              ? const {NewSongRegion.hongKongTaiwan}
              : const {},
        ),
    };
    for (final platform in content.values) {
      PlatformRegistry.register(platform);
    }
    final app = await mountRoot(
      tester,
      hasSong: true,
      viewport: const Size(1186, 793),
      catalogOverride: _Catalog(
        hotTerms: const ['R10热词一', 'R10热词二'],
        resultDuration: Duration.zero,
      ),
      realDiscovery: true,
      interactionIo: true,
    );
    await tester.runAsync(
      () => app.container.read(likesProvider.notifier).toggleLike(_track),
    );
    final seed = await tester.runAsync(
      () => app.container
          .read(myPlaylistsProvider.notifier)
          .importPlaylist(name: 'R10真实含歌歌单', songs: [_track]),
    );
    expect(seed, isNotNull);
    final seedPlaylist = seed!;
    await _rootDrain(tester, binding.trace);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1180, 1));
    binding.trace.onIssue = () => _dumpMarkers(tester, binding.trace);
    final handle = tester.ensureSemantics();
    try {
      binding.trace.step = 'R10真实根启用无障碍：真实喜欢、歌单与三平台推荐已加载';
      await _rootDrain(tester, binding.trace);
      expect(app.container.read(likesProvider).songs, hasLength(1));
      expect(app.container.read(myPlaylistsProvider).playlists, hasLength(1));
      expect(app.container.read(recommendationsProvider).totalCount, 3);
      binding.trace.expectValid();

      await _r10Tap(
        tester,
        binding.trace,
        find.byKey(const ValueKey('ik-workspace-nav-2')),
        'R10进入真实音乐库',
      );
      const categories = ['likes', 'playlists', 'local', 'downloads', 'smart'];
      for (final category in categories.skip(1)) {
        expect(
          find.byKey(
            ValueKey('ik-library-content-$category'),
            skipOffstage: false,
          ),
          findsNothing,
          reason: '未访问分类$category保持lazy，不要求提前构造内容',
        );
      }
      final retained = <String, Element>{};
      final retainedScrolls =
          <String, List<({ScrollableState state, double pixels})>>{};
      for (final category in categories) {
        final tab = find.byKey(ValueKey('ik-library-category-$category'));
        await _r10Tap(tester, binding.trace, tab, 'R10切换音乐库分类$category');
        expect(tab.hitTestable(), findsOneWidget);
        expect(
          tester
              .getSemantics(tab)
              .getSemanticsData()
              .flagsCollection
              .isSelected,
          Tristate.isTrue,
        );
        final owner = find.byKey(ValueKey('ik-library-content-$category'));
        expect(owner, findsOneWidget);
        if (category == 'likes') {
          final row = find.descendant(
            of: owner,
            matching: find.byType(IkSongTableRow),
          );
          expect(row, findsOneWidget);
          await _r10CancelSongMenu(
            tester,
            mouse,
            binding.trace,
            app,
            row,
            'R10喜欢歌曲更多取消',
          );
        } else if (category == 'playlists') {
          expect(find.byType(PlatformPlaylistsPage), findsOneWidget);
          expect(find.text(seedPlaylist.name), findsOneWidget);
          final before = await _r10Snapshot(tester, app);
          await _r10Tap(
            tester,
            binding.trace,
            find.descendant(of: owner, matching: find.byTooltip('新建歌单')),
            'R10实际打开歌单创建对话框',
          );
          expect(find.byType(AlertDialog), findsOneWidget);
          await tester.enterText(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextField),
            ),
            'R10取消不应创建此歌单',
          );
          await _walkPage(
            tester,
            mouse,
            binding.trace,
            'R10歌单创建对话框全部滚动与提示',
            owner: find.byType(AlertDialog),
          );
          await _r10Tap(
            tester,
            binding.trace,
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.widgetWithText(TextButton, '取消'),
            ),
            'R10实际取消歌单创建',
          );
          expect(find.byType(AlertDialog), findsNothing);
          expect(await _r10Snapshot(tester, app), equals(before));
          await _r10Tap(
            tester,
            binding.trace,
            find.descendant(
              of: owner,
              matching: find.byType(PopupMenuButton<String>),
            ),
            'R10实际打开含歌歌单菜单',
          );
          final export = find.byWidgetPredicate(
            (widget) =>
                widget is PopupMenuItem<String> && widget.value == 'export',
          );
          expect(export, findsOneWidget);
          await _r10Tap(tester, binding.trace, export, 'R10实际打开歌单导出选择');
          expect(find.byType(Dialog), findsOneWidget);
          expect(find.text(IkStrings.playlistJson), findsOneWidget);
          await _walkPage(
            tester,
            mouse,
            binding.trace,
            'R10导出选择全部滚动与提示',
            owner: find.byType(Dialog),
          );
          await _r10Tap(
            tester,
            binding.trace,
            find.descendant(
              of: find.byType(Dialog),
              matching: find.byTooltip(IkStrings.close),
            ),
            'R10实际取消歌单导出',
          );
          expect(find.byType(Dialog), findsNothing);
          expect(await _r10Snapshot(tester, app), equals(before));
        } else if (category == 'local') {
          expect(find.byType(LocalMusicPage), findsOneWidget);
          expect(app.container.read(localMusicProvider).tracks, isEmpty);
          expect(
            app.container.read(localMusicProvider).selectedDirectory,
            isNull,
          );
        } else if (category == 'downloads') {
          expect(app.container.read(downloadProvider).tasks, isEmpty);
          expect(find.text(VideoStrings.noDownloads), findsOneWidget);
        } else if (category == 'smart') {
          expect(find.byType(SmartPlaylistsPage), findsOneWidget);
        }
        await _walkPage(
          tester,
          mouse,
          binding.trace,
          'R10音乐库$category完整遍历',
          owner: owner,
        );
        retained[category] = owner.evaluate().single;
        retainedScrolls[category] = [
          for (final scroll in _verticalScrolls(owner))
            (
              state: tester.state<ScrollableState>(scroll),
              pixels: tester.state<ScrollableState>(scroll).position.pixels,
            ),
        ];
        for (final entry in retained.entries) {
          expect(
            find
                .byKey(
                  ValueKey('ik-library-content-${entry.key}'),
                  skipOffstage: false,
                )
                .evaluate()
                .single,
            same(entry.value),
            reason: '已访问${entry.key}的Element必须留存',
          );
        }
      }
      for (final category in categories) {
        await _r10Tap(
          tester,
          binding.trace,
          find.byKey(ValueKey('ik-library-category-$category')),
          'R10往返音乐库$category保留内容和滚动状态',
        );
        final owner = find.byKey(ValueKey('ik-library-content-$category'));
        expect(owner.evaluate().single, same(retained[category]));
        final scrolls = _verticalScrolls(owner);
        expect(scrolls, hasLength(retainedScrolls[category]!.length));
        for (var index = 0; index < scrolls.length; index++) {
          final saved = retainedScrolls[category]![index];
          final actual = tester.state<ScrollableState>(scrolls[index]);
          expect(actual, same(saved.state));
          expect(actual.position.pixels, closeTo(saved.pixels, .001));
        }
        await _allTooltips(tester, mouse, binding.trace, 'R10返回音乐库$category');
      }
      binding.trace.expectValid();

      await _r10Tap(
        tester,
        binding.trace,
        find.byKey(const ValueKey('ik-workspace-nav-0')),
        'R10返回发现并操作真实入口',
      );
      final home = find.byType(IkHomePage);
      final homeElement = home.evaluate().single;
      await _walkPage(
        tester,
        mouse,
        binding.trace,
        'R10发现主页全部内容与提示',
        owner: home,
      );
      await _r10Tap(
        tester,
        binding.trace,
        find.descendant(of: home, matching: find.text(IkStrings.newSongs)),
        'R10实际进入新歌速递路由',
      );
      final newSongs = find.byType(NewSongsPage);
      expect(tester.widget<NewSongsPage>(newSongs).alignToDesign, isTrue);
      for (final platform in PlatformType.musicServices) {
        final fixture = content[platform]!;
        await _r10SelectPlatform(
          tester,
          binding.trace,
          newSongs,
          platform,
          '新歌',
        );
        expect(
          find.descendant(
            of: newSongs,
            matching: find.text(fixture.newSong.name),
          ),
          findsOneWidget,
        );
        await _walkPage(
          tester,
          mouse,
          binding.trace,
          'R10新歌${platform.name}成功',
          owner: newSongs,
        );
        await _r10CancelSongMenu(
          tester,
          mouse,
          binding.trace,
          app,
          find.descendant(of: newSongs, matching: find.byType(IkSongTableRow)),
          'R10新歌${platform.name}更多取消',
          contextual: true,
        );
        fixture.newSongsFailure = 'R10${platform.name}新歌网络失败';
        await _r10Tap(
          tester,
          binding.trace,
          find.descendant(
            of: newSongs,
            matching: find.byTooltip(IkDiscoveryRevisionStrings.refresh),
          ),
          'R10新歌${platform.name}单来源失败',
        );
        final failed = app.container.read(newSongsProvider);
        expect(failed.errorForPlatform(platform), fixture.newSongsFailure);
        expect(
          find.descendant(
            of: newSongs,
            matching: find.text(fixture.newSongsFailure!),
          ),
          findsOneWidget,
        );
        for (final other in PlatformType.musicServices.where(
          (value) => value != platform,
        )) {
          expect(failed.songsForPlatform(other).map(videoSongKey), [
            videoSongKey(content[other]!.newSong),
          ]);
        }
        await _walkPage(
          tester,
          mouse,
          binding.trace,
          'R10新歌${platform.name}错误入口',
          owner: newSongs,
        );
        fixture.newSongsFailure = null;
        final calls = fixture.newSongCalls.length;
        await _r10Tap(
          tester,
          binding.trace,
          find.descendant(
            of: newSongs,
            matching: find.text(IkDiscoveryRevisionStrings.retry),
          ),
          'R10新歌${platform.name}实际重试',
        );
        expect(fixture.newSongCalls, hasLength(calls + 1));
        expect(
          app.container.read(newSongsProvider).errorForPlatform(platform),
          isNull,
        );
        expect(
          find.descendant(
            of: newSongs,
            matching: find.text(fixture.newSong.name),
          ),
          findsOneWidget,
        );
        await _walkPage(
          tester,
          mouse,
          binding.trace,
          'R10新歌${platform.name}重试恢复',
          owner: newSongs,
        );
      }
      var regionViews = 0;
      for (final region in newSongRegionLabels.keys) {
        await _r10Tap(
          tester,
          binding.trace,
          _r10Chip(newSongs, newSongRegionLabels[region]!),
          'R10新歌实际选择地区${region.name}',
        );
        expect(app.container.read(newSongsProvider).region, region);
        for (final platform in PlatformType.musicServices) {
          final fixture = content[platform]!;
          await _r10SelectPlatform(
            tester,
            binding.trace,
            newSongs,
            platform,
            '新歌地区${region.name}',
          );
          expect(fixture.newSongCalls.last.region, region);
          final state = app.container.read(newSongsProvider);
          expect(state.errorForPlatform(platform), isNull);
          if (fixture.unsupportedRegions.contains(region)) {
            expect(
              state.noticeForPlatform(platform),
              contains(newSongRegionLabels[region]),
            );
            expect(
              find.byKey(ValueKey('new-songs-notice-${platform.name}')),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: newSongs,
                matching: find.text(IkDiscoveryRevisionStrings.retry),
              ),
              findsNothing,
            );
          } else {
            expect(state.songsForPlatform(platform), hasLength(1));
            expect(
              find.descendant(
                of: newSongs,
                matching: find.text(fixture.newSong.name),
              ),
              findsOneWidget,
            );
          }
          await _walkPage(
            tester,
            mouse,
            binding.trace,
            'R10新歌${platform.name}/${region.name}完整遍历',
            owner: newSongs,
          );
          regionViews++;
        }
      }
      expect(
        regionViews,
        PlatformType.musicServices.length * newSongRegionLabels.length,
      );
      final unsupported = content[PlatformType.kugou]!;
      unsupported.newSongsSupported = false;
      final beforeUnsupported = unsupported.newSongCalls.length;
      await _r10Tap(
        tester,
        binding.trace,
        find.descendant(
          of: newSongs,
          matching: find.byTooltip(IkDiscoveryRevisionStrings.refresh),
        ),
        'R10酷狗能力不支持不能调用新歌API',
      );
      expect(unsupported.newSongCalls, hasLength(beforeUnsupported));
      expect(
        app.container
            .read(newSongsProvider)
            .noticeForPlatform(PlatformType.kugou),
        '${PlatformType.kugou.displayName}暂不支持新歌速递',
      );
      expect(
        app.container
            .read(newSongsProvider)
            .errorForPlatform(PlatformType.kugou),
        isNull,
      );
      expect(
        find.descendant(
          of: newSongs,
          matching: find.text(IkDiscoveryRevisionStrings.retry),
        ),
        findsNothing,
      );
      await _walkPage(
        tester,
        mouse,
        binding.trace,
        'R10新歌能力notice完整遍历',
        owner: newSongs,
      );
      unsupported.newSongsSupported = true;
      await _r10Tap(
        tester,
        binding.trace,
        find.descendant(of: newSongs, matching: find.byType(BackButton)),
        'R10新歌返回真实发现页',
      );
      expect(home.evaluate().single, same(homeElement));

      await _r10Tap(
        tester,
        binding.trace,
        find.descendant(of: home, matching: find.text(IkStrings.toplists)),
        'R10实际进入榜单路由',
      );
      final toplists = find.byType(ToplistsPage);
      expect(tester.widget<ToplistsPage>(toplists).alignToDesign, isTrue);
      for (final platform in PlatformType.musicServices) {
        final fixture = content[platform]!;
        await _r10SelectPlatform(
          tester,
          binding.trace,
          toplists,
          platform,
          '榜单',
        );
        expect(
          find.descendant(
            of: toplists,
            matching: find.text(fixture.toplist.name),
          ),
          findsOneWidget,
        );
        await _walkPage(
          tester,
          mouse,
          binding.trace,
          'R10榜单${platform.name}成功',
          owner: toplists,
        );
        fixture.toplistsFailure = 'R10${platform.name}榜单网络失败';
        await _r10Tap(
          tester,
          binding.trace,
          find.descendant(
            of: toplists,
            matching: find.byTooltip(IkDiscoveryRevisionStrings.refresh),
          ),
          'R10榜单${platform.name}单来源失败并保留旧行',
        );
        final failed = app.container.read(toplistsProvider);
        expect(
          failed.errorForPlatform(platform),
          contains(fixture.toplistsFailure),
        );
        expect(failed.isOffline(platform), isTrue);
        expect(
          find.descendant(
            of: toplists,
            matching: find.textContaining(fixture.toplistsFailure!),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: toplists, matching: find.text('离线缓存')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: toplists,
            matching: find.text(fixture.toplist.name),
          ),
          findsOneWidget,
        );
        for (final other in PlatformType.musicServices.where(
          (value) => value != platform,
        )) {
          expect(failed.toplistsForPlatform(other).map((item) => item.id), [
            content[other]!.toplist.id,
          ]);
        }
        await _walkPage(
          tester,
          mouse,
          binding.trace,
          'R10榜单${platform.name}错误入口',
          owner: toplists,
        );
        fixture.toplistsFailure = null;
        final calls = fixture.toplistLoads;
        await _r10Tap(
          tester,
          binding.trace,
          find.descendant(
            of: toplists,
            matching: find.text(IkDiscoveryRevisionStrings.retry),
          ),
          'R10榜单${platform.name}实际重试',
        );
        expect(fixture.toplistLoads, calls + 1);
        expect(
          app.container.read(toplistsProvider).errorForPlatform(platform),
          isNull,
        );
        expect(
          app.container.read(toplistsProvider).isOffline(platform),
          isFalse,
        );
        await _walkPage(
          tester,
          mouse,
          binding.trace,
          'R10榜单${platform.name}重试恢复',
          owner: toplists,
        );
      }
      await _r10Tap(
        tester,
        binding.trace,
        find.descendant(of: toplists, matching: find.byType(BackButton)),
        'R10榜单返回真实发现页',
      );
      expect(home.evaluate().single, same(homeElement));

      await _r10Tap(
        tester,
        binding.trace,
        find.descendant(of: home, matching: find.text(IkStrings.browse)),
        'R10实际进入推荐路由',
      );
      final recommendations = find.byType(RecommendationsPage);
      expect(
        tester.widget<RecommendationsPage>(recommendations).alignToDesign,
        isTrue,
      );
      for (final platform in PlatformType.musicServices) {
        final fixture = content[platform]!;
        await _r10SelectPlatform(
          tester,
          binding.trace,
          recommendations,
          platform,
          '推荐',
        );
        expect(
          find.descendant(
            of: recommendations,
            matching: find.text(fixture.recommendedSong.name),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: recommendations,
            matching: find.text(
              IkDiscoveryRevisionStrings.sourceLabel(
                fixture.source,
                platform: platform,
                loggedIn: false,
              ),
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: recommendations,
            matching: find.text(IkDiscoveryRevisionStrings.dailyRecommendation),
          ),
          findsNothing,
        );
        await _walkPage(
          tester,
          mouse,
          binding.trace,
          'R10推荐${platform.name}成功且来源可读',
          owner: recommendations,
        );
        await _r10CancelSongMenu(
          tester,
          mouse,
          binding.trace,
          app,
          find.descendant(
            of: recommendations,
            matching: find.byType(IkSongTableRow),
          ),
          'R10推荐${platform.name}更多取消',
          contextual: true,
        );
        fixture.recommendationFailure = 'R10${platform.name}推荐网络失败';
        await _r10Tap(
          tester,
          binding.trace,
          find.descendant(
            of: recommendations,
            matching: find.byTooltip(IkDiscoveryRevisionStrings.refresh),
          ),
          'R10推荐${platform.name}单来源失败',
        );
        final failed = app.container.read(recommendationsProvider);
        expect(
          failed.errorsByPlatform[platform],
          fixture.recommendationFailure,
        );
        expect(
          find.descendant(
            of: recommendations,
            matching: find.text(fixture.recommendationFailure!),
          ),
          findsOneWidget,
        );
        for (final other in PlatformType.musicServices.where(
          (value) => value != platform,
        )) {
          expect(failed.songsForPlatform(other).map(videoSongKey), [
            videoSongKey(content[other]!.recommendedSong),
          ]);
        }
        await _walkPage(
          tester,
          mouse,
          binding.trace,
          'R10推荐${platform.name}错误入口',
          owner: recommendations,
        );
        fixture.recommendationFailure = null;
        final calls = fixture.recommendationLoads;
        await _r10Tap(
          tester,
          binding.trace,
          find.descendant(
            of: recommendations,
            matching: find.text(IkDiscoveryRevisionStrings.retry),
          ),
          'R10推荐${platform.name}实际重试',
        );
        expect(fixture.recommendationLoads, calls + 1);
        expect(
          app.container
              .read(recommendationsProvider)
              .errorsByPlatform[platform],
          isNull,
        );
        expect(
          find.descendant(
            of: recommendations,
            matching: find.text(fixture.recommendedSong.name),
          ),
          findsOneWidget,
        );
        await _walkPage(
          tester,
          mouse,
          binding.trace,
          'R10推荐${platform.name}重试恢复',
          owner: recommendations,
        );
      }
      await _r10Tap(
        tester,
        binding.trace,
        find.descendant(of: recommendations, matching: find.byType(BackButton)),
        'R10推荐返回真实发现页',
      );
      expect(home.evaluate().single, same(homeElement));
      binding.trace.expectValid();

      await _r10Tap(
        tester,
        binding.trace,
        find.byKey(const ValueKey('ik-workspace-nav-1')),
        'R10进入共享搜索空态',
      );
      final searchPage = find.byType(IkSearchWorkspace);
      final search = tester.widget<IkSearchWorkspace>(searchPage).search;
      expect(search.query, isEmpty);
      for (final term in app.catalog.hotTerms) {
        expect(
          find.descendant(
            of: searchPage,
            matching: find.widgetWithText(ActionChip, term),
          ),
          findsOneWidget,
        );
      }
      await _walkPage(
        tester,
        mouse,
        binding.trace,
        'R10共享搜索空态全部热词和推荐',
        owner: searchPage,
      );
      await _r10Tap(
        tester,
        binding.trace,
        find.descendant(
          of: searchPage,
          matching: find.widgetWithText(ActionChip, app.catalog.hotTerms.first),
        ),
        'R10实际点击热词进入搜索结果',
      );
      expect(search.query, app.catalog.hotTerms.first);
      for (final platform in PlatformType.musicServices) {
        expect(search.groups[platform]!.songs, hasLength(3));
        expect(
          app.catalog.calls.where(
            (call) => call.platform == platform && call.query == search.query,
          ),
          hasLength(1),
        );
      }
      await _walkPage(
        tester,
        mouse,
        binding.trace,
        'R10共享搜索全部来源与结果行',
        owner: searchPage,
      );
      final chosen = search.groups[PlatformType.qq]!.songs[1];
      final chosenRow = find.descendant(
        of: searchPage,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is IkSongTableRow &&
              videoSongKey(widget.song) == videoSongKey(chosen),
        ),
      );
      await _r10CancelSongMenu(
        tester,
        mouse,
        binding.trace,
        app,
        chosenRow,
        'R10搜索结果更多取消',
      );
      _r10ScrollObservation(
        tester,
        binding.trace,
        '行ensure之前',
        searchPage,
        chosenRow,
        chosen.name,
      );
      await tester.ensureVisible(chosenRow);
      _r10ScrollObservation(
        tester,
        binding.trace,
        '行ensure之后',
        searchPage,
        chosenRow,
        chosen.name,
      );
      await _rootDrain(tester, binding.trace);
      final searchElement = searchPage.evaluate().single;
      final searchScroll = tester.state<ScrollableState>(
        _verticalScrolls(searchPage).single,
      );
      var searchPixels = searchScroll.position.pixels;
      void observeSearch(String phase) => _r10ScrollObservation(
        tester,
        binding.trace,
        phase,
        searchPage,
        chosenRow,
        chosen.name,
        capturedPage: searchElement,
        capturedScroll: searchScroll,
        baseline: searchPixels,
      );

      observeSearch('行drain之后原baseline');
      final sharedText = tester
          .widget<TextField>(find.byKey(const ValueKey('ik-workspace-search')))
          .controller!
          .text;
      await _r10Tap(
        tester,
        binding.trace,
        find.descendant(of: chosenRow, matching: find.text(chosen.name)),
        'R10实际点击结果行播放并进入详情prepare',
        onPhase: observeSearch,
        beforeTap: () => searchPixels = searchScroll.position.pixels,
      );
      observeSearch('播放prepare已进入详情');
      final playerPage = find.byType(WindowsPlayerPage);
      expect(playerPage, findsOneWidget);
      final progress = find.byKey(const ValueKey('ik-bar-seek'));
      expect(app.container.read(playerProvider).currentSong, chosen);
      expect(
        app.container.read(playerProvider).playlist.map(videoSongKey),
        search.groups[PlatformType.qq]!.songs.map(videoSongKey),
      );
      expect(tester.widget<Slider>(progress).onChanged, isNull);
      expect(
        _sliderSemantics(
          tester,
          progress,
        ).getSemanticsData().hasAction(SemanticsAction.increase),
        isFalse,
      );
      binding.trace.step = 'R10真实播放器音频时长到达ready';
      (app.container.read(playerProvider.notifier) as _Player).reportDuration(
        const Duration(minutes: 3),
      );
      await _rootDrain(tester, binding.trace);
      observeSearch('音频时长ready之后');
      expect(tester.widget<Slider>(progress).onChanged, isNotNull);
      expect(tester.widget<Slider>(progress).max, 180000);
      expect(
        _sliderSemantics(
          tester,
          progress,
        ).getSemanticsData().hasAction(SemanticsAction.increase),
        isTrue,
      );
      expect(
        _sliderSemantics(
          tester,
          progress,
        ).getSemanticsData().hasAction(SemanticsAction.decrease),
        isTrue,
      );
      await _walkPage(
        tester,
        mouse,
        binding.trace,
        'R10实际播放详情全部滚动区与提示',
        owner: playerPage,
      );
      await _r10Tap(
        tester,
        binding.trace,
        find.descendant(
          of: playerPage,
          matching: find.text(WindowsMusicStrings.back),
        ),
        'R10播放详情实际返回搜索',
      );
      observeSearch('详情实际返回之后');
      expect(searchPage.evaluate().single, same(searchElement));
      expect(
        tester.state<ScrollableState>(_verticalScrolls(searchPage).single),
        same(searchScroll),
      );
      expect(searchScroll.position.pixels, closeTo(searchPixels, .001));
      expect(search.query, app.catalog.hotTerms.first);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('ik-workspace-search')),
            )
            .controller!
            .text,
        sharedText,
      );
      await _r10Tap(
        tester,
        binding.trace,
        find.descendant(
          of: find.byType(IkPlaybackBar),
          matching: find.text(chosen.name),
        ),
        'R10实际点击播放栏歌曲名再次进入详情',
      );
      expect(playerPage, findsOneWidget);
      await _walkPage(
        tester,
        mouse,
        binding.trace,
        'R10播放栏进入详情完整遍历',
        owner: playerPage,
      );
      await _r10Tap(
        tester,
        binding.trace,
        find.descendant(
          of: playerPage,
          matching: find.text(WindowsMusicStrings.back),
        ),
        'R10播放栏详情实际返回搜索',
      );
      expect(searchPage.evaluate().single, same(searchElement));
      expect(searchScroll.position.pixels, closeTo(searchPixels, .001));
      binding.trace.expectValid();

      await _r10Tap(
        tester,
        binding.trace,
        find.byKey(const ValueKey('ik-workspace-nav-4')),
        'R10进入真实设置',
      );
      await _r10Tap(
        tester,
        binding.trace,
        find.byKey(const ValueKey('ik-settings-lyrics')),
        'R10进入桌面歌词设置区',
      );
      final lyricsToggle = find.byKey(const ValueKey('ik-workspace-lyrics'));
      expect(tester.widget<Switch>(lyricsToggle).value, isFalse);
      lyricsCalls.clear();
      for (final enabled in [true, false]) {
        final calls = lyricsCalls.length;
        await _r10Tap(
          tester,
          binding.trace,
          lyricsToggle,
          'R10实际${enabled ? '开启' : '关闭'}桌面歌词并落盘',
        );
        expect(tester.widget<Switch>(lyricsToggle).value, enabled);
        expect(app.container.read(floatingLyricsProvider).enabled, enabled);
        expect(app.container.read(ikLyricsActionProvider), isFalse);
        expect(app.container.read(ikLyricsIssueProvider), isNull);
        expect(
          FloatingLyricsSettings.fromJson(
            settings.get('floating_lyrics_settings'),
          ).enabled,
          enabled,
        );
        final actions = lyricsCalls
            .skip(calls)
            .where((call) => call.method == (enabled ? 'show' : 'hide'));
        expect(actions, isNotEmpty);
        if (enabled) {
          expect((actions.first.arguments as Map)['enabled'], isTrue);
        }
        await _walkPage(
          tester,
          mouse,
          binding.trace,
          'R10桌面歌词${enabled ? '开' : '关'}完整设置区',
          owner: find.byType(IkSettingsWorkspace),
        );
      }
      await _r10Tap(
        tester,
        binding.trace,
        find.byKey(const ValueKey('ik-workspace-nav-2')),
        'R10最终返回音乐库核验五类状态',
      );
      for (final entry in retained.entries) {
        expect(
          find
              .byKey(
                ValueKey('ik-library-content-${entry.key}'),
                skipOffstage: false,
              )
              .evaluate()
              .single,
          same(entry.value),
        );
      }
      expect(app.container.read(likesProvider).songs, hasLength(1));
      expect(
        app.container
            .read(myPlaylistsProvider)
            .playlists
            .map((playlist) => playlist.id),
        [seedPlaylist.id],
      );
      expect(
        await tester.runAsync(
          () => app.container
              .read(myPlaylistsProvider.notifier)
              .getSongs(seedPlaylist.id),
        ),
        hasLength(1),
      );
      expect(app.container.read(downloadProvider).tasks, isEmpty);
      debugPrint(
        'IK_SEMANTICS R10完整执行5音乐库分类、9发现平台成功/失败/重试、$regionViews地区平台视图、能力notice、8歌曲菜单取消、创建与导出取消、2播放详情往返及2次歌词开关',
      );
      binding.trace.expectValid();
    } finally {
      handle.dispose();
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      app.container.dispose();
      app.appearance.dispose();
      app.unified.dispose();
      await tester.pump();
    }
  });
}

Future<void> _r10Tap(
  WidgetTester tester,
  _TreeTrace trace,
  Finder target,
  String stage, {
  void Function(String)? onPhase,
  VoidCallback? beforeTap,
}) async {
  trace.step = stage;
  expect(target, findsOneWidget, reason: stage);
  onPhase?.call('点击目标ensure之前');
  await tester.ensureVisible(target);
  onPhase?.call('点击目标ensure之后');
  await _pumpAndCheck(tester, trace);
  beforeTap?.call();
  onPhase?.call('点击目标pump之后实际tap之前');
  await tester.tap(target.hitTestable());
  onPhase?.call('实际tap之后');
  await _rootDrain(tester, trace);
  onPhase?.call('实际tap的drain之后');
}

void _r10ScrollObservation(
  WidgetTester tester,
  _TreeTrace trace,
  String phase,
  Finder page,
  Finder row,
  String songName, {
  Element? capturedPage,
  ScrollableState? capturedScroll,
  double? baseline,
}) {
  if (!trace._recordEnabled) return;
  final pageElement = capturedPage ?? page.evaluate().single;
  final scroll =
      capturedScroll ??
      tester.state<ScrollableState>(_verticalScrolls(page).single);
  final target = find.descendant(of: row, matching: find.text(songName));
  Map<String, Object?> geometry(Element element) {
    final render = element.findRenderObject();
    final ancestors = <Map<String, Object?>>[];
    element.visitAncestorElements((ancestor) {
      ancestors.add({
        'element': identityHashCode(ancestor),
        'widget': ancestor.widget.runtimeType.toString(),
      });
      return true;
    });
    return {
      'element': identityHashCode(element),
      'widget': element.widget.runtimeType.toString(),
      'mounted': element.mounted,
      'ancestors': ancestors,
      'nearestScroll': Scrollable.maybeOf(element) == null
          ? null
          : identityHashCode(Scrollable.maybeOf(element)!),
      'render': render == null ? null : identityHashCode(render),
      'renderType': render?.runtimeType.toString(),
      'attached': render?.attached,
      if (render is RenderBox && render.hasSize) ...{
        'size': [render.size.width, render.size.height],
        'globalOrigin': [
          render.localToGlobal(Offset.zero).dx,
          render.localToGlobal(Offset.zero).dy,
        ],
      },
    };
  }

  trace._record({
    'kind': 'r10-scroll',
    'phase': phase,
    'baseline': baseline,
    'pixels': scroll.position.pixels,
    'minScrollExtent': scroll.position.minScrollExtent,
    'maxScrollExtent': scroll.position.maxScrollExtent,
    'viewportDimension': scroll.position.viewportDimension,
    'page': geometry(pageElement),
    'scrollState': identityHashCode(scroll),
    'scrollContext': geometry(scroll.context as Element),
    'row': [for (final element in row.evaluate()) geometry(element)],
    'target': [for (final element in target.evaluate()) geometry(element)],
  });
}

Finder _r10Chip(Finder owner, String label) => find.descendant(
  of: owner,
  matching: find.widgetWithText(ChoiceChip, label),
);

Future<void> _r10SelectPlatform(
  WidgetTester tester,
  _TreeTrace trace,
  Finder owner,
  PlatformType platform,
  String page,
) async {
  await _r10Tap(
    tester,
    trace,
    _r10Chip(owner, platform.displayName),
    'R10$page实际切换${platform.name}',
  );
  for (final type in PlatformType.musicServices) {
    final chip = _r10Chip(owner, type.displayName);
    expect(chip.hitTestable(), findsOneWidget);
    expect(tester.widget<ChoiceChip>(chip).selected, type == platform);
    expect(
      tester.getSemantics(chip).getSemanticsData().flagsCollection.isSelected,
      type == platform ? Tristate.isTrue : Tristate.isFalse,
    );
  }
}

Future<Map<String, Object?>> _r10Snapshot(
  WidgetTester tester,
  _RootHarness app,
) async {
  return (await tester.runAsync<Map<String, Object?>>(() async {
    final myPlaylists = app.container.read(myPlaylistsProvider);
    final player = app.container.read(playerProvider);
    final search = tester
        .widget<IkSearchWorkspace>(
          find.byType(IkSearchWorkspace, skipOffstage: false),
        )
        .search;
    return {
      'songs': [
        for (final row
            in await app.db
                .customSelect('SELECT * FROM songs ORDER BY platform, id')
                .get())
          row.data,
      ],
      'likes': [
        for (final row
            in await app.db
                .customSelect('SELECT * FROM user_likes ORDER BY id')
                .get())
          row.data,
      ],
      'localLikes': app.container
          .read(likesProvider)
          .songs
          .map(videoSongKey)
          .toList(),
      'playlists': [
        for (final playlist in myPlaylists.playlists)
          {
            'id': playlist.id,
            'name': playlist.name,
            'songs':
                (await app.container
                        .read(myPlaylistsProvider.notifier)
                        .getSongs(playlist.id))
                    .map(videoSongKey)
                    .toList(),
          },
      ],
      'downloads': app.container
          .read(downloadProvider)
          .tasks
          .map((task) => task.toJson())
          .toList(),
      'player': {
        'song': player.currentSong == null
            ? null
            : videoSongKey(player.currentSong!),
        'playlist': player.playlist.map(videoSongKey).toList(),
        'index': player.currentIndex,
        'position': player.position.inMilliseconds,
        'duration': player.duration.inMilliseconds,
        'playing': player.isPlaying,
      },
      'search': {
        'query': search.query,
        'groups': {
          for (final entry in search.groups.entries)
            entry.key.name: entry.value.songs.map(videoSongKey).toList(),
        },
      },
    };
  }))!;
}

Future<void> _r10CancelSongMenu(
  WidgetTester tester,
  TestGesture mouse,
  _TreeTrace trace,
  _RootHarness app,
  Finder row,
  String stage, {
  bool contextual = false,
}) async {
  final more = find.descendant(
    of: row,
    matching: find.byTooltip(IkStrings.more),
  );
  await tester.ensureVisible(more);
  await _rootDrain(tester, trace);
  final before = await _r10Snapshot(tester, app);
  await _r10Tap(tester, trace, more, '$stage：实际打开更多');
  final items = contextual
      ? find.byType(PopupMenuItem<SongAction>)
      : find.byType(PopupMenuItem<String>);
  expect(items, findsWidgets);
  await _allTooltips(tester, mouse, trace, '$stage：菜单已显示');
  trace.step = '$stage：实际按Escape取消';
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await _rootDrain(tester, trace);
  expect(items, findsNothing);
  expect(
    await _r10Snapshot(tester, app),
    equals(before),
    reason: '$stage不能改歌曲、喜欢、歌单、下载、播放器或查询',
  );
}

void _testWindows(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    PlatformUtils.setDebugOverride(AppPlatform.windows);
    var completed = false;
    try {
      await body(tester);
      completed = true;
    } finally {
      (TestWidgetsFlutterBinding.instance as _SemanticsBinding).trace
          .finishDiagnostics(completed: completed);
      // Flutter在test body返回时验不变量，tearDown清理平台变量已太迟。
      debugDefaultTargetPlatformOverride = null;
      PlatformUtils.setDebugOverride(null);
    }
  }, semanticsEnabled: false);
}

Future<void> _size(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 960);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _hover(
  WidgetTester tester,
  TestGesture mouse,
  Finder target,
  _TreeTrace trace,
) async {
  await mouse.moveTo(tester.getCenter(target));
  await _pumpAndCheck(tester, trace, const Duration(seconds: 1));
  await _pumpAndCheck(tester, trace, const Duration(milliseconds: 250));
}

Future<void> _leave(
  WidgetTester tester,
  TestGesture mouse,
  _TreeTrace trace,
) async {
  await mouse.moveTo(const Offset(1190, 1));
  await _pumpAndCheck(tester, trace, const Duration(seconds: 2));
  await _pumpAndCheck(tester, trace, const Duration(milliseconds: 250));
}

Future<void> _pumpAndCheck(
  WidgetTester tester,
  _TreeTrace trace, [
  Duration duration = Duration.zero,
]) async {
  final pumpId = trace.beginPump();
  final rawStart = trace.batches.length;
  final axStart = trace.ax.commits;
  Object? frameworkError, thrown;
  var completed = false;
  try {
    await tester.pump(duration);
    final error = tester.takeException();
    frameworkError = error;
    if (error != null) trace.dump('框架异常：$error');
    expect(error, isNull, reason: trace.step);
    expect(trace.issues, isEmpty, reason: trace.issues.firstOrNull);
    completed = true;
  } catch (error) {
    thrown = error;
    rethrow;
  } finally {
    trace.recordPump(
      pumpId,
      rawStart: rawStart,
      axStart: axStart,
      duration: duration,
      completed: completed,
      frameworkError: frameworkError,
      thrown: thrown,
    );
  }
}

Future<void> _rootDrain(WidgetTester tester, _TreeTrace trace) async {
  for (var turn = 0; turn < 3; turn++) {
    await _pumpAndCheck(tester, trace, const Duration(milliseconds: 400));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
  }
  await _pumpAndCheck(tester, trace, const Duration(milliseconds: 400));
  await _pumpAndCheck(tester, trace);
}

Future<void> _axFrames(
  WidgetTester tester,
  _TreeTrace trace,
  String stage,
  int count,
) async {
  trace.step = stage;
  for (var frame = 0; frame < count; frame++) {
    await _pumpAndCheck(tester, trace, const Duration(milliseconds: 16));
  }
}

Future<void> _axMouseHover(
  WidgetTester tester,
  TestGesture mouse,
  _TreeTrace trace,
  Finder target,
  String stage,
) async {
  expect(target.hitTestable(), findsOneWidget);
  await mouse.moveTo(tester.getCenter(target.hitTestable()));
  await _axFrames(tester, trace, '$stage 鼠标移入并显示提示', 70);
}

Future<void> _axMouseClick(
  WidgetTester tester,
  TestGesture mouse,
  _TreeTrace trace,
  Finder target,
  String stage, {
  bool leave = true,
}) async {
  await _axMouseHover(tester, mouse, trace, target, stage);
  await mouse.down(tester.getCenter(target.hitTestable()));
  await _axFrames(tester, trace, '$stage 鼠标按下', 1);
  await mouse.up();
  await _axFrames(tester, trace, '$stage 鼠标释放与页面切换', 24);
  if (leave) {
    await mouse.moveTo(const Offset(1918, 1));
    await _axFrames(tester, trace, '$stage 鼠标离开与提示退场', 40);
  }
  trace.expectValid();
}

Future<void> _allTooltips(
  WidgetTester tester,
  TestGesture mouse,
  _TreeTrace trace,
  String stage,
) async {
  final count = find.byType(Tooltip).hitTestable().evaluate().length;
  for (var index = 0; index < count; index++) {
    final target = find.byType(Tooltip).hitTestable().at(index);
    final tooltip = tester.widget<Tooltip>(target);
    trace.step = '$stage 悬停Tooltip$index ${tooltip.message}';
    await _hover(tester, mouse, target, trace);
    trace.step = '$stage 移除Tooltip$index ${tooltip.message}';
    await _leave(tester, mouse, trace);
  }
  debugPrint('IK_SEMANTICS $stage 完整悬停当前$count个Tooltip');
}

Future<void> _walkPage(
  WidgetTester tester,
  TestGesture mouse,
  _TreeTrace trace,
  String stage, {
  Finder? owner,
}) async {
  final scrolls = find
      .descendant(
        of: owner ?? find.byType(IndexedStack),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
        ),
      )
      .hitTestable();
  final count = scrolls.evaluate().length;
  if (count == 0) {
    await _allTooltips(tester, mouse, trace, stage);
    return;
  }
  for (var index = 0; index < count; index++) {
    var positions = 0;
    while (true) {
      await _allTooltips(tester, mouse, trace, '$stage 滚动区$index/位置$positions');
      final scroll = scrolls.at(index);
      final position = tester.state<ScrollableState>(scroll).position;
      if (position.pixels >= position.maxScrollExtent) break;
      final previous = position.pixels;
      trace.step = '$stage 滚动区$index向下遍历';
      await tester.drag(scroll, const Offset(0, -320));
      await _rootDrain(tester, trace);
      expect(position.pixels, greaterThan(previous), reason: '$stage 滚动必须推进');
      positions++;
    }
    debugPrint('IK_SEMANTICS $stage 滚动区$index已走到真实底部，${positions + 1}个位置');
    final position = tester.state<ScrollableState>(scrolls.at(index)).position;
    if (position.pixels != position.minScrollExtent) {
      trace.step = '$stage 回到页首以操作头部控件';
      position.jumpTo(position.minScrollExtent);
      await _rootDrain(tester, trace);
    }
  }
}

List<Finder> _verticalScrolls(Finder owner) {
  final found = find
      .descendant(
        of: owner,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
        ),
      )
      .hitTestable();
  return [
    for (var index = 0; index < found.evaluate().length; index++)
      found.at(index),
  ];
}

Future<void> _operateSettingsSliders(
  WidgetTester tester,
  TestGesture mouse,
  _TreeTrace trace,
  _RootHarness app,
) async {
  final page = find.byType(IkSettingsWorkspace);
  final spatial = find.descendant(
    of: find.byKey(const ValueKey('ik-spatial-emphasis')),
    matching: find.byType(Switch),
  );
  await tester.ensureVisible(spatial);
  await _pumpAndCheck(tester, trace);
  trace.step = '实际音频设置开启3D以启用空间强度滑块';
  await tester.tap(spatial);
  await _rootDrain(tester, trace);
  expect(app.container.read(ikSpatialRuntimeProvider).desired.enabled, isTrue);
  final equalizer = find.descendant(
    of: find.byWidgetPredicate(
      (widget) => widget is IkSettingRow && widget.title == IkStrings.equalizer,
    ),
    matching: find.byType(Switch),
  );
  await tester.ensureVisible(equalizer);
  await _pumpAndCheck(tester, trace);
  trace.step = '实际音频设置开启均衡器以启用五频段滑块';
  await tester.tap(equalizer);
  await _rootDrain(tester, trace);
  expect(
    app.container.read(audioEffectsSettingsProvider).equalizerEnabled,
    isTrue,
  );
  final sliders = find.descendant(of: page, matching: find.byType(Slider));
  expect(sliders, findsNWidgets(7));
  for (var index = 0; index < 7; index++) {
    final current = sliders.at(index);
    await tester.ensureVisible(current);
    await _rootDrain(tester, trace);
    final before = tester.widget<Slider>(current);
    expect(before.onChanged, isNotNull, reason: '第$index个设置滑块应可用');
    final data = _sliderSemantics(tester, current).getSemanticsData();
    expect(
      data.hasAction(SemanticsAction.increase),
      isTrue,
      reason: '第$index个设置滑块子节点应可增加',
    );
    expect(
      data.hasAction(SemanticsAction.decrease),
      isTrue,
      reason: '第$index个设置滑块子节点应可减少',
    );
    trace.step = '实际操作设置滑块$index ${before.label}';
    final vertical = find
        .ancestor(of: current, matching: find.byType(RotatedBox))
        .evaluate()
        .isNotEmpty;
    await tester.drag(
      current,
      vertical ? const Offset(0, -24) : const Offset(30, 0),
    );
    await _rootDrain(tester, trace);
    final after = tester.widget<Slider>(current);
    expect(
      after.value,
      isNot(equals(before.value)),
      reason: '第$index个滑块拖动必须反馈实际值',
    );
    if (index == 0) {
      expect(
        app.container.read(ikSpatialRuntimeProvider).desired.strength,
        closeTo(after.value, .001),
      );
    } else if (index == 1) {
      expect(
        app.container
            .read(audioEffectsSettingsProvider)
            .fadeDuration
            .inMilliseconds,
        after.value.round(),
      );
    } else {
      expect(
        app.container
            .read(audioEffectsSettingsProvider)
            .effectiveEqualizerBandGains[index - 2],
        closeTo(after.value, .001),
      );
    }
    debugPrint(
      'IK_SEMANTICS 设置滑块$index实值${before.value}→${after.value}，'
      '可增加/减少且对应provider值一致',
    );
    await _allTooltips(tester, mouse, trace, '实际设置滑块$index操作后');
  }
  trace.step = '操作设置滑块后切回发现：隐藏滑块不遗留孤点';
  await tester.tap(find.byKey(const ValueKey('ik-workspace-nav-0')));
  await _rootDrain(tester, trace);
  trace.expectValid();
  await tester.tap(find.byKey(const ValueKey('ik-workspace-nav-4')));
  await _rootDrain(tester, trace);
}

SemanticsNode _sliderSemantics(WidgetTester tester, Finder slider) {
  final sliders = <SemanticsNode>[];
  void collect(SemanticsNode node) {
    if (node.getSemanticsData().flagsCollection.isSlider) sliders.add(node);
    node.visitChildren((child) {
      collect(child);
      return true;
    });
  }

  // Slider外层的焦点/浮层标记也是语义节点；动作属于本控件的Slider子节点。
  collect(tester.getSemantics(slider));
  expect(sliders, hasLength(1), reason: '本Slider子树应只有一个可动作滑块');
  return sliders.single;
}

Future<void> _operateLyricsSlider(
  WidgetTester tester,
  TestGesture mouse,
  _TreeTrace trace,
) async {
  final slider = find.byKey(const ValueKey('ik-player-lyrics-size'));
  expect(slider, findsOneWidget);
  await tester.ensureVisible(slider);
  await _rootDrain(tester, trace);
  final tooltip = find.ancestor(of: slider, matching: find.byType(Tooltip));
  expect(tooltip, findsOneWidget);
  final before = tester.widget<Slider>(slider);
  final data = _sliderSemantics(tester, slider).getSemanticsData();
  expect(data.hasAction(SemanticsAction.increase), isTrue);
  expect(data.hasAction(SemanticsAction.decrease), isTrue);
  final tooltipSemantics = find.descendant(
    of: tooltip,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.tooltip == IkPlayerAlignmentStrings.lyricsSize,
    ),
  );
  expect(tooltipSemantics, findsOneWidget);
  // Tooltip根RenderObject是OverlayPortal；直接读它会上溯到空的路由容器。
  expect(
    tester.getSemantics(tooltipSemantics).getSemanticsData().tooltip,
    IkPlayerAlignmentStrings.lyricsSize,
  );
  trace.step = '实际歌词字号Tooltip悬停：两组Portal语义锚点均保留';
  await _hover(tester, mouse, slider, trace);
  trace.expectValid();
  trace.step = '实际歌词字号滑块拖动并反馈到显示字号';
  await tester.drag(slider, const Offset(30, 0));
  await _rootDrain(tester, trace);
  final after = tester.widget<Slider>(slider);
  expect(after.value, isNot(equals(before.value)));
  final displayedLyric = find.descendant(
    of: find.byKey(const ValueKey('windows-lyrics-scroll')),
    matching: find.text('语义验收歌词'),
  );
  expect(displayedLyric, findsOneWidget);
  expect(
    tester.widget<Text>(displayedLyric).style!.fontSize,
    closeTo(after.value, .001),
  );
  expect(
    _sliderSemantics(tester, slider).getSemanticsData().value,
    '${IkPlayerAlignmentStrings.lyricsSize} ${after.value.round()}',
  );
  await _leave(tester, mouse, trace);
  debugPrint(
    'IK_SEMANTICS 歌词字号实值${before.value}→${after.value}，'
    '可增加/减少、Tooltip可读且歌词显示字号一致',
  );
  trace.expectValid();
}

void _dumpMarkers(WidgetTester tester, _TreeTrace trace) {
  final markers = <Map<String, Object?>>[];
  for (final element
      in find.byType(Semantics, skipOffstage: false).evaluate()) {
    final widget = element.widget as Semantics;
    final parent = widget.properties.traversalParentIdentifier;
    final child = widget.properties.traversalChildIdentifier;
    if (parent == null && child == null) continue;
    final ancestors = <String>[];
    element.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      ancestors.add(switch (widget) {
        Tooltip() => 'Tooltip(${widget.message})',
        Slider() =>
          'Slider(key=${widget.key},label=${widget.label},'
              'value=${widget.value},min=${widget.min},max=${widget.max},'
              'enabled=${widget.onChanged != null})',
        IkSettingRow() => 'IkSettingRow(${widget.title})',
        Semantics() => 'Semantics(label=${widget.properties.label})',
        _ => widget.runtimeType.toString(),
      });
      return widget is! VideoMusicApp;
    });
    final node = element.renderObject?.debugSemantics;
    markers.add({
      'widgetParentIdentity': parent == null ? null : identityHashCode(parent),
      'widgetChildIdentity': child == null ? null : identityHashCode(child),
      'ownNode': node?.id,
      'ownParentIdentity': node?.traversalParentIdentifier == null
          ? null
          : identityHashCode(node!.traversalParentIdentifier!),
      'ownChildIdentity': node?.traversalChildIdentifier == null
          ? null
          : identityHashCode(node!.traversalChildIdentifier!),
      'ancestors': ancestors,
    });
  }
  debugPrint(
    'IK_SEMANTICS_MARKERS ${jsonEncode({'step': trace.step, 'batch': trace.batches.length, 'markers': markers})}',
  );
}

class _RootHarness {
  const _RootHarness(
    this.container,
    this.recommendations,
    this.catalog,
    this.unified,
    this.appearance,
    this.db,
  );
  final ProviderContainer container;
  final _Recommendations recommendations;
  final _Catalog catalog;
  final WindowsMusicPreferences unified;
  final WindowsAppearance appearance;
  final AppDatabase db;
}

class _Window extends WindowsWindowController {
  const _Window();
  @override
  Future<void> setCloseAction(WindowsCloseAction action) async {}
  @override
  Future<List<String>> listFonts() async => ['Microsoft YaHei UI'];
}

class _Auth extends AuthNotifier {
  @override
  Future<void> init() async {}
}

class _UnusedSourceEngine extends Fake implements LxSourceEngine {}

class _E16Content extends FakeContentPlatform {
  _E16Content()
    : super(
        type: PlatformType.qq,
        album: _track.album,
        albumSongs: const [_track],
      );
  @override
  Future<String?> getLyrics(String songId) async =>
      '[00:00.00]E16连续路由歌词\n[00:30.00]E16当前播放歌词';
}

class _Content extends FakeContentPlatform {
  _Content(PlatformType platform, {String? lyrics})
    : _lyrics = lyrics ?? '[00:00.00]语义验收歌词\n[00:10.00]语义验收下一句',
      super(type: platform);
  final String _lyrics;
  @override
  Future<String?> getLyrics(String songId) async => _lyrics;
}

class _R10Content extends _Content {
  _R10Content(super.platform, {this.unsupportedRegions = const {}});
  final Set<NewSongRegion> unsupportedRegions;
  bool newSongsSupported = true;
  String? newSongsFailure, toplistsFailure, recommendationFailure;
  int toplistLoads = 0, recommendationLoads = 0;

  Song _song(String kind, String label) => Song(
    id: 'r10-${type.name}-$kind',
    name: 'R10${type.displayName}$label',
    platform: type,
    artists: _track.artists,
    album: _track.album,
    albumId: _track.albumId,
  );
  Song get newSong => _song('new', '新歌');
  Song get recommendedSong => _song('recommended', '推荐歌曲');
  Toplist get toplist => Toplist(
    id: type == PlatformType.qq ? qqHotToplistId : 'r10-${type.name}-chart',
    name: 'R10${type.displayName}榜单',
    songCount: 1,
  );
  RecommendationSource get source => RecommendationSource(
    platform: type,
    kind: switch (type) {
      PlatformType.netease => RecommendationKind.personalizedDaily,
      PlatformType.qq => RecommendationKind.fallbackToplist,
      _ => RecommendationKind.fallbackHomepage,
    },
    label: '${type.displayName}推荐',
    note: type == PlatformType.qq ? '未登录，来源为热歌榜' : '本门按平台返回实际来源',
  );

  @override
  bool get supportsNewSongs => newSongsSupported;
  @override
  bool get supportsDailyRecommendations => true;
  @override
  Future<List<Song>> getNewSongs({
    int limit = 100,
    NewSongRegion region = NewSongRegion.all,
  }) async {
    newSongCalls.add((limit: limit, region: region));
    if (newSongsFailure != null) {
      throw ApiException(message: newSongsFailure!, code: ApiErrorCode.network);
    }
    if (unsupportedRegions.contains(region)) {
      throw UnsupportedActionException(
        type.displayName,
        details: '${newSongRegionLabels[region]}地区暂不支持',
      );
    }
    return [newSong];
  }

  @override
  Future<List<Toplist>> getToplists() async {
    toplistLoads++;
    if (toplistsFailure != null) {
      throw ApiException(message: toplistsFailure!, code: ApiErrorCode.network);
    }
    return [toplist];
  }

  @override
  Future<RecommendationResult> getDailyRecommendation() async {
    recommendationLoads++;
    return recommendationFailure == null
        ? RecommendationResult(songs: [recommendedSong], source: source)
        : RecommendationResult(
            error: recommendationFailure,
            source: RecommendationSource(
              platform: type,
              kind: RecommendationKind.unavailable,
              label: '不可用',
            ),
          );
  }
}

/// 真实仓库完整IO操作离开FakeAsync，仍只读写本门目录。
class _IoPlaylistsRepository extends MyPlaylistsRepository {
  _IoPlaylistsRepository(Directory directory, this.ioZone)
    : super(storageDirectory: directory);
  final Zone ioZone;
  @override
  Future<List<Playlist>> getPlaylists() => ioZone.run(super.getPlaylists);
  @override
  Future<Playlist> createPlaylist(String name) =>
      ioZone.run(() => super.createPlaylist(name));
  @override
  Future<List<Song>> getSongs(String playlistId) =>
      ioZone.run(() => super.getSongs(playlistId));
  @override
  Future<String?> exportPlaylistLink(String playlistId) =>
      ioZone.run(() => super.exportPlaylistLink(playlistId));
}

class _Catalog extends ExpandedVideoCatalog {
  _Catalog({
    this.hotTerms = const [],
    this.resultDuration = const Duration(minutes: 3),
  });
  final List<String> hotTerms;
  final Duration resultDuration;
  final calls = <({PlatformType platform, String query, int page})>[];
  bool fail = false;
  @override
  Future<List<String>> hotSearch() async => hotTerms;
  @override
  Future<VideoPage> search(
    PlatformType platform,
    String query, {
    int page = 1,
    int limit = 30,
  }) async {
    calls.add((platform: platform, query: query, page: page));
    if (fail) {
      throw const VideoFailure(
        VideoFailureKind.network,
        '语义验收来源网络失败',
        canRetry: true,
      );
    }
    return VideoPage(
      songs: [
        for (var index = 0; index < 3; index++)
          Song(
            id: 'semantics-${platform.name}-$index',
            name: '实际搜索曲目${platform.name}$index',
            platform: platform,
            artists: _track.artists,
            album: _track.album,
            duration: resultDuration,
          ),
      ],
      page: page,
      hasMore: false,
      total: 3,
    );
  }
}

class _PendingCatalog extends _Catalog {
  _PendingCatalog({required super.hotTerms});
  final _pending = Completer<List<String>>();
  int hotLoads = 0;
  @override
  Future<List<String>> hotSearch() {
    hotLoads++;
    return _pending.future;
  }

  void release() {
    if (!_pending.isCompleted) _pending.complete(hotTerms);
  }
}

class _PendingContent extends _R10Content {
  _PendingContent(super.platform);
  final _pending = Completer<RecommendationResult>();
  @override
  Future<RecommendationResult> getDailyRecommendation() {
    recommendationLoads++;
    return _pending.future;
  }

  void release() {
    if (!_pending.isCompleted) {
      _pending.complete(
        RecommendationResult(songs: [recommendedSong], source: source),
      );
    }
  }
}

class _Recommendations extends RecommendationsNotifier {
  _Recommendations({this.realLoading = false})
    : super(supportedTypes: realLoading ? PlatformType.musicServices : null) {
    state = const RecommendationsState(isLoading: true);
  }
  final bool realLoading;
  @override
  Future<void> loadRecommendations() async {
    if (realLoading) await super.loadRecommendations();
  }

  void show(RecommendationsState next) => state = next;
}

class _PendingRecommendations extends _Recommendations {
  _PendingRecommendations() : super(realLoading: true);
  @override
  Future<void> loadRecommendations() => loadLatestRecommendations();
}

/// 按生产IkStrictAudioSettings的真实写队列停在落盘前，验收可见busy帧。
class _AudioSaveGate {
  _AudioSaveGate(this._write);
  final Future<void> Function(Map<String, dynamic>) _write;
  Completer<void>? _hold;
  bool waiting = false;

  void hold() => _hold = Completer<void>();
  void release() {
    _hold?.complete();
    _hold = null;
  }

  Future<void> write(Map<String, dynamic> values) async {
    final hold = _hold;
    if (hold != null) {
      waiting = true;
      await hold.future;
      waiting = false;
    }
    await _write(values);
  }
}

class _Player extends PlayerNotifier {
  _Player({
    bool hasSong = true,
    bool verifiedAudio = false,
    PlayerState? initialState,
  }) : super(
         audioController: verifiedAudio ? _Audio() : IdleAudioController(),
         audioControllerFactory: verifiedAudio
             ? _Audio.new
             : IdleAudioController.new,
         keepAliveController: const NoopPlaybackKeepAliveController(),
         notificationController: const NoopPlaybackNotificationController(),
         stuckWatchdogInterval: Duration.zero,
         playbackHealthCheckInterval: Duration.zero,
         playbackMemorySaveInterval: Duration.zero,
       ) {
    state =
        initialState ??
        (hasSong
            ? const PlayerState(
                currentSong: _track,
                duration: Duration(minutes: 3),
              )
            : const PlayerState());
  }

  void reportDuration(Duration duration) {
    state = state.copyWith(duration: duration);
  }
}

class _Audio extends IdleAudioController
    implements VerifiedEqualizerCapable, SpatialAudioCapable {
  int _request = 0;
  @override
  Future<void> applyEqualizerVerified({
    required bool enabled,
    required List<double> bandGains,
  }) async {}
  @override
  Future<bool> supportsSpatialAudio() async => true;
  @override
  Future<void> applySpatialAudio(
    SpatialSettings settings,
    int requestId,
  ) async {
    _request = requestId;
  }

  @override
  Future<SpatialProcessingReport> readSpatialAudio() async =>
      SpatialProcessingReport(requestId: _request, processedFrames: 0);
}

class _LikesDao extends Fake implements LikesDao {}

class _SongsDao extends Fake implements SongsDao {}

class _Likes extends LikesNotifier {
  _Likes() : super(_LikesDao(), _SongsDao());
  @override
  Future<void> loadLikes() async {}
}

class _SemanticsBinding extends AutomatedTestWidgetsFlutterBinding {
  _SemanticsBinding() {
    trace.owner = () => renderViews.single.owner!.semanticsOwner;
  }
  final trace = _TreeTrace();
  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() => _UpdateSpy(trace);
}

typedef _Node = ({
  int id,
  int? parent,
  List<int> traversal,
  List<int> hit,
  String label,
  String tooltip,
  bool button,
  int actions,
  int? flutterParent,
  int? parentIdentity,
  int? childIdentity,
  bool hidden,
  bool merged,
});

_Node _axGoldenNode(int id, List<int> children) => (
  id: id,
  parent: null,
  traversal: children,
  hit: children,
  label: '',
  tooltip: '',
  button: false,
  actions: 0,
  flutterParent: null,
  parentIdentity: null,
  childIdentity: null,
  hidden: false,
  merged: false,
);

Iterable<List<_Node>> _axNodeOrders(List<_Node> nodes) sync* {
  if (nodes.isEmpty) {
    yield const [];
    return;
  }
  for (var index = 0; index < nodes.length; index++) {
    final rest = List<_Node>.of(nodes)..removeAt(index);
    for (final order in _axNodeOrders(rest)) {
      yield [nodes[index], ...order];
    }
  }
}

class _AxNode {
  _AxNode(this.parent, [List<int> children = const []])
    : children = List.of(children);
  final int? parent;
  List<int> children;
}

/// 当前Windows桥先移除重挂子树，再按父先子后的原始pending重新初始化。
/// 只跟踪原生结构；绝不把Flutter最终缓存中的后代当作AX已初始化节点。
class _WindowsAxDelta {
  final nodes = <int, _AxNode>{};
  final pendingInitialization = <int>{};
  final deleted = <int>[];
  final reparented = <int>[];
  Map<int, _AxNode> before = {};
  int commits = 0;
  int totalReparented = 0;
  int totalDeleted = 0;

  void clear() {
    nodes.clear();
    pendingInitialization.clear();
    deleted.clear();
    reparented.clear();
    before = {};
    commits = 0;
    totalReparented = 0;
    totalDeleted = 0;
  }

  List<String> commit(
    List<_Node> batch, {
    required Map<int, int> parents,
    required Set<int> live,
  }) {
    commits++;
    before = {
      for (final entry in nodes.entries)
        entry.key: _AxNode(entry.value.parent, entry.value.children),
    };
    deleted.clear();
    reparented.clear();
    pendingInitialization.clear();
    // Bridge对同id只保留最后一次原始更新。
    final updates = {for (final node in batch) node.id: node};
    final removals = <int, List<int>>{};
    for (final node in updates.values) {
      for (final childId in node.traversal) {
        final child = nodes[childId];
        if (child == null) continue;
        final oldParent = child.parent;
        if (oldParent == null) {
          return ['AX原始节点${node.id}试图重挂无父根节点$childId'];
        }
        if (oldParent == node.id) continue;
        // release桥的assert不会拦截漏发的重挂节点；继续模拟到pending错误。
        removals
            .putIfAbsent(oldParent, () => List.of(nodes[oldParent]!.children))
            .remove(childId);
        reparented.add(childId);
      }
    }
    totalReparented += reparented.length;
    final destroyed = <int>{};
    void collectDestroyed(int id) {
      if (!destroyed.add(id)) return;
      for (final child in nodes[id]!.children) {
        collectDestroyed(child);
      }
    }

    for (final id in reparented) {
      collectDestroyed(id);
    }
    // 第一阶段使用unordered_map。被删除子树的父更新不能依赖碰巧先执行。
    for (final id in removals.keys) {
      if (destroyed.contains(id)) {
        return ['AX第一阶段更新父节点$id也位于待删除子树，不能保证独立更新顺序'];
      }
    }
    for (final entry in removals.entries) {
      final error = _update(entry.key, entry.value);
      if (error != null) return ['AX移除阶段：$error'];
    }
    if (pendingInitialization.isNotEmpty) {
      return ['AX移除阶段待初始化节点${pendingInitialization.join(',')}'];
    }
    // 不允许原始更新依赖已删除节点恰好早于删除父节点执行。
    for (final id in updates.keys) {
      if (!live.contains(id)) {
        return ['AX原始更新节点$id在本批被移出树，不能保证独立更新顺序'];
      }
    }
    final depths = <int, int>{0: 0};
    int depth(int id) => depths.putIfAbsent(id, () => depth(parents[id]!) + 1);
    final ordered = updates.values.toList()
      ..sort((a, b) {
        final order = depth(a.id).compareTo(depth(b.id));
        return order != 0 ? order : a.id.compareTo(b.id);
      });
    // Bridge保证依赖中的父先子后，不假定Dart与原生哈希枚举顺序相同。
    for (final node in ordered) {
      final error = _update(node.id, node.traversal);
      if (error != null) return ['AX初始化阶段：$error'];
    }
    if (pendingInitialization.isNotEmpty) {
      final ids = pendingInitialization.toList()..sort();
      return ['AX待初始化节点${ids.join(',')}，原始pending缺少新建节点的数据'];
    }
    if (nodes.length != live.length || !live.every(nodes.containsKey)) {
      return ['AX原生树与完整图的可达节点不一致'];
    }
    return [];
  }

  String? _update(int id, List<int> childIds) {
    var node = nodes[id];
    if (node == null) {
      if (id != 0 || nodes.isNotEmpty) return '节点$id不在树中且不是新根';
      node = _AxNode(null);
      nodes[id] = node;
    }
    pendingInitialization.remove(id);
    final retained = childIds.toSet();
    for (final child in node.children) {
      if (!retained.contains(child)) _destroy(child);
    }
    for (final childId in childIds) {
      final child = nodes[childId];
      if (child == null) {
        nodes[childId] = _AxNode(id);
        pendingInitialization.add(childId);
      } else if (child.parent != id) {
        return '节点$childId从${child.parent}直接重挂到$id';
      }
    }
    node.children = List.of(childIds);
    return null;
  }

  void _destroy(int id) {
    final node = nodes.remove(id)!;
    for (final child in node.children) {
      _destroy(child);
    }
    pendingInitialization.remove(id);
    deleted.add(id);
    totalDeleted++;
  }

  Map<String, Object?> json() => {
    'before': [
      for (final entry in before.entries)
        {
          'id': entry.key,
          'parent': entry.value.parent,
          'children': entry.value.children,
        },
    ],
    'reparented': reparented,
    'deleted': deleted,
    'pendingInitialization': pendingInitialization.toList(),
  };
}

class _TreeTrace {
  static int _nextTraceId = 0;
  final int _traceId = _nextTraceId++;
  final bool _recordEnabled = Platform.environment['IK_AX_TRACE_FULL'] == '1';
  int _generation = 0, _pumpCount = 0, _stepCount = 0;
  int _stepRawStart = 0, _stepAxStart = 0, _stepPumpStart = 0;
  int? _activePump;
  final ax = _WindowsAxDelta();
  final nodes = <int, _Node>{};
  final batches = <List<_Node>>[];
  final issues = <String>[];
  List<_Node> pending = [];
  Map<int, _Node> before = {};
  Set<int> newIds = {};
  SemanticsOwner? Function()? owner;
  VoidCallback? onIssue;
  String _step = '启动';
  String get step => _step;
  set step(String value) {
    _recordStep();
    _step = value;
    _stepCount++;
    _stepRawStart = batches.length;
    _stepAxStart = ax.commits;
    _stepPumpStart = _pumpCount;
  }

  void _record(Map<String, Object?> record) {
    if (!_recordEnabled) return;
    debugPrint(
      'IK_SEMANTICS_TRACE ${jsonEncode({'traceId': _traceId, 'generation': _generation, 'stepId': _stepCount, 'step': step, ...record})}',
    );
  }

  int _rawNodesSince(int start) =>
      batches.skip(start).fold(0, (count, batch) => count + batch.length);

  void _recordStep() {
    if (!_recordEnabled) return;
    _record({
      'kind': 'step',
      'rawStart': _stepRawStart,
      'rawEnd': batches.length,
      'axStart': _stepAxStart,
      'axEnd': ax.commits,
      'pumpStart': _stepPumpStart,
      'pumpEnd': _pumpCount,
      'rawNodes': _rawNodesSince(_stepRawStart),
      'zero': batches.length == _stepRawStart,
      'issues': issues.toList(),
    });
  }

  int? beginPump() {
    if (!_recordEnabled) return null;
    _activePump = ++_pumpCount;
    return _activePump;
  }

  void recordPump(
    int? pumpId, {
    required int rawStart,
    required int axStart,
    required Duration duration,
    required bool completed,
    Object? frameworkError,
    Object? thrown,
  }) {
    if (pumpId == null) return;
    _record({
      'kind': 'pump',
      'pumpId': pumpId,
      'rawStart': rawStart,
      'rawEnd': batches.length,
      'axStart': axStart,
      'axEnd': ax.commits,
      'rawNodes': _rawNodesSince(rawStart),
      'zero': batches.length == rawStart,
      'durationMicroseconds': duration.inMicroseconds,
      'completed': completed,
      'frameworkError': frameworkError?.toString(),
      'thrown': thrown?.toString(),
      'issues': issues.toList(),
    });
    if (_activePump == pumpId) _activePump = null;
  }

  void finishDiagnostics({required bool completed}) {
    if (!_recordEnabled) return;
    _recordStep();
    _record({
      'kind': 'finish',
      'completed': completed,
      'rawBatches': batches.length,
      'axBatches': ax.commits,
      'rawNodes': _rawNodesSince(0),
      'pumps': _pumpCount,
      'steps': _stepCount + 1,
      'reparented': ax.totalReparented,
      'deleted': ax.totalDeleted,
      'issues': issues.toList(),
    });
  }

  void clear() {
    ax.clear();
    nodes.clear();
    batches.clear();
    issues.clear();
    pending = [];
    before = {};
    newIds = {};
    onIssue = null;
    _step = '启动';
    _generation++;
    _pumpCount = _stepCount = 0;
    _stepRawStart = _stepAxStart = _stepPumpStart = 0;
    _activePump = null;
    _record({'kind': 'reset'});
  }

  void commit(List<_Node> batch) {
    batches.add(List.of(batch));
    if (_recordEnabled) {
      _record({
        'kind': 'batch',
        'batch': batches.length,
        'pumpId': _activePump,
        'eligibleForValidation': issues.isEmpty,
        'axBefore': ax.commits,
        'nodeCount': batch.length,
        'nodes': [for (final node in batch) _json(node)],
      });
    }
    pending = List.of(batch);
    if (issues.isNotEmpty) {
      pending = [];
      return;
    }
    before = Map.of(nodes);
    newIds = {
      for (final node in batch)
        if (!before.containsKey(node.id)) node.id,
    };
    nodes.addAll({for (final node in batch) node.id: node});
    final found = <String>[];
    final live = <int>{};
    final parents = <int, int>{};
    void visit(int id, Set<int> ancestors) {
      if (ancestors.contains(id)) {
        found.add('遍历环：$ancestors -> $id');
        return;
      }
      final node = nodes[id];
      if (node == null) {
        found.add('引用缺失：$id');
        return;
      }
      if (!live.add(id)) return;
      for (final child in node.traversal) {
        if (child == 0) found.add('根0成为节点$id的子节点');
        final oldParent = parents[child];
        if (oldParent != null) {
          found.add('节点$child同时被$oldParent和$id引用');
        }
        parents[child] = id;
        visit(child, {...ancestors, id});
      }
    }

    if (!nodes.containsKey(0)) found.add('缺少根0');
    visit(0, {});
    for (final node in batch) {
      // Bridge先扫描全部原始pending，不能仅检查最终仍可达的节点。
      if (node.traversal.contains(0)) {
        found.add('原始提交节点${node.id}将根0列为子节点');
      }
      if (newIds.contains(node.id) &&
          node.id != 0 &&
          !nodes.values.any((parent) => parent.traversal.contains(node.id))) {
        found.add('本批新增节点${node.id}没有任何traversal父引用');
      }
      if (node.id != 0 &&
          live.contains(node.id) &&
          !parents.containsKey(node.id)) {
        found.add('节点${node.id}没有父节点');
      }
      if (node.parent != null &&
          node.parent! >= 0 &&
          live.contains(node.id) &&
          !live.contains(node.parent)) {
        found.add('节点${node.id}的traversalParent${node.parent}不可达');
      }
      for (final child in node.hit) {
        if (live.contains(node.id) && !live.contains(child)) {
          found.add('节点${node.id}命中顺序引用不可达$child');
        }
        if (child == 0) found.add('命中顺序中根0成为节点${node.id}的子节点');
      }
    }
    if (found.isEmpty) {
      found.addAll(ax.commit(batch, parents: parents, live: live));
    }
    if (found.isNotEmpty) {
      final firstIssue = issues.isEmpty;
      issues.add('批${batches.length} $step：${found.join('；')}');
      if (firstIssue) {
        dump(found.join('；'));
        onIssue?.call();
      } else {
        debugPrint(
          'IK_SEMANTICS_INVALID_BATCH ${jsonEncode({'batch': batches.length, 'step': step, 'reason': found.join('；')})}',
        );
      }
    }
    nodes.removeWhere((id, _) => !live.contains(id));
    pending = [];
  }

  void dump(String reason) {
    debugPrint(
      'IK_SEMANTICS ${jsonEncode({
        'step': step,
        'batchCount': batches.length,
        'reason': reason,
        'newIds': newIds.toList(),
        'before': [for (final node in before.values) _json(node)],
        'pending': [for (final node in pending) _json(node)],
        'current': [for (final node in nodes.values) _json(node)],
        'windowsAx': ax.json(),
      })}',
    );
  }

  Map<String, Object?> _json(_Node node) => {
    'id': node.id,
    'traversalParent': node.parent,
    'childrenInTraversalOrder': node.traversal,
    'childrenInHitTestOrder': node.hit,
    'label': node.label,
    'tooltip': node.tooltip,
    'button': node.button,
    'actions': node.actions,
    'flutterParent': node.flutterParent,
    'parentIdentity': node.parentIdentity,
    'childIdentity': node.childIdentity,
    'hidden': node.hidden,
    'merged': node.merged,
  };

  void expectValid() {
    debugPrint('IK_SEMANTICS 完整检查${batches.length}批，${issues.length}项树错误');
    final rawNodes = batches.fold(0, (count, batch) => count + batch.length);
    debugPrint(
      'IK_SEMANTICS Windows AX检查${ax.commits}批，'
      '$rawNodes个原始节点，${ax.totalReparented}次重挂、'
      '${ax.totalDeleted}个节点销毁，全部新建引用核验初始化',
    );
    expect(batches, isNotEmpty);
    expect(issues.length, 0, reason: issues.firstOrNull);
    expect(ax.commits, batches.length, reason: '每个已提交原始批次都必须经过Windows AX增量门');
  }
}

/// 捕获绑定实际提交给引擎的完整参数，并继续调用原生builder。
class _UpdateSpy extends Fake implements ui.SemanticsUpdateBuilder {
  _UpdateSpy(this.trace) {
    trace.pending = batch;
  }
  final _TreeTrace trace;
  final _builder = ui.SemanticsUpdateBuilder();
  final batch = <_Node>[];

  @override
  void updateNode({
    required int id,
    required ui.SemanticsFlags flags,
    required int actions,
    required int maxValueLength,
    required int currentValueLength,
    required int textSelectionBase,
    required int textSelectionExtent,
    required int platformViewId,
    required int scrollChildren,
    required int scrollIndex,
    required int? traversalParent,
    required double scrollPosition,
    required double scrollExtentMax,
    required double scrollExtentMin,
    required ui.Rect rect,
    required String identifier,
    required String label,
    List<ui.StringAttribute>? labelAttributes,
    required String value,
    List<ui.StringAttribute>? valueAttributes,
    required String increasedValue,
    List<ui.StringAttribute>? increasedValueAttributes,
    required String decreasedValue,
    List<ui.StringAttribute>? decreasedValueAttributes,
    required String hint,
    List<ui.StringAttribute>? hintAttributes,
    String? tooltip,
    ui.TextDirection? textDirection,
    required Float64List transform,
    required Float64List hitTestTransform,
    required Int32List childrenInTraversalOrder,
    required Int32List childrenInHitTestOrder,
    required Int32List additionalActions,
    int headingLevel = 0,
    String? linkUrl,
    ui.SemanticsRole role = ui.SemanticsRole.none,
    required List<String>? controlsNodes,
    ui.SemanticsValidationResult validationResult =
        ui.SemanticsValidationResult.none,
    ui.SemanticsHitTestBehavior hitTestBehavior =
        ui.SemanticsHitTestBehavior.defer,
    required ui.SemanticsInputType inputType,
    required ui.Locale? locale,
    required String minValue,
    required String maxValue,
  }) {
    final node = trace.owner?.call()?.getSemanticsNode(id);
    batch.add((
      id: id,
      parent: traversalParent,
      traversal: childrenInTraversalOrder.toList(),
      hit: childrenInHitTestOrder.toList(),
      label: label,
      tooltip: tooltip ?? '',
      button: flags.isButton,
      actions: actions,
      flutterParent: node?.parent?.id,
      parentIdentity: node?.traversalParentIdentifier == null
          ? null
          : identityHashCode(node!.traversalParentIdentifier!),
      childIdentity: node?.traversalChildIdentifier == null
          ? null
          : identityHashCode(node!.traversalChildIdentifier!),
      hidden: flags.isHidden,
      merged: node?.isMergedIntoParent ?? false,
    ));
    _builder.updateNode(
      id: id,
      flags: flags,
      actions: actions,
      maxValueLength: maxValueLength,
      currentValueLength: currentValueLength,
      textSelectionBase: textSelectionBase,
      textSelectionExtent: textSelectionExtent,
      platformViewId: platformViewId,
      scrollChildren: scrollChildren,
      scrollIndex: scrollIndex,
      traversalParent: traversalParent ?? -1,
      scrollPosition: scrollPosition,
      scrollExtentMax: scrollExtentMax,
      scrollExtentMin: scrollExtentMin,
      rect: rect,
      identifier: identifier,
      label: label,
      labelAttributes: labelAttributes ?? const [],
      value: value,
      valueAttributes: valueAttributes ?? const [],
      increasedValue: increasedValue,
      increasedValueAttributes: increasedValueAttributes ?? const [],
      decreasedValue: decreasedValue,
      decreasedValueAttributes: decreasedValueAttributes ?? const [],
      hint: hint,
      hintAttributes: hintAttributes ?? const [],
      tooltip: tooltip ?? '',
      textDirection: textDirection,
      transform: transform,
      hitTestTransform: hitTestTransform,
      childrenInTraversalOrder: childrenInTraversalOrder,
      childrenInHitTestOrder: childrenInHitTestOrder,
      additionalActions: additionalActions,
      headingLevel: headingLevel,
      linkUrl: linkUrl ?? '',
      role: role,
      controlsNodes: controlsNodes,
      validationResult: validationResult,
      hitTestBehavior: hitTestBehavior,
      inputType: inputType,
      locale: locale,
      minValue: minValue,
      maxValue: maxValue,
    );
  }

  @override
  void updateCustomAction({
    required int id,
    String? label,
    String? hint,
    int overrideId = -1,
  }) => _builder.updateCustomAction(
    id: id,
    label: label,
    hint: hint,
    overrideId: overrideId,
  );

  @override
  ui.SemanticsUpdate build() {
    trace.commit(batch);
    return _builder.build();
  }
}

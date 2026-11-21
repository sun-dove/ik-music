import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

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
import 'package:mconnect/core/platform/platform_utils.dart';
import 'package:mconnect/features/audio_effects/presentation/providers/audio_effects_provider.dart';
import 'package:mconnect/features/auth/presentation/providers/auth_provider.dart';
import 'package:mconnect/features/discovery/presentation/providers/recommendations_provider.dart';
import 'package:mconnect/features/download/data/download_directory_service.dart';
import 'package:mconnect/features/download/data/repositories/download_manager.dart';
import 'package:mconnect/features/download/presentation/providers/download_provider.dart';
import 'package:mconnect/features/download/presentation/providers/download_quality_provider.dart';
import 'package:mconnect/features/library/data/my_playlists_repository.dart';
import 'package:mconnect/features/library/presentation/providers/history_provider.dart';
import 'package:mconnect/features/library/presentation/providers/likes_provider.dart';
import 'package:mconnect/features/library/presentation/providers/my_playlists_provider.dart';
import 'package:mconnect/features/player/data/playback_keep_alive_service.dart';
import 'package:mconnect/features/player/data/playback_notification_service.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/l10n/ik_player_alignment_strings.dart';
import 'package:mconnect/l10n/ik_strings.dart';
import 'package:mconnect/l10n/video_strings.dart';
import 'package:mconnect/models/album.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/platform/base/platform_registry.dart';
import 'package:mconnect/video_app/data/video_catalog.dart';
import 'package:mconnect/video_app/data/video_kugou_catalog.dart';
import 'package:mconnect/video_app/ik/ik_home_page.dart';
import 'package:mconnect/video_app/ik/ik_playback_bar.dart';
import 'package:mconnect/video_app/ik/ik_theme.dart';
import 'package:mconnect/video_app/ik/ik_workspace.dart';
import 'package:mconnect/video_app/ik/ik_controls.dart';
import 'package:mconnect/video_app/ik/ik_search_workspace.dart';
import 'package:mconnect/video_app/ik/ik_settings_workspace.dart';
import 'package:mconnect/video_app/ik/ik_spatial_runtime.dart';
import 'package:mconnect/video_app/multi_source/multi_source_player.dart';
import 'package:mconnect/video_app/video_app.dart';
import 'package:mconnect/video_app/video_preferences.dart';
import 'package:mconnect/video_app/windows/windows_appearance.dart';
import 'package:mconnect/video_app/windows/windows_music_preferences.dart';
import 'package:mconnect/video_app/windows/windows_player_page.dart';
import 'package:mconnect/video_app/windows/windows_window_controller.dart';
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
      (_) async => true,
    );
  });

  setUp(() async {
    binding.trace.clear();
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

  Future<_RootHarness> mountRoot(
    WidgetTester tester, {
    required bool hasSong,
    bool recommendationsLoading = true,
  }) async {
    await _size(tester);
    final db = suiteDb;
    final preferences = VideoPreferences(settings);
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
    final recommendations = _Recommendations();
    if (!recommendationsLoading) {
      recommendations.show(
        RecommendationsState(
          songsByPlatform: {
            PlatformType.qq: [_track],
          },
        ),
      );
    }
    final catalog = _Catalog();
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => _Auth()),
        playerProvider.overrideWith(
          (_) => _Player(hasSong: hasSong, verifiedAudio: true),
        ),
        audioEffectsSettingsStoreProvider.overrideWithValue(
          MemoryAudioEffectsSettingsStore(),
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
        myPlaylistsProvider.overrideWith(
          (_) => MyPlaylistsNotifier(
            repository: MyPlaylistsRepository(storageDirectory: scratch),
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
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: VideoMusicApp(
          redesign: true,
          workspace: true,
          alignToDesign: true,
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
}

void _testWindows(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    PlatformUtils.setDebugOverride(AppPlatform.windows);
    try {
      await body(tester);
    } finally {
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
  await tester.pump(duration);
  final error = tester.takeException();
  if (error != null) trace.dump('框架异常：$error');
  expect(error, isNull, reason: trace.step);
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

class _Content extends FakeContentPlatform {
  _Content(PlatformType platform) : super(type: platform);
  @override
  Future<String?> getLyrics(String songId) async =>
      '[00:00.00]语义验收歌词\n[00:10.00]语义验收下一句';
}

class _Catalog extends ExpandedVideoCatalog {
  bool fail = false;
  @override
  Future<List<String>> hotSearch() async => const [];
  @override
  Future<VideoPage> search(
    PlatformType platform,
    String query, {
    int page = 1,
    int limit = 30,
  }) async {
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
            duration: const Duration(minutes: 3),
          ),
      ],
      page: page,
      hasMore: false,
      total: 3,
    );
  }
}

class _Recommendations extends RecommendationsNotifier {
  _Recommendations() {
    state = const RecommendationsState(isLoading: true);
  }
  @override
  Future<void> loadRecommendations() async {}
  void show(RecommendationsState next) => state = next;
}

class _Player extends PlayerNotifier {
  _Player({bool hasSong = true, bool verifiedAudio = false})
    : super(
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
    state = hasSong
        ? const PlayerState(currentSong: _track, duration: Duration(minutes: 3))
        : const PlayerState();
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

class _TreeTrace {
  final nodes = <int, _Node>{};
  final batches = <List<_Node>>[];
  final issues = <String>[];
  List<_Node> pending = [];
  Map<int, _Node> before = {};
  Set<int> newIds = {};
  SemanticsOwner? Function()? owner;
  VoidCallback? onIssue;
  String step = '启动';

  void clear() {
    nodes.clear();
    batches.clear();
    issues.clear();
    pending = [];
    before = {};
    newIds = {};
    onIssue = null;
    step = '启动';
  }

  void commit(List<_Node> batch) {
    batches.add(List.of(batch));
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
    expect(batches, isNotEmpty);
    expect(issues.length, 0, reason: issues.firstOrNull);
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

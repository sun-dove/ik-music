import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mconnect/core/share/share_service.dart';
import 'package:mconnect/core/transfer/playlist_export.dart';
import 'package:mconnect/features/discovery/presentation/providers/recommendations_provider.dart';
import 'package:mconnect/features/library/data/my_playlists_repository.dart';
import 'package:mconnect/features/library/presentation/pages/platform_playlists_page.dart';
import 'package:mconnect/features/library/presentation/providers/my_playlists_provider.dart';
import 'package:mconnect/features/library/presentation/providers/platform_playlists_provider.dart';
import 'package:mconnect/l10n/ik_discovery_revision_strings.dart';
import 'package:mconnect/l10n/ik_library_revision_strings.dart';
import 'package:mconnect/l10n/ik_strings.dart';
import 'package:mconnect/l10n/ik_workspace_strings.dart';
import 'package:mconnect/l10n/video_strings.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/playlist.dart';
import 'package:mconnect/models/recommendation_source.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/video_app/data/video_catalog.dart';
import 'package:mconnect/video_app/ik/ik_controls.dart';
import 'package:mconnect/video_app/ik/ik_library_workspace.dart';
import 'package:mconnect/video_app/ik/ik_search.dart';
import 'package:mconnect/video_app/ik/ik_search_workspace.dart';
import 'package:mconnect/video_app/ik/ik_song_table.dart';
import 'package:mconnect/video_app/ik/ik_workspace_theme.dart';
import 'package:mconnect/video_app/ui/catalog_pages.dart';

import 'support/content_page_fakes.dart';

// 正式 S01-S07：真实页面、歌单及推荐通知器，只替换网络、仓库和分享边界。
// 详情路由仅记录真实平台/ID与返回，不把此门当作详情或原生成品验收。
void main() {
  testWidgets('S01 同壳五分类保留，歌单只有来源选择器且四来源数据不混用', (tester) async {
    final fixture = _Fixture();
    await _mount(tester, fixture, fixture.library(simplify: true));
    await _tap(
      tester,
      find.byKey(const ValueKey('ik-library-category-playlists')),
    );
    expect(find.text(IkWorkspaceStrings.library), findsOneWidget);
    expect(find.text(IkStrings.playlists), findsOneWidget);
    expect(find.byType(TabBar).hitTestable(), findsNothing);
    for (final category in [
      'likes',
      'playlists',
      'local',
      'downloads',
      'smart',
    ]) {
      expect(
        find.byKey(ValueKey('ik-library-category-$category')).hitTestable(),
        findsOneWidget,
      );
    }
    for (final platform in PlatformType.values) {
      await _select(tester, IkLibraryRevisionStrings.playlistSource, platform);
      expect(find.text(_playlist(platform).name).hitTestable(), findsOneWidget);
      for (final other in PlatformType.values.where((p) => p != platform)) {
        expect(find.text(_playlist(other).name).hitTestable(), findsNothing);
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('S02 四来源刷新新建取消、详情返回及原导出改名复制删除保持目标', (tester) async {
    final fixture = _Fixture();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(body: fixture.library(simplify: true)),
        ),
        GoRoute(
          path: '/playlist/:platform/:id',
          builder: (context, state) => Scaffold(
            body: Column(
              children: [
                Text(
                  '详情:${state.pathParameters['platform']}:${state.pathParameters['id']}',
                ),
                TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('返回歌单'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await _mount(tester, fixture, null, router: router);
    await _tap(
      tester,
      find.byKey(const ValueKey('ik-library-category-playlists')),
    );
    for (final platform in PlatformType.values) {
      await _select(tester, IkLibraryRevisionStrings.playlistSource, platform);
      final beforeLoads = fixture.loads(platform);
      await _tap(tester, find.byTooltip('刷新当前歌单'));
      expect(fixture.loads(platform), beforeLoads + 1);
      final original = _playlist(platform);
      await _tap(tester, find.text(original.name).hitTestable());
      expect(router.routerDelegate.state.uri.pathSegments, [
        'playlist',
        platform.name,
        original.id,
      ]);
      expect(find.text('详情:${platform.name}:${original.id}'), findsOneWidget);
      await _tap(tester, find.text('返回歌单'));
      expect(
        _selectedValue(tester, IkLibraryRevisionStrings.playlistSource),
        platform,
      );

      final beforeWrites = fixture.creates(platform);
      await _tap(tester, find.byTooltip('新建歌单'));
      await _tap(tester, find.text('取消'));
      expect(fixture.creates(platform), beforeWrites);
      await _tap(tester, find.byTooltip('新建歌单'));
      final name = '${platform.name}新建目标';
      await tester.enterText(find.byType(TextField), name);
      await _tap(tester, find.text('新建'));
      expect(fixture.creates(platform), beforeWrites + 1);
      expect(find.text(name).hitTestable(), findsOneWidget);

      if (platform == PlatformType.local) {
        await _playlistAction(tester, original.name, '导出歌单');
        for (final choice in PlaylistExportChoice.values) {
          expect(
            find.text(
              choice == PlaylistExportChoice.json
                  ? IkStrings.playlistJson
                  : choice.label,
            ),
            findsOneWidget,
          );
        }
        expect(find.byType(Dialog), findsOneWidget);
        await _tap(
          tester,
          find.descendant(
            of: find.byType(Dialog),
            matching: find.byTooltip(IkStrings.close),
          ),
        );
        expect(fixture.channel.texts, isEmpty);
        await _playlistAction(tester, original.name, '导出歌单');
        await _tap(tester, find.text(IkStrings.playlistJson));
        final payload =
            jsonDecode(fixture.channel.texts.single) as Map<String, dynamic>;
        expect(payload['format'], 'mconnect.playlist');
        final exported = payload['songs'] as List<dynamic>;
        expect(
          exported.map((s) => s['id']),
          _tracks(platform).map((s) => s.id),
        );
        await _playlistAction(tester, original.name, '删除歌单');
        await _tap(tester, find.text('取消'));
        expect(fixture.repository.deleted, isEmpty);
        await _playlistAction(tester, original.name, '删除歌单');
        await _tap(tester, find.widgetWithText(FilledButton, '删除'));
        expect(fixture.repository.deleted, [original.id]);
      } else {
        final implementation = fixture.platforms[platform]!;
        await _playlistAction(tester, original.name, '复制到我的歌单（本地）');
        expect(
          fixture.repository.imported.last.map((s) => s.id),
          _tracks(platform).map((s) => s.id),
        );
        expect(implementation.songLoads.last, original.id);
        await _playlistAction(tester, original.name, '重命名歌单');
        await _tap(tester, find.text('取消'));
        expect(implementation.renamed, isEmpty);
        await _playlistAction(tester, original.name, '重命名歌单');
        await tester.enterText(find.byType(TextField), '${platform.name}改名目标');
        await _tap(tester, find.widgetWithText(FilledButton, '确定'));
        expect(implementation.renamed.single, (
          original.editableId,
          '${platform.name}改名目标',
        ));
        final renamed = '${platform.name}改名目标';
        await _playlistAction(tester, renamed, '删除歌单');
        await _tap(tester, find.text('取消'));
        expect(implementation.deleted, isEmpty);
        await _playlistAction(tester, renamed, '删除歌单');
        await _tap(tester, find.widgetWithText(FilledButton, '删除'));
        expect(implementation.deleted, [original.editableId]);
      }
      expect(
        _selectedValue(tester, IkLibraryRevisionStrings.playlistSource),
        platform,
      );
      expect(tester.takeException(), isNull);
      debugPrint('S02 已完成 ${platform.name} 的来源、原操作目标与取消验收');
    }
  });

  testWidgets('S03 三十热词输入默认前十，展开收起不重发，全部词使用原分源搜索', (tester) async {
    final fixture = _Fixture();
    await _mount(tester, fixture, _SearchHost(fixture: fixture));
    expect(_visibleHotTerms(tester), fixture.hotTerms.take(10));
    expect(
      find.text(IkLibraryRevisionStrings.hotSearchPreview(30)),
      findsOneWidget,
    );
    final requests = fixture.hotRequests;
    await _tap(tester, find.text(IkLibraryRevisionStrings.expandHotSearch));
    expect(_visibleHotTerms(tester), fixture.hotTerms);
    await _tap(tester, find.text(IkLibraryRevisionStrings.collapseHotSearch));
    expect(_visibleHotTerms(tester), fixture.hotTerms.take(10));
    await _tap(tester, find.text(IkLibraryRevisionStrings.expandHotSearch));
    expect(fixture.hotRequests, requests);
    for (final term in fixture.hotTerms) {
      await fixture.controller.submit('');
      await tester.pumpAndSettle();
      fixture.searchCalls.clear();
      await _tap(tester, find.widgetWithText(ActionChip, term));
      expect(fixture.controller.query, term);
      expect(fixture.searchCalls.length, fixture.controller.platforms.length);
      expect(fixture.searchCalls.map((call) => call.$2).toSet(), {term});
      expect(
        fixture.searchCalls.map((call) => call.$1).toSet(),
        fixture.controller.platforms.toSet(),
      );
      expect(fixture.searchCalls.every((call) => call.$3 == 1), isTrue);
    }
    expect(fixture.hotRequests, requests);
    expect(tester.takeException(), isNull);
  });

  testWidgets('S04 推荐平台独立于搜索来源，来源说明及完整播放列表、更多、重试可达', (tester) async {
    final fixture = _Fixture();
    await _mount(tester, fixture, _SearchHost(fixture: fixture));
    expect(
      _selectedValue(tester, IkLibraryRevisionStrings.recommendationPlatform),
      PlatformType.netease,
    );
    await _select(tester, IkWorkspaceStrings.source, 'qq');
    expect(
      _selectedValue(tester, IkLibraryRevisionStrings.recommendationPlatform),
      PlatformType.netease,
    );
    for (final platform in PlatformType.musicServices) {
      await _select(
        tester,
        IkLibraryRevisionStrings.recommendationPlatform,
        platform,
      );
      final rows = tester
          .widgetList<IkSongTableRow>(find.byType(IkSongTableRow))
          .toList();
      expect(rows.length, 4);
      expect(rows.every((row) => row.song.platform == platform), isTrue);
      final result = fixture.platforms[platform]!.recommendation;
      expect(
        find.text(
          IkDiscoveryRevisionStrings.sourceLabel(
            result.source,
            platform: platform,
            loggedIn: true,
          ),
        ),
        findsOneWidget,
      );
      if (result.source?.note case final note?) {
        expect(find.text(note), findsOneWidget);
      }
      await _tap(tester, find.text(rows.last.song.name));
      expect(fixture.played?.$1, rows.last.song);
      expect(identical(fixture.played?.$2, result.songs), isTrue);
      expect(fixture.played?.$2.length, 7);
      expect(
        fixture.played?.$2.map((song) => '${song.platform.name}:${song.id}'),
        _tracks(platform).map((song) => '${song.platform.name}:${song.id}'),
      );
      await _tap(tester, find.byTooltip(IkStrings.more).first);
      expect(fixture.more?.platform, platform);
      for (final other in PlatformType.musicServices.where(
        (p) => p != platform,
      )) {
        expect(find.text(_tracks(other).first.name), findsNothing);
      }
    }
    await _tap(
      tester,
      find.text(IkLibraryRevisionStrings.browseRecommendations),
    );
    expect(fixture.browseRequests, 1);
    expect(_selectedValue(tester, IkWorkspaceStrings.source), 'qq');
    expect(tester.takeException(), isNull);
  });

  testWidgets('S05 热词及推荐错误加载空态均保留来源入口、真实重试与手动搜索分页', (tester) async {
    for (final state in ['错误', '加载', '空']) {
      final fixture = _Fixture(state: state);
      await _mount(
        tester,
        fixture,
        _SearchHost(fixture: fixture),
        settle: state != '加载',
      );
      expect(
        find.text(IkLibraryRevisionStrings.hotSearchSource),
        findsOneWidget,
      );
      for (final platform in PlatformType.musicServices) {
        debugPrint('S05 场景 $state/${platform.name}');
        await _select(
          tester,
          IkLibraryRevisionStrings.recommendationPlatform,
          platform,
          settle: state != '加载',
        );
        if (state == '错误') {
          final implementation = fixture.platforms[platform]!;
          expect(find.text('${platform.name}推荐请求失败'), findsOneWidget);
          final loads = fixture.platforms.map(
            (p, value) => MapEntry(p, value.recommendationLoads),
          );
          implementation.recommendation = _recommendation(platform);
          final recommendationSection = find.byType(IkSearchWorkspace);
          final retry = find
              .descendant(
                of: recommendationSection,
                matching: find.widgetWithText(TextButton, VideoStrings.retry),
              )
              .last;
          await _tap(tester, retry);
          for (final other in PlatformType.musicServices) {
            expect(
              fixture.platforms[other]!.recommendationLoads,
              loads[other]! + (other == platform ? 1 : 0),
            );
          }
          expect(find.text('${platform.name}推荐请求失败'), findsNothing);
        } else if (state == '空') {
          expect(
            find.text(IkDiscoveryRevisionStrings.noRecommendations),
            findsOneWidget,
          );
        } else {
          expect(find.byType(LinearProgressIndicator), findsWidgets);
        }
      }
      if (state == '错误') {
        expect(find.text('热词请求失败'), findsOneWidget);
        fixture.hotError = null;
        fixture.hotTerms = ['热词重试恢复'];
        await _tap(
          tester,
          find.widgetWithText(TextButton, VideoStrings.retry).first,
        );
        expect(fixture.hotRequests, 2);
        expect(find.text('热词重试恢复'), findsOneWidget);
      } else if (state == '空') {
        expect(
          find.text(IkLibraryRevisionStrings.hotSearchEmpty),
          findsOneWidget,
        );
        expect(
          find.text(IkLibraryRevisionStrings.expandHotSearch),
          findsNothing,
        );
      }
      await tester.enterText(find.byType(TextField), '手动搜索');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(fixture.controller.query, '手动搜索');
      final before = fixture.searchCalls.length;
      await _tap(
        tester,
        find.widgetWithText(TextButton, VideoStrings.loadMore).first,
      );
      expect(fixture.searchCalls.length, before + 1);
      expect(fixture.searchCalls.last.$3, 2);
      fixture.finishPending();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: state);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('S06 浅深六宽三字号完整36组合、四歌单来源三推荐来源及热词全部操作', (tester) async {
    final failures = <String>[];
    var combinations = 0,
        librarySources = 0,
        recommendationSources = 0,
        hotActions = 0;
    for (final brightness in Brightness.values) {
      for (final width in [320.0, 390.0, 720.0, 900.0, 1200.0, 1440.0]) {
        for (final scale in [1.0, 1.25, 1.5]) {
          final label = '${brightness.name} $width/$scale';
          combinations++;
          final fixture = _Fixture(longTerms: true);
          try {
            await _mount(
              tester,
              fixture,
              fixture.library(simplify: true),
              width: width,
              scale: scale,
              brightness: brightness,
            );
            await _tap(
              tester,
              find.byKey(const ValueKey('ik-library-category-playlists')),
            );
            for (final platform in PlatformType.values) {
              await _select(
                tester,
                IkLibraryRevisionStrings.playlistSource,
                platform,
              );
              _expectInside(tester, find.byTooltip('刷新当前歌单'));
              _expectInside(tester, find.byTooltip('新建歌单'));
              expect(
                find.text(_playlist(platform).name).hitTestable(),
                findsOneWidget,
              );
              librarySources++;
            }
            await tester.pumpWidget(const SizedBox.shrink());
            await _mount(
              tester,
              fixture,
              _SearchHost(fixture: fixture, sharedSearch: true),
              width: width,
              scale: scale,
              brightness: brightness,
            );
            expect(_visibleHotTerms(tester).length, 10);
            for (final platform in PlatformType.musicServices) {
              await _select(
                tester,
                IkLibraryRevisionStrings.recommendationPlatform,
                platform,
              );
              final rows = await _allSongRows(tester);
              expect(rows.length, 4);
              expect(
                rows.keys.toSet(),
                _tracks(platform)
                    .take(4)
                    .map((song) => '${song.platform.name}:${song.id}')
                    .toSet(),
              );
              recommendationSources++;
            }
            await _tap(
              tester,
              find.text(IkLibraryRevisionStrings.expandHotSearch),
            );
            expect(_visibleHotTerms(tester), fixture.hotTerms);
            hotActions++;
            await _tap(
              tester,
              find.text(IkLibraryRevisionStrings.collapseHotSearch),
            );
            expect(_visibleHotTerms(tester).length, 10);
            hotActions++;
            expect(tester.takeException(), isNull);
          } catch (error) {
            failures.add('$label: $error');
            tester.takeException();
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
          }
        }
      }
    }
    debugPrint(
      'S06 完整进入 $combinations 组合，完成 $librarySources 歌单来源、$recommendationSources 推荐来源、$hotActions 热词操作，${failures.length} 项失败。',
    );
    expect(combinations, 36);
    expect(failures, isEmpty, reason: failures.join('\n'));
    expect(librarySources, 144);
    expect(recommendationSources, 108);
    expect(hotActions, 72);
  });

  testWidgets('S07 缺省和显式关闭保持旧独立、嵌入歌单及完整热词三平台呈现', (tester) async {
    for (final embedded in [false, true]) {
      final fixture = _Fixture();
      await _mount(
        tester,
        fixture,
        embedded
            ? const PlatformPlaylistsPage.embedded()
            : const PlatformPlaylistsPage(),
      );
      expect(find.byType(TabBar).hitTestable(), findsOneWidget);
      expect(
        _selectFinder(IkLibraryRevisionStrings.playlistSource),
        findsNothing,
      );
      expect(
        find.text('我的歌单').hitTestable(),
        embedded ? findsNWidgets(2) : findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
    final snapshots = <List<String>>[];
    for (final compact in [null, false]) {
      final fixture = _Fixture();
      await _mount(
        tester,
        fixture,
        _SearchHost(fixture: fixture, compact: compact),
      );
      expect(_visibleHotTerms(tester), fixture.hotTerms);
      expect(
        _selectFinder(IkLibraryRevisionStrings.recommendationPlatform),
        findsNothing,
      );
      final rows = await _allSongRows(tester);
      expect(rows.length, 12);
      for (final platform in PlatformType.musicServices) {
        expect(
          rows.values
              .where((song) => song.platform == platform)
              .map((song) => song.id)
              .toSet(),
          _tracks(platform).take(4).map((song) => song.id).toSet(),
        );
      }
      snapshots.add(
        tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data ?? '')
            .toList(),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
    expect(snapshots.last, snapshots.first);
    for (final simplify in [null, false]) {
      final fixture = _Fixture();
      await _mount(tester, fixture, fixture.library(simplify: simplify));
      await _tap(
        tester,
        find.byKey(const ValueKey('ik-library-category-playlists')),
      );
      expect(find.byType(TabBar).hitTestable(), findsOneWidget);
      expect(find.text(IkStrings.playlists), findsNWidgets(3));
      expect(
        _selectFinder(IkLibraryRevisionStrings.playlistSource),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('S08 匿名全局提示和三平台账号入口可达，已知网络错误及旧默认不误归登录', (tester) async {
    const loginPrompt = '请先登录平台账号';
    final fixture = _Fixture(state: '空', loggedIn: false);
    await _mount(
      tester,
      fixture,
      _SearchHost(fixture: fixture, onAccount: fixture.accountRequests.add),
    );
    final emptyState = _recommendationState(tester);
    expect(emptyState.isLoading, isFalse);
    expect(emptyState.totalCount, 0);
    expect(emptyState.errorsByPlatform, isEmpty);
    expect(emptyState.error, loginPrompt);
    for (final platform in PlatformType.musicServices) {
      await _select(
        tester,
        IkLibraryRevisionStrings.recommendationPlatform,
        platform,
      );
      expect(find.text(loginPrompt), findsOneWidget);
      expect(
        find.text(IkDiscoveryRevisionStrings.noRecommendations),
        findsNothing,
      );
      final account = find.widgetWithText(
        TextButton,
        VideoStrings.loginPlatform(videoPlatformLabel(platform)),
      );
      await _tap(tester, account);
      expect(fixture.accountRequests.last, platform);
      for (final other in PlatformType.musicServices.where(
        (candidate) => candidate != platform,
      )) {
        expect(
          find.text(VideoStrings.loginPlatform(videoPlatformLabel(other))),
          findsNothing,
        );
      }
    }
    expect(fixture.accountRequests, PlatformType.musicServices);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());

    final withoutAccount = _Fixture(state: '空', loggedIn: false);
    await _mount(tester, withoutAccount, _SearchHost(fixture: withoutAccount));
    expect(find.text(loginPrompt), findsOneWidget);
    for (final platform in PlatformType.musicServices) {
      expect(
        find.text(VideoStrings.loginPlatform(videoPlatformLabel(platform))),
        findsNothing,
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());

    final network = _Fixture(state: '错误', loggedIn: false);
    await _mount(
      tester,
      network,
      _SearchHost(fixture: network, onAccount: network.accountRequests.add),
    );
    final failedState = _recommendationState(tester);
    expect(failedState.error, loginPrompt);
    expect(failedState.totalCount, 0);
    expect(
      failedState.errorsByPlatform.keys.toSet(),
      PlatformType.musicServices.toSet(),
    );
    for (final platform in PlatformType.musicServices) {
      await _select(
        tester,
        IkLibraryRevisionStrings.recommendationPlatform,
        platform,
      );
      expect(find.text('${platform.name}推荐请求失败'), findsOneWidget);
      expect(find.text(loginPrompt), findsNothing);
      for (final other in PlatformType.musicServices) {
        expect(
          find.text(VideoStrings.loginPlatform(videoPlatformLabel(other))),
          findsNothing,
        );
      }
      final beforeLoads = network.platforms.map(
        (p, implementation) => MapEntry(p, implementation.recommendationLoads),
      );
      network.platforms[platform]!.recommendation = _recommendation(platform);
      await _tap(
        tester,
        find
            .descendant(
              of: find.byType(IkSearchWorkspace),
              matching: find.widgetWithText(TextButton, VideoStrings.retry),
            )
            .last,
      );
      for (final other in PlatformType.musicServices) {
        expect(
          network.platforms[other]!.recommendationLoads,
          beforeLoads[other]! + (other == platform ? 1 : 0),
        );
      }
      expect(find.text('${platform.name}推荐请求失败'), findsNothing);
      expect(find.text(loginPrompt), findsNothing);
    }
    expect(network.accountRequests, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());

    final loading = _Fixture(state: '加载', loggedIn: false);
    await _mount(
      tester,
      loading,
      _SearchHost(fixture: loading, onAccount: loading.accountRequests.add),
      settle: false,
    );
    for (final platform in PlatformType.musicServices) {
      await _select(
        tester,
        IkLibraryRevisionStrings.recommendationPlatform,
        platform,
        settle: false,
      );
      expect(_recommendationState(tester).isLoading, isTrue);
      expect(find.byType(LinearProgressIndicator), findsWidgets);
      expect(find.text(loginPrompt), findsNothing);
      expect(
        find.text(VideoStrings.loginPlatform(videoPlatformLabel(platform))),
        findsNothing,
      );
    }
    loading.finishPending();
    await tester.pumpAndSettle();
    expect(_recommendationState(tester).totalCount, 21);
    expect(_recommendationState(tester).error, isNull);
    expect(find.text(loginPrompt), findsNothing);
    expect(loading.accountRequests, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());

    for (final compact in [null, false]) {
      final legacy = _Fixture(state: '空', loggedIn: false);
      await _mount(
        tester,
        legacy,
        _SearchHost(
          fixture: legacy,
          compact: compact,
          onAccount: legacy.accountRequests.add,
        ),
      );
      expect(_recommendationState(tester).error, loginPrompt);
      expect(find.text(loginPrompt), findsNothing);
      expect(
        find.text(IkDiscoveryRevisionStrings.noRecommendations),
        findsNWidgets(3),
      );
      for (final platform in PlatformType.musicServices) {
        expect(
          find.text(VideoStrings.loginPlatform(videoPlatformLabel(platform))),
          findsNothing,
        );
      }
      expect(legacy.accountRequests, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    }
    expect(tester.takeException(), isNull);
    debugPrint('S08 三平台账号动作、匿名网络重试、加载与公开结果、无回调及两种旧默认全部完成');
  });

  testWidgets('S09 真实通知器超时仅紧凑界面译成中文，同平台重试与非精确值及旧默认保持', (tester) async {
    const timeoutMessage = '推荐加载超时，请重试';
    final fixture = _Fixture(state: '空');
    for (final platform in fixture.platforms.values) {
      platform.recommendationError = TimeoutException('验收中的真实超时异常');
    }
    await _mount(tester, fixture, _SearchHost(fixture: fixture));
    expect(_recommendationState(tester).isLoading, isFalse);
    expect(_recommendationState(tester).errorsByPlatform, {
      for (final platform in PlatformType.musicServices) platform: 'timeout',
    });
    for (final platform in PlatformType.musicServices) {
      await _select(
        tester,
        IkLibraryRevisionStrings.recommendationPlatform,
        platform,
      );
      expect(find.text(timeoutMessage), findsOneWidget);
      expect(find.text('timeout'), findsNothing);
      final source = _recommendationState(tester).sourceForPlatform(platform)!;
      expect(source.platform, platform);
      expect(source.kind, RecommendationKind.unavailable);
      expect(source.note, '请求超时');
      final beforeLoads = fixture.platforms.map(
        (p, implementation) => MapEntry(p, implementation.recommendationLoads),
      );
      final implementation = fixture.platforms[platform]!;
      implementation.recommendationError = null;
      implementation.recommendation = _recommendation(platform);
      await _tap(
        tester,
        find
            .descendant(
              of: find.byType(IkSearchWorkspace),
              matching: find.widgetWithText(TextButton, VideoStrings.retry),
            )
            .last,
      );
      for (final other in PlatformType.musicServices) {
        expect(
          fixture.platforms[other]!.recommendationLoads,
          beforeLoads[other]! + (other == platform ? 1 : 0),
        );
        if (other != platform &&
            fixture.platforms[other]!.recommendationError != null) {
          expect(
            _recommendationState(tester).errorsByPlatform[other],
            'timeout',
          );
        }
      }
      expect(
        _recommendationState(tester).errorsByPlatform.containsKey(platform),
        isFalse,
      );
      expect(find.text(timeoutMessage), findsNothing);
      expect(
        _recommendationState(tester)
            .songsForPlatform(platform)
            .map((song) => '${song.platform.name}:${song.id}'),
        _tracks(platform).map((song) => '${song.platform.name}:${song.id}'),
      );
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());

    const otherError = '服务timeout：请稍后再试';
    final nonExact = _Fixture(state: '空');
    for (final platform in nonExact.platforms.values) {
      platform.recommendation = const RecommendationResult(error: otherError);
    }
    await _mount(tester, nonExact, _SearchHost(fixture: nonExact));
    for (final platform in PlatformType.musicServices) {
      await _select(
        tester,
        IkLibraryRevisionStrings.recommendationPlatform,
        platform,
      );
      expect(find.text(otherError), findsOneWidget);
      expect(find.text(timeoutMessage), findsNothing);
      expect(
        _recommendationState(tester).errorsByPlatform[platform],
        otherError,
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());

    for (final compact in [null, false]) {
      final legacy = _Fixture(state: '空');
      for (final platform in legacy.platforms.values) {
        platform.recommendationError = TimeoutException('旧默认的真实超时异常');
      }
      await _mount(
        tester,
        legacy,
        _SearchHost(fixture: legacy, compact: compact),
      );
      expect(_recommendationState(tester).errorsByPlatform, {
        for (final platform in PlatformType.musicServices) platform: 'timeout',
      });
      expect(find.text('timeout'), findsNWidgets(3));
      expect(find.text(timeoutMessage), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    }
    expect(tester.takeException(), isNull);
    debugPrint('S09 三平台真实超时及原重试、非精确值和两种旧默认全部完成');
  });
}

Future<void> _mount(
  WidgetTester tester,
  _Fixture fixture,
  Widget? page, {
  GoRouter? router,
  double width = 1200,
  double scale = 1,
  Brightness brightness = Brightness.light,
  bool settle = true,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final theme = IkWorkspaceTheme.aligned(ThemeData(brightness: brightness));
  Widget media(BuildContext context, Widget? child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        myPlaylistsProvider.overrideWith(
          (_) => MyPlaylistsNotifier(repository: fixture.repository),
        ),
        platformPlaylistsProvider.overrideWith(
          (_) => PlatformPlaylistsNotifier(
            platformResolver: (p) => fixture.platforms[p]!,
          ),
        ),
        recommendationsProvider.overrideWith(
          (_) => RecommendationsNotifier(
            supportedTypes: PlatformType.musicServices,
            platformResolver: (p) => fixture.platforms[p]!,
          ),
        ),
        shareServiceProvider.overrideWithValue(ShareService(fixture.channel)),
      ],
      child: router == null
          ? MaterialApp(
              theme: theme,
              builder: media,
              home: Scaffold(body: page),
            )
          : MaterialApp.router(
              theme: theme,
              builder: media,
              routerConfig: router,
            ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Finder _selectFinder(String label) =>
    find.byWidgetPredicate((w) => w is IkSelect && w.label == label);
Object? _selectedValue(WidgetTester tester, String label) {
  final select = _selectFinder(label);
  expect(select, findsOneWidget, reason: '$label必须存在后才能读取当前来源');
  return tester.widget<IkSelect>(select).value;
}

RecommendationsState _recommendationState(WidgetTester tester) =>
    ProviderScope.containerOf(
      tester.element(find.byType(_SearchHost)),
      listen: false,
    ).read(recommendationsProvider);

Future<void> _select(
  WidgetTester tester,
  String label,
  Object value, {
  bool settle = true,
}) async {
  final select = _selectFinder(label);
  expect(select, findsOneWidget, reason: '$label必须为可操作来源入口');
  final control = tester.widget<IkSelect>(select);
  final text = control.items[value]!;
  await _tap(
    tester,
    find.descendant(of: select, matching: find.byType(OutlinedButton)),
    settle: settle,
  );
  final option = find.widgetWithText(MenuItemButton, text);
  expect(option, findsOneWidget);
  _expectInside(tester, option);
  await _tap(tester, option, settle: settle);
  expect(_selectedValue(tester, label), value);
}

Future<void> _tap(
  WidgetTester tester,
  Finder target, {
  bool settle = true,
}) async {
  expect(target, findsOneWidget, reason: '目标必须存在后才能真实点击');
  await tester.ensureVisible(target);
  await tester.pump();
  _expectInside(tester, target);
  await tester.tap(target);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 300));
    // 菜单在帧尾触发 onPressed，下一帧才能读到来源的新值；加载动画不等待静止。
    await tester.pump();
  }
}

void _expectInside(WidgetTester tester, Finder target) {
  expect(target.hitTestable(), findsOneWidget);
  final view =
      Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);
  expect(view.contains(tester.getCenter(target)), isTrue);
}

Future<void> _playlistAction(
  WidgetTester tester,
  String name,
  String action,
) async {
  final tile = find.ancestor(
    of: find.text(name).hitTestable(),
    matching: find.byType(ListTile),
  );
  await _tap(
    tester,
    find.descendant(of: tile, matching: find.byType(PopupMenuButton<String>)),
  );
  await _tap(tester, find.text(action));
}

List<String> _visibleHotTerms(WidgetTester tester) => tester
    .widgetList<ActionChip>(find.byType(ActionChip))
    .map((w) => (w.label as Text).data!)
    .toList();

Future<Map<String, Song>> _allSongRows(WidgetTester tester) async {
  final scrollable = find
      .descendant(
        of: find.byType(IkSearchWorkspace),
        matching: find.byType(Scrollable),
      )
      .first;
  final position = tester.state<ScrollableState>(scrollable).position;
  final songs = <String, Song>{};
  position.jumpTo(0);
  await tester.pumpAndSettle();
  while (true) {
    for (final row in tester.widgetList<IkSongTableRow>(
      find.byType(IkSongTableRow),
    )) {
      songs['${row.song.platform.name}:${row.song.id}'] = row.song;
    }
    if (position.pixels >= position.maxScrollExtent) break;
    final next = (position.pixels + position.viewportDimension / 2).clamp(
      0.0,
      position.maxScrollExtent,
    );
    position.jumpTo(next);
    await tester.pumpAndSettle();
  }
  return songs;
}

Playlist _playlist(PlatformType platform) => Playlist(
  id: '${platform.name}_原始ID',
  editId: '${platform.name}_编辑ID',
  name: '${platform.name}已有歌单',
  platform: platform,
  songCount: 7,
  editable: true,
);
List<Song> _tracks(PlatformType platform) => [
  for (var index = 0; index < 7; index++)
    Song(
      id: '${platform.name}_$index',
      platform: platform,
      name: '${platform.name}推荐曲目$index',
      artists: const [Artist(id: '真实歌手ID', name: '歌手名字')],
      duration: const Duration(minutes: 3),
    ),
];

RecommendationResult _recommendation(PlatformType platform) =>
    RecommendationResult(
      songs: _tracks(platform),
      source: RecommendationSource(
        platform: platform,
        kind: switch (platform) {
          PlatformType.netease => RecommendationKind.personalizedDaily,
          PlatformType.qq => RecommendationKind.fallbackToplist,
          _ => RecommendationKind.fallbackHomepage,
        },
        label: '原来源',
        note: platform == PlatformType.netease
            ? null
            : '${platform.name}公开回退来源',
      ),
    );

class _Fixture {
  _Fixture({String state = '数据', bool longTerms = false, bool loggedIn = true})
    : hotTerms = state == '空'
          ? []
          : [
              for (var i = 1; i <= 30; i++)
                '热词${i.toString().padLeft(2, '0')}${longTerms ? '很长的歌手和歌曲查询名称' : ''}',
            ],
      hotError = state == '错误'
          ? const VideoFailure(
              VideoFailureKind.network,
              '热词请求失败',
              canRetry: true,
            )
          : null,
      hotPending = state == '加载' ? Completer<List<String>>() : null {
    for (final platform in PlatformType.musicServices) {
      final implementation = _Platform(platform, loggedIn: loggedIn);
      if (state == '错误') {
        implementation.recommendation = RecommendationResult(
          error: '${platform.name}推荐请求失败',
        );
      }
      if (state == '空') {
        implementation.recommendation = const RecommendationResult();
      }
      if (state == '加载') {
        implementation.pending = Completer<RecommendationResult>();
      }
      platforms[platform] = implementation;
      registerFake(implementation);
    }
    controller = IkSearchController(
      search: (platform, query, page) async {
        searchCalls.add((platform, query, page));
        return VideoPage(
          songs: [
            Song(
              id: '${platform.name}_搜索$page',
              platform: platform,
              name: '${platform.name}搜索曲目$page',
              artists: const [],
            ),
          ],
          page: page,
          hasMore: page == 1,
          total: 2,
        );
      },
    );
    addTearDown(controller.dispose);
  }
  final repository = _MemoryPlaylists();
  final channel = _ShareChannel();
  final platforms = <PlatformType, _Platform>{};
  final searchCalls = <(PlatformType, String, int)>[];
  final accountRequests = <PlatformType>[];
  late final IkSearchController controller;
  List<String> hotTerms;
  VideoFailure? hotError;
  final Completer<List<String>>? hotPending;
  var hotRequests = 0, browseRequests = 0;
  (Song, List<Song>)? played;
  Song? more;
  Set<PlatformType> get loggedInPlatforms => {
    for (final entry in platforms.entries)
      if (entry.value.isLoggedIn) entry.key,
  };

  Future<List<String>> loadHot() async {
    hotRequests++;
    if (hotError case final error?) throw error;
    return hotPending == null ? hotTerms : hotPending!.future;
  }

  int loads(PlatformType p) =>
      p == PlatformType.local ? repository.loads : platforms[p]!.playlistLoads;
  int creates(PlatformType p) => p == PlatformType.local
      ? repository.created.length
      : platforms[p]!.created.length;
  void finishPending() {
    if (hotPending != null && !hotPending!.isCompleted) {
      hotPending!.complete(hotTerms);
    }
    for (final p in platforms.values) {
      if (p.pending != null && !p.pending!.isCompleted) {
        p.pending!.complete(p.recommendation);
      }
    }
  }

  Widget library({bool? simplify}) {
    if (simplify == null) {
      return IkLibraryWorkspace(
        alignToDesign: true,
        libraries: const {},
        syncing: const {},
        loggedIn: const {},
        onSync: (_) {},
        onPlay: (_, _) {},
        onMore: (_) {},
        onNavigate: (_) {},
        onDownloads: () {},
        onAccounts: () {},
        onRetryLocal: () {},
        localLikes: const [],
        localLoading: false,
        downloadsBuilder: (_) => const Text('原下载内容'),
      );
    }
    return IkLibraryWorkspace(
      alignToDesign: true,
      simplifySources: simplify,
      libraries: const {},
      syncing: const {},
      loggedIn: const {},
      onSync: (_) {},
      onPlay: (_, _) {},
      onMore: (_) {},
      onNavigate: (_) {},
      onDownloads: () {},
      onAccounts: () {},
      onRetryLocal: () {},
      localLikes: const [],
      localLoading: false,
      downloadsBuilder: (_) => const Text('原下载内容'),
    );
  }
}

class _SearchHost extends ConsumerStatefulWidget {
  const _SearchHost({
    required this.fixture,
    this.compact = true,
    this.sharedSearch = false,
    this.onAccount,
  });
  final _Fixture fixture;
  final bool? compact;
  final bool sharedSearch;
  final ValueChanged<PlatformType>? onAccount;
  @override
  ConsumerState<_SearchHost> createState() => _SearchHostState();
}

class _SearchHostState extends ConsumerState<_SearchHost> {
  List<String> _terms = [];
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadHot());
      unawaited(
        ref.read(recommendationsProvider.notifier).loadLatestRecommendations(),
      );
    });
  }

  Future<void> _loadHot() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final terms = await widget.fixture.loadHot();
      if (mounted) setState(() => _terms = terms);
    } catch (error) {
      if (mounted) setState(() => _error = VideoFailure.from(error).message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fixture = widget.fixture;
    final recommendations = ref.watch(recommendationsProvider);
    if (widget.compact == null) {
      return IkSearchWorkspace(
        search: fixture.controller,
        alignToDesign: true,
        useSharedSearch: widget.sharedSearch,
        onPlay: (song, songs) => fixture.played = (song, songs),
        onMore: (song) => fixture.more = song,
        onLike: (_) {},
        onAccount: widget.onAccount,
        hotTerms: _terms,
        hotLoading: _loading,
        hotError: _error,
        onRetryHot: () => unawaited(_loadHot()),
        recommendations: recommendations,
        loggedIn: fixture.loggedInPlatforms,
        onBrowseRecommendations: () => fixture.browseRequests++,
        onRetryRecommendation: (p) => unawaited(
          ref.read(recommendationsProvider.notifier).retryLatestPlatform(p),
        ),
      );
    }
    return IkSearchWorkspace(
      search: fixture.controller,
      alignToDesign: true,
      compactDiscovery: widget.compact!,
      useSharedSearch: widget.sharedSearch,
      onPlay: (song, songs) => fixture.played = (song, songs),
      onMore: (song) => fixture.more = song,
      onLike: (_) {},
      onAccount: widget.onAccount,
      hotTerms: _terms,
      hotLoading: _loading,
      hotError: _error,
      onRetryHot: () => unawaited(_loadHot()),
      recommendations: recommendations,
      loggedIn: fixture.loggedInPlatforms,
      onBrowseRecommendations: () => fixture.browseRequests++,
      onRetryRecommendation: (p) => unawaited(
        ref.read(recommendationsProvider.notifier).retryLatestPlatform(p),
      ),
    );
  }
}

class _Platform extends FakeContentPlatform {
  _Platform(PlatformType platform, {super.loggedIn = true})
    : recommendation = _recommendation(platform),
      playlists = [_playlist(platform)],
      super(type: platform);
  RecommendationResult recommendation;
  Object? recommendationError;
  Completer<RecommendationResult>? pending;
  final List<Playlist> playlists;
  var playlistLoads = 0, recommendationLoads = 0;
  final created = <String>[];
  final renamed = <(String, String)>[];
  final deleted = <String>[];
  final songLoads = <String>[];
  @override
  bool get supportsDailyRecommendations => true;
  @override
  Future<RecommendationResult> getDailyRecommendation() async {
    recommendationLoads++;
    if (recommendationError case final error?) throw error;
    return pending == null ? recommendation : pending!.future;
  }

  @override
  Future<List<Playlist>> getUserPlaylists() async {
    playlistLoads++;
    return List.of(playlists);
  }

  @override
  Future<Playlist?> createPlaylist(String name) async {
    created.add(name);
    return Playlist(
      id: '${type.name}_新增${created.length}',
      platform: type,
      name: name,
    );
  }

  @override
  Future<List<Song>> getPlaylistDetail(String playlistId) async {
    songLoads.add(playlistId);
    return _tracks(type);
  }

  @override
  Future<bool> renamePlaylist(String id, String name) async {
    renamed.add((id, name));
    final index = playlists.indexWhere((p) => p.editableId == id);
    final old = playlists[index];
    playlists[index] = Playlist(
      id: old.id,
      editId: old.editId,
      name: name,
      platform: type,
      songCount: old.songCount,
      editable: true,
    );
    return true;
  }

  @override
  Future<bool> deletePlaylist(String id) async {
    deleted.add(id);
    playlists.removeWhere((p) => p.editableId == id);
    return true;
  }
}

class _MemoryPlaylists extends MyPlaylistsRepository {
  final playlists = [_playlist(PlatformType.local)];
  var loads = 0;
  final created = <String>[];
  final deleted = <String>[];
  final imported = <List<Song>>[];
  @override
  Future<List<Playlist>> getPlaylists() async {
    loads++;
    return List.of(playlists);
  }

  @override
  Future<Playlist> createPlaylist(String name) async {
    created.add(name);
    final playlist = Playlist(
      id: '本机新增${created.length}',
      platform: PlatformType.local,
      name: name,
    );
    playlists.add(playlist);
    return playlist;
  }

  @override
  Future<Playlist> importPlaylist({
    required String name,
    required List<Song> songs,
  }) async {
    imported.add(List.of(songs));
    return createPlaylist(name);
  }

  @override
  Future<List<Song>> getSongs(String playlistId) async =>
      _tracks(PlatformType.local);
  @override
  Future<String?> exportPlaylistLink(String playlistId) async =>
      'mconnect://playlist?data=source_identity';
  @override
  Future<bool> deletePlaylist(String playlistId) async {
    deleted.add(playlistId);
    playlists.removeWhere((p) => p.id == playlistId);
    return true;
  }
}

class _ShareChannel implements ShareChannel {
  final texts = <String>[];
  @override
  Future<void> shareText(String text, {String? subject, Rect? origin}) async =>
      texts.add(text);
  @override
  Future<void> shareFiles(
    List<String> paths, {
    String? subject,
    String? text,
    Rect? origin,
  }) async {}
}

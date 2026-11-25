import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/discovery/presentation/providers/recommendations_provider.dart';
import 'package:mconnect/l10n/ik_discovery_revision_strings.dart';
import 'package:mconnect/l10n/ik_library_revision_strings.dart';
import 'package:mconnect/l10n/ik_page_revision_strings.dart';
import 'package:mconnect/l10n/video_strings.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/recommendation_source.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/video_app/data/video_catalog.dart';
import 'package:mconnect/video_app/ik/ik_controls.dart';
import 'package:mconnect/video_app/ik/ik_search.dart';
import 'package:mconnect/video_app/ik/ik_search_workspace.dart';
import 'package:mconnect/video_app/ik/ik_song_table.dart';
import 'package:mconnect/video_app/ik/ik_workspace_theme.dart';
import 'package:mconnect/video_app/ui/catalog_pages.dart';

void main() {
  for (final platform in PlatformType.musicServices) {
    testWidgets('E01 ${platform.name}加载空态错误与重试只影响当前平台', (tester) async {
      final search = _searchController();
      addTearDown(search.dispose);
      RecommendationsState state = const RecommendationsState(isLoading: true);
      late StateSetter update;
      PlatformType? retried;
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return _workspace(
                search,
                fullRecommendations: true,
                recommendations: state,
                onRetry: (value) => retried = value,
              );
            },
          ),
        ),
      );
      await tester.pump();
      await _selectRecommendationPlatform(tester, platform, settle: false);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '播放全部'))
            .onPressed,
        isNull,
      );
      update(() => state = const RecommendationsState());
      await tester.pumpAndSettle();
      expect(find.text('暂无推荐歌曲'), findsOneWidget);
      update(
        () => state = RecommendationsState(
          errorsByPlatform: {platform: 'timeout'},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('推荐加载超时，请重试'), findsOneWidget);
      await tester.tap(find.text('重试'));
      expect(retried, platform);
      update(() => state = _recommendations());
      await tester.pumpAndSettle();
      expect(find.text('推荐加载超时，请重试'), findsNothing);
      expect(find.text('${platform.displayName}歌曲01'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('E01 全局失败保留登录入口，匿名每日来源不冒充个人', (tester) async {
    final search = _searchController();
    addTearDown(search.dispose);
    PlatformType? requested;
    await tester.pumpWidget(
      _app(
        _workspace(
          search,
          fullRecommendations: true,
          recommendations: const RecommendationsState(error: '请登录后获取推荐'),
          onAccount: (platform) => requested = platform,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('请登录后获取推荐'), findsOneWidget);
    await tester.tap(
      find.text(
        VideoStrings.loginPlatform(videoPlatformLabel(PlatformType.netease)),
      ),
    );
    expect(requested, PlatformType.netease);
    await tester.pumpWidget(
      _app(_workspace(search, fullRecommendations: true)),
    );
    await tester.pumpAndSettle();
    expect(find.text('每日推荐'), findsNothing);
    expect(find.text('平台推荐'), findsWidgets);
  });

  for (final dark in [false, true]) {
    for (final width in [320.0, 390.0, 720.0, 900.0, 1200.0, 1440.0, 1920.0]) {
      for (final scale in [1.0, 1.25, 1.5]) {
        testWidgets('E01 ${dark ? '深' : '浅'}宽$width字号$scale三平台列表无溢出', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 960);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final search = _searchController();
          addTearDown(search.dispose);
          await tester.pumpWidget(
            MaterialApp(
              theme: IkWorkspaceTheme.aligned(
                ThemeData(
                  brightness: dark ? Brightness.dark : Brightness.light,
                ),
              ),
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 960),
                  textScaler: TextScaler.linear(scale),
                ),
                child: Scaffold(
                  body: _workspace(
                    search,
                    fullRecommendations: true,
                    hotTerms: [for (var i = 1; i <= 11; i++) '很长的热门关键词$i'],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          for (final platform in PlatformType.musicServices) {
            await _selectRecommendationPlatform(tester, platform);
            expect(find.text('共 31 首'), findsOneWidget);
            expect(
              find.widgetWithText(TextButton, '播放全部').hitTestable(),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull, reason: platform.name);
          }
        });
      }
    }
  }

  testWidgets('E01 full=true 搜索空态显示完整来源列表并用完整顺序播放', (tester) async {
    final search = _searchController();
    addTearDown(search.dispose);
    List<Song>? playedSongs;
    Song? playedSong;
    await tester.pumpWidget(
      _app(
        _workspace(
          search,
          fullRecommendations: true,
          loggedIn: const {PlatformType.netease},
          onBrowseRecommendations: () {},
          onPlay: (song, songs) {
            playedSong = song;
            playedSongs = songs;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(IkLibraryRevisionStrings.browseRecommendations),
      findsNothing,
    );
    expect(find.byType(IkSongTableHeader), findsOneWidget);
    expect(
      find.text(IkPageRevisionStrings.platformRecommendations),
      findsOneWidget,
    );
    expect(
      find.text(IkPageRevisionStrings.recommendationCount(31)),
      findsOneWidget,
    );
    expect(
      find.text(IkDiscoveryRevisionStrings.dailyRecommendation),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text(IkPageRevisionStrings.playAll));
    await tester.tap(find.text(IkPageRevisionStrings.playAll));
    await tester.pump();
    expect(playedSong?.id, 'netease-01');
    expect(
      playedSongs?.map((song) => song.id).toList(),
      _ids(PlatformType.netease),
    );

    await tester.scrollUntilVisible(
      find.widgetWithText(IkSongTableRow, '网易云音乐歌曲31'),
      320,
      scrollable: find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('网易云音乐歌曲31'), findsOneWidget);
    await tester.tap(find.widgetWithText(IkSongTableRow, '网易云音乐歌曲31'));
    await tester.pump();
    expect(playedSong?.id, 'netease-31');
    expect(
      playedSongs?.map((song) => song.id).toList(),
      _ids(PlatformType.netease),
    );

    _scrollPosition(tester).jumpTo(0);
    await tester.pumpAndSettle();
    await _selectRecommendationPlatform(tester, PlatformType.qq);
    expect(
      find.text(IkDiscoveryRevisionStrings.toplistRecommendation),
      findsOneWidget,
    );
    expect(
      find.text(IkPageRevisionStrings.recommendationCount(31)),
      findsOneWidget,
    );
    expect(find.text('QQ音乐歌曲01'), findsOneWidget);
    expect(find.text('网易云音乐歌曲01'), findsNothing);
    await tester.tap(find.text(IkPageRevisionStrings.playAll));
    await tester.pump();
    expect(playedSong?.id, 'qq-01');
    expect(playedSongs?.map((song) => song.id).toList(), _ids(PlatformType.qq));
    await tester.scrollUntilVisible(
      find.widgetWithText(IkSongTableRow, 'QQ音乐歌曲31'),
      320,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(find.widgetWithText(IkSongTableRow, 'QQ音乐歌曲31'));
    await tester.pump();
    expect(playedSong?.id, 'qq-31');
    expect(playedSongs?.map((song) => song.id).toList(), _ids(PlatformType.qq));

    _scrollPosition(tester).jumpTo(0);
    await tester.pumpAndSettle();
    await _selectRecommendationPlatform(tester, PlatformType.kugou);
    expect(
      find.text(IkDiscoveryRevisionStrings.homepageRecommendation),
      findsOneWidget,
    );
    await tester.tap(find.text(IkPageRevisionStrings.playAll));
    await tester.pump();
    expect(playedSong?.id, 'kugou-01');
    expect(
      playedSongs?.map((song) => song.id).toList(),
      _ids(PlatformType.kugou),
    );
    await tester.scrollUntilVisible(
      find.widgetWithText(IkSongTableRow, '酷狗音乐歌曲31'),
      320,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('酷狗音乐歌曲31'), findsOneWidget);
    await tester.tap(find.widgetWithText(IkSongTableRow, '酷狗音乐歌曲31'));
    await tester.pump();
    expect(playedSong?.id, 'kugou-31');
    expect(
      playedSongs?.map((song) => song.id).toList(),
      _ids(PlatformType.kugou),
    );
  });

  testWidgets('E01 缺省仍只显示四首并保留查看全部推荐', (tester) async {
    final search = _searchController();
    addTearDown(search.dispose);
    await tester.pumpWidget(
      _app(_workspace(search, onBrowseRecommendations: () {})),
    );
    await tester.pumpAndSettle();

    expect(find.byType(IkSongTableRow), findsNWidgets(4));
    expect(find.text('网易云音乐歌曲04'), findsOneWidget);
    expect(find.text('网易云音乐歌曲05'), findsNothing);
    expect(
      find.text(IkLibraryRevisionStrings.browseRecommendations),
      findsOneWidget,
    );
  });

  testWidgets('E01 搜索结果与推荐各自恢复滚动位置并保留热词展开和推荐平台', (tester) async {
    final search = _searchController(platforms: const [PlatformType.netease]);
    addTearDown(search.dispose);
    await tester.pumpWidget(
      _app(
        _withSharedSearch(
          search,
          fullRecommendations: true,
          hotTerms: [for (var i = 1; i <= 11; i++) '热词$i'],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(IkLibraryRevisionStrings.expandHotSearch));
    await tester.pumpAndSettle();
    await _selectRecommendationPlatform(tester, PlatformType.qq);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1000));
    await tester.pumpAndSettle();
    final recommendationOffset = _scrollOffset(tester);
    expect(recommendationOffset, greaterThan(0));

    await tester.enterText(find.byKey(const Key('shared-search-field')), '查询');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('netease-结果01'), findsOneWidget);
    expect(
      find.byType(IkSelect<String>),
      findsOneWidget,
      reason: '仅搜索结果显示来源筛选',
    );
    expect(_scrollOffset(tester), lessThan(recommendationOffset));

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -520));
    await tester.pumpAndSettle();
    final resultOffset = _scrollOffset(tester);
    expect(resultOffset, greaterThan(0));

    await tester.enterText(find.byKey(const Key('shared-search-field')), '');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(_scrollOffset(tester), closeTo(recommendationOffset, 2));
    _scrollPosition(tester).jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('热词11'), findsOneWidget);
    expect(find.text('QQ音乐歌曲01'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('shared-search-field')), '查询');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(_scrollOffset(tester), closeTo(resultOffset, 2));
  });

  testWidgets('E01 同一查询真实等待500毫秒后恢复原结果滚动位置', (tester) async {
    final pendingReload = Completer<VideoPage>();
    final result = VideoPage(
      songs: _songs(PlatformType.netease),
      page: 1,
      total: 31,
      hasMore: false,
    );
    var requestCount = 0;
    final search = IkSearchController(
      platforms: const [PlatformType.netease],
      search: (platform, query, page) {
        expect(platform, PlatformType.netease);
        expect(query, '延迟重查');
        expect(page, 1);
        requestCount++;
        return requestCount == 2 ? pendingReload.future : Future.value(result);
      },
    );
    addTearDown(search.dispose);
    await tester.pumpWidget(
      _app(_withSharedSearch(search, fullRecommendations: true)),
    );
    await tester.pumpAndSettle();

    final input = find.byKey(const Key('shared-search-field'));
    await tester.enterText(input, '延迟重查');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(requestCount, 1);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();
    final resultOffset = _scrollOffset(tester);
    expect(resultOffset, greaterThan(500));

    await tester.enterText(input, '');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(search.query, isEmpty);
    await tester.enterText(input, '延迟重查');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(requestCount, 2);
    expect(pendingReload.isCompleted, isFalse);
    expect(search.groups[PlatformType.netease]!.loading, isTrue);
    expect(search.groups[PlatformType.netease]!.songs, isEmpty);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    pendingReload.complete(result);
    await tester.pumpAndSettle();
    expect(search.groups[PlatformType.netease]!.loading, isFalse);
    expect(search.groups[PlatformType.netease]!.songs, hasLength(31));
    expect(
      _scrollOffset(tester),
      closeTo(resultOffset, 2),
      reason: '真实网络等待产生的短加载态不得丢失同一查询的已保存滚动位置',
    );
    expect(tester.takeException(), isNull);
  });

  for (final scenario in [
    (sameQuery: false, failLast: false),
    (sameQuery: true, failLast: true),
  ]) {
    testWidgets(
      'E01 三平台分批返回${scenario.sameQuery ? '同查询恢复' : '新查询'}中途拖动后末平台${scenario.failLast ? '失败' : '成功'}不抢回位置',
      (tester) async {
        final pending = {
          for (final platform in PlatformType.musicServices)
            platform: Completer<VideoPage>(),
        };
        VideoPage result(PlatformType platform) => VideoPage(
          songs: _songs(platform),
          page: 1,
          total: 31,
          hasMore: false,
        );
        var stagedLoading = !scenario.sameQuery;
        var requestCount = 0;
        final search = IkSearchController(
          platforms: PlatformType.musicServices,
          search: (platform, query, page) {
            expect(query, '分批返回');
            expect(page, 1);
            requestCount++;
            return stagedLoading
                ? pending[platform]!.future
                : Future.value(result(platform));
          },
        );
        addTearDown(search.dispose);
        await tester.pumpWidget(
          _app(_withSharedSearch(search, fullRecommendations: true)),
        );
        await tester.pumpAndSettle();
        final input = find.byKey(const Key('shared-search-field'));
        var savedOffset = 0.0;
        if (scenario.sameQuery) {
          await tester.enterText(input, '分批返回');
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await tester.pumpAndSettle();
          await tester.drag(
            find.byType(CustomScrollView),
            const Offset(0, -1200),
          );
          await tester.pumpAndSettle();
          savedOffset = _scrollOffset(tester);
          expect(savedOffset, greaterThan(900));
          await tester.enterText(input, '');
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await tester.pumpAndSettle();
          stagedLoading = true;
        }

        await tester.enterText(input, '分批返回');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pump();
        expect(requestCount, scenario.sameQuery ? 6 : 3);
        expect(search.groups.values.every((group) => group.loading), isTrue);
        pending[PlatformType.netease]!.complete(result(PlatformType.netease));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(search.groups[PlatformType.netease]!.songs, hasLength(31));
        expect(search.groups[PlatformType.qq]!.loading, isTrue);
        expect(search.groups[PlatformType.kugou]!.loading, isTrue);
        pending[PlatformType.qq]!.complete(result(PlatformType.qq));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(search.groups[PlatformType.qq]!.songs, hasLength(31));

        await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 16));
        final readingOffset = _scrollOffset(tester);
        expect(readingOffset, greaterThan(400));
        expect((readingOffset - savedOffset).abs(), greaterThan(200));
        expect(search.groups[PlatformType.kugou]!.loading, isTrue);
        expect(pending[PlatformType.kugou]!.isCompleted, isFalse);

        if (scenario.failLast) {
          pending[PlatformType.kugou]!.completeError(
            const VideoFailure(
              VideoFailureKind.network,
              '末平台网络失败',
              canRetry: true,
            ),
          );
        } else {
          pending[PlatformType.kugou]!.complete(result(PlatformType.kugou));
        }
        await tester.pumpAndSettle();
        expect(search.groups.values.any((group) => group.loading), isFalse);
        expect(search.groups[PlatformType.netease]!.songs, hasLength(31));
        expect(search.groups[PlatformType.qq]!.songs, hasLength(31));
        if (scenario.failLast) {
          expect(
            search.groups[PlatformType.kugou]!.error?.kind,
            VideoFailureKind.network,
          );
          expect(search.groups[PlatformType.kugou]!.songs, isEmpty);
        } else {
          expect(search.groups[PlatformType.kugou]!.songs, hasLength(31));
        }
        expect(
          _scrollOffset(tester),
          closeTo(readingOffset, 2),
          reason: '用户在部分结果中主动拖动后，末平台完成不得跳回待恢复位置',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

List<String> _ids(PlatformType platform) => [
  for (var index = 1; index <= 31; index++)
    '${platform.name}-${index.toString().padLeft(2, '0')}',
];

List<Song> _songs(PlatformType platform) => [
  for (var index = 1; index <= 31; index++)
    Song(
      id: '${platform.name}-${index.toString().padLeft(2, '0')}',
      platform: platform,
      name: '${platform.displayName}歌曲${index.toString().padLeft(2, '0')}',
      artists: const [],
      duration: const Duration(minutes: 3),
    ),
];

RecommendationsState _recommendations() => RecommendationsState(
  songsByPlatform: {
    for (final platform in PlatformType.musicServices)
      platform: _songs(platform),
  },
  sourceByPlatform: {
    for (final platform in PlatformType.musicServices)
      platform: RecommendationSource(
        platform: platform,
        kind: switch (platform) {
          PlatformType.qq => RecommendationKind.fallbackToplist,
          PlatformType.kugou => RecommendationKind.fallbackHomepage,
          _ => RecommendationKind.personalizedDaily,
        },
        label: switch (platform) {
          PlatformType.netease => '每日推荐',
          PlatformType.qq => '新歌榜',
          PlatformType.kugou => '酷狗推荐',
          PlatformType.local => '本地',
        },
        note: switch (platform) {
          PlatformType.qq => '未登录，已回退到新歌榜',
          PlatformType.kugou => '官方推荐接口已不可用，来源为首页推荐',
          _ => null,
        },
      ),
  },
);

IkSearchController _searchController({
  List<PlatformType> platforms = PlatformType.musicServices,
}) => IkSearchController(
  platforms: platforms,
  search: (platform, query, page) async => VideoPage(
    songs: [
      for (var index = 1; index <= 15; index++)
        Song(
          id: '${platform.name}-result-${index.toString().padLeft(2, '0')}',
          platform: platform,
          name: '${platform.name}-结果${index.toString().padLeft(2, '0')}',
          artists: const [],
        ),
    ],
    page: page,
    total: 15,
    hasMore: false,
  ),
);

Widget _workspace(
  IkSearchController search, {
  bool fullRecommendations = false,
  Set<PlatformType> loggedIn = const {},
  VoidCallback? onBrowseRecommendations,
  List<String> hotTerms = const [],
  void Function(Song, List<Song>)? onPlay,
  RecommendationsState? recommendations,
  ValueChanged<PlatformType>? onRetry,
  ValueChanged<PlatformType>? onAccount,
}) => IkSearchWorkspace(
  alignToDesign: true,
  compactDiscovery: true,
  useSharedSearch: true,
  fullRecommendations: fullRecommendations,
  search: search,
  onPlay: onPlay ?? (_, _) {},
  onLike: (_) {},
  onMore: (_) {},
  hotTerms: hotTerms,
  recommendations: recommendations ?? _recommendations(),
  onRetryRecommendation: onRetry,
  onAccount: onAccount,
  loggedIn: loggedIn,
  onBrowseRecommendations: onBrowseRecommendations,
);

Widget _withSharedSearch(
  IkSearchController search, {
  bool fullRecommendations = false,
  List<String> hotTerms = const [],
}) => Column(
  children: [
    TextField(
      key: const Key('shared-search-field'),
      textInputAction: TextInputAction.search,
      onSubmitted: search.submit,
    ),
    Expanded(
      child: _workspace(
        search,
        fullRecommendations: fullRecommendations,
        hotTerms: hotTerms,
      ),
    ),
  ],
);

Widget _app(Widget body) => MaterialApp(
  home: Scaffold(body: SizedBox.expand(child: body)),
);

ScrollPosition _scrollPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

double _scrollOffset(WidgetTester tester) => _scrollPosition(tester).pixels;

Future<void> _selectRecommendationPlatform(
  WidgetTester tester,
  PlatformType platform, {
  bool settle = true,
}) async {
  final selector = find.byWidgetPredicate(
    (widget) =>
        widget is IkSelect<PlatformType> &&
        widget.label == IkLibraryRevisionStrings.recommendationPlatform,
  );
  await tester.ensureVisible(selector);
  await tester.tap(selector);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(
    find.widgetWithText(MenuItemButton, videoPlatformLabel(platform)),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

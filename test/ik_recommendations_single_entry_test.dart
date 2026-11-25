import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/auth/presentation/providers/auth_provider.dart';
import 'package:mconnect/features/discovery/presentation/providers/recommendations_provider.dart';
import 'package:mconnect/features/player/data/playback_keep_alive_service.dart';
import 'package:mconnect/features/player/data/playback_notification_service.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/l10n/ik_library_revision_strings.dart';
import 'package:mconnect/l10n/ik_personal_daily_strings.dart';
import 'package:mconnect/l10n/ik_workspace_strings.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/recommendation_source.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/video_app/data/video_catalog.dart';
import 'package:mconnect/video_app/ik/ik_controls.dart';
import 'package:mconnect/video_app/ik/ik_home_page.dart';
import 'package:mconnect/video_app/ik/ik_search.dart';
import 'package:mconnect/video_app/ik/ik_search_workspace.dart';
import 'package:mconnect/video_app/ik/ik_song_table.dart';
import 'package:mconnect/video_app/ik/ik_workspace_theme.dart';

import 'support/content_page_fakes.dart' show IdleAudioController;

// E10 正式长期门：个人日推只保留发现入口，公开回退不冒充个人列表。
void main() {
  testWidgets('E10 新搜索只留热搜，推荐数据与失败都不重复展示', (tester) async {
    final search = _search();
    addTearDown(search.dispose);
    var recommendationRetries = 0;
    var browse = 0;
    await _mount(
      tester,
      _searchPage(
        search,
        state: _mixed().copyWith(
          errorsByPlatform: const {PlatformType.netease: '旧推荐失败'},
          error: () => '旧推荐全局失败',
        ),
        onRetryRecommendation: (_) => recommendationRetries++,
        onBrowse: () => browse++,
      ),
    );
    expect(find.text('热门搜索'), findsOneWidget);
    expect(find.text('夏日'), findsOneWidget);
    expect(find.byType(IkSongTableRow), findsNothing);
    expect(find.byType(IkSelect<PlatformType>), findsNothing);
    expect(find.byType(IkSelect<String>), findsNothing);
    expect(find.text('平台推荐'), findsNothing);
    expect(
      find.text(IkLibraryRevisionStrings.recommendationSelection),
      findsNothing,
    );
    expect(find.text('旧推荐失败'), findsNothing);
    expect(find.text('旧推荐全局失败'), findsNothing);
    expect(
      find.text(IkLibraryRevisionStrings.browseRecommendations),
      findsNothing,
    );
    expect(recommendationRetries, 0);
    expect(browse, 0);
  });

  testWidgets('E10 热词搜索仍返回真实结果和队列，清空回热搜', (tester) async {
    final search = _search();
    addTearDown(search.dispose);
    List<Song>? queue;
    Song? selected;
    await _mount(
      tester,
      _searchPage(
        search,
        onPlay: (song, songs) {
          selected = song;
          queue = songs;
        },
      ),
    );
    await tester.tap(find.text('夏日'));
    await tester.pumpAndSettle();
    expect(search.query, '夏日');
    expect(find.text('夏日-结果1'), findsOneWidget);
    expect(find.byType(IkSelect<String>), findsOneWidget);
    expect(find.text('热门搜索'), findsNothing);
    await tester.tap(find.widgetWithText(IkSongTableRow, '夏日-结果1'));
    expect(selected?.id, 'result-1');
    expect(queue?.map((song) => song.id), ['result-1', 'result-2']);
    await search.submit('');
    await tester.pumpAndSettle();
    expect(find.text('热门搜索'), findsOneWidget);
    expect(find.byType(IkSelect<String>), findsNothing);
    expect(find.byType(IkSongTableRow), findsNothing);
  });

  for (final full in [false, true]) {
    for (final compact in [false, true]) {
      testWidgets('E10 独立开关full=$full compact=$compact始终只在结果态显示筛选', (
        tester,
      ) async {
        final search = _search();
        addTearDown(search.dispose);
        await _mount(
          tester,
          _searchPage(
            search,
            fullRecommendations: full,
            compactDiscovery: compact,
          ),
        );
        expect(find.text('热门搜索'), findsOneWidget);
        expect(find.byType(IkSelect<String>), findsNothing);
        expect(find.byType(IkSelect<PlatformType>), findsNothing);
        expect(find.byType(IkSongTableRow), findsNothing);
        await tester.tap(find.text('夏日'));
        await tester.pumpAndSettle();
        expect(find.text('夏日-结果1'), findsOneWidget);
        expect(find.byType(IkSelect<String>), findsOneWidget);
        expect(find.byType(IkSelect<PlatformType>), findsNothing);
        await search.submit('');
        await tester.pumpAndSettle();
        expect(find.text('热门搜索'), findsOneWidget);
        expect(find.byType(IkSelect<String>), findsNothing);
        expect(find.byType(IkSongTableRow), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('E10 热搜加载失败重试和空态仍分别可见', (tester) async {
    final search = _search();
    addTearDown(search.dispose);
    var retries = 0;
    var loading = true;
    String? error;
    late StateSetter update;
    await _mount(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return _searchPage(
            search,
            hotTerms: const [],
            hotLoading: loading,
            hotError: error,
            onRetryHot: () => retries++,
          );
        },
      ),
      settle: false,
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    update(() {
      loading = false;
      error = '热搜暂时不可用';
    });
    await tester.pumpAndSettle();
    expect(find.text('热搜暂时不可用'), findsOneWidget);
    await tester.tap(find.text('重试'));
    expect(retries, 1);
    update(() => error = null);
    await tester.pumpAndSettle();
    expect(find.text(IkLibraryRevisionStrings.hotSearchEmpty), findsOneWidget);
    expect(find.byType(IkSongTableRow), findsNothing);
  });

  testWidgets('E10 发现只留一个个人入口，网易与QQ私享不再次铺开', (tester) async {
    final navigation = <String>[];
    await _mount(tester, _home(_mixed(), onNavigate: navigation.add));
    final daily = find.byKey(const Key('ik-personal-daily-entry'));
    expect(daily, findsOneWidget);
    expect(find.text(IkPersonalDailyStrings.title), findsOneWidget);
    expect(find.text('netease-推荐1'), findsNothing);
    expect(find.text('qq-推荐1'), findsNothing);
    expect(find.text('首页推荐'), findsOneWidget);
    expect(find.text('kugou-推荐1'), findsOneWidget);
    expect(find.text('浏览全部'), findsNothing);
    await tester.tap(daily);
    expect(navigation, ['/daily']);
  });

  for (final item in [
    (PlatformType.qq, RecommendationKind.fallbackToplist, '榜单推荐'),
    (PlatformType.kugou, RecommendationKind.fallbackHomepage, '首页推荐'),
  ]) {
    testWidgets('E10 ${item.$1.name}公开来源展示全部已返回歌曲并保持完整队列', (tester) async {
      final songs = _songs(item.$1, count: 31);
      final navigation = <String>[];
      Song? selected;
      List<Song>? queue;
      await _mount(
        tester,
        _home(
          RecommendationsState(
            songsByPlatform: {item.$1: songs},
            sourceByPlatform: {
              item.$1: _source(item.$1, item.$2, note: '真实公开来源说明'),
            },
          ),
          onNavigate: navigation.add,
          onPlay: (song, all) {
            selected = song;
            queue = all;
          },
        ),
      );
      expect(find.text(item.$3), findsOneWidget);
      expect(find.text('真实公开来源说明'), findsOneWidget);
      expect(find.text(IkWorkspaceStrings.previewTracks(6)), findsNothing);
      final last = find.byKey(ValueKey('ik-discovery-song-${item.$1.name}-30'));
      await tester.scrollUntilVisible(last, 500, maxScrolls: 40);
      await tester.tap(last);
      expect(selected?.id, '${item.$1.name}-31');
      expect(queue?.map((song) => song.id), songs.map((song) => song.id));
      expect(navigation, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final item in <(String, RecommendationSource?)>[
    ('未知来源', null),
    ('平台不匹配', _source(PlatformType.kugou, RecommendationKind.fallbackToplist)),
    ('来源不可用', _source(PlatformType.qq, RecommendationKind.unavailable)),
    ('个人私享', _source(PlatformType.qq, RecommendationKind.personalPrivate)),
    ('个人日推', _source(PlatformType.qq, RecommendationKind.personalizedDaily)),
  ]) {
    testWidgets('E10 ${item.$1}不会被提升为公共推荐或个人日推成功', (tester) async {
      await _mount(
        tester,
        _home(
          RecommendationsState(
            songsByPlatform: {PlatformType.qq: _songs(PlatformType.qq)},
            sourceByPlatform: {if (item.$2 != null) PlatformType.qq: item.$2!},
          ),
        ),
      );
      expect(find.byKey(const Key('ik-personal-daily-entry')), findsOneWidget);
      expect(find.text('qq-推荐1'), findsNothing);
      expect(find.text('榜单推荐'), findsNothing);
      expect(find.text('首页推荐'), findsNothing);
      expect(find.text('今日私享'), findsNothing);
    });
  }

  testWidgets('E10 公开来源错误与重试保留，个人来源错误不混进公开区', (tester) async {
    final notifier = _Recommendations(
      RecommendationsState(
        songsByPlatform: {
          PlatformType.qq: _songs(PlatformType.qq),
          PlatformType.netease: _songs(PlatformType.netease),
        },
        sourceByPlatform: {
          PlatformType.qq: _source(
            PlatformType.qq,
            RecommendationKind.fallbackToplist,
          ),
          PlatformType.netease: _source(
            PlatformType.netease,
            RecommendationKind.personalizedDaily,
          ),
        },
        errorsByPlatform: const {
          PlatformType.qq: '公开列表不完整',
          PlatformType.netease: '旧个人请求失败',
        },
      ),
    );
    await _mount(
      tester,
      _home(const RecommendationsState(), notifier: notifier),
    );
    expect(find.text('公开列表不完整'), findsOneWidget);
    expect(find.text('旧个人请求失败'), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, '重试'));
    expect(notifier.retries, [PlatformType.qq]);
  });

  testWidgets('E10 缺省保留旧发现个人预览与六首上限和旧搜索推荐', (tester) async {
    await _mount(
      tester,
      _home(
        RecommendationsState(
          songsByPlatform: {
            PlatformType.netease: _songs(PlatformType.netease, count: 8),
          },
          sourceByPlatform: {
            PlatformType.netease: _source(
              PlatformType.netease,
              RecommendationKind.personalizedDaily,
            ),
          },
        ),
        enabled: false,
      ),
    );
    expect(find.text('netease-推荐1'), findsOneWidget);
    expect(find.text(IkWorkspaceStrings.previewTracks(6)), findsOneWidget);
    expect(find.text('浏览全部'), findsOneWidget);
    final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
    expect(grid.delegate.estimatedChildCount, 6);
    final search = _search();
    addTearDown(search.dispose);
    await _mount(tester, _searchPage(search, enabled: false));
    expect(find.text('平台推荐'), findsWidgets);
    expect(find.byType(IkSelect<PlatformType>), findsOneWidget);
    expect(find.byType(IkSongTableRow), findsWidgets);
  });

  for (final dark in [false, true]) {
    for (final width in [320.0, 390.0, 720.0, 900.0, 1200.0, 1440.0, 1920.0]) {
      for (final scale in [1.0, 1.25, 1.5]) {
        testWidgets('E10 ${dark ? '深' : '浅'}宽$width字号$scale唯一入口与热搜无溢出', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 960);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final search = _search();
          addTearDown(search.dispose);
          await _mount(tester, _searchPage(search), dark: dark, scale: scale);
          expect(find.text('热门搜索'), findsOneWidget);
          expect(find.byType(IkSongTableRow), findsNothing);
          expect(tester.takeException(), isNull);
          await _mount(tester, _home(_mixed()), dark: dark, scale: scale);
          expect(
            find.byKey(const Key('ik-personal-daily-entry')),
            findsOneWidget,
          );
          expect(find.text('netease-推荐1'), findsNothing);
          expect(find.text('qq-推荐1'), findsNothing);
          await tester.scrollUntilVisible(find.text('kugou-推荐1'), 300);
          expect(find.text('kugou-推荐1'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}

List<Song> _songs(PlatformType platform, {int count = 2}) => [
  for (var i = 1; i <= count; i++)
    Song(
      id: '${platform.name}-$i',
      platform: platform,
      name: '${platform.name}-推荐$i',
      artists: const [],
    ),
];

RecommendationSource _source(
  PlatformType platform,
  RecommendationKind kind, {
  String? note,
}) => RecommendationSource(
  platform: platform,
  kind: kind,
  label: '接口原标签',
  note: note,
);

RecommendationsState _mixed() => RecommendationsState(
  songsByPlatform: {
    for (final platform in PlatformType.musicServices)
      platform: _songs(platform),
  },
  sourceByPlatform: {
    PlatformType.netease: _source(
      PlatformType.netease,
      RecommendationKind.personalizedDaily,
    ),
    PlatformType.qq: _source(
      PlatformType.qq,
      RecommendationKind.personalPrivate,
    ),
    PlatformType.kugou: _source(
      PlatformType.kugou,
      RecommendationKind.fallbackHomepage,
    ),
  },
);

IkSearchController _search() => IkSearchController(
  platforms: const [PlatformType.netease],
  search: (platform, query, page) async => VideoPage(
    songs: [
      for (var i = 1; i <= 2; i++)
        Song(
          id: 'result-$i',
          platform: platform,
          name: '$query-结果$i',
          artists: const [],
        ),
    ],
    page: page,
    total: 2,
    hasMore: false,
  ),
);

Widget _searchPage(
  IkSearchController search, {
  bool enabled = true,
  bool fullRecommendations = true,
  bool compactDiscovery = true,
  RecommendationsState? state,
  List<String> hotTerms = const ['夏日', '轻音乐'],
  bool hotLoading = false,
  String? hotError,
  VoidCallback? onRetryHot,
  ValueChanged<PlatformType>? onRetryRecommendation,
  VoidCallback? onBrowse,
  void Function(Song, List<Song>)? onPlay,
}) => IkSearchWorkspace(
  search: search,
  alignToDesign: true,
  compactDiscovery: compactDiscovery,
  fullRecommendations: fullRecommendations,
  recommendationsInDiscovery: enabled,
  useSharedSearch: true,
  hotTerms: hotTerms,
  hotLoading: hotLoading,
  hotError: hotError,
  onRetryHot: onRetryHot,
  recommendations: state ?? _mixed(),
  onRetryRecommendation: onRetryRecommendation,
  onBrowseRecommendations: onBrowse,
  onPlay: onPlay ?? (_, _) {},
  onLike: (_) {},
  onMore: (_) {},
);

Widget _home(
  RecommendationsState state, {
  bool enabled = true,
  _Recommendations? notifier,
  ValueChanged<String>? onNavigate,
  void Function(Song, List<Song>)? onPlay,
}) => ProviderScope(
  key: UniqueKey(),
  overrides: [
    authProvider.overrideWith((_) => AuthNotifier()),
    playerProvider.overrideWith((_) => _Player()),
    recommendationsProvider.overrideWith(
      (_) => notifier ?? _Recommendations(state),
    ),
  ],
  child: IkHomePage(
    workspace: true,
    alignToDesign: true,
    recommendationsInDiscovery: enabled,
    onNavigate: onNavigate ?? (_) {},
    onPlayer: () {},
    onPlay: onPlay ?? (_, _) {},
    onMore: (_) {},
  ),
);

Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  bool dark = false,
  double scale = 1,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: IkWorkspaceTheme.aligned(
        ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      ),
      builder: (context, body) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: body!,
      ),
      home: Scaffold(body: child),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

class _Recommendations extends IkRecommendationsNotifier {
  _Recommendations(RecommendationsState initial) {
    state = initial;
  }
  final retries = <PlatformType>[];
  @override
  Future<void> loadRecommendations() async {}
  @override
  Future<void> retryLatestPlatform(PlatformType platform) async {
    retries.add(platform);
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/auth/presentation/providers/auth_provider.dart';
import 'package:mconnect/features/discovery/presentation/providers/recommendations_provider.dart';
import 'package:mconnect/features/player/data/playback_keep_alive_service.dart';
import 'package:mconnect/features/player/data/playback_notification_service.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/recommendation_source.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/video_app/ik/ik_home_page.dart';
import 'package:mconnect/video_app/ik/ik_theme.dart';
import 'package:mconnect/video_app/ik/ik_workspace.dart';
import 'package:mconnect/video_app/ui/video_theme.dart';

import 'support/content_page_fakes.dart';

const _searchKey = ValueKey('ik-workspace-search');
const _crumbKey = ValueKey('ik-workspace-location');

Song _song(int index, {bool longName = false}) => Song(
  id: '$index',
  platform: PlatformType.qq,
  name: longName ? '推荐$index：这是很长的真实歌曲名称用于检查标题和操作不会重叠' : '推荐$index',
  artists: const [Artist(id: 'artist', name: '真实歌手')],
);

RecommendationsState _catalog({bool longName = false}) => RecommendationsState(
  songsByPlatform: {
    PlatformType.qq: [for (var i = 0; i < 8; i++) _song(i, longName: longName)],
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
);

Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  double width = 1200,
  double height = 960,
  double scale = 1,
  bool dark = false,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: IkTheme.from(dark ? VideoTheme.dark : VideoTheme.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: child,
    ),
  );
  await tester.pump();
}

Widget _home({
  required RecommendationsNotifier recommendations,
  _Player? player,
  bool align = true,
  bool workspace = true,
  ValueChanged<String>? navigate,
  VoidCallback? openPlayer,
  void Function(Song, List<Song>)? play,
  ValueChanged<Song>? more,
}) => ProviderScope(
  key: UniqueKey(),
  overrides: [
    recommendationsProvider.overrideWith((ref) => recommendations),
    playerProvider.overrideWith((ref) => player ?? _Player()),
    authProvider.overrideWith((ref) => AuthNotifier()),
  ],
  child: IkHomePage(
    workspace: workspace,
    alignToDesign: align,
    onNavigate: navigate ?? (_) {},
    onPlayer: openPlayer ?? () {},
    onPlay: play ?? (_, _) {},
    onMore: more ?? (_) {},
  ),
);

IkDesktopWorkspace _shell({
  int index = 0,
  ValueChanged<int>? select,
  ValueChanged<String>? search,
  bool align = true,
  Widget? home,
  Widget? playbackBar,
}) => IkDesktopWorkspace(
  index: index,
  onSelect: select ?? (_) {},
  onAccount: () {},
  alignToDesign: align,
  onSearch: search,
  pages: [
    home ?? const _CounterPage(),
    const Text('搜索页内容'),
    const Text('音乐库内容'),
    const Text('最近播放内容'),
    const Text('设置页内容'),
  ],
  playbackBar: playbackBar ?? const SizedBox(height: 64, child: Text('共用播放栏')),
);

void main() {
  testWidgets('A01 顶栏提交真实搜索并保留子页及输入状态', (tester) async {
    var index = 0;
    final queries = <String>[];
    late StateSetter updateShell;
    await _mount(
      tester,
      StatefulBuilder(
        builder: (context, update) {
          updateShell = update;
          return _shell(
            index: index,
            select: (next) => update(() => index = next),
            search: (query) {
              queries.add(query);
              update(() => index = 1);
            },
          );
        },
      ),
    );
    expect(find.byKey(_searchKey), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(_crumbKey)).data, '发现');
    await tester.tap(find.text('计数 0'));
    await tester.pump();
    await tester.enterText(find.byKey(_searchKey), '真实歌名 歌手');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(queries, ['真实歌名 歌手']);
    expect(find.text('搜索页内容'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(_crumbKey)).data, '搜索');
    updateShell(() => index = 0);
    await tester.pump();
    expect(find.text('计数 1'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(_searchKey)).controller!.text,
      '真实歌名 歌手',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('A01 未开启或无搜索回调时不出现空搜索控件', (tester) async {
    for (final config in [(false, true), (false, false), (true, false)]) {
      await _mount(
        tester,
        _shell(align: config.$1, search: config.$2 ? (_) {} : null),
      );
      expect(find.byKey(_searchKey), findsNothing);
      expect(find.byType(IndexedStack), findsOneWidget);
      expect(find.text('共用播放栏'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('A07 顶栏主标题推荐与封面左缘统一正文24px', (tester) async {
    final mismatches = <String>[];
    for (final dark in [false, true]) {
      for (final width in [320.0, 390.0, 720.0, 900.0, 1200.0, 1440.0]) {
        for (final scale in [1.0, 1.25, 1.5]) {
          await _mount(
            tester,
            _shell(
              search: (_) {},
              home: _home(recommendations: _Recommendations(_catalog())),
            ),
            width: width,
            scale: scale,
            dark: dark,
          );
          final expected =
              tester.getTopLeft(find.byType(CustomScrollView)).dx + 24;
          final locationContainer = find
              .ancestor(
                of: find.byKey(_crumbKey),
                matching: find.byType(Container),
              )
              .first;
          final discoveryScroll = find.descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          );
          void check(String name, Finder finder) {
            final actual = tester.getTopLeft(finder).dx;
            if ((actual - expected).abs() > .01) {
              mismatches.add('$width/$scale/$dark $name: $actual，预期$expected');
            }
          }

          check('顶栏分割线', locationContainer);
          check('主标题', find.text('听点喜欢的。'));
          await tester.scrollUntilVisible(
            find.text('推荐').first.hitTestable(),
            140,
            scrollable: discoveryScroll,
          );
          check('推荐标题', find.text('推荐').first);
          await tester.scrollUntilVisible(
            find.text('当前内容来自新歌榜').hitTestable(),
            140,
            scrollable: discoveryScroll,
          );
          check('推荐出处', find.text('当前内容来自新歌榜'));
          await tester.scrollUntilVisible(
            find.text('推荐0').hitTestable(),
            140,
            scrollable: discoveryScroll,
          );
          check('封面网格', find.byKey(const ValueKey('ik-discovery-cover-qq-0')));
          expect(tester.takeException(), isNull);
        }
      }
    }
    expect(mismatches, isEmpty);
  });

  for (final width in [390.0, 1200.0]) {
    testWidgets('A07 首屏推荐在真实底栏预留区域上方 $width', (tester) async {
      await _mount(
        tester,
        _shell(
          search: (_) {},
          home: _home(recommendations: _Recommendations(_catalog())),
          playbackBar: SizedBox(
            key: const ValueKey('reserved-playback-bar'),
            height: width < 720 ? 196 : 96,
          ),
        ),
        width: width,
        height: 900,
        scale: width < 720 ? 1.5 : 1,
      );
      final viewport = tester.getRect(find.byType(CustomScrollView));
      final bottom = tester
          .getTopLeft(find.byKey(const ValueKey('reserved-playback-bar')))
          .dy;
      expect(viewport.bottom, bottom);
      final requiredTexts = width < 720
          ? ['开始探索', '推荐', 'QQ 音乐']
          : ['开始探索', '推荐0'];
      for (final text in requiredTexts) {
        final item = find.text(text).first;
        expect(item, findsOneWidget, reason: '$text应在初屏构建');
        final bounds = tester.getRect(item);
        expect(bounds.top, greaterThanOrEqualTo(viewport.top));
        expect(
          bounds.bottom,
          lessThanOrEqualTo(bottom),
          reason: '$text完整显示，不能被播放栏遮挡',
        );
        expect(item.hitTestable(), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('A07 推荐出处样式继承用户选择的字体', (tester) async {
    final theme = IkTheme.from(VideoTheme.light);
    await _mount(
      tester,
      Theme(
        data: theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'UserFontFixture'),
        ),
        child: Scaffold(
          body: _home(recommendations: _Recommendations(_catalog())),
        ),
      ),
    );
    final tile = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('当前内容来自新歌榜'),
        matching: find.byType(ListTile),
      ),
    );
    expect(tile.subtitleTextStyle?.fontFamily, 'UserFontFixture');
    expect(tester.takeException(), isNull);
  });

  testWidgets('A02 封面横排展示真实歌曲且播放保留来源完整队列', (tester) async {
    final catalog = _catalog();
    final recommendations = _Recommendations(catalog);
    final played = <(Song, List<Song>)>[];
    final more = <Song>[];
    final navigation = <String>[];
    await _mount(
      tester,
      Scaffold(
        body: _home(
          recommendations: recommendations,
          play: (song, songs) => played.add((song, songs)),
          more: more.add,
          navigate: navigation.add,
        ),
      ),
      width: 1440,
    );
    expect(recommendations.loads, 1);
    expect(find.byType(SliverGrid), findsOneWidget);
    await tester.scrollUntilVisible(find.text('推荐0').hitTestable(), 160);
    final first = tester.getRect(
      find.byKey(const ValueKey('ik-discovery-cover-qq-0')),
    );
    final second = tester.getRect(
      find.byKey(const ValueKey('ik-discovery-cover-qq-1')),
    );
    expect(first.top, second.top);
    expect(second.left, greaterThan(first.right));
    await tester.tap(find.text('推荐0'));
    expect(played.single.$1.id, '0');
    expect(played.single.$2, catalog.songsForPlatform(PlatformType.qq));
    expect(played.single.$2.length, 8);
    await tester.tap(find.byKey(const ValueKey('ik-discovery-more-qq-0')));
    expect(more.single.id, '0');
    await tester.scrollUntilVisible(find.text('浏览全部 · 8 首').hitTestable(), 160);
    expect(find.text('推荐6'), findsNothing);
    expect(find.text('推荐7'), findsNothing);
    await tester.tap(find.text('浏览全部 · 8 首'));
    expect(navigation, ['/recommendations']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A02 原始出处、精选上限、失败重试和登录动作可达', (tester) async {
    final recommendations = _Recommendations(_catalog());
    final navigation = <String>[];
    await _mount(
      tester,
      Scaffold(
        body: _home(recommendations: recommendations, navigate: navigation.add),
      ),
      width: 390,
      scale: 1.5,
    );
    for (final label in ['榜单推荐', '当前内容来自新歌榜', '先听这 6 首']) {
      await tester.scrollUntilVisible(find.text(label), 120);
      expect(find.text(label), findsOneWidget);
    }
    await tester.scrollUntilVisible(find.text('请登录后获取每日推荐'), 150);
    await tester.scrollUntilVisible(find.text('登录网易云').hitTestable(), 100);
    await tester.tap(find.text('登录网易云'));
    await tester.tap(find.widgetWithText(TextButton, '重试'));
    expect(navigation, ['/login/netease']);
    expect(recommendations.loads, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A02 加载、空结果和全局失败分别展示真实状态', (tester) async {
    final recommendations = _Recommendations(
      const RecommendationsState(isLoading: true),
    );
    final navigation = <String>[];
    await _mount(
      tester,
      Scaffold(
        body: _home(recommendations: recommendations, navigate: navigation.add),
      ),
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == '重试',
            ),
          )
          .onPressed,
      isNull,
    );
    expect(find.text('当前没有推荐歌曲，可以浏览榜单或新歌'), findsNothing);
    recommendations.show(const RecommendationsState(error: '推荐加载失败'));
    await tester.pump();
    expect(find.text('推荐加载失败'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('当前没有推荐歌曲，可以浏览榜单或新歌'), findsNothing);
    await tester.tap(find.byTooltip('重试'));
    expect(recommendations.loads, 2);
    recommendations.show(const RecommendationsState());
    await tester.pump();
    expect(find.text('当前没有推荐歌曲，可以浏览榜单或新歌'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '浏览全部'));
    expect(navigation, ['/recommendations']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A02 实际IK入口按失败来源重试且忙碌时禁用重复请求', (tester) async {
    final recommendations = _LatestRecommendations(_catalog());
    await _mount(
      tester,
      Scaffold(body: _home(recommendations: recommendations)),
    );
    await tester.scrollUntilVisible(
      find.widgetWithText(TextButton, '重试').hitTestable(),
      160,
    );
    await tester.tap(find.widgetWithText(TextButton, '重试'));
    expect(recommendations.retries, [PlatformType.netease]);
    expect(recommendations.loads, 1);
    recommendations.show(_catalog().copyWith(isLoading: true));
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '重试'))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('A02 已知来源空结果不伪造封面或全部入口', (tester) async {
    await _mount(
      tester,
      Scaffold(
        body: _home(
          recommendations: _Recommendations(
            const RecommendationsState(songsByPlatform: {PlatformType.qq: []}),
          ),
        ),
      ),
    );
    expect(find.text('当前没有推荐歌曲，可以浏览榜单或新歌'), findsOneWidget);
    expect(find.byKey(const ValueKey('ik-discovery-song-qq-0')), findsNothing);
    expect(find.textContaining('浏览全部 ·'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A02 继续播放卡片保持详情和播放暂停两种动作', (tester) async {
    final player = _Player(currentSong: _song(0, longName: true));
    var opened = 0;
    await _mount(
      tester,
      Scaffold(
        body: _home(
          recommendations: _Recommendations(const RecommendationsState()),
          player: player,
          openPlayer: () => opened++,
        ),
      ),
      width: 320,
      scale: 1.5,
    );
    await tester.scrollUntilVisible(find.text('继续播放').hitTestable(), 120);
    await tester.tap(find.text('继续播放'));
    expect(opened, 1);
    await tester.tap(find.byTooltip('播放'));
    await tester.pump();
    expect(player.toggles, 1);
    expect(find.byTooltip('暂停'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A02 默认和非workspace入口保持原推荐列表', (tester) async {
    for (final config in [(false, true), (true, false)]) {
      await _mount(
        tester,
        Scaffold(
          body: _home(
            recommendations: _Recommendations(_catalog()),
            align: config.$1,
            workspace: config.$2,
          ),
        ),
      );
      expect(find.byType(SliverGrid), findsNothing);
      expect(find.byType(SliverList), findsWidgets);
      expect(tester.takeException(), isNull);
    }
  });

  for (final dark in [false, true]) {
    for (final width in [320.0, 390.0, 720.0, 900.0, 1200.0, 1440.0]) {
      for (final scale in [1.0, 1.25, 1.5]) {
        testWidgets('A07 主壳发现布局 ${dark ? '深' : '浅'} $width/$scale', (
          tester,
        ) async {
          final queries = <String>[];
          final navigation = <String>[];
          await _mount(
            tester,
            _shell(
              search: queries.add,
              home: _home(
                recommendations: _Recommendations(_catalog(longName: true)),
                player: _Player(currentSong: _song(9, longName: true)),
                navigate: navigation.add,
              ),
            ),
            width: width,
            scale: scale,
            dark: dark,
          );
          expect(find.byKey(_searchKey).hitTestable(), findsOneWidget);
          expect(find.byKey(_crumbKey), findsOneWidget);
          await tester.enterText(find.byKey(_searchKey), '布局验收');
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await tester.pump();
          expect(queries, ['布局验收']);
          final discoveryScroll = find.descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          );
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('ik-discovery-song-qq-5')).hitTestable(),
            180,
            scrollable: discoveryScroll,
          );
          expect(
            find.byKey(const ValueKey('ik-discovery-song-qq-5')).hitTestable(),
            findsOneWidget,
          );
          await tester.scrollUntilVisible(
            find.text('登录网易云').hitTestable(),
            150,
            scrollable: discoveryScroll,
          );
          await tester.tap(find.text('登录网易云'));
          expect(navigation, ['/login/netease']);
          expect(find.text('共用播放栏').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}

class _CounterPage extends StatefulWidget {
  const _CounterPage();
  @override
  State<_CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<_CounterPage> {
  var count = 0;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => setState(() => count++),
    child: Text('计数 $count'),
  );
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

  void show(RecommendationsState next) => state = next;
}

class _Player extends PlayerNotifier {
  _Player({Song? currentSong})
    : super(
        audioController: IdleAudioController(),
        audioControllerFactory: IdleAudioController.new,
        keepAliveController: const NoopPlaybackKeepAliveController(),
        notificationController: const NoopPlaybackNotificationController(),
        stuckWatchdogInterval: Duration.zero,
      ) {
    if (currentSong != null) state = PlayerState(currentSong: currentSong);
  }
  int toggles = 0;
  @override
  Future<void> togglePlay() async {
    toggles++;
    state = state.copyWith(isPlaying: !state.isPlaying);
  }
}

class _LatestRecommendations extends IkRecommendationsNotifier {
  _LatestRecommendations(RecommendationsState initial) {
    state = initial;
  }
  int loads = 0;
  final retries = <PlatformType>[];
  @override
  Future<void> loadRecommendations() async {
    loads++;
  }

  @override
  Future<void> retryLatestPlatform(PlatformType platform) async {
    retries.add(platform);
  }

  void show(RecommendationsState next) => state = next;
}

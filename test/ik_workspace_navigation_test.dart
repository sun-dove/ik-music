import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mconnect/features/album/presentation/pages/album_page.dart';
import 'package:mconnect/features/album/presentation/providers/album_provider.dart';
import 'package:mconnect/features/player/data/playback_keep_alive_service.dart';
import 'package:mconnect/features/player/data/playback_notification_service.dart';
import 'package:mconnect/features/player/presentation/pages/queue_page.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/l10n/ik_strings.dart';
import 'package:mconnect/video_app/ik/ik_router.dart';
import 'package:mconnect/video_app/ik/ik_theme.dart';
import 'package:mconnect/video_app/ik/ik_workspace.dart';
import 'package:mconnect/video_app/ik/ik_workspace_navigation.dart';
import 'package:mconnect/video_app/ui/video_theme.dart';

import 'support/content_page_fakes.dart' show IdleAudioController;

const _baseline = bool.fromEnvironment('IK_WORKSPACE_BASELINE');
const _searchKey = ValueKey('ik-workspace-search');
const _outerBarKey = ValueKey('navigation-shared-playback');
const _playerBarKey = ValueKey('navigation-player-playback');

// 路由契约完整覆盖32条；业务页面的全部实际装配另由E12集成门验证。
// 本文件真实挂载队列、专辑和错误页，播放、设置、下载使用轻量回调夹具。
const _routes = <String, String>{
  '/': '/',
  '/player': '/player',
  '/queue': '/queue',
  '/recommendations': '/recommendations',
  '/daily?platform=qq': '/daily',
  '/toplists': '/toplists',
  '/new-songs': '/new-songs',
  '/history': '/history',
  '/local-music': '/local-music',
  '/likes': '/likes',
  '/platform-playlists': '/platform-playlists',
  '/import-playlist': '/import-playlist',
  '/downloads': '/downloads',
  '/offline-cache': '/offline-cache',
  '/listening-stats': '/listening-stats',
  '/smart-playlists': '/smart-playlists',
  '/smart-playlists/editor?id=rule-1': '/smart-playlists/editor',
  '/backup': '/backup',
  '/settings/audio': '/settings/audio',
  '/settings/floating-lyrics': '/settings/floating-lyrics',
  '/settings': '/settings',
  '/settings/appearance': '/settings/appearance',
  '/settings/lyrics': '/settings/lyrics',
  '/settings/sources': '/settings/sources',
  '/settings/downloads': '/settings/downloads',
  '/settings/accounts': '/settings/accounts',
  '/settings/backup': '/settings/backup',
  '/login/qq': '/login/:platform',
  '/album/qq/nav-album?name=路由专辑': '/album/:platform/:id',
  '/artist/netease/nav-artist?name=路由歌手': '/artist/:platform/:id',
  '/toplist/kugou/nav-toplist?name=路由榜单': '/toplist/:platform/:id',
  '/playlist/qq/nav-playlist?name=路由歌单': '/playlist/:platform/:id',
};

const _invalidLocations = [
  '/unknown/detail',
  '/daily?platform=local',
  '/daily?platform=missing',
  '/login/local',
  '/login/missing',
  '/album/missing/id',
  '/artist/missing/id',
  '/toplist/missing/id',
  '/playlist/missing/id',
  '/album/qq/%20',
];

Iterable<GoRoute> _declaredRoutes(Iterable<RouteBase> routes) sync* {
  for (final route in routes) {
    if (route is GoRoute) yield route;
    yield* _declaredRoutes(route.routes);
  }
}

GoRouter _createRouter({
  required GlobalKey<_WorkspaceHarnessState> workspaceKey,
  required GlobalKey<NavigatorState> navigatorKey,
}) {
  Widget player(BuildContext context) => const _PlayerPage();
  Widget downloads(BuildContext context) => const _DetailPage('下载夹具');
  Widget settings(BuildContext context, String section) =>
      _DetailPage('设置夹具 $section');
  if (_baseline) {
    return createIkRouter(
      home: (_) => _WorkspaceHarness(key: workspaceKey),
      player: player,
      settings: settings,
      downloads: downloads,
      alignToDesign: true,
    );
  }
  return createIkWorkspaceRouter(
    workspace: (_, child, path) =>
        _WorkspaceHarness(key: workspaceKey, routeBody: child, path: path),
    player: player,
    settings: settings,
    downloads: downloads,
    navigatorKey: navigatorKey,
  );
}

typedef _Fixture = ({
  GoRouter router,
  GlobalKey<_WorkspaceHarnessState> workspaceKey,
  GlobalKey<NavigatorState> navigatorKey,
});

Future<_Fixture> _mount(
  WidgetTester tester, {
  double width = 1200,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 960);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final workspaceKey = GlobalKey<_WorkspaceHarnessState>();
  final navigatorKey = GlobalKey<NavigatorState>();
  final router = _createRouter(
    workspaceKey: workspaceKey,
    navigatorKey: navigatorKey,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playerProvider.overrideWith((ref) => _Player()),
        albumDetailProvider.overrideWith(
          (ref, key) async => const AlbumDetailData(),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: IkTheme.from(VideoTheme.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (
    router: router,
    workspaceKey: workspaceKey,
    navigatorKey: navigatorKey,
  );
}

Future<void> _push(
  WidgetTester tester,
  GoRouter router,
  String location,
) async {
  unawaited(router.push<void>(location));
  await tester.pumpAndSettle();
}

Future<void> _pop(WidgetTester tester, GoRouter router) async {
  router.pop();
  await tester.pumpAndSettle();
}

void _expectEmbedded(WidgetTester tester) {
  expect(find.byType(IkDesktopWorkspace), findsOneWidget);
  expect(find.byKey(_outerBarKey), findsOneWidget);
  expect(find.byKey(_searchKey), findsOneWidget);
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('E03 路由契约仍完整声明32条既有路径', () {
    final router = _createRouter(
      workspaceKey: GlobalKey<_WorkspaceHarnessState>(),
      navigatorKey: GlobalKey<NavigatorState>(),
    );
    addTearDown(router.dispose);
    expect(_routes, hasLength(32));
    expect(
      _declaredRoutes(router.configuration.routes)
          .map((route) => route.path)
          .where((path) => path != '/:unmatched(.*)'),
      unorderedEquals(_routes.values),
    );
  });

  for (final route in _routes.entries) {
    test('E03 全量路由保持路径并进入常驻主框架 ${route.value}', () {
      final router = _createRouter(
        workspaceKey: GlobalKey<_WorkspaceHarnessState>(),
        navigatorKey: GlobalKey<NavigatorState>(),
      );
      addTearDown(router.dispose);
      final match = router.configuration.findMatch(Uri.parse(route.key));
      expect(match.isError, isFalse, reason: route.key);
      expect(match.last.route.path, route.value);
      expect(match.fullPath, route.value);
      expect(match.matches, hasLength(1));
      expect(match.matches.single, isA<ShellRouteMatch>());
    });
  }

  for (final location in _invalidLocations) {
    testWidgets('E03 未知路径或非法参数留在主框架 $location', (tester) async {
      final fixture = await _mount(tester);
      final originalWorkspace = fixture.workspaceKey.currentState;
      fixture.router.go(location);
      await tester.pumpAndSettle();
      expect(find.byType(IkRouteError), findsOneWidget);
      expect(find.text(IkStrings.pageMissing), findsOneWidget);
      _expectEmbedded(tester);
      expect(fixture.workspaceKey.currentState, same(originalWorkspace));
      await tester.tap(find.text(IkStrings.backHome));
      await tester.pumpAndSettle();
      expect(fixture.router.routerDelegate.state.uri.path, '/');
      expect(find.text('主区0计数0'), findsOneWidget);
      expect(fixture.workspaceKey.currentState, same(originalWorkspace));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('E03 多层push按顺序返回且主框架始终只有一个', (tester) async {
    final fixture = await _mount(tester);
    final workspace = fixture.workspaceKey.currentState!;
    await tester.tap(find.text('主区0计数0'));
    await tester.pump();
    for (final location in [
      '/downloads',
      '/settings/appearance',
      '/settings/lyrics',
    ]) {
      await _push(tester, fixture.router, location);
      _expectEmbedded(tester);
      expect(fixture.workspaceKey.currentState, same(workspace));
      expect(
        find.byType(IkDesktopWorkspace, skipOffstage: false),
        findsOneWidget,
      );
      expect(fixture.router.routerDelegate.state.uri.path, location);
    }
    for (final expected in [
      ('/settings/appearance', '设置夹具 appearance'),
      ('/downloads', '下载夹具'),
      ('/', '主区0计数1'),
    ]) {
      expect(fixture.router.canPop(), isTrue);
      await _pop(tester, fixture.router);
      expect(fixture.router.routerDelegate.state.uri.path, expected.$1);
      expect(find.text(expected.$2), findsOneWidget);
      _expectEmbedded(tester);
      expect(fixture.workspaceKey.currentState, same(workspace));
    }
    expect(fixture.router.canPop(), isFalse);
  });

  testWidgets('E03 独立播放详情经真实队列专辑往返保持同一导航栈', (tester) async {
    final fixture = await _mount(tester);
    final workspace = fixture.workspaceKey.currentState!;
    await _push(tester, fixture.router, '/player');
    final playerState = tester.state(find.byType(_PlayerPage));
    expect(find.byType(IkDesktopWorkspace), findsOneWidget);
    expect(find.byKey(_outerBarKey), findsNothing);
    expect(find.byKey(_searchKey), findsNothing);
    expect(find.byKey(_playerBarKey), findsOneWidget);
    await tester.tap(find.text('打开真实队列'));
    await tester.pumpAndSettle();
    expect(find.byType(QueuePage), findsOneWidget);
    expect(find.text('队列是空的'), findsOneWidget);
    expect(find.byKey(_playerBarKey), findsNothing);
    _expectEmbedded(tester);
    await _pop(tester, fixture.router);
    expect(fixture.router.routerDelegate.state.uri.path, '/player');
    expect(tester.state(find.byType(_PlayerPage)), same(playerState));
    expect(find.byKey(_outerBarKey), findsNothing);
    expect(find.byKey(_playerBarKey), findsOneWidget);
    await tester.tap(find.text('打开真实专辑'));
    await tester.pumpAndSettle();
    expect(find.byType(AlbumPage), findsOneWidget);
    expect(find.text('暂无专辑信息'), findsOneWidget);
    expect(find.byKey(_playerBarKey), findsNothing);
    _expectEmbedded(tester);
    await _pop(tester, fixture.router);
    expect(tester.state(find.byType(_PlayerPage)), same(playerState));
    expect(find.byKey(_playerBarKey), findsOneWidget);
    expect(find.byKey(_outerBarKey), findsNothing);
    await _pop(tester, fixture.router);
    expect(fixture.router.routerDelegate.state.uri.path, '/');
    expect(fixture.workspaceKey.currentState, same(workspace));
    expect(find.text('主区0计数0'), findsOneWidget);
    _expectEmbedded(tester);
  });

  testWidgets('E03 首页连续push两次使用独立PageKey并可逐层返回', (tester) async {
    final fixture = await _mount(tester);
    final workspace = fixture.workspaceKey.currentState!;
    await tester.tap(find.text('主区0计数0'));
    await tester.pump();
    for (var index = 0; index < 2; index++) {
      await _push(tester, fixture.router, '/');
      expect(tester.takeException(), isNull);
      expect(fixture.router.canPop(), isTrue);
      expect(fixture.workspaceKey.currentState, same(workspace));
      expect(find.text('主区0计数1'), findsOneWidget);
    }
    final pages = fixture.navigatorKey.currentState!.widget.pages;
    expect(pages, hasLength(3));
    expect(pages.map((page) => page.key).toSet(), hasLength(3));
    await _pop(tester, fixture.router);
    expect(fixture.router.canPop(), isTrue);
    await _pop(tester, fixture.router);
    expect(fixture.router.canPop(), isFalse);
    expect(find.text('主区0计数1'), findsOneWidget);
    expect(fixture.workspaceKey.currentState, same(workspace));
    _expectEmbedded(tester);
  });

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('E03 $width宽$scale倍字五主区和顶栏输入往返保活', (tester) async {
        final fixture = await _mount(tester, width: width, scale: scale);
        final workspace = fixture.workspaceKey.currentState!;
        final states = [
          for (final key in workspace.pageKeys) key.currentState!,
        ];
        final offsets = <double>[];
        for (var index = 0; index < 5; index++) {
          tester
              .widget<IkDesktopWorkspace>(find.byType(IkDesktopWorkspace))
              .onSelect(index);
          await tester.pump();
          await tester.tap(find.text('主区$index计数0'));
          await tester.enterText(
            find.byKey(ValueKey('primary-input-$index')),
            '主区$index的未提交输入',
          );
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pump();
          await tester.drag(
            find.byKey(ValueKey('primary-scroll-$index')),
            const Offset(0, -220),
          );
          await tester.pumpAndSettle();
          expect(states[index].scroll.offset, greaterThan(0));
          offsets.add(states[index].scroll.offset);
        }
        await tester.enterText(find.byKey(_searchKey), '顶栏未提交搜索');
        final searchController = tester
            .widget<TextField>(find.byKey(_searchKey))
            .controller;
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        for (final location in [
          '/downloads',
          '/settings/appearance',
          '/player',
        ]) {
          await _push(tester, fixture.router, location);
          expect(fixture.workspaceKey.currentState, same(workspace));
          for (var index = 0; index < 5; index++) {
            expect(workspace.pageKeys[index].currentState, same(states[index]));
            expect(states[index].mounted, isTrue);
          }
          expect(
            tester
                .widget<TextField>(find.byKey(_searchKey, skipOffstage: false))
                .controller,
            same(searchController),
          );
          if (location == '/player') {
            expect(find.byKey(_searchKey), findsNothing);
            expect(find.byKey(_outerBarKey), findsNothing);
            expect(find.byKey(_playerBarKey), findsOneWidget);
          } else {
            _expectEmbedded(tester);
          }
          await _pop(tester, fixture.router);
          expect(find.byKey(_searchKey), findsOneWidget);
          expect(searchController!.text, '顶栏未提交搜索');
          for (var index = 0; index < 5; index++) {
            expect(workspace.pageKeys[index].currentState, same(states[index]));
            expect(states[index].count, 1);
            expect(states[index].input.text, '主区$index的未提交输入');
            expect(states[index].scroll.offset, closeTo(offsets[index], .01));
          }
          expect(tester.takeException(), isNull);
        }
        expect(workspace.index, 4);
        expect(find.text('主区4计数1'), findsOneWidget);
        _expectEmbedded(tester);
      });
    }
  }
}

class _WorkspaceHarness extends StatefulWidget {
  const _WorkspaceHarness({super.key, this.routeBody, this.path = '/'});

  final Widget? routeBody;
  final String path;

  @override
  State<_WorkspaceHarness> createState() => _WorkspaceHarnessState();
}

class _WorkspaceHarnessState extends State<_WorkspaceHarness> {
  final pageKeys = [
    for (var index = 0; index < 5; index++) GlobalKey<_PrimaryPageState>(),
  ];
  int index = 0;

  @override
  Widget build(BuildContext context) => IkDesktopWorkspace(
    index: index,
    onSelect: (next) => setState(() => index = next),
    onAccount: () => setState(() => index = 4),
    onSearch: (_) => setState(() => index = 1),
    alignToDesign: true,
    routeBody: widget.routeBody,
    showRouteBody: widget.path != '/',
    fullPage: widget.path == '/player',
    pages: [
      for (var page = 0; page < 5; page++)
        _PrimaryPage(key: pageKeys[page], index: page),
    ],
    playbackBar: const SizedBox(
      key: _outerBarKey,
      height: 56,
      child: Center(child: Text('常驻播放栏')),
    ),
  );
}

class _PrimaryPage extends StatefulWidget {
  const _PrimaryPage({super.key, required this.index});

  final int index;

  @override
  State<_PrimaryPage> createState() => _PrimaryPageState();
}

class _PrimaryPageState extends State<_PrimaryPage> {
  final input = TextEditingController();
  final scroll = ScrollController();
  int count = 0;

  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextButton(
        onPressed: () => setState(() => count++),
        child: Text('主区${widget.index}计数$count'),
      ),
      TextField(
        key: ValueKey('primary-input-${widget.index}'),
        controller: input,
      ),
      Expanded(
        child: ListView.builder(
          key: ValueKey('primary-scroll-${widget.index}'),
          controller: scroll,
          itemCount: 60,
          itemExtent: 48,
          itemBuilder: (_, row) => Text('主区${widget.index}第$row行'),
        ),
      ),
    ],
  );
}

class _DetailPage extends StatelessWidget {
  const _DetailPage(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Center(child: Text('$title正文')),
  );
}

class _PlayerPage extends StatefulWidget {
  const _PlayerPage();

  @override
  State<_PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<_PlayerPage> {
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('独立播放器夹具')),
    body: Column(
      children: [
        TextButton(
          onPressed: () => context.push('/queue'),
          child: const Text('打开真实队列'),
        ),
        TextButton(
          onPressed: () => context.push('/album/qq/nav-album'),
          child: const Text('打开真实专辑'),
        ),
      ],
    ),
    bottomNavigationBar: const SizedBox(
      key: _playerBarKey,
      height: 56,
      child: Center(child: Text('详情播放栏')),
    ),
  );
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

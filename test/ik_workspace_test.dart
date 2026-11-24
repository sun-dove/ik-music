import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/platform/platform_utils.dart';
import 'package:mconnect/video_app/ik/ik_workspace.dart';
import 'package:mconnect/video_app/ik/ik_controls.dart';

void main() {
  for (final width in [320.0, 390.0, 720.0, 900.0, 1200.0, 1440.0]) {
    for (final scale in [1.0, 1.25, 1.5]) {
      testWidgets('U01/U02/U11 五区、账号、底栏 $width/$scale', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var selected = -1;
        var account = false;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 900),
                textScaler: TextScaler.linear(scale),
              ),
              child: IkDesktopWorkspace(
                index: 0,
                onSelect: (value) => selected = value,
                onAccount: () => account = true,
                pages: const [
                  Text('发现内容'),
                  Text('搜索内容'),
                  Text('曲库内容'),
                  Text('历史内容'),
                  Text('设置内容'),
                ],
                playbackBar: const Text('共用播放栏'),
              ),
            ),
          ),
        );
        for (var i = 0; i < 5; i++) {
          await tester.tap(find.byKey(ValueKey('ik-workspace-nav-$i')));
          expect(selected, i);
        }
        await tester.tap(find.byKey(const ValueKey('ik-workspace-account')));
        expect(account, isTrue);
        expect(find.text('IK Music'), findsOneWidget);
        expect(find.text('共用播放栏'), findsOneWidget);
        expect(find.text('我的'), findsNothing);
        expect(find.text('接下来播放'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('U03 下拉键盘选择、勾选及取消', (tester) async {
    var value = 'a';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => Center(
              child: IkSelect<String>(
                label: '来源',
                value: value,
                items: const {'a': '全部来源', 'b': '网易云', 'c': '酷狗'},
                onChanged: (next) => update(() => value = next),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(IkSelect<String>));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    await tester.tap(find.text('网易云'));
    await tester.pumpAndSettle();
    expect(value, 'b');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(value, 'b');
    expect(tester.takeException(), isNull);
  });

  // 正式长期门：系统返回必须经过真实Navigator，不以Escape代替。
  testWidgets('B01/B03 来源菜单系统返回先取消，第二次返回恢复导航', (tester) async {
    final h = await _mountSourceBack(tester);
    final query = h.page.query;
    h.page.results.jumpTo(120);
    await tester.pump();
    final offset = h.page.results.offset;
    await tester.tap(find.byType(IkSelect<String>));
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNWidgets(5));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('source-back-page')), findsOneWidget);
    expect(find.byType(MenuItemButton), findsNothing);
    expect(h.route.isCurrent, isTrue);
    expect(h.page.mounted, isTrue);
    expect(h.page.query, same(query));
    expect(query.text, 'music');
    expect(h.page.filter, 'netease');
    expect(h.page.selections, 0);
    expect(h.page.results.offset, offset);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('测试起点'), findsOneWidget);
    expect(find.byKey(const ValueKey('source-back-page')), findsNothing);
    expect(h.page.disposed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('B02 来源选择仅一次，外点Escape系统返回取消保持选择', (tester) async {
    final h = await _mountSourceBack(tester);
    Future<void> open() async {
      await tester.tap(find.byType(IkSelect<String>));
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNWidgets(5));
    }

    await open();
    await tester.tap(find.widgetWithText(MenuItemButton, '酷狗'));
    await tester.pumpAndSettle();
    expect(h.page.filter, 'kugou');
    expect(h.page.selections, 1);
    expect(find.byType(MenuItemButton), findsNothing);
    await open();
    await tester.tapAt(const Offset(10, 580));
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNothing);
    await open();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNothing);
    await open();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNothing);
    expect(h.route.isCurrent, isTrue);
    expect(h.page.filter, 'kugou');
    expect(h.page.selections, 1);
    expect(h.page.query.text, 'music');
    expect(tester.takeException(), isNull);
  });

  testWidgets('B04 来源菜单打开时route移除可安全dispose', (tester) async {
    final h = await _mountSourceBack(tester);
    await tester.tap(find.byType(IkSelect<String>));
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNWidgets(5));
    h.navigator.currentState!.removeRoute(h.route);
    await tester.pumpAndSettle();
    expect(h.page.disposed, isTrue);
    expect(find.byType(MenuItemButton), findsNothing);
    expect(find.text('测试起点'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final flag in <bool?>[null, false]) {
    testWidgets('B05 Windows菜单缺省$flag保持旧系统返回', (tester) async {
      final h = await _mountSourceBack(
        tester,
        dismissOnSystemBack: flag,
        platform: AppPlatform.windows,
      );
      await tester.tap(find.byType(IkSelect<String>));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('source-back-page')), findsNothing);
      expect(find.text('测试起点'), findsOneWidget);
      expect(h.page.disposed, isTrue);
      expect(h.page.selections, 0);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<
  ({
    GlobalKey<NavigatorState> navigator,
    MaterialPageRoute<void> route,
    _SourceBackPageState page,
  })
>
_mountSourceBack(
  WidgetTester tester, {
  bool? dismissOnSystemBack = true,
  AppPlatform platform = AppPlatform.android,
}) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  PlatformUtils.setDebugOverride(platform);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    PlatformUtils.setDebugOverride(null);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final navigator = GlobalKey<NavigatorState>();
  final pageKey = GlobalKey<_SourceBackPageState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      home: const Scaffold(body: Center(child: Text('测试起点'))),
    ),
  );
  final route = MaterialPageRoute<void>(
    builder: (_) =>
        _SourceBackPage(key: pageKey, dismissOnSystemBack: dismissOnSystemBack),
  );
  navigator.currentState!.push(route);
  await tester.pumpAndSettle();
  return (navigator: navigator, route: route, page: pageKey.currentState!);
}

class _SourceBackPage extends StatefulWidget {
  const _SourceBackPage({super.key, this.dismissOnSystemBack});
  final bool? dismissOnSystemBack;
  @override
  State<_SourceBackPage> createState() => _SourceBackPageState();
}

class _SourceBackPageState extends State<_SourceBackPage> {
  final query = TextEditingController(text: 'music');
  final results = ScrollController();
  var filter = 'netease';
  var selections = 0;
  var disposed = false;
  @override
  void dispose() {
    disposed = true;
    query.dispose();
    results.dispose();
    super.dispose();
  }

  void _select(String next) => setState(() {
    filter = next;
    selections++;
  });

  static const _items = {
    'all': '全部来源',
    'local': '本地',
    'qq': 'QQ音乐',
    'netease': '网易云',
    'kugou': '酷狗',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const ValueKey('source-back-page'),
    body: Column(
      children: [
        TextField(controller: query),
        if (widget.dismissOnSystemBack case final flag?)
          IkSelect<String>(
            dismissOnSystemBack: flag,
            label: '来源',
            value: filter,
            items: _items,
            onChanged: _select,
          )
        else
          IkSelect<String>(
            label: '来源',
            value: filter,
            items: _items,
            onChanged: _select,
          ),
        Expanded(
          child: ListView(
            controller: results,
            children: [
              for (var i = 0; i < 30; i++)
                SizedBox(height: 48, child: Text('来源结果 $i')),
            ],
          ),
        ),
      ],
    ),
  );
}

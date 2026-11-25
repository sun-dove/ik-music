import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/l10n/expanded_strings.dart';
import 'package:mconnect/video_app/ik/ik_workspace_navigation.dart';
import 'package:mconnect/video_app/lx_source/lx_source.dart';
import 'package:mconnect/video_app/multi_source/source_collection.dart';
import 'package:mconnect/video_app/ui/source_manager_page.dart';

// 正式长期门：主导航与共用搜索离开音源草稿时，复用原保存契约。
void main() {
  testWidgets('E05 现代音源页向正文注册一次且销毁注销，未改动可直接离开', (tester) async {
    final h = await _mount(tester);
    expect(h.guards, hasLength(1));
    final identity = h.guards.keys.single;
    final check = h.guards.values.single;
    expect(await check(), isTrue);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.byKey(const ValueKey('manager-platform-tx')));
    await tester.pumpAndSettle();
    expect(h.guards.keys.single, same(identity));
    expect(h.registrations, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(h.guards, isEmpty);
    expect(h.unregistrations, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('E05 旧默认即使有正文scope也不注册', (tester) async {
    final h = await _mount(tester, modern: false);
    expect(h.guards, isEmpty);
    expect(h.registrations, 0);
    expect(find.byType(ExpansionTile), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(h.unregistrations, 0);
  });

  testWidgets('E05 无scope的新菜单沿用页内返回草稿保护', (tester) async {
    final h = await _mount(tester, withScope: false, pushed: true);
    await _dirty(tester);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text(ExpandedStrings.keepEditing));
    await tester.pumpAndSettle();
    expect(find.byType(SourceManagerPage), findsOneWidget);
    expect(h.saves, isEmpty);
    expect(h.guards, isEmpty);
  });

  testWidgets('E05 主导航继续编辑不离开不写入，草稿和选择保持', (tester) async {
    final h = await _mount(tester);
    await _dirty(tester);
    final decision = h.guards.values.single();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text(ExpandedStrings.keepEditing));
    await tester.pumpAndSettle();
    expect(await decision, isFalse);
    expect(h.saves, isEmpty);
    expect(find.text(ExpandedStrings.dirty), findsOneWidget);
    expect(_autoSwitch(tester), isTrue);
    expect(find.byType(SourceManagerPage), findsOneWidget);
  });

  testWidgets('E05 主导航放弃允许离开但不写入，父级尚未清栈时不丢草稿', (tester) async {
    final h = await _mount(tester);
    await _dirty(tester);
    final decision = h.guards.values.single();
    await tester.pumpAndSettle();
    await tester.tap(find.text(ExpandedStrings.discard));
    await tester.pumpAndSettle();
    expect(await decision, isTrue);
    expect(h.saves, isEmpty);
    expect(_autoSwitch(tester), isTrue);
    expect(find.text(ExpandedStrings.dirty), findsOneWidget);
    expect(find.byType(SourceManagerPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(h.guards, isEmpty);
  });

  testWidgets('E05 主导航保存失败阻止离开，重试成功后仅保存一次成功结果', (tester) async {
    final h = await _mount(tester);
    h.failSave = true;
    await _dirty(tester);
    var decision = h.guards.values.single();
    await tester.pumpAndSettle();
    await tester.tap(find.text(ExpandedStrings.saveAndReturn));
    await tester.pumpAndSettle();
    expect(await decision, isFalse);
    expect(find.text(ExpandedStrings.saveFailed), findsOneWidget);
    expect(find.text(ExpandedStrings.dirty), findsOneWidget);
    expect(h.saves, isEmpty);
    expect(_autoSwitch(tester), isTrue);
    h.failSave = false;
    decision = h.guards.values.single();
    await tester.pumpAndSettle();
    await tester.tap(find.text(ExpandedStrings.saveAndReturn));
    await tester.pumpAndSettle();
    expect(await decision, isTrue);
    expect(h.saves, hasLength(1));
    expect(h.saves.single.autoSwitch, isTrue);
    expect(find.text(ExpandedStrings.dirty), findsNothing);
    expect(await h.guards.values.single(), isTrue);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('E05 检查音源时主导航阻止离开且不取消正在运行任务', (tester) async {
    final pending = Completer<void>();
    CancelToken? token;
    final h = await _mount(
      tester,
      inspect: (_, value) {
        token = value;
        return pending.future;
      },
    );
    await tester.tap(find.byKey(const ValueKey('manager-inspect-all')));
    await tester.pump();
    expect(token, isNotNull);
    expect(await h.guards.values.single(), isFalse);
    expect(token!.isCancelled, isFalse);
    expect(find.byType(AlertDialog), findsNothing);
    pending.complete();
    await tester.pumpAndSettle();
    expect(await h.guards.values.single(), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('E05 主导航连续两次离开请求共用同一个草稿提示', (tester) async {
    final h = await _mount(tester);
    await _dirty(tester);
    final first = h.guards.values.single();
    final second = h.guards.values.single();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text(ExpandedStrings.keepEditing));
    await tester.pumpAndSettle();
    expect(await first, isFalse);
    expect(await second, isFalse);
    expect(h.saves, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('E05 主导航先关闭展开菜单，再处理一次草稿确认', (tester) async {
    final h = await _mount(tester);
    await _dirty(tester);
    await tester.tap(find.byKey(const ValueKey('manager-policy-trigger')));
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNWidgets(2));
    final decision = h.guards.values.single();
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNothing);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text(ExpandedStrings.keepEditing));
    await tester.pumpAndSettle();
    expect(await decision, isFalse);
    expect(find.byType(SourceManagerPage), findsOneWidget);
  });

  testWidgets('E05 音源保存返回晚完成不弹覆盖页，返回原页已保存且不再提示', (tester) async {
    final h = await _mount(tester, pushed: true);
    final pending = Completer<void>();
    h.pendingSave = pending;
    final managerState = tester.state(find.byType(SourceManagerPage));
    await _dirty(tester);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ExpandedStrings.saveAndReturn));
    await tester.pump();
    expect(h.saveCalls, 1);
    expect(h.saves, isEmpty);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    final navigator = Navigator.of(
      tester.element(find.byType(SourceManagerPage)),
    );
    var coverReturned = false;
    unawaited(
      navigator
          .push<void>(
            MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('保存期间打开的播放详情')),
                body: const Text('播放详情仍需保留'),
              ),
            ),
          )
          .then((_) => coverReturned = true),
    );
    await tester.pumpAndSettle();
    expect(find.text('播放详情仍需保留'), findsOneWidget);
    expect(coverReturned, isFalse);
    pending.complete();
    await tester.pumpAndSettle();
    expect(h.saves, hasLength(1));
    expect(h.saves.single.autoSwitch, isTrue);
    expect(find.text('播放详情仍需保留'), findsOneWidget, reason: '音源页保存晚完成不能pop当前覆盖页');
    expect(coverReturned, isFalse);

    navigator.pop();
    await tester.pumpAndSettle();
    expect(coverReturned, isTrue);
    expect(tester.state(find.byType(SourceManagerPage)), same(managerState));
    expect(find.text(ExpandedStrings.saved), findsOneWidget);
    expect(find.text(ExpandedStrings.dirty), findsNothing);
    expect(_autoSwitch(tester), isTrue);
    expect(await h.guards.values.single(), isTrue);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('测试起点'), findsOneWidget);
    expect(h.guards, isEmpty);
    expect(h.saveCalls, 1);
    expect(h.saves, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}

bool _autoSwitch(WidgetTester tester) => tester
    .widget<SwitchListTile>(find.byKey(const ValueKey('manager-auto-switch')))
    .value;

Future<void> _dirty(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('manager-auto-switch')));
  await tester.pumpAndSettle();
  expect(find.text(ExpandedStrings.dirty), findsOneWidget);
}

class _Harness {
  final guards = <Object, Future<bool> Function()>{};
  final saves = <SourceCollection>[];
  bool failSave = false;
  Completer<void>? pendingSave;
  int saveCalls = 0;
  int registrations = 0, unregistrations = 0;

  void register(Object identity, Future<bool> Function() check) {
    registrations++;
    guards[identity] = check;
  }

  void unregister(Object identity) {
    unregistrations++;
    guards.remove(identity);
  }

  Future<void> save(SourceCollection value) async {
    saveCalls++;
    await pendingSave?.future;
    if (failSave) throw StateError('fixture-save');
    saves.add(value);
  }
}

Future<_Harness> _mount(
  WidgetTester tester, {
  bool modern = true,
  bool withScope = true,
  bool pushed = false,
  Future<void> Function(LxSourceConfig, CancelToken)? inspect,
}) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final h = _Harness();
  final navigator = GlobalKey<NavigatorState>();
  Widget page() => SourceManagerPage(
    modernPolicyMenu: modern,
    initial: SourceCollection(
      entries: [
        SourceEntry(
          'one',
          LxSourceConfig(
            name: '保留音源',
            version: '1',
            origin: Uri.parse('https://example.com/source.js'),
            script: 'fixture',
            sha256: 'fixture',
            enabled: true,
            sources: const {
              'tx': ['128k'],
            },
          ),
        ),
      ],
    ),
    onImport: (_, _) async => throw UnimplementedError(),
    onInspect: inspect ?? (_, _) async {},
    onSave: h.save,
    onHttp: () {},
  );
  final app = MaterialApp(
    navigatorKey: navigator,
    home: pushed ? const Scaffold(body: Text('测试起点')) : page(),
  );
  await tester.pumpWidget(
    withScope
        ? IkWorkspaceNavigation(
            register: h.register,
            unregister: h.unregister,
            child: app,
          )
        : app,
  );
  if (pushed) {
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => page()),
      ),
    );
  }
  await tester.pumpAndSettle();
  return h;
}

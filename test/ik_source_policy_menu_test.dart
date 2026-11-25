import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/l10n/expanded_strings.dart';
import 'package:mconnect/l10n/source_strings.dart';
import 'package:mconnect/video_app/ik/ik_theme.dart';
import 'package:mconnect/video_app/lx_source/lx_source.dart';
import 'package:mconnect/video_app/multi_source/source_collection.dart';
import 'package:mconnect/video_app/ui/source_manager_page.dart';

// 正式长期门：音源顺序菜单与三项既有策略的保存、取消及兼容。
void main() {
  for (final enabled in [false, true]) {
    testWidgets('E11 菜单开关$enabled保留旧默认或启用新菜单', (tester) async {
      await _mount(tester, modern: enabled);
      expect(
        find.byType(ExpansionTile),
        enabled ? findsNothing : findsOneWidget,
      );
      expect(_trigger, enabled ? findsOneWidget : findsNothing);
      if (!enabled) {
        await tester.tap(find.text(ExpandedStrings.playPolicy));
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(SwitchListTile, SourceStrings.autoSwitch),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(SwitchListTile, SourceStrings.sourceFirst),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(SwitchListTile, SourceStrings.highest),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('E11 展开菜单不挤列表，宽度与触发框一致，选择只改变优先顺序', (tester) async {
    SourceCollection? saved;
    final initial = _sources().copyWith(autoSwitch: true, highestQuality: true);
    await _mount(
      tester,
      initial: initial,
      onSave: (value) async => saved = value,
    );
    final before = tester.getRect(find.byKey(const ValueKey('manager-search')));
    await _open(tester);
    final anchor = tester.widget<MenuAnchor>(find.byType(MenuAnchor));
    final menu = find
        .ancestor(of: _option(false), matching: find.byType(Material))
        .first;
    expect(
      tester.getRect(find.byKey(const ValueKey('manager-search'))),
      before,
    );
    expect(
      tester.getSize(menu).width,
      closeTo(tester.getSize(_trigger).width, 1),
    );
    expect(anchor.style!.backgroundColor!.resolve({})!.a, 1);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    await tester.tap(_option(true));
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNothing);
    expect(
      find.descendant(of: _trigger, matching: find.text('备用音源优先')),
      findsOneWidget,
    );
    expect(find.text(ExpandedStrings.dirty), findsOneWidget);
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(saved!.sourceFirst, isTrue);
    expect(saved!.autoSwitch, initial.autoSwitch);
    expect(saved!.highestQuality, initial.highestQuality);
    expect(saved!.entries, orderedEquals(initial.entries));
    expect(saved!.preferredId, initial.preferredId);
    expect(tester.takeException(), isNull);
  });

  testWidgets('E11 三个策略全部八种组合保存后可回读', (tester) async {
    for (final auto in [false, true]) {
      for (final highest in [false, true]) {
        for (final sourceFirst in [false, true]) {
          SourceCollection? saved;
          await _mount(tester, onSave: (value) async => saved = value);
          if (sourceFirst) {
            await _open(tester);
            await tester.tap(_option(true));
            await tester.pumpAndSettle();
          }
          if (auto) {
            await tester.tap(find.byKey(const ValueKey('manager-auto-switch')));
            await tester.pumpAndSettle();
          }
          if (highest) {
            await tester.tap(find.byKey(const ValueKey('manager-highest')));
            await tester.pumpAndSettle();
          }
          await tester.tap(_save);
          await tester.pumpAndSettle();
          expect(saved!.autoSwitch, auto);
          expect(saved!.highestQuality, highest);
          expect(saved!.sourceFirst, sourceFirst);
          await _mount(tester, initial: saved!);
          expect(_switch(tester, 'manager-auto-switch'), auto);
          expect(_switch(tester, 'manager-highest'), highest);
          await _open(tester);
          expect(
            find.descendant(
              of: _option(sourceFirst),
              matching: find.byIcon(Icons.check_rounded),
            ),
            findsOneWidget,
          );
        }
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('E11 推荐设置保留三项开启与已存条目', (tester) async {
    SourceCollection? saved;
    final initial = _sources();
    await _mount(
      tester,
      initial: initial,
      onSave: (value) async => saved = value,
    );
    await tester.tap(find.text(SourceStrings.recommended));
    await tester.pumpAndSettle();
    expect(_switch(tester, 'manager-auto-switch'), isTrue);
    expect(_switch(tester, 'manager-highest'), isTrue);
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(saved!.sourceFirst, isTrue);
    expect(saved!.autoSwitch, isTrue);
    expect(saved!.highestQuality, isTrue);
    expect(saved!.entries, orderedEquals(initial.entries));
  });

  testWidgets('E11 方向键Enter选择，Esc和外点取消不改变草稿', (tester) async {
    SourceCollection? saved;
    await _mount(tester, onSave: (value) async => saved = value);
    await _open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNWidgets(2));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNothing);
    expect(
      find.descendant(of: _trigger, matching: find.text('备用音源优先')),
      findsOneWidget,
    );
    await _open(tester);
    await tester.tapAt(const Offset(900, 870));
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNothing);
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(saved!.sourceFirst, isTrue);
    expect(saved!.autoSwitch, isFalse);
    expect(saved!.highestQuality, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('E11 菜单打开时系统返回只关菜单，随后草稿可放弃不写入', (tester) async {
    var writes = 0;
    await _mount(tester, pushed: true, onSave: (_) async => writes++);
    await _open(tester);
    await tester.tap(_option(true));
    await tester.pumpAndSettle();
    await _open(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SourceManagerPage), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text(ExpandedStrings.discard));
    await tester.pumpAndSettle();
    expect(find.text('测试起点'), findsOneWidget);
    expect(writes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('E11 保存失败保留新策略可重试，保存期间菜单禁用', (tester) async {
    var fail = true;
    SourceCollection? saved;
    await _mount(
      tester,
      onSave: (value) async {
        if (fail) throw StateError('fixture-save');
        saved = value;
      },
    );
    await _open(tester);
    await tester.tap(_option(true));
    await tester.pumpAndSettle();
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(find.text(ExpandedStrings.saveFailed), findsOneWidget);
    expect(find.text(ExpandedStrings.dirty), findsOneWidget);
    fail = false;
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(saved!.sourceFirst, isTrue);
    expect(find.text(ExpandedStrings.saved), findsOneWidget);

    final waiting = Completer<void>();
    await _mount(tester, onSave: (_) => waiting.future);
    await tester.tap(_save);
    await tester.pump();
    expect(tester.widget<OutlinedButton>(_trigger).onPressed, isNull);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('manager-auto-switch')),
          )
          .onChanged,
      isNull,
    );
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const ValueKey('manager-highest')))
          .onChanged,
      isNull,
    );
    waiting.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    for (final width in [320.0, 390.0, 720.0, 900.0, 1200.0, 1440.0, 1920.0]) {
      for (final scale in [1.0, 1.25, 1.5]) {
        testWidgets('E11 菜单尺寸与文字 $brightness/$width/$scale', (tester) async {
          await _mount(
            tester,
            width: width,
            scale: scale,
            brightness: brightness,
          );
          final before = tester.getRect(
            find.byKey(const ValueKey('manager-search')),
          );
          await _open(tester);
          expect(
            tester.getRect(find.byKey(const ValueKey('manager-search'))),
            before,
          );
          for (final value in [false, true]) {
            final rect = tester.getRect(_option(value));
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(width));
            expect(rect.bottom, lessThanOrEqualTo(900));
            expect(_option(value).hitTestable(), findsOneWidget);
          }
          await tester.tap(_option(true));
          await tester.pumpAndSettle();
          expect(find.byType(MenuItemButton), findsNothing);
          expect(_save.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}

Finder get _trigger => find.byKey(const ValueKey('manager-policy-trigger'));
Finder get _save => find.byKey(const ValueKey('manager-save'));
Finder _option(bool value) =>
    find.byKey(ValueKey('manager-policy-option-$value'));
bool _switch(WidgetTester tester, String key) =>
    tester.widget<SwitchListTile>(find.byKey(ValueKey(key))).value;

Future<void> _open(WidgetTester tester) async {
  if (_trigger.hitTestable().evaluate().isEmpty) {
    await tester.ensureVisible(_trigger);
  }
  await tester.tap(_trigger);
  await tester.pumpAndSettle();
  expect(find.byType(MenuItemButton), findsNWidgets(2));
}

SourceCollection _sources() => SourceCollection(
  preferredId: 'source-1',
  entries: [
    for (var i = 0; i < 3; i++)
      SourceEntry(
        'source-$i',
        LxSourceConfig(
          name: '音源$i',
          version: '1',
          origin: Uri.parse('https://example.com/$i.js'),
          script: 'fixture',
          sha256: 'hash-$i',
          enabled: true,
          sources: const {
            'tx': ['128k'],
            'wy': ['320k'],
          },
        ),
      ),
  ],
);

Future<void> _mount(
  WidgetTester tester, {
  bool modern = true,
  bool pushed = false,
  SourceCollection? initial,
  Future<void> Function(SourceCollection)? onSave,
  double width = 1200,
  double scale = 1,
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final navigator = GlobalKey<NavigatorState>();
  Widget page() => SourceManagerPage(
    initial: initial ?? _sources(),
    modernPolicyMenu: modern,
    onImport: (_, _) async => throw UnimplementedError(),
    onInspect: (_, _) async {},
    onSave: onSave ?? (_) async {},
    onHttp: () {},
  );
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      theme: IkTheme.from(ThemeData(brightness: brightness)),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: pushed ? const Scaffold(body: Text('测试起点')) : page(),
    ),
  );
  if (pushed) {
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => page()),
      ),
    );
  }
  await tester.pumpAndSettle();
}

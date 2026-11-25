import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/l10n/expanded_strings.dart';
import 'package:mconnect/l10n/source_strings.dart';
import 'package:mconnect/l10n/video_strings.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/video_app/custom_source/custom_source_models.dart';
import 'package:mconnect/video_app/ik/ik_workspace_navigation.dart';
import 'package:mconnect/video_app/ui/custom_source_page.dart';

// 正式长期门：HTTP音源草稿离开保护及异步提交不误弹新页面。
void main() {
  testWidgets('E05 HTTP新模式注册一次且销毁注销，未修改直接离开', (tester) async {
    final h = await _mount(tester);
    expect(h.guards, hasLength(1));
    expect(await h.check(), isTrue);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(h.guards, isEmpty);
    expect(h.unregistered, 1);
  });

  testWidgets('E05 HTTP旧默认不注册且沿用void保存删除回调', (tester) async {
    final h = await _mount(tester, protect: false);
    expect(h.guards, isEmpty);
    await tester.tap(find.text(VideoStrings.customSourceSave));
    await tester.pumpAndSettle();
    expect(h.legacySaves, 1);
    expect(h.commits, isEmpty);
    await tester.tap(find.text(VideoStrings.customSourceDelete));
    await tester.pumpAndSettle();
    await tester.tap(find.text(VideoStrings.customSourceConfirmDelete));
    await tester.pumpAndSettle();
    expect(h.legacyDeletes, 1);
    expect(h.removes, 0);
    expect(find.byType(VideoCustomSourcePage), findsOneWidget);
  });

  for (final field in [
    VideoCustomSourcePage.nameFieldKey,
    VideoCustomSourcePage.endpointFieldKey,
    VideoCustomSourcePage.tokenFieldKey,
    VideoCustomSourcePage.timeoutFieldKey,
    VideoCustomSourcePage.qqSwitchKey,
    VideoCustomSourcePage.neteaseSwitchKey,
    VideoCustomSourcePage.downloadSwitchKey,
    VideoCustomSourcePage.enabledSwitchKey,
  ]) {
    testWidgets('E05 HTTP所有字段$field修改均阻止静默离开', (tester) async {
      final h = await _mount(tester);
      final target = find.byKey(field);
      if (tester.widget(target) is TextField) {
        await tester.enterText(
          target,
          field == VideoCustomSourcePage.timeoutFieldKey ? '19' : '修改后的值',
        );
      } else {
        await tester.tap(target);
      }
      await tester.pumpAndSettle();
      final leaving = h.check();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text(ExpandedStrings.keepEditing));
      await tester.pumpAndSettle();
      expect(await leaving, isFalse);
      expect(h.commits, isEmpty);
      expect(find.byType(VideoCustomSourcePage), findsOneWidget);
    });
  }

  testWidgets('E05 HTTP放弃只授权离开，父级清栈前草稿保留且不写入', (tester) async {
    final h = await _mount(tester);
    await _rename(tester);
    final leaving = h.check();
    await tester.pumpAndSettle();
    await tester.tap(find.text(ExpandedStrings.discard));
    await tester.pumpAndSettle();
    expect(await leaving, isTrue);
    expect(h.commits, isEmpty);
    expect(_name(tester), '修改音源');
    expect(find.byType(VideoCustomSourcePage), findsOneWidget);
  });

  testWidgets('E05 HTTP保存失败留草稿，成功更新基准，主导航提交不自行pop', (tester) async {
    final h = await _mount(tester);
    h.commitResult = false;
    await _rename(tester);
    var leaving = h.check();
    await tester.pumpAndSettle();
    await tester.tap(find.text(ExpandedStrings.saveAndReturn));
    await tester.pumpAndSettle();
    expect(await leaving, isFalse);
    expect(find.text(ExpandedStrings.saveFailed), findsOneWidget);
    expect(_name(tester), '修改音源');
    h.commitResult = true;
    leaving = h.check();
    await tester.pumpAndSettle();
    await tester.tap(find.text(ExpandedStrings.saveAndReturn));
    await tester.pumpAndSettle();
    expect(await leaving, isTrue);
    expect(h.commits, hasLength(2));
    expect(h.commits.last.name, '修改音源');
    expect(find.byType(VideoCustomSourcePage), findsOneWidget);
    expect(await h.check(), isTrue);
    expect(find.byType(AlertDialog), findsNothing);
    expect(h.legacySaves, 0);
  });

  testWidgets('E05 HTTP配置错误显示可读原因，其他异常不泄漏内容', (tester) async {
    final h = await _mount(tester);
    h.commitError = const CustomSourceConfigurationException(
      'endpoint',
      '必须填写HTTPS地址',
    );
    await _rename(tester);
    await tester.tap(find.text(VideoStrings.customSourceSave));
    await tester.pumpAndSettle();
    expect(find.text('必须填写HTTPS地址'), findsOneWidget);
    expect(find.byType(VideoCustomSourcePage), findsOneWidget);
    h.commitError = StateError('private-fixture-value');
    await tester.tap(find.text(VideoStrings.customSourceSave));
    await tester.pumpAndSettle();
    expect(find.text(ExpandedStrings.saveFailed), findsOneWidget);
    expect(find.textContaining('private-fixture-value'), findsNothing);
  });

  testWidgets('E05 HTTP保存中禁用编辑及按钮并阻止主导航系统返回', (tester) async {
    final h = await _mount(tester);
    h.pendingCommit = Completer<bool>();
    await _rename(tester);
    await tester.tap(find.text(VideoStrings.customSourceSave));
    await tester.pump();
    expect(await h.check(), isFalse);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(VideoCustomSourcePage), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
      expect(field.enabled, isFalse);
    }
    for (final control in tester.widgetList<SwitchListTile>(
      find.byType(SwitchListTile),
    )) {
      expect(control.onChanged, isNull);
    }
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, VideoStrings.customSourceSave),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, VideoStrings.customSourceTest),
          )
          .onPressed,
      isNull,
    );
    h.pendingCommit!.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('HTTP测试起点'), findsOneWidget);
    expect(h.guards, isEmpty);
  });

  testWidgets('E05 HTTP晚到保存成功不pop覆盖页，回访已保存基准不再提示', (tester) async {
    final h = await _mount(tester);
    h.pendingCommit = Completer<bool>();
    await _rename(tester);
    await tester.tap(find.text(VideoStrings.customSourceSave));
    await tester.pump();
    unawaited(
      h.navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('覆盖页')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    h.pendingCommit!.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('覆盖页'), findsOneWidget);
    h.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(VideoCustomSourcePage), findsOneWidget);
    expect(await h.check(), isTrue);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('E05 HTTP保存时页面被移除，晚结果不会弹其他页或报错', (tester) async {
    final h = await _mount(tester);
    h.pendingCommit = Completer<bool>();
    await _rename(tester);
    await tester.tap(find.text(VideoStrings.customSourceSave));
    await tester.pump();
    h.navigator.currentState!.removeRoute(h.route);
    await tester.pumpAndSettle();
    h.pendingCommit!.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('HTTP测试起点'), findsOneWidget);
    expect(h.guards, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('E05 HTTP删除取消不执行，失败保留，删除中阻止离开，晚成功不弹覆盖页', (tester) async {
    final h = await _mount(tester);
    await tester.tap(find.text(VideoStrings.customSourceDelete));
    await tester.pumpAndSettle();
    await tester.tap(find.text(VideoStrings.customSourceCancel));
    await tester.pumpAndSettle();
    expect(h.removes, 0);
    h.removeResult = false;
    await _confirmDelete(tester);
    await tester.pumpAndSettle();
    expect(find.text(SourceStrings.operationFailed), findsOneWidget);
    expect(find.byType(VideoCustomSourcePage), findsOneWidget);
    h.pendingRemove = Completer<bool>();
    await _confirmDelete(tester);
    await tester.pump();
    expect(await h.check(), isFalse);
    unawaited(
      h.navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('删除覆盖页')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    h.pendingRemove!.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('删除覆盖页'), findsOneWidget);
    expect(h.legacyDeletes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('E05 HTTP无scope页内返回保护，重复主导航请求仅一个提示', (tester) async {
    final plain = await _mount(tester, withScope: false);
    await _rename(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text(ExpandedStrings.keepEditing));
    await tester.pumpAndSettle();
    expect(plain.commits, isEmpty);
    final h = await _mount(tester);
    await _rename(tester);
    final first = h.check();
    final second = h.check();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text(ExpandedStrings.keepEditing));
    await tester.pumpAndSettle();
    expect(await first, isFalse);
    expect(await second, isFalse);
  });

  testWidgets('E05 HTTP缺少新成功回调不猜void成功，也不调用旧保存删除', (tester) async {
    final h = await _mount(tester, commitCallback: false);
    await _rename(tester);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, VideoStrings.customSourceSave),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, VideoStrings.customSourceDelete),
          )
          .onPressed,
      isNull,
    );
    final leaving = h.check();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, ExpandedStrings.saveAndReturn),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text(ExpandedStrings.keepEditing));
    await tester.pumpAndSettle();
    expect(await leaving, isFalse);
    expect(h.legacySaves, 0);
    expect(h.legacyDeletes, 0);
  });
}

Future<void> _rename(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(VideoCustomSourcePage.nameFieldKey),
    '修改音源',
  );
  await tester.pumpAndSettle();
}

String _name(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(VideoCustomSourcePage.nameFieldKey))
    .controller!
    .text;

Future<void> _confirmDelete(WidgetTester tester) async {
  await tester.tap(find.text(VideoStrings.customSourceDelete));
  await tester.pumpAndSettle();
  await tester.tap(find.text(VideoStrings.customSourceConfirmDelete));
}

class _Harness {
  final navigator = GlobalKey<NavigatorState>();
  late MaterialPageRoute<void> route;
  final guards = <Object, Future<bool> Function()>{};
  final commits = <VideoCustomSourceDraft>[];
  int legacySaves = 0, legacyDeletes = 0, removes = 0, unregistered = 0;
  bool commitResult = true, removeResult = true;
  Object? commitError;
  Completer<bool>? pendingCommit, pendingRemove;
  Future<bool> check() => guards.values.single();

  Future<bool> commit(VideoCustomSourceDraft draft) async {
    commits.add(draft);
    if (commitError != null) throw commitError!;
    return pendingCommit?.future ?? commitResult;
  }

  Future<bool> remove() async {
    removes++;
    return pendingRemove?.future ?? removeResult;
  }
}

Future<_Harness> _mount(
  WidgetTester tester, {
  bool protect = true,
  bool withScope = true,
  bool commitCallback = true,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  tester.view.physicalSize = const Size(1200, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final h = _Harness();
  final app = MaterialApp(
    navigatorKey: h.navigator,
    home: const Scaffold(body: Text('HTTP测试起点')),
  );
  await tester.pumpWidget(
    withScope
        ? IkWorkspaceNavigation(
            register: (identity, check) => h.guards[identity] = check,
            unregister: (identity) {
              h.unregistered++;
              h.guards.remove(identity);
            },
            child: app,
          )
        : app,
  );
  h.route = MaterialPageRoute<void>(
    builder: (_) => VideoCustomSourcePage(
      protectWorkspaceDraft: protect,
      initialDraft: const VideoCustomSourceDraft(
        name: '家庭音源',
        endpoint: 'https://example.com/source',
        platforms: {PlatformType.qq},
      ),
      onTest: (_) async => const VideoCustomSourceTestResult.success(),
      onSave: (_) async => h.legacySaves++,
      onDelete: () async => h.legacyDeletes++,
      onCommit: commitCallback ? h.commit : null,
      onRemove: commitCallback ? h.remove : null,
    ),
  );
  unawaited(h.navigator.currentState!.push(h.route));
  await tester.pumpAndSettle();
  return h;
}

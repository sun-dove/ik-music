import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/core/theme/app_theme.dart';
import 'package:mconnect/features/smart_playlists/data/smart_playlist_repository.dart';
import 'package:mconnect/features/smart_playlists/domain/smart_playlist_rule.dart';
import 'package:mconnect/features/smart_playlists/presentation/pages/smart_playlist_editor_page.dart';
import 'package:mconnect/features/smart_playlists/presentation/providers/smart_playlists_provider.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/video_app/ik/ik_controls.dart';
import 'package:mconnect/video_app/ik/ik_workspace_theme.dart';
import 'package:mconnect/video_app/ui/video_theme.dart';

/// 正式 R07/R09 体验与功能门，见中文修订票据。
/// 成功路径使用真实编辑页、原通知器与实际 Hive 落盘读回，不替换保存算法。
/// 36 个布局组合各检查全部四排序；取消不保存，旧默认完整保持。
void main() {
  final captureFont = Platform.environment['IK_CAPTURE_UI_FONT'];
  if (captureFont != null && captureFont.isNotEmpty) {
    _ReadableCaptureBinding();
  } else {
    TestWidgetsFlutterBinding.ensureInitialized();
  }
  late Directory scratch;

  setUpAll(() async {
    scratch = await Directory.systemTemp.createTemp('ik-smart-sort-gate-');
    Hive.init(scratch.path);
    await Hive.openBox<dynamic>(smartPlaylistRulesBoxName);
    if (captureFont == null || captureFont.isEmpty) return;
    final data = ByteData.sublistView(await File(captureFont).readAsBytes());
    for (final family in [
      'sans-serif',
      'Roboto',
      'Microsoft YaHei UI',
      'Ahem',
    ]) {
      await (FontLoader(family)..addFont(Future.value(data))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  setUp(() async {
    await const HiveSmartPlaylistRepository().saveRules(const []);
  });

  tearDownAll(() async {
    await Hive.close();
    if (await scratch.exists()) await scratch.delete(recursive: true);
  });

  testWidgets('R07 IK 真实规则排序菜单锚定按钮且 Esc 不离开编辑页', (tester) async {
    // 自然锚点留出菜单宽度；全视窗右缘钳位由 36 个 R09 门另行全量检查。
    final fixture = await _mount(tester, rightInset: 48);
    await fixture.open(tester);
    await _revealSort(tester);
    _expectInlinePresentation(tester);
    await _openSort(tester);
    final anchor = tester.getRect(_selectButton());
    final first = tester.getRect(
      _menuItem(SmartPlaylistSortOrder.mostListened),
    );
    expect(first.top - anchor.bottom, inInclusiveRange(0, 20));
    expect(first.left - anchor.left, inInclusiveRange(-8, 20));
    _expectAllMenuItems(tester, SmartPlaylistSortOrder.mostListened);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNothing);
    expect(find.byType(SmartPlaylistEditorPage), findsOneWidget);
    expect(await _reloadRules(tester), isEmpty);
    await _openSort(tester);
    _expectAllMenuItems(tester, SmartPlaylistSortOrder.mostListened);
    expect(tester.takeException(), isNull);
  });

  for (final order in SmartPlaylistSortOrder.values) {
    testWidgets('R07 IK ${order.displayName} 经真实菜单保存并落盘读回', (tester) async {
      final fixture = await _mount(tester);
      await fixture.open(tester);
      await tester.enterText(find.byType(TextField).first, '排序-${order.name}');
      await _openSort(tester);
      _expectAllMenuItems(tester, SmartPlaylistSortOrder.mostListened);
      await _choose(tester, order);
      expect(await _reloadRules(tester), isEmpty);
      await fixture.save(tester);
      expect(find.byType(SmartPlaylistEditorPage), findsNothing);
      expect(find.text('打开规则编辑器'), findsOneWidget);
      final saved = (await _reloadRules(tester)).single;
      expect(saved.name, '排序-${order.name}');
      expect(saved.sortBy, order);
      expect(fixture.notifier.state.error, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('R07 IK 已存非默认排序正确加载，修改保留全部其他规则字段', (tester) async {
    final original = _existingRule();
    final fixture = await _mount(
      tester,
      rules: [original],
      ruleId: original.id,
    );
    await fixture.open(tester);
    await _openSort(tester);
    _expectAllMenuItems(tester, original.sortBy);
    await _choose(tester, SmartPlaylistSortOrder.mostPlayed);
    expect((await _reloadRules(tester)).single, original);
    await fixture.save(tester);
    final saved = (await _reloadRules(tester)).single;
    expect(saved.sortBy, SmartPlaylistSortOrder.mostPlayed);
    final originalFields = original.toJson()
      ..remove('sortBy')
      ..remove('updatedAt');
    final savedFields = saved.toJson()
      ..remove('sortBy')
      ..remove('updatedAt');
    expect(savedFields, originalFields);
    expect(saved.updatedAt.isBefore(original.updatedAt), isFalse);
    expect(find.text('打开规则编辑器'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('R07 IK 排序菜单两种取消均不保存、不改变原规则且留在编辑页', (tester) async {
    final original = _existingRule();
    final fixture = await _mount(
      tester,
      rules: [original],
      ruleId: original.id,
    );
    await fixture.open(tester);
    for (final escape in [true, false]) {
      await _openSort(tester);
      _expectAllMenuItems(tester, original.sortBy);
      if (escape) {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      } else {
        await tester.tap(find.text('编辑智能歌单'));
      }
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNothing);
      expect(find.byType(SmartPlaylistEditorPage), findsOneWidget);
      expect(
        tester.widget<IkSelect<SmartPlaylistSortOrder>>(_select()).value,
        original.sortBy,
      );
      expect((await _reloadRules(tester)).single, original);
      expect(fixture.notifier.state.rules.single, original);
    }
    expect(tester.takeException(), isNull);
  });

  for (final enabled in [null, false]) {
    testWidgets('R07 ${enabled == null ? '未标记' : '关闭标记'} 保持原排序下拉及四值实际保存', (
      tester,
    ) async {
      final fixture = await _mount(tester, enabled: enabled);
      for (final order in SmartPlaylistSortOrder.values) {
        await fixture.open(tester);
        await tester.enterText(
          find.byType(TextField).first,
          '旧排序-${order.name}',
        );
        await _revealSort(tester);
        final dropdown = find.byType(DropdownButton<SmartPlaylistSortOrder>);
        expect(dropdown, findsOneWidget);
        expect(_select(), findsNothing);
        final widget = tester.widget<DropdownButton<SmartPlaylistSortOrder>>(
          dropdown,
        );
        expect(widget.value, SmartPlaylistSortOrder.mostListened);
        expect(
          widget.items!.map((item) => item.value),
          SmartPlaylistSortOrder.values,
        );
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text(order.displayName).hitTestable().last);
        await tester.pumpAndSettle();
        expect(
          tester.widget<DropdownButton<SmartPlaylistSortOrder>>(dropdown).value,
          order,
        );
        await fixture.save(tester);
        expect(find.text('打开规则编辑器'), findsOneWidget);
        final saved = (await _reloadRules(tester))
            .singleWhere((rule) => rule.name == '旧排序-${order.name}');
        expect(saved.sortBy, order);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('R07 IK 排序保存失败显示原错误、保留编辑页及原持久化规则', (tester) async {
    final original = _existingRule();
    final fixture = await _mount(
      tester,
      rules: [original],
      ruleId: original.id,
      repository: const _RejectWrites(),
    );
    await fixture.open(tester);
    await _openSort(tester);
    await _choose(tester, SmartPlaylistSortOrder.recentlyPlayed);
    await fixture.save(tester);
    expect(find.byType(SmartPlaylistEditorPage), findsOneWidget);
    expect(find.text('智能歌单保存失败'), findsOneWidget);
    expect(fixture.notifier.state.error, '智能歌单保存失败');
    expect((await _reloadRules(tester)).single, original);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '保存'))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    for (final width in [320.0, 390.0, 720.0, 900.0, 1200.0, 1440.0]) {
      for (final scale in [1.0, 1.25, 1.5]) {
        testWidgets(
          'R09 IK 规则排序全四项 ${brightness == Brightness.light ? '浅' : '深'} ${width.toInt()}/$scale',
          (tester) async {
            final fixture = await _mount(
              tester,
              width: width,
              brightness: brightness,
              scale: scale,
            );
            await fixture.open(tester);
            await _openSort(tester);
            _expectInlinePresentation(tester);
            _expectInside(tester.getRect(_selectButton()), width);
            for (final order in SmartPlaylistSortOrder.values) {
              _expectAllMenuItems(
                tester,
                tester
                    .widget<IkSelect<SmartPlaylistSortOrder>>(_select())
                    .value,
              );
              for (final item in SmartPlaylistSortOrder.values) {
                _expectInside(tester.getRect(_menuItem(item)), width);
              }
              await _choose(tester, order);
              await _openSort(tester);
              _expectAllMenuItems(tester, order);
              final selected = _menuItem(order);
              final label = find.descendant(
                of: selected,
                matching: find.text(order.displayName),
              );
              final check = find.descendant(
                of: selected,
                matching: find.byIcon(Icons.check_rounded),
              );
              expect(
                (tester.getCenter(label).dy - tester.getCenter(check).dy).abs(),
                lessThanOrEqualTo(1),
              );
            }
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
            expect(find.byType(MenuItemButton), findsNothing);
            expect(find.byType(SmartPlaylistEditorPage), findsOneWidget);
            expect(await _reloadRules(tester), isEmpty);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}

Finder _select() => find.byType(IkSelect<SmartPlaylistSortOrder>);

Finder _selectButton() =>
    find.descendant(of: _select(), matching: find.byType(OutlinedButton));

Finder _menuItem(SmartPlaylistSortOrder order) =>
    find.widgetWithText(MenuItemButton, order.displayName);

Future<void> _revealSort(WidgetTester tester) async {
  if (find.text('排序方式').evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      find.text('排序方式'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(find.text('排序方式'));
  await tester.pumpAndSettle();
}

Future<void> _openSort(WidgetTester tester) async {
  await _revealSort(tester);
  expect(_selectButton(), findsOneWidget);
  await tester.tap(_selectButton());
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, SmartPlaylistSortOrder order) async {
  await tester.tap(_menuItem(order));
  await tester.pumpAndSettle();
  expect(find.byType(MenuItemButton), findsNothing);
  expect(
    tester.widget<IkSelect<SmartPlaylistSortOrder>>(_select()).value,
    order,
  );
}

void _expectInlinePresentation(WidgetTester tester) {
  expect(find.byType(SmartPlaylistEditorPage), findsOneWidget);
  expect(_select(), findsOneWidget);
  expect(
    tester.widget<IkSelect<SmartPlaylistSortOrder>>(_select()).alignToDesign,
    isTrue,
  );
  expect(find.byType(DropdownButton<SmartPlaylistSortOrder>), findsNothing);
  expect(find.byType(BottomSheet), findsNothing);
  expect(find.byType(Dialog), findsNothing);
}

void _expectAllMenuItems(WidgetTester tester, SmartPlaylistSortOrder selected) {
  expect(
    find.byType(MenuItemButton),
    findsNWidgets(SmartPlaylistSortOrder.values.length),
  );
  for (final order in SmartPlaylistSortOrder.values) {
    expect(_menuItem(order), findsOneWidget);
    final check = find.descendant(
      of: _menuItem(order),
      matching: find.byIcon(Icons.check_rounded),
    );
    expect(check, order == selected ? findsOneWidget : findsNothing);
  }
  expect(find.byType(BottomSheet), findsNothing);
  expect(tester.takeException(), isNull);
}

void _expectInside(Rect rect, double width) {
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(width));
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.bottom, lessThanOrEqualTo(900));
}

SmartPlaylistRule _existingRule() => SmartPlaylistRule(
  id: 'ik-smart-existing',
  name: '已存完整规则',
  platforms: const {PlatformType.netease, PlatformType.qq},
  keyword: 'live',
  minPlayCount: 2,
  maxPlayCount: 12,
  recentlyPlayedDays: 30,
  notPlayedSinceDays: 7,
  likedOnly: true,
  cachedOnly: true,
  downloadedOnly: true,
  localOnly: true,
  excludeLiked: false,
  maxSongs: 40,
  artistIds: const {'artist-1', 'artist-2'},
  albumIds: const {'album-1', 'album-2'},
  minDurationMs: 90000,
  maxDurationMs: 360000,
  match: SmartPlaylistMatch.any,
  sortBy: SmartPlaylistSortOrder.titleAsc,
  createdAt: DateTime(2026, 11, 20, 10),
  updatedAt: DateTime(2026, 11, 21, 12),
);

Future<List<SmartPlaylistRule>> _reloadRules(WidgetTester tester) async {
  final rules = await tester.runAsync(() async {
    await Hive.box<dynamic>(smartPlaylistRulesBoxName).close();
    final restored = SmartPlaylistsNotifier(
      repository: const HiveSmartPlaylistRepository(),
    );
    try {
      await restored.ready;
      expect(restored.state.error, isNull);
      return List<SmartPlaylistRule>.from(restored.state.rules);
    } finally {
      restored.dispose();
    }
  });
  return rules!;
}

Future<_EditorFixture> _mount(
  WidgetTester tester, {
  bool? enabled = true,
  List<SmartPlaylistRule> rules = const [],
  String? ruleId,
  SmartPlaylistRepository repository = const HiveSmartPlaylistRepository(),
  double width = 1200,
  Brightness brightness = Brightness.light,
  double scale = 1,
  double rightInset = 0,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final notifier = (await tester.runAsync(() async {
    await const HiveSmartPlaylistRepository().saveRules(rules);
    final notifier = SmartPlaylistsNotifier(repository: repository);
    await notifier.ready;
    return notifier;
  }))!;
  expect(notifier.state.error, isNull);
  final container = ProviderContainer(
    overrides: [smartPlaylistsProvider.overrideWith((ref) => notifier)],
  );
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => context.push('/smart-playlists/editor'),
              child: const Text('打开规则编辑器'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/smart-playlists/editor',
        builder: (context, state) {
          final page = SmartPlaylistEditorPage(ruleId: ruleId);
          return rightInset == 0
              ? page
              : Padding(
                  padding: EdgeInsets.only(right: rightInset),
                  child: page,
                );
        },
      ),
    ],
  );
  final base = IkWorkspaceTheme.from(
    brightness == Brightness.light ? VideoTheme.light : VideoTheme.dark,
  );
  final theme = enabled == null
      ? base
      : base.copyWith(
          extensions: [
            ...base.extensions.values,
            ContextualActionTheme(enabled: enabled),
          ],
        );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    container.dispose();
    await tester.pump();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: theme,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _EditorFixture(notifier);
}

class _EditorFixture {
  const _EditorFixture(this.notifier);

  final SmartPlaylistsNotifier notifier;

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('打开规则编辑器'));
    await tester.pumpAndSettle();
    expect(find.byType(SmartPlaylistEditorPage), findsOneWidget);
  }

  Future<void> save(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(TextButton, '保存'));
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (notifier.state.isSaving && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(
        notifier.state.isSaving,
        isFalse,
        reason: '真实 Hive 写入应完成，不能用模拟时钟冒充落盘',
      );
    });
    await tester.pumpAndSettle();
  }
}

class _RejectWrites extends HiveSmartPlaylistRepository {
  const _RejectWrites();

  @override
  Future<void> saveRules(List<SmartPlaylistRule> rules) =>
      Future.error(StateError('正式失败门：只读仓库'));
}

class _ReadableCaptureBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get disableShadows => false;
}

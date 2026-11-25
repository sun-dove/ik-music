import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mconnect/core/theme/app_theme.dart';
import 'package:mconnect/core/transfer/transfer_format.dart';
import 'package:mconnect/core/transfer/transfer_providers.dart';
import 'package:mconnect/core/transfer/transfer_report.dart';
import 'package:mconnect/features/library/data/my_playlists_repository.dart';
import 'package:mconnect/features/library/presentation/pages/import_playlist_page.dart';
import 'package:mconnect/features/library/presentation/providers/my_playlists_provider.dart';
import 'package:mconnect/features/smart_playlists/data/smart_playlist_repository.dart';
import 'package:mconnect/features/smart_playlists/domain/smart_playlist_rule.dart';
import 'package:mconnect/features/smart_playlists/presentation/pages/smart_playlist_editor_page.dart';
import 'package:mconnect/features/smart_playlists/presentation/providers/smart_playlists_provider.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/playlist.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/platform/base/music_platform.dart';
import 'package:mconnect/platform/base/platform_registry.dart';
import 'package:mconnect/video_app/ik/ik_controls.dart';
import 'package:mconnect/video_app/ik/ik_workspace_navigation.dart';
import 'package:mconnect/video_app/ik/ik_workspace_theme.dart';

// 正式验收门：常驻主导航新增离开入口时，保护原编辑内容与真实保存结果。
// 使用真实页面、原通知器、内存仓库；不联网、不写临时文件。
void main() {
  for (final smart in [true, false]) {
    final label = smart ? '智能歌单' : '导入歌单';
    _widgetTest('E15 $label 仅新开关注册一次，空白可离开，销毁注销', (tester) async {
      final h = await _mount(tester, smart: smart);
      expect(h.guards, hasLength(1));
      await _expectClean(tester, h);
      expect(find.byType(AlertDialog), findsNothing);
      expect(h.registrations, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(h.guards, isEmpty);
      expect(h.unregistrations, 1);
      expect(tester.takeException(), isNull);
    });

    for (final enabled in [null, false]) {
      _widgetTest('E15 $label 开关$enabled保持原返回和不注册', (tester) async {
        final h = await _mount(tester, smart: smart, enabled: enabled);
        await tester.enterText(find.byType(TextField).first, '旧入口草稿');
        expect(h.guards, isEmpty);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.text('工作区起点'), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
        expect(h.smartStore.saved, isEmpty);
        expect(h.importStore.saved, isEmpty);
      });
    }

    _widgetTest('E15 $label 主导航取消保留输入，重复离开共用提示，放弃不保存', (tester) async {
      final h = await _mount(tester, smart: smart);
      await tester.enterText(find.byType(TextField).first, '需要保留的输入');
      expect(h.guards, hasLength(1));
      final first = h.check();
      final second = h.check();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('继续编辑'), findsOneWidget);
      expect(find.text('放弃'), findsOneWidget);
      expect(find.text('保存并返回'), findsNothing);
      await tester.tap(find.text('继续编辑'));
      await tester.pumpAndSettle();
      expect(await first, isFalse);
      expect(await second, isFalse);
      expect(_input(tester), '需要保留的输入');
      final discard = h.check();
      await tester.pumpAndSettle();
      await tester.tap(find.text('放弃'));
      await tester.pumpAndSettle();
      expect(await discard, isTrue);
      expect(_input(tester), '需要保留的输入');
      expect(h.smartStore.saved, isEmpty);
      expect(h.importStore.saved, isEmpty);
      h.router.pop();
      await tester.pumpAndSettle();
      expect(find.text('工作区起点'), findsOneWidget);
      expect(h.guards, isEmpty);
    });

    _widgetTest('E15 $label 无scope页内返回同样保护输入，放弃才离开', (tester) async {
      final h = await _mount(tester, smart: smart, withScope: false);
      await tester.enterText(find.byType(TextField).first, '返回前输入');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('继续编辑'));
      await tester.pumpAndSettle();
      expect(_input(tester), '返回前输入');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('放弃'));
      await tester.pumpAndSettle();
      expect(find.text('工作区起点'), findsOneWidget);
      expect(h.guards, isEmpty);
    });

    _widgetTest('E22 $label 帧尾返回被覆盖后恢复草稿保护', (tester) async {
      final h = await _mount(tester, smart: smart);
      await tester.enterText(find.byType(TextField).first, '帧尾仍须保护的内容');
      final page = find.byType(
        smart ? SmartPlaylistEditorPage : ImportPlaylistPage,
      );
      final originalPage = tester.state(page);
      final navigator = Navigator.of(tester.element(page));
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(
          navigator.push<void>(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('帧尾覆盖页面')),
            ),
          ),
        );
      });
      await tester.tap(find.text('放弃'));
      await tester.pumpAndSettle();
      expect(find.text('帧尾覆盖页面'), findsOneWidget);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(page.hitTestable(), findsOneWidget);
      expect(tester.state(page), same(originalPage));
      expect(_input(tester), '帧尾仍须保护的内容');
      unawaited(navigator.maybePop());
      await tester.pumpAndSettle();
      expect(
        find.byType(AlertDialog),
        findsOneWidget,
        reason: '未执行的旧pop必须恢复离开保护，不能让下一次系统返回直接丢弃',
      );
      await tester.tap(find.text('继续编辑'));
      await tester.pumpAndSettle();
      expect(_input(tester), '帧尾仍须保护的内容');
      expect(h.guards, hasLength(1));
      expect(h.smartStore.saved, isEmpty);
      expect(h.importStore.saved, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  _widgetTest('E15 已存智能规则完整载入不算草稿', (tester) async {
    final existing = SmartPlaylistRule.create(
      name: '原有规则',
      keyword: '原关键词',
      platforms: {PlatformType.qq, PlatformType.netease},
      artistIds: {'a', 'b'},
      albumIds: {'c', 'd'},
      minPlayCount: 2,
      maxPlayCount: 8,
      recentlyPlayedDays: 7,
      notPlayedSinceDays: 30,
      likedOnly: true,
      excludeLiked: true,
      cachedOnly: true,
      downloadedOnly: true,
      localOnly: true,
      maxSongs: 80,
      minDurationMs: 30000,
      maxDurationMs: 180000,
      match: SmartPlaylistMatch.any,
      sortBy: SmartPlaylistSortOrder.titleAsc,
    );
    final h = await _mount(tester, rule: existing);
    expect(h.guards, hasLength(1));
    await _expectClean(tester, h);
    expect(_input(tester), '原有规则');
    expect(find.byType(AlertDialog), findsNothing);
    expect(h.smartStore.saved, isEmpty);
  });

  final mutations = <String, Future<void> Function(WidgetTester, bool)>{
    for (final (label, original) in [
      ('歌单名称', '智能歌单'),
      ('关键词', ''),
      ('限定歌手 ID（可选）', ''),
      ('限定专辑 ID（可选）', ''),
    ])
      label: (tester, changed) async {
        final field = find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == label,
        );
        await tester.ensureVisible(field);
        await tester.enterText(field, changed ? '已修改-$label' : original);
      },
    '平台': (tester, changed) async {
      final chip = find.widgetWithText(FilterChip, PlatformType.qq.displayName);
      await _reveal(tester, chip);
      await tester.tap(chip);
    },
    for (final label in ['只包含我喜欢', '排除我喜欢的', '只包含已缓存', '只包含已下载', '只包含本地文件'])
      label: (tester, changed) async {
        final tile = find.widgetWithText(SwitchListTile, label);
        await _reveal(tester, tile);
        await tester.tap(tile);
      },
    for (final (label, original) in [
      ('最低播放次数', 0.0),
      ('最高播放次数', 0.0),
      ('最近播放范围', 0.0),
      ('多久没听', 0.0),
      ('最多歌曲数', 100.0),
    ])
      label: (tester, changed) async {
        final tile = find.widgetWithText(ListTile, label);
        await _reveal(tester, tile);
        tester
            .widget<Slider>(
              find.descendant(of: tile, matching: find.byType(Slider)),
            )
            .onChanged!(changed ? original + 2 : original);
      },
    '最短时长': (tester, changed) async {
      await _reveal(tester, find.byType(RangeSlider));
      tester.widget<RangeSlider>(find.byType(RangeSlider)).onChanged!(
        changed ? const RangeValues(15, 0) : const RangeValues(0, 0),
      );
    },
    '最长时长': (tester, changed) async {
      await _reveal(tester, find.byType(RangeSlider));
      tester.widget<RangeSlider>(find.byType(RangeSlider)).onChanged!(
        changed ? const RangeValues(0, 150) : const RangeValues(0, 0),
      );
    },
    '条件组合': (tester, changed) async {
      final label = changed ? '满足任一' : '同时满足';
      await _reveal(tester, find.text(label));
      await tester.tap(find.text(label));
    },
    '排序': (tester, changed) async {
      final select = find.byType(IkSelect<SmartPlaylistSortOrder>);
      await _reveal(tester, select);
      await tester.tap(select);
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(MenuItemButton, changed ? '标题升序' : '听得最多'),
      );
    },
  };
  for (final entry in mutations.entries) {
    _widgetTest('E15 智能规则${entry.key}独立变更受保护，改回原值无提示', (tester) async {
      final h = await _mount(tester);
      expect(h.guards, hasLength(1));
      await entry.value(tester, true);
      await tester.pumpAndSettle();
      await _expectDirty(tester, h);
      await entry.value(tester, false);
      await tester.pumpAndSettle();
      await _expectClean(tester, h);
      expect(find.byType(AlertDialog), findsNothing);
      expect(h.smartStore.saved, isEmpty);
    });
  }

  _widgetTest('E15 智能规则保存中阻止主导航和返回，失败保留，重试成功正常返回', (tester) async {
    final h = await _mount(tester);
    expect(h.guards, hasLength(1));
    await tester.enterText(find.byType(TextField).first, '保存中的规则');
    h.smartStore.gate = Completer<void>();
    h.smartStore.fail = true;
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pump();
    expect(await h.check(), isFalse);
    await tester.tap(find.byType(BackButton));
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SmartPlaylistEditorPage), findsOneWidget);
    h.smartStore.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('智能歌单保存失败'), findsOneWidget);
    expect(_input(tester), '保存中的规则');
    expect(h.smartStore.saved, isEmpty);
    await _expectDirty(tester, h);
    h.smartStore.gate = null;
    h.smartStore.fail = false;
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();
    expect(h.smartStore.saved.single.name, '保存中的规则');
    expect(find.text('工作区起点'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(h.guards, isEmpty);
  });

  _widgetTest('E15 智能规则保存完成不弹走覆盖页面，返回后已保存无二次确认', (tester) async {
    final h = await _mount(tester);
    expect(h.guards, hasLength(1));
    await tester.enterText(find.byType(TextField).first, '被覆盖时保存');
    h.smartStore.gate = Completer<void>();
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pump();
    unawaited(h.router.push<void>('/cover'));
    await tester.pumpAndSettle();
    h.smartStore.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('覆盖页面'), findsOneWidget);
    expect(h.smartStore.saved.single.name, '被覆盖时保存');
    h.router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(SmartPlaylistEditorPage), findsOneWidget);
    await _expectClean(tester, h);
    expect(find.byType(AlertDialog), findsNothing);
  });

  _widgetTest('E15 智能规则保存期间的新输入仍保留为未保存，不被成功基线吞掉', (tester) async {
    final h = await _mount(tester);
    expect(h.guards, hasLength(1));
    await tester.enterText(find.byType(TextField).first, '提交版本');
    h.smartStore.gate = Completer<void>();
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '提交后的新输入');
    h.smartStore.gate!.complete();
    await tester.pumpAndSettle();
    expect(h.smartStore.saved.single.name, '提交版本');
    expect(_input(tester), '提交后的新输入');
    await _expectDirty(tester, h);
  });

  _widgetTest('E15 智能规则首次保存留页后续存更新同一ID，不重复新建', (tester) async {
    final h = await _mount(tester);
    expect(h.guards, hasLength(1));
    await tester.enterText(find.byType(TextField).first, '第一次提交');
    h.smartStore.gate = Completer<void>();
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '第二次提交');
    h.smartStore.gate!.complete();
    await tester.pumpAndSettle();
    expect(_input(tester), '第二次提交');
    final firstId = h.smartStore.writes.single.single.id;
    h.smartStore.gate = null;
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();
    expect(h.smartStore.writes, hasLength(2));
    expect(h.smartStore.writes.last, hasLength(1));
    expect(h.smartStore.writes.last.single.id, firstId);
    expect(h.smartStore.writes.last.single.name, '第二次提交');
    expect(find.text('工作区起点'), findsOneWidget);
    expect(h.guards, isEmpty);
  });

  _widgetTest('E15 导入解析中阻止离开，完成后三桶报告与勾选取消后完整保留', (tester) async {
    final h = await _mount(tester, smart: false);
    expect(h.guards, hasLength(1));
    h.matcher.gate = Completer<void>();
    await tester.enterText(find.byType(TextField), _document);
    await tester.tap(find.text('解析'));
    await tester.pump();
    expect(await h.check(), isFalse);
    await tester.tap(find.byType(BackButton));
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
    h.matcher.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('可入 (1)'), findsOneWidget);
    expect(find.text('待确认 (1)'), findsOneWidget);
    expect(find.text('未匹配 (1)'), findsOneWidget);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await _expectDirty(tester, h);
    expect(find.text('将导入 2 首'), findsOneWidget);
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isTrue,
    );
    expect(h.importStore.saved, isEmpty);
  });

  _widgetTest('E15 导入一次性深链消费后报告仍受保护，取消不会丢失选择', (tester) async {
    final h = await _mount(tester, smart: false);
    expect(h.guards, hasLength(1));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ImportPlaylistPage)),
    );
    container.read(pendingPlaylistTransferProvider.notifier).state = _document;
    await tester.pumpAndSettle();
    expect(container.read(pendingPlaylistTransferProvider), isNull);
    expect(find.text('将导入 1 首'), findsOneWidget);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await _expectDirty(tester, h);
    expect(_input(tester), _document);
    expect(find.text('将导入 2 首'), findsOneWidget);
  });

  _widgetTest('E15 导入保存中阻止离开，失败保留，成功后基线随勾选结果更新', (tester) async {
    final h = await _mount(tester, smart: false);
    expect(h.guards, hasLength(1));
    await _parse(tester, _document);
    await tester.tap(find.byType(CheckboxListTile));
    h.importStore.gate = Completer<void>();
    h.importStore.fail = true;
    await tester.tap(find.text('保存到我的歌单'));
    await tester.pump();
    expect(await h.check(), isFalse);
    h.importStore.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('保存失败'), findsOneWidget);
    expect(find.text('将导入 2 首'), findsOneWidget);
    expect(h.importStore.saved, isEmpty);
    await _expectDirty(tester, h);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    h.importStore.gate = null;
    h.importStore.fail = false;
    await tester.tap(find.text('保存到我的歌单'));
    await tester.pumpAndSettle();
    expect(h.importStore.saved.single.songs, [_exact, _weak]);
    await _expectClean(tester, h);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await _expectDirty(tester, h);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await _expectClean(tester, h);
  });

  _widgetTest('E15 导入保存期间新勾选不会被成功基线吞掉', (tester) async {
    final h = await _mount(tester, smart: false);
    expect(h.guards, hasLength(1));
    await _parse(tester, _document);
    h.importStore.gate = Completer<void>();
    await tester.tap(find.text('保存到我的歌单'));
    await tester.pump();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    h.importStore.gate!.complete();
    await tester.pumpAndSettle();
    expect(h.importStore.saved.single.songs, [_exact]);
    expect(find.text('将导入 2 首'), findsOneWidget);
    await _expectDirty(tester, h);
  });

  _widgetTest('E15 平台链接解析结果未保存受保护，保存后无二次确认', (tester) async {
    final h = await _mount(tester, smart: false);
    expect(h.guards, hasLength(1));
    await _parse(tester, 'https://example.com/playlist/one');
    expect(find.text('平台歌单 (1首)'), findsOneWidget);
    await _expectDirty(tester, h);
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();
    expect(h.importStore.saved.single.name, '平台歌单');
    expect(h.importStore.saved.single.songs, [_exact]);
    await _expectClean(tester, h);
    expect(find.byType(AlertDialog), findsNothing);
  });

  _widgetTest('E15 本地分享解析已真实入库，不虚报未保存，结果保持可见', (tester) async {
    final h = await _mount(tester, smart: false);
    expect(h.guards, hasLength(1));
    final link = MyPlaylistsRepository.encodeShareLink(
      name: '本地已导入',
      songsJson: const [],
    );
    await _parse(tester, link);
    expect(h.importStore.saved, hasLength(1));
    expect(h.importStore.saved.single.name, '本地已导入');
    expect(find.text('本地已导入 (0首)'), findsOneWidget);
    await _expectClean(tester, h);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.enterText(find.byType(TextField), '$link ');
    await _expectDirty(tester, h);
    await tester.enterText(find.byType(TextField), link);
    await _expectClean(tester, h);
  });

  _widgetTest('E15 本地分享入库失败保留原输入与未保存保护', (tester) async {
    final h = await _mount(tester, smart: false);
    expect(h.guards, hasLength(1));
    h.importStore.fail = true;
    final link = MyPlaylistsRepository.encodeShareLink(
      name: '待导入',
      songsJson: const [],
    );
    await _parse(tester, link);
    expect(h.importStore.saved, isEmpty);
    expect(find.text('导入 Mconnect 歌单失败'), findsOneWidget);
    expect(_input(tester), link);
    await _expectDirty(tester, h);
  });

  for (final document in [true, false]) {
    _widgetTest('E15 ${document ? '文档' : '平台链接'}解析后修改输入，保存原结果仍保护新输入', (
      tester,
    ) async {
      final h = await _mount(tester, smart: false);
      expect(h.guards, hasLength(1));
      final input = document ? _document : 'https://example.com/playlist/one';
      await _parse(tester, input);
      await tester.enterText(find.byType(TextField), '尚未解析的新输入');
      await tester.tap(
        document ? find.text('保存到我的歌单') : find.widgetWithText(TextButton, '保存'),
      );
      await tester.pumpAndSettle();
      expect(h.importStore.saved.single.songs, [_exact]);
      expect(_input(tester), '尚未解析的新输入');
      await _expectDirty(tester, h);
      await tester.enterText(find.byType(TextField), input);
      await _expectClean(tester, h);
      expect(find.byType(AlertDialog), findsNothing);
    });
  }
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

String _input(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField).first).controller!.text;

Future<void> _expectDirty(WidgetTester tester, _Harness h) async {
  final decision = h.check();
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsOneWidget);
  await tester.tap(find.text('继续编辑'));
  await tester.pumpAndSettle();
  expect(await decision, isFalse);
  expect(tester.takeException(), isNull);
}

Future<void> _expectClean(WidgetTester tester, _Harness h) async {
  final decision = h.check();
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsNothing);
  expect(await decision, isTrue);
}

void _widgetTest(
  String description,
  Future<void> Function(WidgetTester) body,
) => testWidgets(
  description,
  body,
  timeout: const Timeout(Duration(seconds: 30)),
);

Future<void> _parse(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.tap(find.text('解析'));
  await tester.pumpAndSettle();
}

class _Harness {
  final guards = <Object, Future<bool> Function()>{};
  final smartStore = _SmartStore();
  final importStore = _ImportStore();
  final matcher = _Matcher();
  late final GoRouter router;
  int registrations = 0, unregistrations = 0;

  Future<bool> check() => guards.values.single();

  void register(Object identity, Future<bool> Function() check) {
    registrations++;
    guards[identity] = check;
  }

  void unregister(Object identity) {
    unregistrations++;
    guards.remove(identity);
  }
}

Future<_Harness> _mount(
  WidgetTester tester, {
  bool smart = true,
  bool? enabled = true,
  bool withScope = true,
  SmartPlaylistRule? rule,
}) async {
  tester.view.physicalSize = const Size(1100, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final h = _Harness();
  if (rule != null) h.smartStore.initial = [rule];
  final notifier = SmartPlaylistsNotifier(repository: h.smartStore);
  await notifier.ready;
  PlatformRegistry.register(_Platform());
  h.router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('工作区起点')),
      ),
      GoRoute(
        path: '/edit',
        builder: (_, _) => smart
            ? enabled == null
                  ? SmartPlaylistEditorPage(ruleId: rule?.id)
                  : SmartPlaylistEditorPage(
                      ruleId: rule?.id,
                      protectWorkspaceDraft: enabled,
                    )
            : enabled == null
            ? const ImportPlaylistPage()
            : ImportPlaylistPage(protectWorkspaceDraft: enabled),
      ),
      GoRoute(
        path: '/cover',
        builder: (_, _) => const Scaffold(body: Text('覆盖页面')),
      ),
    ],
  );
  addTearDown(h.router.dispose);
  final app = MaterialApp.router(
    routerConfig: h.router,
    theme: IkWorkspaceTheme.aligned(AppTheme.light()),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        smartPlaylistsProvider.overrideWith((ref) => notifier),
        myPlaylistsProvider.overrideWith(
          (ref) => MyPlaylistsNotifier(repository: h.importStore),
        ),
        playlistSourceMatcherProvider.overrideWithValue(h.matcher),
      ],
      child: withScope
          ? IkWorkspaceNavigation(
              register: h.register,
              unregister: h.unregister,
              child: app,
            )
          : app,
    ),
  );
  await tester.pumpAndSettle();
  unawaited(h.router.push<void>('/edit'));
  await tester.pumpAndSettle();
  return h;
}

class _SmartStore implements SmartPlaylistRepository {
  List<SmartPlaylistRule> initial = [];
  final saved = <SmartPlaylistRule>[];
  final writes = <List<SmartPlaylistRule>>[];
  Completer<void>? gate;
  bool fail = false;

  @override
  Future<List<SmartPlaylistRule>> loadRules() async => initial;

  @override
  Future<void> saveRules(List<SmartPlaylistRule> rules) async {
    await gate?.future;
    if (fail) throw StateError('正式门的预期保存失败');
    saved.addAll(rules);
    writes.add(List.of(rules));
  }
}

class _ImportStore extends MyPlaylistsRepository {
  final saved = <({String name, List<Song> songs})>[];
  Completer<void>? gate;
  bool fail = false;

  @override
  Future<List<Playlist>> getPlaylists() async => const [];

  @override
  Future<List<Song>> getSongs(String playlistId) async => saved.last.songs;

  @override
  Future<Playlist> importPlaylist({
    required String name,
    required List<Song> songs,
  }) async {
    await gate?.future;
    if (fail) throw StateError('正式门的预期导入失败');
    saved.add((name: name, songs: List.of(songs)));
    return Playlist(
      id: 'local-${saved.length}',
      name: name,
      platform: PlatformType.local,
      songCount: songs.length,
    );
  }
}

const _document = '确定歌曲 - 歌手甲\n候选歌曲 - 歌手乙\n缺失歌曲 - 歌手丙';
const _exact = Song(
  id: 'one',
  platform: PlatformType.netease,
  name: '确定歌曲',
  artists: [Artist(id: 'a', name: '歌手甲')],
);
const _weak = Song(
  id: 'two',
  platform: PlatformType.qq,
  name: '候选歌曲',
  artists: [Artist(id: 'b', name: '歌手乙')],
);

class _Matcher implements PlaylistSourceMatcher {
  Completer<void>? gate;

  @override
  Future<List<SourceMatchCandidate>> candidatesFor(TransferEntry entry) async {
    await gate?.future;
    return switch (entry.title) {
      '确定歌曲' => const [SourceMatchCandidate(song: _exact, confident: true)],
      '候选歌曲' => const [SourceMatchCandidate(song: _weak, confident: false)],
      _ => const [],
    };
  }
}

class _Platform extends MusicPlatform {
  @override
  PlatformType get platformType => PlatformType.netease;

  @override
  Future<Playlist?> parseShareLink(String url) async =>
      url == 'https://example.com/playlist/one'
      ? const Playlist(id: 'one', name: '平台歌单', platform: PlatformType.netease)
      : null;

  @override
  Future<List<Song>> getPlaylistDetail(String playlistId) async => [_exact];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/l10n/expanded_strings.dart';
import 'package:mconnect/video_app/lx_source/lx_source.dart';
import 'package:mconnect/video_app/multi_source/source_collection.dart';
import 'package:mconnect/video_app/ui/source_manager_page.dart';

// 正式体验门：真实来源、草稿回调与后台状态，不依赖远端接口。
void main() {
  testWidgets('20 个音源首屏可操作，不被维护工具遮住；第 20 项可达', (tester) async {
    await _mount(tester);
    expect(find.text('20 个音源 · 19 个启用'), findsOneWidget);
    expect(_key('manager-enabled-s1').hitTestable(), findsOneWidget);
    expect(find.text('优先使用').hitTestable(), findsOneWidget);
    final searchLeft = tester.getTopLeft(_key('manager-search')).dx;
    expect(
      tester.getTopLeft(_key('manager-platform-all')).dx,
      closeTo(searchLeft, 1),
    );
    expect(tester.getTopLeft(_key('s1')).dx, closeTo(searchLeft, 1));
    expect(_key('manager-check-updates'), findsNothing);
    expect(_key('manager-import-link'), findsNothing);
    expect(find.text('目录资料'), findsNothing);
    expect(_save(tester).onPressed, isNull);
    await tester.dragUntilVisible(
      _key('manager-enabled-s20').hitTestable(),
      _key('manager-scroll'),
      const Offset(0, -210),
    );
    expect(_key('manager-enabled-s20').hitTestable(), findsOneWidget);
    expect(_key('manager-tab-add').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('筛选、分区和即时音质选择保留现有草稿；保存只写一次', (tester) async {
    final model = await _mount(tester);
    expect(_save(tester).onPressed, isNull);
    await tester.enterText(_key('manager-search'), '19');
    await tester.tap(_key('manager-platform-tx'));
    await tester.pumpAndSettle();
    expect(_key('manager-enabled-s19'), findsOneWidget);
    expect(_key('manager-enabled-s1'), findsNothing);
    await tester.tap(_key('manager-enabled-s19'));
    await tester.pumpAndSettle();
    expect(_save(tester).onPressed, isNotNull);
    await tester.tap(_key('manager-tab-add'));
    await tester.pumpAndSettle();
    expect(_key('manager-import-link').hitTestable(), findsOneWidget);
    expect(find.text('本机导入'), findsOneWidget);
    expect(find.text('目录资料'), findsOneWidget);
    expect(_key('manager-check-updates'), findsNothing);
    await tester.tap(_key('manager-tab-list'));
    await tester.pumpAndSettle();
    await tester.tap(_key('manager-playback-quality'));
    await tester.pumpAndSettle();
    expect(model.qualityOpens, 1);
    expect(find.textContaining('智能均衡'), findsOneWidget);
    expect(_key('manager-highest'), findsNothing);
    expect(model.saved, isEmpty);
    expect(
      tester.widget<TextField>(_key('manager-search')).controller!.text,
      '19',
    );
    expect(tester.widget<Switch>(_key('manager-enabled-s19')).value, isFalse);
    await tester.tap(_key('manager-save'));
    await tester.pumpAndSettle();
    expect(model.saved, hasLength(1));
    expect(model.saved.single.enabled, hasLength(18));
    expect(_save(tester).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('后台更新可查看和取消，可继续浏览；不允许重复更新或导入', (tester) async {
    final model = await _mount(tester);
    await tester.tap(_key('manager-tab-updates'));
    await tester.pumpAndSettle();
    expect(find.text('自动更新设置'), findsOneWidget);
    expect(find.text('目录资料'), findsNothing);
    await tester.tap(_key('manager-check-updates'));
    await tester.pump();
    expect(model.checks, 1);
    expect(
      tester.widget<OutlinedButton>(_key('manager-update-all')).onPressed,
      isNull,
    );
    await tester.tap(_key('manager-tab-add'));
    await tester.pump();
    expect(
      tester.widget<TextField>(_key('manager-import-link')).enabled,
      isFalse,
    );
    await tester.tap(_key('manager-tab-list'));
    await tester.pump();
    expect(find.text('正在检查更新').hitTestable(), findsOneWidget);
    await tester.enterText(_key('manager-search'), '11');
    await tester.pump();
    await tester.ensureVisible(_key('manager-enabled-s11'));
    await tester.tap(_key('manager-enabled-s11'));
    await tester.pump();
    expect(model.draft.enabled, hasLength(18));
    await tester.tap(_key('manager-notice-details'));
    await tester.pump();
    expect(find.text('自动更新设置').hitTestable(), findsOneWidget);
    await tester.tap(find.text(ExpandedStrings.cancelOperation));
    await tester.pumpAndSettle();
    expect(model.cancels, 1);
    expect(
      tester.widget<OutlinedButton>(_key('manager-update-all')).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('本机导入失败指向添加视图；空库和无匹配各有恢复路径', (tester) async {
    final model = await _mount(tester, empty: true, failedImport: true);
    expect(find.text('本机导入有 1 项需要处理').hitTestable(), findsOneWidget);
    await tester.tap(_key('manager-notice-details'));
    await tester.pumpAndSettle();
    expect(find.text('本机导入'), findsOneWidget);
    await tester.tap(_key('manager-tab-list'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      _key('manager-empty-add').hitTestable(),
      _key('manager-scroll'),
      const Offset(0, -90),
    );
    await tester.tap(_key('manager-empty-add'));
    await tester.pumpAndSettle();
    await tester.enterText(
      _key('manager-import-link'),
      'https://example.org/new.js',
    );
    await tester.tap(_key('manager-import'));
    await tester.pumpAndSettle();
    expect(model.imported, ['https://example.org/new.js']);
    await tester.enterText(_key('manager-search'), '不存在');
    await tester.pumpAndSettle();
    expect(find.text(ExpandedStrings.noMatches), findsOneWidget);
    await tester.ensureVisible(_key('manager-empty-reset'));
    await tester.tap(_key('manager-empty-reset'));
    await tester.pumpAndSettle();
    expect(find.text('新导入音源'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄正文和 150% 字号仍可访问三个分区和实际源', (tester) async {
    await _mount(tester, size: const Size(340, 450), textScale: 1.5);
    for (final view in ['updates', 'add', 'list']) {
      await tester.ensureVisible(_key('manager-tab-$view'));
      await tester.tap(_key('manager-tab-$view'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.dragUntilVisible(
      _key('manager-enabled-s1').hitTestable(),
      _key('manager-scroll'),
      const Offset(0, -90),
    );
    expect(_key('manager-enabled-s1').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Finder _key(String key) => find.byKey(ValueKey(key));
FilledButton _save(WidgetTester tester) =>
    tester.widget<FilledButton>(_key('manager-save'));

LxSourceConfig _config(
  String name,
  String id, {
  bool enabled = true,
  String platform = 'tx',
}) => LxSourceConfig(
  name: name,
  version: '1.0',
  origin: Uri.parse('https://example.org/$id.js'),
  script: 'fixture',
  sha256: id,
  sources: {
    platform: ['128k'],
  },
  enabled: enabled,
);

class _Model {
  _Model(this.initial);
  SourceCollection initial;
  late SourceCollection draft = initial;
  final saved = <SourceCollection>[];
  final imported = <String>[];
  var quality = '高品质', qualityOpens = 0, checks = 0, cancels = 0;
  var busy = false;
}

Future<_Model> _mount(
  WidgetTester tester, {
  bool empty = false,
  bool failedImport = false,
  Size size = const Size(780, 470),
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final model = _Model(
    SourceCollection(
      entries: [
        if (!empty)
          for (var i = 1; i <= 20; i++)
            SourceEntry(
              's$i',
              _config(
                '来源 ${i.toString().padLeft(2, '0')}',
                's$i',
                enabled: i != 20,
                platform: i.isOdd ? 'tx' : 'kg',
              ),
            ),
      ],
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: StatefulBuilder(
              builder: (context, set) => SourceManagerPage(
                embedded: true,
                refinedLayout: true,
                organizedLayout: true,
                modernPolicyMenu: true,
                playbackQualityControl: OutlinedButton(
                  key: const ValueKey('manager-playback-quality'),
                  onPressed: () => set(() {
                    model.qualityOpens++;
                    model.quality = '智能均衡';
                  }),
                  child: Text(model.quality),
                ),
                updatePanel: const Text('自动更新设置'),
                localImportPanel: const Text('本机导入'),
                maintenanceNotice: failedImport ? '本机导入有 1 项需要处理' : null,
                maintenanceNoticeIsImport: failedImport,
                catalogPanel: const SizedBox(height: 230, child: Text('目录资料')),
                keepBackgroundDraft: true,
                backgroundBusy: model.busy,
                backgroundDirty: !identical(model.draft, model.initial),
                initial: model.draft,
                onDraftChanged: (value) => set(() => model.draft = value),
                onBackgroundCheck: (_) async => set(() {
                  model.checks++;
                  model.busy = true;
                }),
                onBackgroundUpdateAll: (_) async {},
                onCancelBackground: () => set(() {
                  model.cancels++;
                  model.busy = false;
                }),
                onImport: (link, _) async {
                  model.imported.add(link);
                  return _config('新导入音源', 'new');
                },
                onInspect: (_, _) async {},
                onSave: (value) async => set(() {
                  model.saved.add(value);
                  model.initial = value;
                }),
                onHttp: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return model;
}

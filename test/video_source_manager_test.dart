import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/video_app/lx_source/lx_source.dart';
import 'package:mconnect/video_app/multi_source/source_collection.dart';
import 'package:mconnect/video_app/ui/source_manager_page.dart';

SourceCollection _sources(int count) => SourceCollection(
  entries: [
    for (var index = 0; index < count; index++)
      SourceEntry(
        'source-$index',
        LxSourceConfig(
          name: '音源$index',
          version: '1',
          origin: Uri.parse('https://example.com/$index.js'),
          script: 'fixture',
          sha256: 'hash-$index',
          enabled: true,
          sources: {
            index.isEven ? 'kg' : 'tx': ['128k'],
          },
        ),
      ),
  ],
);

void main() {
  testWidgets('窄屏放大文字并展开策略时仍能滚动列表与保存', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: SourceManagerPage(
          initial: _sources(5),
          onImport: (_, _) async => throw UnimplementedError(),
          onInspect: (_, _) async {},
          onSave: (_) async {},
          onHttp: () {},
        ),
      ),
    );
    await tester.tap(find.text('播放策略'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('manager-save')).hitTestable(),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('音源4'),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('manager-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('音源4').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('取消批量检查后剩余条目明确未检查，迟到结果不记成功', (tester) async {
    final waiting = Completer<void>();
    final checked = <String>[];
    CancelToken? active;
    await tester.pumpWidget(
      MaterialApp(
        home: SourceManagerPage(
          initial: _sources(3),
          onImport: (_, _) async => throw UnimplementedError(),
          onInspect: (config, token) async {
            checked.add(config.name);
            active = token;
            await waiting.future;
          },
          onSave: (_) async {},
          onHttp: () {},
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('manager-inspect-all')));
    await tester.pump();
    await tester.tap(find.text('取消当前操作'));
    expect(active!.isCancelled, isTrue);
    waiting.complete();
    await tester.pumpAndSettle();
    expect(checked, ['音源0']);
    expect(find.textContaining('已取消，检查完成 0 / 3'), findsOneWidget);
    expect(find.text('本次未检查'), findsWidgets);
    expect(find.textContaining('初始化通过'), findsNothing);
  });

  testWidgets('筛选不改播放顺序，保存失败保留草稿和可重试按钮', (tester) async {
    SourceCollection? saved;
    var fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: SourceManagerPage(
          initial: _sources(3),
          onImport: (_, _) async => throw UnimplementedError(),
          onInspect: (_, _) async {},
          onHttp: () {},
          onSave: (value) async {
            if (fail) throw StateError('fixture');
            saved = value;
          },
        ),
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('manager-search')), '音源2');
    await tester.pumpAndSettle();
    expect(find.text('音源0'), findsNothing);
    expect(find.text('音源2', findRichText: false).last, findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('manager-enabled-source-2')));
    await tester.pumpAndSettle();
    expect(find.text('有未保存的更改'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('manager-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('保存失败'), findsOneWidget);
    expect(find.text('有未保存的更改'), findsOneWidget);
    fail = false;
    await tester.tap(find.byKey(const ValueKey('manager-save')));
    await tester.pumpAndSettle();
    expect(saved!.entries.map((entry) => entry.id), [
      'source-0',
      'source-1',
      'source-2',
    ]);
    expect(saved!.entries.last.config.enabled, isFalse);
    expect(find.text('已保存'), findsOneWidget);
  });

  testWidgets('批量检查完整23条记录，不能只测可见行或前N条', (tester) async {
    final checked = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: SourceManagerPage(
          initial: _sources(23),
          onImport: (_, _) async => throw UnimplementedError(),
          onInspect: (config, _) async {
            checked.add(config.name);
          },
          onSave: (_) async {},
          onHttp: () {},
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('manager-inspect-all')));
    await tester.pumpAndSettle();
    expect(checked, [for (var index = 0; index < 23; index++) '音源$index']);
    expect(find.textContaining('23 / 23'), findsOneWidget);
  });
}

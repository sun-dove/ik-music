import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
}

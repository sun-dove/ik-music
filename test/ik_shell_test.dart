import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/video_app/ik/ik_shell.dart';

void main() {
  for (final width in [320.0, 720.0, 900.0, 1200.0]) {
    for (final scale in [1.0, 1.25, 1.5]) {
      testWidgets('K02/K08 四导航可操作 ${width.toInt()} / $scale', (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var selected = -1;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 800),
                textScaler: TextScaler.linear(scale),
              ),
              child: IkShell(
                index: 0,
                onSelect: (value) => selected = value,
                pages: const [
                  Text('首页内容'),
                  Text('搜索内容'),
                  Text('曲库内容'),
                  Text('设置内容'),
                ],
                miniPlayer: const Text('当前播放'),
              ),
            ),
          ),
        );
        for (final entry in ['首页', '搜索', '我的音乐', '我的'].indexed) {
          await tester.tap(find.text(entry.$2));
          expect(selected, entry.$1);
        }
        expect(find.text('当前播放'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}

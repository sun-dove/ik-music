import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/video_app/ui/video_shell.dart';

void main() {
  for (final width in [320.0, 900.0, 1200.0]) {
    testWidgets('酷狗入口与播放器在${width.toInt()}宽度可见且可操作', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      int? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: VideoShell(
            index: 0,
            onSelect: (value) => selected = value,
            expandedPlatforms: true,
            pages: const [
              Text('搜索内容'),
              Text('QQ内容'),
              Text('网易内容'),
              Text('酷狗内容'),
              Text('设置内容'),
            ],
            miniPlayer: const Text('固定播放器'),
          ),
        ),
      );
      expect(find.text('酷狗'), findsOneWidget);
      await tester.tap(find.text('酷狗'));
      expect(selected, 3);
      expect(find.text('固定播放器'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

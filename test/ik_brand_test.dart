import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/l10n/video_strings.dart';
import 'package:mconnect/video_app/ui/my_page.dart';
import 'package:mconnect/video_app/windows/windows_my_page.dart';

void main() {
  test('K01 当前产品显示 ik 并保持安装和数据身份', () {
    expect(VideoStrings.appName, 'ik');
    expect(VideoStrings.appVersion, 'ik · 0.6.0');
    final installer = File('installer/yueyin.iss').readAsStringSync();
    expect(installer, contains('54A778C9-2261-4E1F-BA89-EE68844DA7AA'));
    expect(installer, contains('IconFilename: "{app}\\ik.ico"'));
    final resource = File('windows/runner/Yueyin.rc').readAsStringSync();
    expect(resource, contains('"ProductName", "YueyinMusic"'));
    expect(resource, contains('"CompanyName", "sun-dove"'));
  });
  testWidgets('K01 我的标题下没有重复品牌，版本保留底部', (tester) async {
    tester.view.physicalSize = const Size(1200, 1900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = VideoMyPage(
      accounts: const {},
      cacheLabel: '0 MB',
      downloadLabel: '0',
      themeLabel: '浅色',
      onAccount: (_) {},
      onQuality: (_, _) {},
      onCache: () {},
      onDownloads: () {},
      onDirectory: () {},
      onTheme: () {},
      onLocal: () {},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WindowsMyPage(
            settings: settings,
            playQuality: '标准',
            downloadQuality: '标准',
            onQuality: (_) {},
            showBrandSubtitle: false,
          ),
        ),
      ),
    );
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('ik'), findsNothing);
    expect(find.text('DJ Music'), findsNothing);
    await tester.scrollUntilVisible(find.text('ik · 0.6.0'), 300);
    expect(find.text('ik · 0.6.0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

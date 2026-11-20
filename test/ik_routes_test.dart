import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/video_app/ik/ik_router.dart';

void main() {
  test('K06 Android独立入口仅由app_links交付链接，旧入口保持平台默认', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(
      RegExp(
        r'<meta-data\s+android:name="flutter_deeplinking_enabled"\s+'
        r'android:value="\$\{flutterDeepLinkingEnabled\}"\s*/>',
      ).hasMatch(manifest),
      isTrue,
      reason: 'MainActivity必须通过构建占位符决定是否接收Flutter自动深链',
    );
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(
      gradle,
      contains(
        'manifestPlaceholders["flutterDeepLinkingEnabled"] = !videoAppBuild',
      ),
    );
  });

  testWidgets('K02 全部独立详情和工具路径可匹配，非法平台显示错误页', (tester) async {
    final router = createIkRouter(
      home: (_) => const Text('主区'),
      player: (_) => const Text('播放器'),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    final parser = router.configuration;
    for (final path in [
      '/recommendations',
      '/toplists',
      '/new-songs',
      '/history',
      '/local-music',
      '/platform-playlists',
      '/smart-playlists',
      '/smart-playlists/editor',
      '/listening-stats',
      '/backup',
      '/settings/audio',
      '/settings/floating-lyrics',
      '/player',
      '/queue',
      '/downloads',
      '/album/qq/123',
      '/artist/netease/12',
      '/playlist/local/id',
      '/toplist/kugou/2',
      '/login/qq',
    ]) {
      expect(parser.findMatch(Uri.parse(path)).isError, isFalse, reason: path);
    }
    router.go('/album/invalid/12');
    await tester.pumpAndSettle();
    expect(find.text('这个页面暂时无法打开'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

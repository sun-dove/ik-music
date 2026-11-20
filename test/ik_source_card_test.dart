import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/lyrics/models/lyrics_line.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/video_app/ik/ik_theme.dart';
import 'package:mconnect/video_app/ui/video_theme.dart';
import 'package:mconnect/video_app/windows/windows_player_page.dart';

const song = Song(
  id: 'source',
  platform: PlatformType.qq,
  name: '真实音源曲目',
  artists: [Artist(id: 'artist', name: '歌手')],
);

Future<void> mount(
  WidgetTester tester, {
  double width = 1200,
  double height = 800,
  double scale = 1,
  bool modern = true,
  bool dark = false,
  VoidCallback? quality,
  WindowsSourceDetails? details,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final base = dark ? VideoTheme.dark : VideoTheme.light;
  await tester.pumpWidget(
    MaterialApp(
      theme: modern ? IkTheme.from(base) : base,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: WindowsPlayerPage(
        song: song,
        position: const Duration(seconds: 5),
        duration: const Duration(minutes: 3),
        isPlaying: true,
        lyrics: const [
          LyricsLine(timestamp: Duration.zero, text: '当前歌词'),
          LyricsLine(timestamp: Duration(seconds: 10), text: '下一句歌词'),
        ],
        qualityLabel: 'FLAC · 900 kbps',
        sourceStatus: const Text('已从备用源播放，原请求暂不可用'),
        sourceDetails: details,
        onToggle: () {},
        onPrevious: () {},
        onNext: () {},
        onSeek: (_) {},
        onQueue: () {},
        onMode: () {},
        onQuality: quality,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('K06 音源卡片打开详情并保留当前音质操作，旧默认不变', (tester) async {
    var changes = 0;
    await mount(tester, quality: () => changes++);
    expect(find.byKey(const ValueKey('ik-source-card')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ik-source-card')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('已从备用源播放，原请求暂不可用'), findsOneWidget);
    expect(find.textContaining('FLAC'), findsWidgets);
    await tester.tap(find.text('调整音质'));
    await tester.pumpAndSettle();
    expect(changes, 1);
    expect(find.byType(AlertDialog), findsNothing);
    await mount(tester, modern: false);
    expect(find.byKey(const ValueKey('ik-source-card')), findsNothing);
    expect(find.text('已从备用源播放，原请求暂不可用'), findsOneWidget);
  });

  testWidgets('K06 详情只展示已知真实格式/码率，未知值明确保留', (tester) async {
    await mount(
      tester,
      details: const WindowsSourceDetails(
        sourceName: '备用源',
        format: 'flac',
        bitrate: 900000,
        note: '原请求暂不可用，已使用备用音源',
      ),
    );
    await tester.tap(find.byKey(const ValueKey('ik-source-card')));
    await tester.pumpAndSettle();
    expect(find.text('实际音源：备用源'), findsOneWidget);
    expect(find.text('音频格式：FLAC'), findsOneWidget);
    expect(find.text('码率：900 kbps'), findsOneWidget);
    expect(find.text('原请求暂不可用，已使用备用音源'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await mount(tester, details: const WindowsSourceDetails());
    expect(
      find.text('尚未确认 · FLAC · 900 kbps'),
      findsOneWidget,
      reason: '未知音源的卡片摘要不得用歌曲所属平台冒充实际音源',
    );
    await tester.tap(find.byKey(const ValueKey('ik-source-card')));
    await tester.pumpAndSettle();
    expect(find.text('实际音源：尚未确认'), findsOneWidget);
    expect(find.text('音频格式：尚未确认'), findsOneWidget);
    expect(find.text('码率：尚未确认'), findsOneWidget);
    expect(find.text('调整音质'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    for (final width in [320.0, 720.0, 900.0, 1200.0]) {
      for (final scale in [1.0, 1.25, 1.5]) {
        testWidgets('K06/K08 播放及来源卡片 ${dark ? '深' : '浅'} $width / $scale', (
          tester,
        ) async {
          await mount(
            tester,
            width: width,
            height: width == 900 ? 600 : 800,
            scale: scale,
            dark: dark,
          );
          expect(
            find.byKey(const ValueKey('ik-source-card')).hitTestable(),
            findsOneWidget,
          );
          expect(find.byTooltip('暂停').hitTestable(), findsOneWidget);
          expect(find.byTooltip('播放队列').hitTestable(), findsOneWidget);
          final context = tester.element(find.text('当前歌词'));
          final active = tester.widget<Text>(find.text('当前歌词'));
          expect(active.style?.color, Theme.of(context).colorScheme.primary);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}

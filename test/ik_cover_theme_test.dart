import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/video_app/ik/ik_theme.dart';
import 'package:mconnect/video_app/ui/video_theme.dart';
import 'package:mconnect/video_app/windows/windows_player_page.dart';

Future<Uint8List> imageBytes(Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 32, 32), Paint()..color = color);
  final picture = recorder.endRecording();
  final image = await picture.toImage(32, 32);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List();
}

void main() {
  testWidgets('K08 封面实际取色、换封面更新，失败和自定义背景保留主题', (tester) async {
    final red = await tester.runAsync(() => imageBytes(Colors.red));
    final blue = await tester.runAsync(() => imageBytes(Colors.blue));
    ColorScheme? actual;
    Color? background;
    final base = IkTheme.from(VideoTheme.light);
    Future<void> mount(
      ImageProvider? cover, {
      bool customBackground = false,
    }) async {
      final theme = customBackground
          ? IkTheme.from(
              VideoTheme.light.copyWith(
                extensions: [const WindowsAppearanceTheme(hasBackground: true)],
              ),
            )
          : base;
      await tester.runAsync(
        () => tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: IkCoverTheme(
              cover: cover,
              child: Builder(
                builder: (context) {
                  actual = Theme.of(context).colorScheme;
                  background = VideoTheme.canvas(context);
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        for (var i = 0; i < 5; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pumpAndSettle();
    }

    await mount(MemoryImage(red!));
    expect(actual!.primary, isNot(base.colorScheme.primary));
    final redPrimary = actual!.primary;
    await mount(MemoryImage(blue!));
    expect(actual!.primary, isNot(redPrimary));
    final bluePrimary = actual!.primary;
    const lateCover = NetworkImage('https://cover.example/late.png');
    final lateImage = Completer<ImageInfo>();
    PaintingBinding.instance.imageCache.putIfAbsent(
      lateCover,
      () => OneFrameImageStreamCompleter(lateImage.future),
    );
    addTearDown(() => PaintingBinding.instance.imageCache.evict(lateCover));
    await mount(lateCover);
    await mount(MemoryImage(blue));
    final decoded = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(red);
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    });
    lateImage.complete(ImageInfo(image: decoded!));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(actual!.primary, bluePrimary, reason: '已切换封面后，迟到旧图不得覆盖新配色');
    await mount(null);
    expect(actual!.primary, base.colorScheme.primary);
    await mount(MemoryImage(Uint8List.fromList([0, 1, 2])));
    expect(actual!.primary, base.colorScheme.primary);
    await mount(MemoryImage(red), customBackground: true);
    expect(background, Colors.transparent);
    expect(tester.takeException(), isNull);
  });
}

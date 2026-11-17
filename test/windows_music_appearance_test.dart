import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:mconnect/video_app/video_preferences.dart';
import 'package:mconnect/video_app/windows/windows_appearance.dart';
import 'package:mconnect/video_app/windows/windows_music_preferences.dart';
import 'package:mconnect/video_app/windows/windows_window_controller.dart';

class NativeFixture extends WindowsWindowController {
  WindowsCloseAction action = WindowsCloseAction.minimize;
  bool available = true;
  @override
  Future<void> setCloseAction(WindowsCloseAction value) async {
    if (!available) {
      throw const DesktopConfigurationException(
        DesktopFailure.nativeUnavailable,
      );
    }
    action = value;
  }

  @override
  Future<List<String>> listFonts() async => [
    'Microsoft YaHei UI',
    'Noto Sans SC',
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late WindowsMusicPreferences preferences;
  late WindowsAppearance appearance;
  late NativeFixture native;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('leyin-appearance-gate-');
    Hive.init(root.path);
    preferences = WindowsMusicPreferences(
      VideoPreferences(await Hive.openBox('settings')),
    )..load();
    native = NativeFixture();
    appearance = WindowsAppearance(
      preferences: preferences,
      directory: Directory(p.join(root.path, 'appearance')),
      window: native,
    );
    await appearance.initialize();
  });
  tearDown(() async {
    appearance.dispose();
    preferences.dispose();
    await Hive.close();
    expect(
      p.isWithin(Directory.systemTemp.absolute.path, root.absolute.path),
      isTrue,
    );
    await root.delete(recursive: true);
  });
  Future<File> imageFixture() async =>
      File('design/platform-icons-010/qq-music.jpg')
          .copy(p.join(root.path, 'user-image.jpg'));
  test('W04：预览取消不落盘，确认后独立复制，原图移动不影响', () async {
    final image = await imageFixture();
    final draft = await appearance.prepareBackground(image);
    expect(preferences.value.background, isNull);
    expect(await appearance.directory.exists(), isFalse);
    await appearance.applyBackground(draft, soften: 5);
    final stored = appearance.backgroundFile!;
    expect(p.isWithin(appearance.directory.path, stored.path), isTrue);
    await image.delete();
    expect(await stored.exists(), isTrue);
    expect(preferences.value.background?.soften, 5);
    await appearance.initialize();
    expect(appearance.backgroundFile?.path, stored.path);
    await appearance.resetBackground();
    expect(appearance.backgroundFile, isNull);
    expect(await stored.exists(), isFalse);
  });
  test('W04：坏图片、缺图分别分类，坏图不改变当前配置', () async {
    final draft = await appearance.prepareBackground(await imageFixture());
    await appearance.applyBackground(draft);
    final saved = preferences.value;
    final invalid = await File(p.join(root.path, 'invalid.png'))
        .writeAsBytes([1, 2, 3]);
    await expectLater(
      appearance.prepareBackground(invalid),
      throwsA(
        isA<DesktopConfigurationException>().having(
          (e) => e.kind,
          '坏图片',
          DesktopFailure.invalidImage,
        ),
      ),
    );
    expect(preferences.value, same(saved));
    await appearance.backgroundFile!.delete();
    await appearance.initialize();
    expect(appearance.backgroundError, DesktopFailure.fileMissing);
    expect(appearance.backgroundFile, isNull);
    expect(preferences.value, same(saved));
  });
  test('W04：保存失败保留当前背景，精确移除本次未应用文件', () async {
    final failingPreferences = WindowsMusicPreferences(
      preferences.legacy,
      write: (_) async => throw const FileSystemException('模拟失败'),
    )..load();
    final failing = WindowsAppearance(
      preferences: failingPreferences,
      directory: appearance.directory,
      window: native,
    );
    addTearDown(failing.dispose);
    addTearDown(failingPreferences.dispose);
    final draft = await failing.prepareBackground(await imageFixture());
    await expectLater(
      failing.applyBackground(draft),
      throwsA(
        isA<DesktopConfigurationException>().having(
          (e) => e.kind,
          '保存失败',
          DesktopFailure.saveFailed,
        ),
      ),
    );
    expect(failing.backgroundFile, isNull);
    expect(await appearance.directory.list().length, 0);
  });
  test('W05：实际枚举列表不伪造苹方，系统字体与缺失回退', () async {
    expect(appearance.fonts, isNot(contains('PingFang SC')));
    await appearance.selectSystemFont('Noto Sans SC');
    expect(appearance.fontFamily, 'Noto Sans SC');
    expect(preferences.value.font?.family, 'Noto Sans SC');
    await appearance.resetFont();
    expect(appearance.fontFamily, 'Microsoft YaHei UI');
  });
  test('W05：无效TTF拒绝并保留当前字体，不保存样例', () async {
    await appearance.selectSystemFont('Noto Sans SC');
    final invalid = await File(p.join(root.path, 'invalid.ttf'))
        .writeAsBytes([0, 1, 0, 0]);
    await expectLater(
      appearance.prepareFont(invalid),
      throwsA(
        isA<DesktopConfigurationException>().having(
          (e) => e.kind,
          '无效字体',
          DesktopFailure.invalidFont,
        ),
      ),
    );
    expect(appearance.fontFamily, 'Noto Sans SC');
    expect(await appearance.directory.exists(), isFalse);
  });
  test('W05：仅伪造有效字体头、没有字形表的TTF不能假报导入成功', () async {
    final data = ByteData(28)
      ..setUint32(0, 0x00010000)
      ..setUint16(4, 1)
      ..setUint32(12, 0x636d6170)
      ..setUint32(20, 28);
    final invalid = await File(p.join(root.path, 'fake-header.ttf'))
        .writeAsBytes(data.buffer.asUint8List());
    await expectLater(
      appearance.prepareFont(invalid),
      throwsA(
        isA<DesktopConfigurationException>().having(
          (error) => error.kind,
          '无字形字体',
          DesktopFailure.invalidFont,
        ),
      ),
    );
    expect(preferences.value.font, isNull);
    expect(await appearance.directory.exists(), isFalse);
  });
  test('W05：有效TTF导入、确认、重启加载、缺失回退并释放原文件', () async {
    final packages = jsonDecode(
      File('.dart_tool/package_config.json').readAsStringSync(),
    ) as Map;
    final flutter = (packages['packages'] as List).cast<Map>().singleWhere(
      (package) => package['name'] == 'flutter',
    );
    final flutterPackage = Directory.fromUri(
      Uri.parse(flutter['rootUri'] as String),
    );
    final sdk = p.dirname(p.dirname(flutterPackage.path));
    final file = await File(
      p.join(sdk, 'bin/cache/artifacts/material_fonts/roboto-regular.ttf'),
    ).copy(p.join(root.path, 'user-font.ttf'));
    final draft = await appearance.prepareFont(file);
    expect(preferences.value.font, isNull);
    await appearance.applyFont(draft);
    final selected = preferences.value.font!;
    final stored = File(p.join(appearance.directory.path, selected.file!));
    await file.delete();
    await appearance.initialize();
    expect(appearance.fontFamily, selected.family);
    expect(appearance.fontError, isNull);
    expect(await stored.exists(), isTrue);
    await stored.delete();
    await appearance.initialize();
    expect(appearance.fontError, DesktopFailure.fileMissing);
    expect(appearance.fontFamily, 'Microsoft YaHei UI');
  });
  test('W10：关闭配置保存失败恢复原生动作，不假报成功', () async {
    final failingPreferences = WindowsMusicPreferences(
      preferences.legacy,
      write: (_) async => throw const FileSystemException('模拟失败'),
    )..load();
    final failing = WindowsAppearance(
      preferences: failingPreferences,
      directory: appearance.directory,
      window: native,
    );
    addTearDown(failing.dispose);
    addTearDown(failingPreferences.dispose);
    await expectLater(
      failing.setCloseAction(WindowsCloseAction.exit),
      throwsA(isA<DesktopConfigurationException>()),
    );
    expect(native.action, WindowsCloseAction.minimize);
    expect(failingPreferences.closeAction, WindowsCloseAction.minimize);
  });
  test('W10：原生通道失效后保留关闭配置并禁用相关选项，重试可恢复', () async {
    expect(appearance.nativeAvailable, isTrue);
    native.available = false;
    await expectLater(
      appearance.setCloseAction(WindowsCloseAction.exit),
      throwsA(isA<DesktopConfigurationException>()),
    );
    expect(preferences.closeAction, WindowsCloseAction.minimize);
    expect(appearance.nativeAvailable, isFalse);
    expect(appearance.nativeError, DesktopFailure.nativeUnavailable);
    native.available = true;
    await appearance.initialize();
    expect(appearance.nativeAvailable, isTrue);
    expect(appearance.nativeError, isNull);
  });
}

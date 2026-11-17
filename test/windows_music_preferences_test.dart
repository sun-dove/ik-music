import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/video_app/video_preferences.dart';
import 'package:mconnect/video_app/windows/windows_music_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Box box;
  late VideoPreferences legacy;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'leyin-preferences-gate-',
    );
    Hive.init(directory.path);
    box = await Hive.openBox('settings');
    legacy = VideoPreferences(box);
  });
  tearDown(() async {
    await Hive.close();
    expect(
      p.isWithin(Directory.systemTemp.absolute.path, directory.absolute.path),
      isTrue,
    );
    await directory.delete(recursive: true);
  });
  test('W01/W11：缺省全局键精确沿用旧三平台，混合值显示沿用原设置', () async {
    await legacy.setQuality(PlatformType.qq, AudioLevel.lossless);
    await legacy.setQuality(PlatformType.netease, AudioLevel.high);
    final desktop = WindowsMusicPreferences(legacy)..load();
    for (final platform in [
      PlatformType.qq,
      PlatformType.netease,
      PlatformType.kugou,
    ]) {
      expect(desktop.quality(platform), legacy.quality(platform));
      expect(
        desktop.quality(platform, download: true),
        legacy.quality(platform, download: true),
      );
    }
    expect(desktop.qualityLabel(), '沿用原设置');
    expect(box.containsKey(WindowsMusicPreferences.key), isFalse);
  });
  test('W02/W03：统一播放下载分别保存，所有平台读取一致，旧键保留', () async {
    await legacy.setQuality(PlatformType.qq, AudioLevel.medium);
    final desktop = WindowsMusicPreferences(legacy)..load();
    await desktop.setQuality(AudioLevel.lossless);
    await desktop.setQuality(AudioLevel.high, download: true);
    for (final platform in [
      PlatformType.qq,
      PlatformType.netease,
      PlatformType.kugou,
    ]) {
      expect(desktop.quality(platform), AudioLevel.lossless);
      expect(desktop.quality(platform, download: true), AudioLevel.high);
    }
    expect(legacy.quality(PlatformType.qq), AudioLevel.medium);
    expect(legacy.quality(PlatformType.netease), AudioLevel.low);
    final restored = WindowsMusicPreferences(legacy)..load();
    expect(restored.quality(PlatformType.kugou), AudioLevel.lossless);
    expect(restored.quality(PlatformType.qq, download: true), AudioLevel.high);
  });
  test('W02：最高与固定模式一次持久化，失败不改变任一快照', () async {
    final sources = WindowsSourceSettings(legacy)..load();
    final desktop = WindowsMusicPreferences(legacy, sources: sources)..load();
    await desktop.setQuality(null, highest: true);
    expect(sources.value.highestQuality, isTrue);
    final saved = box.get(WindowsMusicPreferences.key);
    final failing = WindowsMusicPreferences(
      legacy,
      sources: sources,
      write: (_) async => throw const FileSystemException('模拟保存失败'),
    )..load();
    await expectLater(
      failing.setQuality(AudioLevel.hires),
      throwsA(
        isA<DesktopConfigurationException>().having(
          (e) => e.kind,
          '保存失败类别',
          DesktopFailure.saveFailed,
        ),
      ),
    );
    expect(sources.value.highestQuality, isTrue);
    expect(box.get(WindowsMusicPreferences.key), saved);
    expect(failing.value.playQuality, isNull);
    await desktop.setQuality(AudioLevel.lossless);
    expect(sources.value.highestQuality, isFalse);
    sources.load();
    expect(sources.value.highestQuality, isFalse);
    expect(desktop.quality(PlatformType.netease), AudioLevel.lossless);
  });
  test('W04/W05/W10：外观与关闭可重启恢复，缺省不写旧键', () async {
    final desktop = WindowsMusicPreferences(legacy)..load();
    await desktop.update(
      desktop.value.copyWith(
        background: const BackgroundSelection(
          file: 'background.png',
          soften: 8,
        ),
        font: const FontSelection(family: 'Noto Sans SC'),
        closeAction: WindowsCloseAction.exit,
      ),
    );
    final restored = WindowsMusicPreferences(legacy)..load();
    expect(restored.value.background?.file, 'background.png');
    expect(restored.value.font?.family, 'Noto Sans SC');
    expect(restored.closeAction, WindowsCloseAction.exit);
    expect(box.get('video.theme'), isNull);
    expect(restored.quality(PlatformType.qq), AudioLevel.low);
  });
  test('W11：损坏或未来版本配置回退，不清除原文件与旧键', () async {
    for (final raw in [
      '{invalid',
      jsonEncode({'schemaVersion': 99}),
    ]) {
      await box.put(WindowsMusicPreferences.key, raw);
      final desktop = WindowsMusicPreferences(legacy)..load();
      expect(desktop.loadError, DesktopFailure.readFailed);
      expect(desktop.quality(PlatformType.qq), AudioLevel.low);
      expect(box.get(WindowsMusicPreferences.key), raw);
    }
  });
}

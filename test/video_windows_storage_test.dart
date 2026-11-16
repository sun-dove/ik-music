import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/video_app/data/video_windows_storage.dart';

void main() {
  test('Windows设置写入独立应用目录，不改写原产品的同名文件', () async {
    final root = await Directory.systemTemp.createTemp('yueyin-storage-gate-');
    addTearDown(() async {
      await Hive.close();
      await root.delete(recursive: true);
    });
    final legacy = File('${root.path}/settings.hive');
    await legacy.writeAsString('legacy-sentinel');
    final appDirectory = Directory('${root.path}/sun-dove/YueyinMusic');
    final result = await initializeWindowsVideoHive(
      directoryProvider: () async => appDirectory,
    );
    final settings = await Hive.openBox('settings');
    await settings.put('fixture', 'yueyin');
    expect(result.path, appDirectory.path);
    expect(settings.path, startsWith(appDirectory.path));
    expect(await legacy.readAsString(), 'legacy-sentinel');
  });
}

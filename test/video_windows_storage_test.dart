import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/core/database/app_database.dart';
import 'package:mconnect/video_app/data/video_windows_storage.dart';

void main() {
  test('Windows曲库写入独立数据库，保留原产品文件', () async {
    final root = await Directory.systemTemp.createTemp('yueyin-database-gate-');
    final legacy = File('${root.path}/mconnect.sqlite');
    await legacy.writeAsString('legacy-database-sentinel');
    final appDirectory = Directory('${root.path}/sun-dove/YueyinMusic');
    final db = await initializeWindowsVideoDatabase(appDirectory);
    expect(database, same(db));
    addTearDown(() async {
      await db.close();
      await root.delete(recursive: true);
    });
    final rows = await db.customSelect('PRAGMA database_list').get();
    final main = rows.singleWhere((row) => row.read<String>('name') == 'main');
    expect(main.read<String>('file'), contains('YueyinMusic'));
    expect(await File('${appDirectory.path}/yueyin.sqlite').exists(), isTrue);
    expect(await legacy.readAsString(), 'legacy-database-sentinel');
  });

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

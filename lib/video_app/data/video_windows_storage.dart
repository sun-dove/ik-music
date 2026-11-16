import 'dart:io';

import 'package:drift/native.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/database/app_database.dart';

Future<AppDatabase> initializeWindowsVideoDatabase(Directory directory) async {
  await directory.create(recursive: true);
  final db = AppDatabase.withExecutor(
    NativeDatabase.createInBackground(
      File('${directory.path}${Platform.pathSeparator}yueyin.sqlite'),
      setup: (rawDb) {
        rawDb.execute('PRAGMA journal_mode=WAL;');
        rawDb.execute('PRAGMA busy_timeout=5000;');
      },
    ),
  );
  initializeApplicationDatabase(db);
  return db;
}

Future<Directory> initializeWindowsVideoHive({
  Future<Directory> Function()? directoryProvider,
}) async {
  final directory =
      await (directoryProvider ?? getApplicationSupportDirectory)();
  await directory.create(recursive: true);
  Hive.init(directory.path);
  return directory;
}

import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

Future<Directory> initializeWindowsVideoHive({
  Future<Directory> Function()? directoryProvider,
}) async {
  final directory =
      await (directoryProvider ?? getApplicationSupportDirectory)();
  await directory.create(recursive: true);
  Hive.init(directory.path);
  return directory;
}

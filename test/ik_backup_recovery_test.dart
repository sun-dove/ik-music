import 'dart:io';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/database/app_database.dart';
import 'package:mconnect/features/backup/data/backup_store.dart';
import 'package:mconnect/features/backup/data/backup_service.dart';
import 'package:mconnect/features/backup/data/guarded_backup_store.dart';
import 'package:mconnect/features/backup/domain/backup_models.dart';
import 'package:mconnect/features/library/data/my_playlists_repository.dart';
import 'package:mconnect/features/smart_playlists/data/smart_playlist_repository.dart';

class _FailingSettings extends MemorySettingsSnapshotSource {
  _FailingSettings() : super({'font': '微软雅黑'});
  int failures = 1;
  @override
  Future<void> write(Map<String, dynamic> values) async {
    await super.write(values);
    if (failures-- > 0) throw const FileSystemException('write rejected');
  }
}

void main() {
  test('K06 实际中文备份经过文件选择器字节路径完整恢复', () async {
    final directory = await Directory.systemTemp.createTemp('ik-backup-gate-');
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      await db.close();
      expect(
        directory.absolute.path,
        startsWith(Directory.systemTemp.absolute.path),
      );
      await directory.delete(recursive: true);
    });
    final playlists = MyPlaylistsRepository(storageDirectory: directory);
    final settings = MemorySettingsSnapshotSource({'font': '微软雅黑'});
    final store = GuardedAppBackupStore(
      database: db,
      playlists: playlists,
      smartRules: MemorySmartPlaylistRepository(),
      settings: settings,
      recoveryDirectory: directory,
      appVersion: 'ik-test',
    );
    await playlists.createPlaylist('我的夜曲 🎵');
    final service = BackupService(
      store: store,
      appVersion: 'ik-test',
      fileNamePrefix: 'ik-backup-',
    );
    final raw = await service.exportToJson();
    await store.clearAll();
    await service.importFromJson(
      BackupService.decodeFileBytes(utf8.encode(raw)),
    );
    expect((await playlists.getPlaylists()).single.name, '我的夜曲 🎵');
    expect(settings.values, {'font': '微软雅黑'});
  });
  test('K06 中途导入失败回滚数据库和全部外部存储，保留恢复点', () async {
    final directory = await Directory.systemTemp.createTemp('ik-backup-gate-');
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      await db.close();
      expect(
        directory.absolute.path,
        startsWith(Directory.systemTemp.absolute.path),
      );
      await directory.delete(recursive: true);
    });
    final playlists = MyPlaylistsRepository(storageDirectory: directory);
    final original = await playlists.createPlaylist('原歌单');
    final rawBefore = await File('${directory.path}/my_playlists.json')
        .readAsString();
    final settings = _FailingSettings();
    final rules = MemorySmartPlaylistRepository();
    final store = GuardedAppBackupStore(
      database: db,
      playlists: playlists,
      smartRules: rules,
      settings: settings,
      recoveryDirectory: directory,
      appVersion: 'ik-test',
    );
    await expectLater(
      store.restore(
        const BackupData(
          songs: [
            BackupSong(id: 'new', platform: 'qq', name: '导入歌曲', artists: '歌手'),
          ],
          playlists: [BackupPlaylist(id: 'new', name: '新增歌单', songs: [])],
          settings: {'font': '错误字体', 'newSetting': true},
        ),
      ),
      throwsA(
        isA<BackupRestoreException>().having(
          (e) => e.recovered,
          'recovered',
          isTrue,
        ),
      ),
    );
    expect(await db.songsDao.getAllSongs(), isEmpty);
    expect(
      (await playlists.getPlaylists()).single.editableId,
      original.editableId,
    );
    expect(
      await File('${directory.path}/my_playlists.json').readAsString(),
      rawBefore,
    );
    expect(settings.values, {'font': '微软雅黑'});
    final recovery = directory
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('ik-before-import-'))
        .single;
    expect(await recovery.readAsString(), contains('微软雅黑'));
  });

  test('K06 自动恢复也失败时明确返回恢复文件，不能报告导入成功', () async {
    final directory = await Directory.systemTemp.createTemp('ik-backup-gate-');
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      await db.close();
      expect(
        directory.absolute.path,
        startsWith(Directory.systemTemp.absolute.path),
      );
      await directory.delete(recursive: true);
    });
    final settings = _FailingSettings()..failures = 2;
    final store = GuardedAppBackupStore(
      database: db,
      playlists: MyPlaylistsRepository(storageDirectory: directory),
      smartRules: MemorySmartPlaylistRepository(),
      settings: settings,
      recoveryDirectory: directory,
      appVersion: 'ik-test',
    );
    await expectLater(
      store.restore(const BackupData(settings: {'font': '新字体'})),
      throwsA(
        isA<BackupRestoreException>()
            .having((e) => e.recovered, 'recovered', isFalse)
            .having(
              (e) => File(e.recoveryPath).existsSync(),
              'recovery file',
              isTrue,
            ),
      ),
    );
  });
}

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
// ignore: implementation_imports
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
// ignore: implementation_imports
import 'package:file_picker/src/platform/file_picker_method_channel.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/features/download/data/download_directory_service.dart';
import 'package:mconnect/features/download/data/repositories/download_manager.dart';
import 'package:mconnect/features/download/domain/entities/download_task.dart';
import 'package:mconnect/features/download/presentation/providers/download_provider.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/platform/base/platform_registry.dart';
import 'package:mconnect/video_app/video_preferences.dart';
import 'package:mconnect/video_app/windows/windows_download.dart';
import 'package:mconnect/video_app/windows/windows_music_preferences.dart';
import 'package:path/path.dart' as p;

import 'download_fakes.dart';

const _baseline = bool.fromEnvironment('LEYIN_BASELINE');
const _platforms = [PlatformType.qq, PlatformType.netease, PlatformType.kugou];

class _QualityPlatform extends FakeDownloadPlatform {
  _QualityPlatform({required super.url, required super.platform});
  final qualities = <AudioLevel>[];
  @override
  Future<String> getSongUrl(
    String songId, {
    AudioLevel quality = AudioLevel.low,
  }) {
    qualities.add(quality);
    return super.getSongUrl(songId, quality: quality);
  }
}

Song _song(PlatformType platform) => Song(
  id: 'desktop-download',
  platform: platform,
  name: '下载档位验收',
  artists: const [Artist(id: 'fixture', name: '验收')],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late HttpServer server;
  late WindowsMusicPreferences preferences;
  late DownloadNotifier notifier;
  late Map<PlatformType, _QualityPlatform> platforms;
  late MemoryDownloadDirectoryStore directoryStore;
  late HttpOverrides? originalOverrides;
  final bytes = List<int>.generate(2048, (i) => i % 251);

  setUp(() async {
    originalOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    root = await Directory.systemTemp.createTemp('leyin-download-gate-');
    Hive.init(root.path);
    preferences = WindowsMusicPreferences(
      VideoPreferences(await Hive.openBox('settings')),
    )..load();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      request.response.contentLength = bytes.length;
      request.response.add(bytes);
      unawaited(request.response.close());
    });
    platforms = {
      for (final platform in _platforms)
        platform: _QualityPlatform(
          url: 'http://127.0.0.1:${server.port}/audio',
          platform: platform,
        ),
    };
    for (final platform in platforms.values) {
      PlatformRegistry.register(platform);
    }
    directoryStore = MemoryDownloadDirectoryStore();
    notifier = DownloadNotifier(
      manager: DownloadManager(
        directoryService: DownloadDirectoryService(
          store: directoryStore,
          defaultRootProvider: () async =>
              Directory(p.join(root.path, 'files')),
        ),
        freeSpaceProbe: (_) async => null,
      ),
      taskStore: MemoryDownloadTaskStore([]),
      policy: () =>
          const DownloadQueuePolicy(autoRetry: false, autoCleanup: false),
    );
    await notifier.ready;
  });
  tearDown(() async {
    notifier.dispose();
    preferences.dispose();
    await server.close(force: true);
    await Hive.close();
    HttpOverrides.global = originalOverrides;
    expect(
      p.isWithin(Directory.systemTemp.absolute.path, root.absolute.path),
      isTrue,
    );
    await root.delete(recursive: true);
  });

  Future<void> settleTask(String id) async {
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    while (!notifier.state.tasks.any(
      (task) => task.id == id && task.status == DownloadStatus.completed,
    )) {
      if (DateTime.now().isAfter(deadline)) {
        fail(
          '下载没有完成：${notifier.state.tasks.map((task) => '${task.id}:${task.status}:${task.error}').join(', ')}',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<void> retry(DownloadTask task) => _baseline
      ? notifier.resumeDownload(task.id)
      : retryWindowsDownload(
          notifier,
          task,
          preferences.quality(task.song.platform, download: true),
          readState: () => notifier.state,
        );

  test('W03：Windows选择下载目录复用保存契约，取消不改变已有目录', () async {
    const channel = MethodChannel('miguelruivo.flutter.plugins.filepicker');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final original = FilePickerPlatform.instance;
    FilePickerPlatform.instance = MethodChannelFilePicker();
    addTearDown(() {
      FilePickerPlatform.instance = original;
      messenger.setMockMethodCallHandler(channel, null);
    });
    final selected = await Directory(p.join(root.path, 'chosen-downloads'))
        .create();
    messenger.setMockMethodCallHandler(channel, (_) async => selected.path);
    final result = _baseline
        ? await notifier.manager.directoryService.applySafTreeDirectory()
        : await chooseWindowsDownloadDirectory(notifier);
    expect(result?.isOk, isTrue);
    expect(directoryStore.customRootPath, selected.path);
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(await chooseWindowsDownloadDirectory(notifier), isNull);
    expect(directoryStore.customRootPath, selected.path);
  });

  test('W03：三平台新下载传到实际URL解析器，播放档位不影响下载', () async {
    await preferences.setQuality(AudioLevel.hires);
    await preferences.setQuality(AudioLevel.high, download: true);
    for (final platform in _platforms) {
      final song = _song(platform);
      await notifier.startDownload(
        song,
        preferences.quality(platform, download: true),
      );
      final id = DownloadTask.buildId(song, AudioLevel.high);
      await settleTask(id);
      expect(platforms[platform]!.qualities, [AudioLevel.high]);
      final task = notifier.state.tasks.singleWhere((task) => task.id == id);
      expect(task.quality, AudioLevel.high);
      expect(await File(task.filePath!).readAsBytes(), bytes);
    }
  });

  test('W03：三平台明确重试失败任务采用当前档位，不重复旧任务', () async {
    await preferences.setQuality(AudioLevel.lossless, download: true);
    for (final platform in _platforms) {
      final song = _song(platform);
      await notifier.startDownload(song, AudioLevel.low);
      final oldId = DownloadTask.buildId(song, AudioLevel.low);
      await settleTask(oldId);
      final completed = notifier.state.tasks.singleWhere(
        (task) => task.id == oldId,
      );
      notifier.dispose();
      notifier = DownloadNotifier(
        manager: notifier.manager,
        initialState: DownloadState(
          tasks: [completed.copyWith(status: DownloadStatus.failed)],
        ),
        taskStore: MemoryDownloadTaskStore([]),
        policy: () =>
            const DownloadQueuePolicy(autoRetry: false, autoCleanup: false),
      );
      final failed = notifier.state.tasks.single;
      await retry(failed);
      final expected = _baseline
          ? oldId
          : DownloadTask.buildId(song, AudioLevel.lossless);
      await settleTask(expected);
      expect(platforms[platform]!.qualities.last, AudioLevel.lossless);
      expect(notifier.state.tasks.single.quality, AudioLevel.lossless);
      expect(notifier.state.tasks.any((task) => task.id == oldId), isFalse);
    }
  });

  test('W03：暂停续传保持原档，设置变化不改已有任务', () async {
    final song = _song(PlatformType.qq);
    final id = DownloadTask.buildId(song, AudioLevel.low);
    final paused = DownloadTask(
      id: id,
      song: song,
      quality: AudioLevel.low,
      status: DownloadStatus.paused,
      createdAt: DateTime(2026),
    );
    notifier.dispose();
    notifier = DownloadNotifier(
      manager: notifier.manager,
      initialState: DownloadState(tasks: [paused]),
      taskStore: MemoryDownloadTaskStore([]),
    );
    await preferences.setQuality(AudioLevel.hires, download: true);
    await retry(paused);
    await settleTask(id);
    expect(notifier.state.tasks.single.quality, AudioLevel.low);
    expect(platforms[PlatformType.qq]!.qualities, [AudioLevel.low]);
  });

  test('W03：离线缓存明确重试同步采用新档位并保留缓存标记', () async {
    final song = _song(PlatformType.kugou);
    final failed = DownloadTask(
      id: DownloadTask.buildCacheId(song, AudioLevel.low),
      song: song,
      quality: AudioLevel.low,
      status: DownloadStatus.failed,
      isOfflineCache: true,
      createdAt: DateTime(2026),
    );
    notifier.dispose();
    notifier = DownloadNotifier(
      manager: notifier.manager,
      initialState: DownloadState(tasks: [failed]),
      taskStore: MemoryDownloadTaskStore([]),
      policy: () =>
          const DownloadQueuePolicy(autoRetry: false, autoCleanup: false),
    );
    await preferences.setQuality(AudioLevel.hires, download: true);
    await retry(failed);
    final expected = _baseline
        ? failed.id
        : DownloadTask.buildCacheId(song, AudioLevel.hires);
    await settleTask(expected);
    expect(notifier.state.tasks.single.isOfflineCache, isTrue);
    expect(notifier.state.tasks.single.quality, AudioLevel.hires);
    expect(platforms[PlatformType.kugou]!.qualities, [AudioLevel.hires]);
  });
}

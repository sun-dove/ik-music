import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/video_app/built_in/catalog.dart';
import 'package:mconnect/video_app/built_in/catalog_coordinator.dart';
import 'package:mconnect/video_app/built_in/catalog_panel.dart';
import 'package:mconnect/video_app/built_in/fixed_importer.dart';
import 'package:mconnect/video_app/built_in/managed_settings.dart';
import 'package:mconnect/video_app/custom_source/custom_source_models.dart';
import 'package:mconnect/video_app/lx_source/lx_source.dart';
import 'package:mconnect/video_app/multi_source/source_collection.dart';
import 'package:mconnect/video_app/video_preferences.dart';

const _script = '/* @name 正式验收源\n * @version 1\n */\nfixture';
final _bytes = utf8.encode(_script);
IkCatalogEntry _entry(String name, {List<int>? bytes}) => IkCatalogEntry(
  sourceKey: 'pdone:$name',
  displayName: name,
  path: '$name/1.js',
  byteLength: (bytes ?? _bytes).length,
  contentSha256: sha256.convert(bytes ?? _bytes).toString(),
  autoPolicy: 'prepare',
  licenseEvidence: 'none',
  licenseNote: '验收样例，不联系真实上游',
);
IkSourceCatalog _catalog([int count = 2]) => IkSourceCatalog(
  catalogVersion: 1,
  commit: 'ed8328dbd1a77aee3ee0116d835eb9d907eeaad2',
  entries: List.generate(count, (i) => _entry('source$i')),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('S01 完整固定目录保留20项，许可与历史限制不掩盖', () {
    final catalog = IkSourceCatalog.fromJson(
      jsonDecode(File('assets/source-catalog/pdone-v1.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    expect(catalog.entries, hasLength(20));
    expect(catalog.entries.map((e) => e.sourceKey).toSet(), hasLength(20));
    expect(catalog.commit, 'ed8328dbd1a77aee3ee0116d835eb9d907eeaad2');
    expect(catalog.entries.fold<int>(0, (n, e) => n + e.byteLength), 1558217);
    for (final entry in catalog.entries) {
      expect(entry.contentSha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(entry.path, isNot(contains('latest')));
      expect(entry.licenseNote, isNotEmpty);
      expect(
        entry.blockReason('windows-lx3') != null ||
            entry.autoPolicy == 'prepare',
        isTrue,
      );
    }
    expect(
      catalog.entries.where((e) => e.blockReason('windows-lx3') == null),
      hasLength(15),
    );
  });

  test('S05 修改字节与无效编码在inspect之前拒绝', () async {
    final engine = _Engine();
    final importer = IkFixedSourceImporter(
      engine: engine,
      fetch: (_, _) async => [0, 1],
    );
    await expectLater(
      importer.prepare(_catalog(), _entry('a'), CancelToken()),
      throwsA(
        isA<LxSourceException>().having((e) => e.code, '类别', 'integrity'),
      ),
    );
    expect(engine.calls, 0);
    final invalid = [0xc3, 0x28];
    final encoding = IkFixedSourceImporter(
      engine: engine,
      fetch: (_, _) async => invalid,
    );
    await expectLater(
      encoding.prepare(_catalog(), _entry('a', bytes: invalid), CancelToken()),
      throwsA(
        isA<LxSourceException>().having((e) => e.code, '类别', 'invalidEncoding'),
      ),
    );
    expect(engine.calls, 0);
  });

  test('S01/S02 自动准备、完整20项、并发单飞及重开不重复执行', () async {
    final box = _Box();
    final settings = IkManagedSourceSettings(VideoPreferences(box))..load();
    final engine = _Engine();
    var downloads = 0;
    final gate = Completer<void>();
    final coordinator = IkSourceCatalogCoordinator(
      catalog: _catalog(20),
      settings: settings,
      runtimeId: 'windows-lx3',
      importer: IkFixedSourceImporter(
        engine: engine,
        fetch: (_, _) async {
          downloads++;
          await gate.future;
          return _bytes;
        },
      ),
    );
    addTearDown(coordinator.dispose);
    final first = coordinator.prepareOnce();
    final second = coordinator.prepareOnce();
    expect(identical(first, second), isTrue);
    expect(settings.value.entries, isEmpty);
    gate.complete();
    await first;
    expect(downloads, 20);
    expect(engine.calls, 20);
    expect(settings.value.entries, hasLength(20));
    expect(settings.value.autoSwitch, isTrue);
    expect(settings.value.sourceFirst, isFalse);
    expect(
      settings.value.entries.every(
        (e) => e.config.enabled && !e.config.allowForDownloads,
      ),
      isTrue,
    );
    expect(
      coordinator.items.every((e) => e.stage == IkSourceStage.ready),
      isTrue,
    );
    final reopened = IkManagedSourceSettings(VideoPreferences(box))..load();
    final next = IkSourceCatalogCoordinator(
      catalog: _catalog(20),
      settings: reopened,
      runtimeId: 'windows-lx3',
      importer: IkFixedSourceImporter(
        engine: engine,
        fetch: (_, _) async {
          downloads++;
          return _bytes;
        },
      ),
    );
    addTearDown(next.dispose);
    await next.prepareOnce();
    expect(downloads, 20);
    expect(engine.calls, 20);
    expect(reopened.value.entries, hasLength(20));
  });

  test('S03/S04 离线不清已有配置，逐项失败可重试', () async {
    var offline = true;
    final settings = IkManagedSourceSettings(VideoPreferences(_Box()))..load();
    final coordinator = IkSourceCatalogCoordinator(
      catalog: _catalog(),
      settings: settings,
      runtimeId: 'windows-lx3',
      importer: IkFixedSourceImporter(
        engine: _Engine(),
        fetch: (uri, _) async {
          if (offline && uri.path.contains('source1')) {
            throw const LxSourceException('network', '离线');
          }
          return _bytes;
        },
      ),
    );
    addTearDown(coordinator.dispose);
    await coordinator.prepareOnce();
    expect(settings.value.entries, hasLength(1));
    expect(coordinator.items.last.stage, IkSourceStage.waitingNetwork);
    offline = false;
    await coordinator.retry('pdone:source1');
    expect(settings.value.entries, hasLength(2));
    expect(
      coordinator.items.every((e) => e.stage == IkSourceStage.ready),
      isTrue,
    );
  });

  test('S07 禁用、删除墓碑、下载选择重启后不复活', () async {
    final box = _Box();
    final settings = IkManagedSourceSettings(VideoPreferences(box))..load();
    final importer = IkFixedSourceImporter(
      engine: _Engine(),
      fetch: (_, _) async => _bytes,
    );
    final coordinator = IkSourceCatalogCoordinator(
      catalog: _catalog(),
      settings: settings,
      runtimeId: 'windows-lx3',
      importer: importer,
    );
    addTearDown(coordinator.dispose);
    await coordinator.prepareOnce();
    final first = settings.value.entries.first;
    final last = settings.value.entries.last;
    await settings.save(
      settings.value
          .replace(
            first.id,
            first.config.copyWith(enabled: false, allowForDownloads: true),
          )
          .remove(last.id),
    );
    final reopened = IkManagedSourceSettings(VideoPreferences(box))..load();
    final next = IkSourceCatalogCoordinator(
      catalog: _catalog(),
      settings: reopened,
      runtimeId: 'windows-lx3',
      importer: importer,
    );
    addTearDown(next.dispose);
    await next.prepareOnce();
    await next.retry();
    expect(reopened.value.entries, hasLength(1));
    expect(reopened.value.entries.single.config.enabled, isFalse);
    expect(reopened.value.entries.single.config.allowForDownloads, isTrue);
    expect(next.items.map((e) => e.stage), [
      IkSourceStage.disabled,
      IkSourceStage.removed,
    ]);
  });

  test('S09/S10 编辑租约及在播期间只准备，质量写入与发布不丢字段', () async {
    var playing = true;
    final settings = IkManagedSourceSettings(VideoPreferences(_Box()))..load();
    final coordinator = IkSourceCatalogCoordinator(
      catalog: _catalog(),
      settings: settings,
      runtimeId: 'windows-lx3',
      isPlaybackActive: () => playing,
      importer: IkFixedSourceImporter(
        engine: _Engine(),
        fetch: (_, _) async => _bytes,
      ),
    );
    addTearDown(coordinator.dispose);
    coordinator.suspendPublishing();
    var notifications = 0;
    settings.addListener(() => notifications++);
    await coordinator.prepareOnce();
    expect(
      coordinator.items.every((e) => e.stage == IkSourceStage.pendingApply),
      isTrue,
    );
    expect(settings.value.entries, isEmpty);
    await coordinator.commitAtPlaybackBoundary();
    expect(settings.value.entries, isEmpty);
    final quality = IkManagedMusicPreferences(
      settings.preferences,
      sources: settings,
    )..load();
    await quality.setQuality(AudioLevel.lossless, highest: true);
    coordinator.resumePublishing();
    await coordinator.commitAtPlaybackBoundary();
    expect(settings.value.entries, hasLength(2));
    expect(settings.value.highestQuality, isTrue);
    expect(notifications, 1, reason: '自动发布不得触发旧播放器的配置变更暂停');
    playing = false;
  });

  test('S11 发布失败不改变集合，可重试发布且元数据同批恢复', () async {
    final box = _Box();
    final settings = IkManagedSourceSettings(VideoPreferences(box))..load();
    final coordinator = IkSourceCatalogCoordinator(
      catalog: _catalog(),
      settings: settings,
      runtimeId: 'windows-lx3',
      isPlaybackActive: () => true,
      importer: IkFixedSourceImporter(
        engine: _Engine(),
        fetch: (_, _) async => _bytes,
      ),
    );
    addTearDown(coordinator.dispose);
    await coordinator.prepareOnce();
    box.fail = true;
    await expectLater(coordinator.commitAtPlaybackBoundary(), throwsStateError);
    expect(settings.value.entries, isEmpty);
    box.fail = false;
    await coordinator.commitAtPlaybackBoundary();
    final reopened = IkManagedSourceSettings(VideoPreferences(box))..load();
    expect(reopened.value.entries, hasLength(2));
    expect(
      reopened.managed.records.values.every((e) => e.entryId != null),
      isTrue,
    );
  });

  test('S02 取消后迟到下载不执行也不发布', () async {
    final gate = Completer<List<int>>();
    final engine = _Engine();
    final settings = IkManagedSourceSettings(VideoPreferences(_Box()))..load();
    final coordinator = IkSourceCatalogCoordinator(
      catalog: _catalog(1),
      settings: settings,
      runtimeId: 'windows-lx3',
      importer: IkFixedSourceImporter(
        engine: engine,
        fetch: (_, _) => gate.future,
      ),
    );
    addTearDown(coordinator.dispose);
    final running = coordinator.prepareOnce();
    await Future<void>.delayed(Duration.zero);
    coordinator.cancel();
    gate.complete(_bytes);
    await running;
    expect(settings.value.entries, isEmpty);
    expect(engine.calls, 0);
  });

  test('S08 正规latest地址沿用id，同名自定义源不误合并，旧策略不变', () async {
    final prefs = VideoPreferences(_Box());
    final settings = IkManagedSourceSettings(prefs)..load();
    final known = _config(
      Uri.parse(
        'https://raw.githubusercontent.com/pdone/lx-music-source/main/source0/latest.js',
      ),
    );
    final custom = _config(Uri.parse('https://custom.example/source0.js'));
    await settings.save(
      const SourceCollection(
        highestQuality: true,
        sourceFirst: true,
      ).upsert(known).upsert(custom),
    );
    final id = settings.value.entries.first.id;
    final engine = _Engine();
    var downloads = 0;
    final coordinator = IkSourceCatalogCoordinator(
      catalog: _catalog(1),
      settings: settings,
      runtimeId: 'windows-lx3',
      importer: IkFixedSourceImporter(
        engine: engine,
        fetch: (_, _) async {
          downloads++;
          return _bytes;
        },
      ),
    );
    addTearDown(coordinator.dispose);
    await coordinator.prepareOnce();
    expect(downloads, 0);
    expect(engine.calls, 1);
    expect(settings.value.entries, hasLength(2));
    expect(settings.value.entries.first.id, id);
    expect(settings.value.highestQuality, isTrue);
    expect(settings.value.sourceFirst, isTrue);
    expect(settings.value.autoSwitch, isFalse);
  });

  test('S12 固定版本更新失败保留旧版本，回滚含旧hash且不再次自动升回', () async {
    final settings = IkManagedSourceSettings(VideoPreferences(_Box()))..load();
    var script = _bytes;
    final importer = IkFixedSourceImporter(
      engine: _Engine(),
      fetch: (_, _) async => script,
    );
    final first = IkSourceCatalogCoordinator(
      catalog: _catalog(1),
      settings: settings,
      runtimeId: 'windows-lx3',
      importer: importer,
    );
    addTearDown(first.dispose);
    await first.prepareOnce();
    final old = settings.value.entries.single;
    script = utf8.encode('$_script\nupdated');
    final updatedCatalog = IkSourceCatalog(
      catalogVersion: 2,
      commit: '1111111111111111111111111111111111111111',
      entries: [_entry('source0', bytes: script)],
    );
    final update = IkSourceCatalogCoordinator(
      catalog: updatedCatalog,
      settings: settings,
      runtimeId: 'windows-lx3',
      importer: importer,
    );
    addTearDown(update.dispose);
    await update.prepareOnce();
    expect(settings.value.entries.single.id, old.id);
    expect(
      settings.value.entries.single.config.sha256,
      isNot(old.config.sha256),
    );
    expect(
      settings.managed.records['pdone:source0']!.previous!.script,
      _script,
    );
    await update.rollback('pdone:source0');
    expect(settings.value.entries.single.config.sha256, old.config.sha256);
    expect(
      settings.managed.records['pdone:source0']!.contentSha256,
      old.config.sha256,
    );
    await update.prepareOnce();
    expect(settings.value.entries.single.config.sha256, old.config.sha256);
  });

  test('S13 未支持元数据版本不会触碰既有集合', () async {
    final box = _Box();
    final prefs = VideoPreferences(box);
    final previous = SourceSettings(prefs)..load();
    await previous.save(
      const SourceCollection().upsert(
        _config(Uri.parse('https://custom.example/a.js')),
      ),
    );
    box.data[IkManagedSourceSettings.managedKey] = jsonEncode({
      'schemaVersion': 99,
    });
    final saved = box.data[SourceSettings.key];
    final settings = IkManagedSourceSettings(prefs)..load();
    final engine = _Engine();
    final coordinator = IkSourceCatalogCoordinator(
      catalog: _catalog(),
      settings: settings,
      runtimeId: 'windows-lx3',
      importer: IkFixedSourceImporter(
        engine: engine,
        fetch: (_, _) async => _bytes,
      ),
    );
    addTearDown(coordinator.dispose);
    await coordinator.prepareOnce();
    expect(engine.calls, 0);
    expect(box.data[SourceSettings.key], saved);
    expect(settings.managedError, isNotNull);
  });

  test('S14 跨运行时记录不标绿，重新检查无需重复下载', () async {
    final settings = IkManagedSourceSettings(VideoPreferences(_Box()))..load();
    var downloads = 0;
    final engine = _Engine();
    final importer = IkFixedSourceImporter(
      engine: engine,
      fetch: (_, _) async {
        downloads++;
        return _bytes;
      },
    );
    final first = IkSourceCatalogCoordinator(
      catalog: _catalog(1),
      settings: settings,
      runtimeId: 'windows-lx3',
      importer: importer,
    );
    addTearDown(first.dispose);
    await first.prepareOnce();
    final android = IkSourceCatalogCoordinator(
      catalog: _catalog(1),
      settings: settings,
      runtimeId: 'android-lx3',
      importer: importer,
    );
    addTearDown(android.dispose);
    expect(android.readyCount, 0);
    await android.prepareOnce();
    expect(android.readyCount, 1);
    expect(engine.calls, 2);
    expect(downloads, 1);
  });

  test('S09 音质修改与管理页旧草稿保存并发仍保留新音质', () async {
    final settings = IkManagedSourceSettings(VideoPreferences(_Box()))..load();
    final coordinator = IkSourceCatalogCoordinator(
      catalog: _catalog(1),
      settings: settings,
      runtimeId: 'windows-lx3',
      importer: IkFixedSourceImporter(
        engine: _Engine(),
        fetch: (_, _) async => _bytes,
      ),
    );
    addTearDown(coordinator.dispose);
    await coordinator.prepareOnce();
    coordinator.suspendPublishing();
    final draft = settings.value;
    final quality = IkManagedMusicPreferences(
      settings.preferences,
      sources: settings,
    )..load();
    await quality.setQuality(null, highest: true);
    await settings.save(draft.copyWith(autoSwitch: false));
    expect(settings.value.autoSwitch, isFalse);
    expect(settings.value.highestQuality, isTrue);
    coordinator.resumePublishing();
  });

  testWidgets('S16 完整20项真实状态可展开且离线重试入口可达', (tester) async {
    final settings = IkManagedSourceSettings(VideoPreferences(_Box()))..load();
    final coordinator = IkSourceCatalogCoordinator(
      catalog: _catalog(20),
      settings: settings,
      runtimeId: 'windows-lx3',
      importer: IkFixedSourceImporter(
        engine: _Engine(),
        fetch: (_, _) async => throw const LxSourceException('network', '等待联网'),
      ),
    );
    addTearDown(coordinator.dispose);
    await coordinator.prepareOnce();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [ikSourceCatalogProvider.overrideWithValue(coordinator)],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: IkSourceCatalogPanel()),
          ),
        ),
      ),
    );
    expect(find.byType(ExpansionTile), findsNWidgets(20));
    expect(find.text('本机已准备 0 / 20 项'), findsOneWidget);
    expect(find.text('重试失败项'), findsOneWidget);
    expect(find.text('等待联网 / 校验'), findsNWidgets(20));
    expect(tester.takeException(), isNull);
  });

  test('S06/S07/S15 内容被改的缓存不借检查记录标绿，保存的HTTP配置不被自动关闭', () async {
    final box = _Box();
    final prefs = VideoPreferences(box)
      ..customSource = CustomSourceConfig(
        id: 'http',
        name: '已有HTTP',
        endpoint: Uri.parse('https://source.example/api'),
        enabled: true,
        platforms: const {PlatformType.qq},
      );
    final settings = IkManagedSourceSettings(prefs)..load();
    final first = IkSourceCatalogCoordinator(
      catalog: _catalog(1),
      settings: settings,
      runtimeId: 'windows-lx3',
      importer: IkFixedSourceImporter(
        engine: _Engine(),
        fetch: (_, _) async => _bytes,
      ),
    );
    addTearDown(first.dispose);
    await first.prepareOnce();
    expect(prefs.customSource!.enabled, isTrue);
    expect(prefs.lxSource, isNull);
    expect(settings.value.autoSwitch, isFalse);
    final entry = settings.value.entries.single;
    final bad = LxSourceConfig(
      name: entry.config.name,
      version: '1',
      origin: entry.config.origin,
      script: 'modified',
      sha256: entry.config.sha256,
      sources: entry.config.sources,
      enabled: true,
    );
    settings.value = settings.value.replace(entry.id, bad);
    var downloads = 0;
    final next = IkSourceCatalogCoordinator(
      catalog: _catalog(1),
      settings: settings,
      runtimeId: 'windows-lx3',
      importer: IkFixedSourceImporter(
        engine: _Engine(),
        fetch: (_, _) async {
          downloads++;
          return _bytes;
        },
      ),
    );
    addTearDown(next.dispose);
    expect(next.readyCount, 0);
    await next.prepareOnce();
    expect(downloads, 1);
    expect(settings.value.entries.single.config.script, _script);
  });

  test('S02/S03 重启恢复待发布项目、缺失的登记条目保留删除意图', () async {
    final box = _Box();
    final settings = IkManagedSourceSettings(VideoPreferences(box))..load();
    var downloads = 0;
    final importer = IkFixedSourceImporter(
      engine: _Engine(),
      fetch: (_, _) async {
        downloads++;
        return _bytes;
      },
    );
    final first = IkSourceCatalogCoordinator(
      catalog: _catalog(1),
      settings: settings,
      runtimeId: 'windows-lx3',
      isPlaybackActive: () => true,
      importer: importer,
    );
    addTearDown(first.dispose);
    await first.prepareOnce();
    expect(settings.value.entries, isEmpty);
    final reopened = IkManagedSourceSettings(VideoPreferences(box))..load();
    final next = IkSourceCatalogCoordinator(
      catalog: _catalog(1),
      settings: reopened,
      runtimeId: 'windows-lx3',
      importer: importer,
    );
    addTearDown(next.dispose);
    await next.prepareOnce();
    expect(downloads, 1);
    expect(reopened.value.entries, hasLength(1));
    await SourceSettings(VideoPreferences(box)).save(const SourceCollection());
    final removed = IkManagedSourceSettings(VideoPreferences(box))..load();
    final last = IkSourceCatalogCoordinator(
      catalog: _catalog(1),
      settings: removed,
      runtimeId: 'windows-lx3',
      importer: importer,
    );
    addTearDown(last.dispose);
    await last.prepareOnce();
    expect(downloads, 1);
    expect(removed.value.entries, isEmpty);
    expect(last.items.single.stage, IkSourceStage.removed);
  });

  test('S07 用户在首次准备时明确关闭自动切换，默认策略不覆盖选择', () async {
    final gate = Completer<List<int>>();
    final settings = IkManagedSourceSettings(VideoPreferences(_Box()))..load();
    final coordinator = IkSourceCatalogCoordinator(
      catalog: _catalog(1),
      settings: settings,
      runtimeId: 'windows-lx3',
      importer: IkFixedSourceImporter(
        engine: _Engine(),
        fetch: (_, _) => gate.future,
      ),
    );
    addTearDown(coordinator.dispose);
    final running = coordinator.prepareOnce();
    await settings.save(settings.value.copyWith(autoSwitch: false));
    gate.complete(_bytes);
    await running;
    expect(settings.value.entries, hasLength(1));
    expect(settings.value.autoSwitch, isFalse);
  });

  test('S04 429不继续备用请求，平台不匹配不发布，失败可读且检查持久化', () async {
    final settings = IkManagedSourceSettings(VideoPreferences(_Box()))..load();
    var requests = 0;
    final coordinator = IkSourceCatalogCoordinator(
      catalog: _catalog(),
      settings: settings,
      runtimeId: 'windows-lx3',
      importer: IkFixedSourceImporter(
        engine: _Engine(),
        fetch: (_, _) async {
          requests++;
          throw const LxSourceException('rateLimited', '来源请求受限');
        },
      ),
    );
    addTearDown(coordinator.dispose);
    await coordinator.prepareOnce();
    expect(requests, 2);
    expect(
      coordinator.items.every((e) => e.failureCode == 'rateLimited'),
      isTrue,
    );
    expect(settings.value.entries, isEmpty);
    final reopened = IkSourceCatalogCoordinator(
      catalog: _catalog(),
      settings: settings,
      runtimeId: 'windows-lx3',
      importer: IkFixedSourceImporter(
        engine: _Engine(),
        fetch: (_, _) async => _bytes,
      ),
    );
    addTearDown(reopened.dispose);
    expect(reopened.items.every((e) => e.failureCode == 'rateLimited'), isTrue);
  });
}

LxSourceConfig _config(Uri origin) => LxSourceConfig(
  name: 'source0',
  version: '1',
  origin: origin,
  script: _script,
  sha256: sha256.convert(_bytes).toString(),
  sources: const {
    'tx': ['128k'],
  },
  enabled: true,
);

class _Engine implements LxSourceEngine {
  int calls = 0;
  @override
  Future<Map<String, List<String>>> inspect(
    String script, {
    CancelToken? cancelToken,
  }) async {
    calls++;
    return {
      'tx': ['128k', 'flac'],
    };
  }

  @override
  Future<String> resolve(
    LxSourceConfig config,
    CustomSourceRequest request, {
    CancelToken? cancelToken,
  }) => throw UnimplementedError();
}

class _Box extends Fake implements Box {
  final data = <dynamic, dynamic>{};
  bool fail = false;
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => data[key] ?? defaultValue;
  @override
  bool containsKey(dynamic key) => data.containsKey(key);
  @override
  Future<void> put(dynamic key, dynamic value) async {
    if (fail) throw StateError('保存失败');
    data[key] = value;
  }

  @override
  Future<void> putAll(Map<dynamic, dynamic> entries) async {
    if (fail) throw StateError('保存失败');
    data.addAll(entries);
  }
}

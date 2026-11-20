// 正式设备任务门：显式启用后走完整新协调器，不使用真实用户配置。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/video_app/built_in/catalog.dart';
import 'package:mconnect/video_app/built_in/catalog_coordinator.dart';
import 'package:mconnect/video_app/built_in/catalog_sandbox.dart';
import 'package:mconnect/video_app/built_in/fixed_importer.dart';
import 'package:mconnect/video_app/built_in/managed_settings.dart';
import 'package:mconnect/video_app/lx_source/lx_runtime_v3.dart';
import 'package:mconnect/video_app/video_preferences.dart';
import 'package:mconnect/video_app/windows/managed_windows_lx_sandbox.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final enabled =
      Platform.isWindows &&
      Platform.environment['IK_CATALOG_DEVICE_GATE'] == '1';
  test(
    'S16 Windows新目录完整获取、哈希、受限初始化与安全发布',
    () async {
      final previousHttp = HttpOverrides.current;
      HttpOverrides.global = null; // 本门明确使用真实公网，不能拿测试框架HTTP400冒充上游失败。
      addTearDown(() => HttpOverrides.global = previousHttp);
      final sandbox = ManagedWindowsLxSandbox(
        hostPath: Platform.environment['YUEYIN_LX_HOST'],
      );
      addTearDown(sandbox.shutdown);
      final engine = LxSourceRuntimeV3(
        sandbox: IkCatalogSandbox(sandbox),
        environment: 'desktop',
        vendors:
            '${File('assets/lx-runtime/forge-1.3.1.min.js').readAsStringSync()}\n${File('assets/lx-runtime/pako-2.1.0.min.js').readAsStringSync()}',
      );
      final catalog = IkSourceCatalog.fromJson(
        jsonDecode(
          File('assets/source-catalog/pdone-v1.json').readAsStringSync(),
        ) as Map<String, dynamic>,
      );
      final settings = IkManagedSourceSettings(VideoPreferences(_MemoryBox()))
        ..load();
      final coordinator = IkSourceCatalogCoordinator(
        catalog: catalog,
        settings: settings,
        runtimeId: 'windows-lx3',
        importer: IkFixedSourceImporter(engine: engine),
      );
      addTearDown(coordinator.dispose);
      final seen = <String, IkSourceStage>{};
      coordinator.addListener(() {
        for (final item in coordinator.items) {
          if (seen[item.entry.sourceKey] == item.stage) continue;
          seen[item.entry.sourceKey] = item.stage;
          // 只输出状态，不输出脚本、远端响应或凭据。
          // ignore: avoid_print
          print(
            'IK_CATALOG ${item.entry.sourceKey} ${item.stage.name} ${item.failureCode ?? ''}',
          );
        }
      });
      await coordinator.prepareOnce();
      expect(coordinator.items, hasLength(20));
      expect(
        coordinator.items.where(
          (e) =>
              e.stage == IkSourceStage.downloading ||
              e.stage == IkSourceStage.checking,
        ),
        isEmpty,
      );
      expect(settings.value.entries.length, coordinator.readyCount);
      expect(
        settings.value.entries.every(
          (e) => e.config.enabled && !e.config.allowForDownloads,
        ),
        isTrue,
      );
      final report = StringBuffer('# IK Music U08 Windows 自动目录设备记录\n\n')
        ..writeln(
          '运行时间：${DateTime.now().toIso8601String()}。固定提交：`${catalog.commit}`。',
        )
        ..writeln(
          '这是新自动装配链路验证；既有040矩阵不重跑。完整目录20项，${coordinator.readyCount}项本机准备并发布，其余逐项说明。',
        )
        ..writeln(
          '使用内存配置，未读写用户音源、账号或安装数据；脚本文本只在内存。初始化不等于实际歌曲播放。Android未连接设备，本门不代表Android通过。\n',
        )
        ..writeln('| 目录 | 最终状态 | 原因 |')
        ..writeln('| --- | --- | --- |');
      for (final item in coordinator.items) {
        report.writeln(
          '| ${item.entry.sourceKey} | ${item.stage.name} | ${(item.message ?? '').replaceAll('|', '／').replaceAll('\n', ' ')} |',
        );
      }
      File('docs/IK-Music-U08Windows设备记录.md')
          .writeAsStringSync(report.toString());
      expect(
        coordinator.readyCount,
        greaterThan(0),
        reason: '必须至少有一项从真实网络走完新自动准备链路',
      );
    },
    skip: enabled
        ? false
        : '需显式 IK_CATALOG_DEVICE_GATE=1 和 Windows LX 宿主；未运行不代表设备通过',
    timeout: const Timeout(Duration(minutes: 12)),
  );
}

class _MemoryBox extends Fake implements Box {
  final data = <dynamic, dynamic>{};
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => data[key] ?? defaultValue;
  @override
  bool containsKey(dynamic key) => data.containsKey(key);
  @override
  Future<void> put(dynamic key, dynamic value) async => data[key] = value;
  @override
  Future<void> putAll(Map<dynamic, dynamic> entries) async =>
      data.addAll(entries);
}

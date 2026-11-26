import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as hashes;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../lx_source/lx_source.dart';
import '../multi_source/source_checks.dart';
import '../multi_source/source_collection.dart';
import 'managed_settings.dart';

final ikLocalLxSourceBridgeProvider = Provider<IkLocalLxSourceBridge?>((ref) => null);

class IkLocalLxSourceResult {
  const IkLocalLxSourceResult({
    required this.name,
    required this.version,
    required this.sha256,
    required this.selected,
    required this.state,
    required this.status,
  });
  final String name, version, sha256, state, status;
  final bool selected;
  bool get retryable => state == 'failed' || state == 'deferred';
}

/// 只消费用户随预览交付的私有目录，不扫描LX或改写其配置。
class IkLocalLxSourceBridge extends ChangeNotifier {
  IkLocalLxSourceBridge({
    required this.settings,
    required this.engine,
    required this.directory,
    required this.runtimeId,
    bool Function()? isSourceWorkBusy,
  }) : isSourceWorkBusy = isSourceWorkBusy ?? (() => false);

  static const receiptKey = 'ik.sources.localLxReceipts.v1';
  static const _maxScriptBytes = 1024 * 1024;
  static final _hash = RegExp(r'^[0-9a-f]{64}$');
  final IkManagedSourceSettings settings;
  final LxSourceEngine engine;
  final Directory directory;
  final String runtimeId;
  final bool Function() isSourceWorkBusy;
  final _results = <String, IkLocalLxSourceResult>{};
  Map<String, Map<String, dynamic>> _receipts = {};
  CancelToken? _activeToken;
  Timer? _retryTimer;
  bool _started = false, _disposed = false;
  bool busy = false;
  String? message;
  List<IkLocalLxSourceResult> get results => List.unmodifiable(_results.values);
  bool get retryQueued => _retryTimer != null;

  Future<void> importOnce() async {
    if (_started || _disposed) return;
    _started = true;
    await _run(retry: false);
  }

  Future<void> retryFailures() async {
    if (_disposed || busy) return;
    _retryTimer?.cancel();
    _retryTimer = null;
    if (settings.writesBlocked) {
      message = '当前音源存储不可写，迁移未启动';
      _notify();
      return;
    }
    if (settings.editing || isSourceWorkBusy()) {
      message = '已安排重试，保存音源草稿并离开音源设置后自动导入';
      final deadline = DateTime.now().add(const Duration(minutes: 2));
      _retryTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
        if (_disposed || settings.writesBlocked || DateTime.now().isAfter(deadline)) {
          timer.cancel();
          _retryTimer = null;
          if (!_disposed) {
            message = '重试等待已结束，空闲后可再次重试';
            _notify();
          }
          return;
        }
        if (settings.editing || isSourceWorkBusy() || busy) return;
        timer.cancel();
        _retryTimer = null;
        unawaited(_run(retry: true));
      });
      _notify();
      return;
    }
    await _run(retry: true);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _set(_LocalLxSource source, String state, String status) {
    _results[source.sha256] = IkLocalLxSourceResult(
      name: source.name,
      version: source.version,
      sha256: source.sha256,
      selected: source.selected,
      state: state,
      status: status,
    );
    _notify();
  }

  bool get _paused => settings.editing || settings.writesBlocked || isSourceWorkBusy();

  void _checkAvailable() {
    if (_disposed) throw const LxSourceException('cancelled', '迁移已取消');
    if (_paused) throw const LxSourceException('busy', '音源正在编辑或更新，迁移已暂缓');
  }

  Future<void> _run({required bool retry}) async {
    if (_disposed || busy) return;
    busy = true;
    message = '正在读取本机LX音源…';
    _notify();
    try {
      final manifest = await _loadManifest();
      if (_disposed) return;
      _results.clear();
      if (manifest == null) {
        message = '没有本机LX音源迁移文件';
        return;
      }
      for (final source in manifest.sources) {
        _set(source, 'waiting', '等待准备');
      }
      _loadReceipts();
      final baseline = settings.value;
      final ordered = [
        ...manifest.sources.where((source) => source.selected),
        ...manifest.sources.where((source) => !source.selected),
      ];
      for (final source in ordered) {
        if (_disposed) break;
        final receipt = _receipts[source.sha256];
        if (receipt?['state'] == 'complete') {
          final completed = receipt!;
          final existing = _existing(completed['scriptSha256'] as String) ??
              settings.value.entries.where((entry) => entry.id == completed['entryId']).firstOrNull;
          _set(source, existing == null ? 'removed' : 'existing',
              existing == null ? '已迁移后移除，不会自动恢复'
                  : existing.config.enabled ? '已在列表中（${existing.config.name}），保留现有设置'
                      : '已在列表中（${existing.config.name}），当前已停用');
          continue;
        }
        if (receipt?['state'] == 'failed' && !retry) {
          _set(source, 'failed', _failure(receipt?['errorCode'] as String?));
          continue;
        }
        if (_paused) {
          _set(source, 'deferred', '音源正在编辑或更新，稍后可重试');
          continue;
        }
        try {
          _set(source, 'initializing', '正在准备本地音源…');
          await _prepare(source, manifest, baseline);
        } catch (error) {
          if (_disposed) break;
          final code = error is LxSourceException ? error.code : 'storage';
          if (code == 'busy' || code == 'cancelled') {
            _set(source, 'deferred', '迁移已暂缓，稍后可重试');
          } else {
            final recorded = await _recordFailure(source, code);
            _set(source, 'failed', '${_failure(code)}${recorded ? '' : '；状态暂未保存'}');
          }
        }
      }
      if (!_disposed) {
        final imported = results.where((r) => r.state == 'imported').length;
        final existing = results.where((r) => r.state == 'existing').length;
        final failed = results.where((r) => r.state == 'failed').length;
        final deferred = results.where((r) => r.state == 'deferred').length;
        final removed = results.where((r) => r.state == 'removed').length;
        message = '本机LX音源 · $imported 项已导入 · $existing 项已有'
            '${failed > 0 ? ' · $failed 项失败，可重试' : ''}'
            '${deferred > 0 ? ' · $deferred 项暂缓' : ''}'
            '${removed > 0 ? ' · $removed 项已移除' : ''}';
      }
    } catch (error) {
      final code = error is LxSourceException ? error.code : 'metadata';
      message = _failure(code);
      for (final entry in _results.entries.toList()) {
        final value = entry.value;
        _results[entry.key] = IkLocalLxSourceResult(
          name: value.name, version: value.version, sha256: value.sha256,
          selected: value.selected, state: 'failed', status: message!,
        );
      }
    } finally {
      busy = false;
      _activeToken = null;
      _notify();
    }
  }

  Future<_LocalLxManifest?> _loadManifest() async {
    final rootType = await FileSystemEntity.type(directory.path, followLinks: false);
    if (rootType == FileSystemEntityType.notFound) return null;
    if (rootType != FileSystemEntityType.directory) throw _invalidPath;
    final root = await directory.resolveSymbolicLinks();
    final manifestFile = await _safeFile(root, 'manifest.json');
    final bytes = await _readBytes(manifestFile, 128 * 1024);
    final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    if (decoded is! Map || decoded['schemaVersion'] != 1 ||
        decoded['preferSelected'] is! bool || decoded['sourceFirstWhenSelected'] is! bool ||
        decoded['sources'] is! List) throw _invalidManifest;
    final rows = decoded['sources'] as List;
    if (rows.isEmpty || rows.length > 64) throw _invalidManifest;
    final sources = <_LocalLxSource>[];
    final seen = <String>{};
    var total = 0, selected = 0;
    for (final row in rows) {
      if (row is! Map) throw _invalidManifest;
      final name = row['name'], version = row['version'], hash = row['sha256'];
      final length = row['byteLength'], relative = row['relativeFile'];
      if (name is! String || name.trim().isEmpty || name.length > 160 ||
          version is! String || version.length > 160 || hash is! String ||
          !_hash.hasMatch(hash) || !seen.add(hash) || row['selected'] is! bool ||
          length is! int || length <= 0 || length > _maxScriptBytes ||
          relative != 'scripts/$hash.js') throw _invalidManifest;
      final update = row['updateUrl'];
      Uri? updateUrl;
      if (update != null) {
        updateUrl = update is String ? Uri.tryParse(update) : null;
        if (updateUrl == null || updateUrl.scheme != 'https' || updateUrl.host.isEmpty ||
            updateUrl.userInfo.isNotEmpty || updateUrl.hasFragment ||
            !updateUrl.path.toLowerCase().endsWith('.js')) throw _invalidManifest;
      }
      total += length;
      if (row['selected'] == true) selected++;
      sources.add(_LocalLxSource(name, version, hash, relative as String, length,
          row['selected'] == true, updateUrl));
    }
    if (total > 8 * _maxScriptBytes || selected > 1) throw _invalidManifest;
    return _LocalLxManifest(root, sources, decoded['preferSelected'] == true,
        decoded['sourceFirstWhenSelected'] == true);
  }

  Future<File> _safeFile(String root, String relative) async {
    final path = p.joinAll([root, ...relative.split('/')]);
    if (!p.isWithin(root, path)) throw _invalidPath;
    if (relative.startsWith('scripts/') &&
        await FileSystemEntity.type(p.join(root, 'scripts'), followLinks: false) !=
            FileSystemEntityType.directory) throw _invalidPath;
    if (await FileSystemEntity.type(path, followLinks: false) != FileSystemEntityType.file) {
      throw _invalidPath;
    }
    final resolved = await File(path).resolveSymbolicLinks();
    if (!p.isWithin(root, resolved) || !p.equals(path, resolved)) throw _invalidPath;
    return File(resolved);
  }

  Future<List<int>> _readBytes(File file, int limit) async {
    if (await file.length() > limit) throw const LxSourceException('size', '音源文件过大');
    final bytes = <int>[];
    await for (final chunk in file.openRead()) {
      if (_disposed) throw const LxSourceException('cancelled', '迁移已取消');
      if (bytes.length + chunk.length > limit) throw const LxSourceException('size', '音源文件过大');
      bytes.addAll(chunk);
    }
    return bytes;
  }

  void _loadReceipts() {
    final raw = settings.preferences.box.get(receiptKey);
    if (raw == null) { _receipts = {}; return; }
    try {
      final decoded = jsonDecode(raw as String) as Map;
      if (decoded['schemaVersion'] != 1 || decoded['sources'] is! Map) throw const FormatException();
      final values = <String, Map<String, dynamic>>{};
      for (final row in (decoded['sources'] as Map).entries) {
        if (row.key is! String || !_hash.hasMatch(row.key as String) || row.value is! Map) {
          throw const FormatException();
        }
        final value = Map<String, dynamic>.from(row.value as Map);
        if (!['complete', 'failed'].contains(value['state']) ||
            (value['state'] == 'complete' &&
                (value['scriptSha256'] is! String || !_hash.hasMatch(value['scriptSha256'] as String))) ||
            (value['errorCode'] != null && value['errorCode'] is! String)) throw const FormatException();
        values[row.key as String] = value;
      }
      _receipts = values;
    } catch (_) {
      throw const LxSourceException('receipt', '迁移记录无法读取');
    }
  }

  SourceEntry? _existing(String scriptHash) => settings.value.entries.where((entry) =>
      entry.config.sha256 == scriptHash &&
      hashes.sha256.convert(utf8.encode(entry.config.script)).toString() == scriptHash).firstOrNull;

  Future<void> _prepare(_LocalLxSource source, _LocalLxManifest manifest,
      SourceCollection baseline) async {
    _checkAvailable();
    final file = await _safeFile(manifest.root, source.relativeFile);
    final bytes = await _readBytes(file, _maxScriptBytes);
    if (bytes.length != source.byteLength || hashes.sha256.convert(bytes).toString() != source.sha256) {
      throw const LxSourceException('integrity', '本地音源完整性不匹配');
    }
    String script;
    try {
      script = utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      throw const LxSourceException('invalidEncoding', '音源不是UTF-8');
    }
    String? field(String key) =>
        RegExp('^\\s*(?:\\*|//)?\\s*@$key\\s+([^\\r\\n]+)', multiLine: true)
            .firstMatch(script)?.group(1)?.replaceFirst(RegExp(r'\s*\*/\s*$'), '').trim();
    if (field('name') != source.name || (field('version') ?? '') != source.version ||
        script.trimLeft().startsWith('<')) throw _invalidManifest;
    final scriptHash = hashes.sha256.convert(utf8.encode(script)).toString();
    final existing = _existing(scriptHash);
    final check = existing == null ? null : SourceCheckStore(settings.preferences.box).load()[existing.id];
    final initialized = existing != null && check?.outcome == 'initialized' &&
        check!.applies(existing, runtimeId);
    _checkAvailable();
    final sources = initialized ? existing!.config.sources : await _inspect(script);
    if (!sources.entries.any((entry) =>
        ['tx', 'wy', 'kg'].contains(entry.key) && entry.value.isNotEmpty)) {
      throw const LxSourceException('platform', '音源不支持当前平台');
    }
    await settings.serialize(() async {
      _checkAvailable();
      final current = settings.value;
      final prior = _existing(scriptHash);
      final id = prior?.id ?? 'local-lx:$scriptHash';
      if (prior == null && current.entries.any((entry) => entry.id == id)) {
        throw const LxSourceException('integrity', '本地音源身份冲突');
      }
      final config = prior?.config ?? LxSourceConfig(
        name: source.name, version: source.version, origin: file.uri, script: script,
        sha256: scriptHash, sources: sources, enabled: true, allowForDownloads: false,
      );
      var next = prior == null
          ? current.copyWith(entries: [...current.entries, SourceEntry(id, config)])
          : current;
      final applyPolicy = source.selected && config.enabled &&
          identical(current, baseline) && !settings.userPolicyTouched &&
          settings.preferences.customSource?.enabled != true;
      if (applyPolicy) {
        next = next.copyWith(
          preferredId: manifest.preferSelected ? id : next.preferredId,
          sourceFirst: manifest.sourceFirstWhenSelected ? true : next.sourceFirst,
        );
      }
      if (!identical(next, current)) {
        await settings.persist(next, settings.managed, notifyPlayback: true, manual: false);
      }
      final checks = SourceCheckStore(settings.preferences.box).load();
      checks[id] = SourceCheckRecord(
        entryId: id, scriptSha256: scriptHash, runtimeId: runtimeId,
        outcome: 'initialized', checkedAt: DateTime.now(),
      );
      final receipts = {..._receipts, source.sha256: <String, dynamic>{
        'state': 'complete', 'scriptSha256': scriptHash, 'runtimeId': runtimeId,
        'entryId': id, 'policyHandled': true,
        if (source.updateUrl != null) 'updateUrl': source.updateUrl.toString(),
      }};
      await settings.preferences.box.putAll({
        receiptKey: jsonEncode({'schemaVersion': 1, 'sources': receipts}),
        SourceCheckStore.key: jsonEncode(checks.map((id, record) => MapEntry(id, record.toJson()))),
      });
      _receipts = receipts;
      _set(source, prior == null ? 'imported' : 'existing',
          prior != null
              ? '已在列表中（${prior.config.name}）${applyPolicy && manifest.preferSelected ? '，已设为首选' : '，保留原设置'}'
              : applyPolicy && manifest.preferSelected ? '已导入并设为首选'
                  : '已导入，原播放策略保留');
    });
  }

  Future<Map<String, List<String>>> _inspect(String script) async {
    final token = CancelToken();
    _activeToken = token;
    var timedOut = false;
    final timer = Timer(const Duration(seconds: 5), () {
      timedOut = true;
      token.cancel();
    });
    try {
      return await Future.any([
        engine.inspect(script, cancelToken: token),
        token.whenCancel.then<Map<String, List<String>>>(
            (_) => throw const LxSourceException('cancelled', '初始化已取消')),
      ]);
    } catch (error) {
      if (timedOut) throw const LxSourceException('timeout', '初始化超过5秒');
      if (error is LxSourceException) rethrow;
      throw const LxSourceException('script', '初始化失败');
    } finally {
      timer.cancel();
      token.cancel();
      if (identical(_activeToken, token)) _activeToken = null;
    }
  }

  Future<bool> _recordFailure(_LocalLxSource source, String code) async {
    try {
      return await settings.serialize(() async {
        if (_disposed || _paused) return false;
        final receipts = {..._receipts, source.sha256: <String, dynamic>{
          'state': 'failed', 'errorCode': code, 'runtimeId': runtimeId,
        }};
        await settings.preferences.box.put(receiptKey,
            jsonEncode({'schemaVersion': 1, 'sources': receipts}));
        _receipts = receipts;
        return true;
      });
    } catch (_) { return false; }
  }

  static String _failure(String? code) => switch (code) {
    'timeout' => '初始化超过5秒，未启用；可重试',
    'platform' || 'unsupported' => '当前运行时不支持此音源，未启用',
    'integrity' => '本地音源长度或哈希不匹配，未启用',
    'path' => '音源文件缺失或路径不安全，未启用',
    'size' => '音源大小超过限制，未启用',
    'invalidEncoding' => '音源不是有效UTF-8，未启用',
    'metadata' => '迁移清单或音源头部无效，未启用',
    'receipt' => '迁移记录无法读取，已停止导入以保留现有设置',
    'storage' => '迁移保存失败，已有音源保留；可重试',
    'network' || 'download' || 'rateLimited' => '初始化网络请求失败，未启用；可重试',
    _ => '音源初始化失败，未启用；请检查兼容性或激活要求',
  };
  static const _invalidManifest = LxSourceException('metadata', '迁移清单无效');
  static const _invalidPath = LxSourceException('path', '迁移文件路径无效');

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    _activeToken?.cancel();
    super.dispose();
  }
}

class _LocalLxManifest {
  const _LocalLxManifest(this.root, this.sources, this.preferSelected, this.sourceFirstWhenSelected);
  final String root;
  final List<_LocalLxSource> sources;
  final bool preferSelected, sourceFirstWhenSelected;
}

class _LocalLxSource {
  const _LocalLxSource(this.name, this.version, this.sha256, this.relativeFile,
      this.byteLength, this.selected, this.updateUrl);
  final String name, version, sha256, relativeFile;
  final int byteLength;
  final bool selected;
  final Uri? updateUrl;
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as hashes;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../l10n/ik_local_lx_strings.dart';
import '../lx_source/lx_source.dart';
import '../multi_source/source_checks.dart';
import '../multi_source/source_collection.dart';
import 'managed_settings.dart';

final ikLocalLxSourceBridgeProvider = Provider<IkLocalLxSourceBridge?>(
  (ref) => null,
);

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
      message = IkLocalLxStrings.storageBlocked;
      _notify();
      return;
    }
    if (settings.editing || isSourceWorkBusy()) {
      message = IkLocalLxStrings.retryQueued;
      final deadline = DateTime.now().add(const Duration(minutes: 2));
      _retryTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
        if (_disposed ||
            settings.writesBlocked ||
            DateTime.now().isAfter(deadline)) {
          timer.cancel();
          _retryTimer = null;
          if (!_disposed) {
            message = IkLocalLxStrings.retryExpired;
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

  bool get _paused =>
      settings.editing || settings.writesBlocked || isSourceWorkBusy();

  void _checkAvailable() {
    if (_disposed) {
      throw const LxSourceException('cancelled', IkLocalLxStrings.cancelled);
    }
    if (_paused) {
      throw const LxSourceException('busy', IkLocalLxStrings.busy);
    }
  }

  Future<void> _run({required bool retry}) async {
    if (_disposed || busy) return;
    busy = true;
    message = IkLocalLxStrings.opening;
    _notify();
    try {
      final manifest = await _loadManifest();
      if (_disposed) return;
      _results.clear();
      if (manifest == null) {
        message = IkLocalLxStrings.noManifest;
        return;
      }
      for (final source in manifest.sources) {
        _set(source, 'waiting', IkLocalLxStrings.waiting);
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
          final existing =
              _existing(completed['scriptSha256'] as String) ??
              settings.value.entries
                  .where((entry) => entry.id == completed['entryId'])
                  .firstOrNull;
          _set(
            source,
            existing == null ? 'removed' : 'existing',
            existing == null
                ? IkLocalLxStrings.removed
                : IkLocalLxStrings.existing(
                    existing.config.name,
                    existing.config.enabled,
                  ),
          );
          continue;
        }
        if (receipt?['state'] == 'failed' && !retry) {
          _set(source, 'failed', _failure(receipt?['errorCode'] as String?));
          continue;
        }
        if (_paused) {
          _set(source, 'deferred', IkLocalLxStrings.waitForIdle);
          continue;
        }
        try {
          _set(source, 'initializing', IkLocalLxStrings.preparing);
          await _prepare(source, manifest, baseline);
        } catch (error) {
          if (_disposed) break;
          final code = error is LxSourceException ? error.code : 'storage';
          if (code == 'busy' || code == 'cancelled') {
            _set(source, 'deferred', IkLocalLxStrings.deferred);
          } else {
            final recorded = await _recordFailure(source, code);
            _set(
              source,
              'failed',
              IkLocalLxStrings.failed(_failure(code), recorded),
            );
          }
        }
      }
      if (!_disposed) {
        final imported = results.where((r) => r.state == 'imported').length;
        final existing = results.where((r) => r.state == 'existing').length;
        final failed = results.where((r) => r.state == 'failed').length;
        final deferred = results.where((r) => r.state == 'deferred').length;
        final removed = results.where((r) => r.state == 'removed').length;
        message = IkLocalLxStrings.summary(
          imported,
          existing,
          failed,
          deferred,
          removed,
        );
      }
    } catch (error) {
      final code = error is LxSourceException ? error.code : 'metadata';
      message = _failure(code);
      for (final entry in _results.entries.toList()) {
        final value = entry.value;
        _results[entry.key] = IkLocalLxSourceResult(
          name: value.name,
          version: value.version,
          sha256: value.sha256,
          selected: value.selected,
          state: 'failed',
          status: message!,
        );
      }
    } finally {
      busy = false;
      _activeToken = null;
      _notify();
    }
  }

  Future<_LocalLxManifest?> _loadManifest() async {
    final rootType = await FileSystemEntity.type(
      directory.path,
      followLinks: false,
    );
    if (rootType == FileSystemEntityType.notFound) return null;
    if (rootType != FileSystemEntityType.directory) throw _invalidPath;
    final root = await directory.resolveSymbolicLinks();
    final manifestFile = await _safeFile(root, 'manifest.json');
    final bytes = await _readBytes(manifestFile, 128 * 1024);
    final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    if (decoded is! Map ||
        decoded['schemaVersion'] != 1 ||
        decoded['preferSelected'] is! bool ||
        decoded['sourceFirstWhenSelected'] is! bool ||
        decoded['sources'] is! List) {
      throw _invalidManifest;
    }
    final rows = decoded['sources'] as List;
    if (rows.isEmpty || rows.length > 64) throw _invalidManifest;
    final sources = <_LocalLxSource>[];
    final seen = <String>{};
    var total = 0, selected = 0;
    for (final row in rows) {
      if (row is! Map) {
        throw _invalidManifest;
      }
      final name = row['name'], version = row['version'], hash = row['sha256'];
      final length = row['byteLength'], relative = row['relativeFile'];
      if (name is! String ||
          name.trim().isEmpty ||
          name.length > 160 ||
          version is! String ||
          version.length > 160 ||
          hash is! String ||
          !_hash.hasMatch(hash) ||
          !seen.add(hash) ||
          row['selected'] is! bool ||
          length is! int ||
          length <= 0 ||
          length > _maxScriptBytes ||
          relative != 'scripts/$hash.js') {
        throw _invalidManifest;
      }
      final update = row['updateUrl'];
      Uri? updateUrl;
      if (update != null) {
        updateUrl = update is String ? Uri.tryParse(update) : null;
        if (updateUrl == null ||
            updateUrl.scheme != 'https' ||
            updateUrl.host.isEmpty ||
            updateUrl.userInfo.isNotEmpty ||
            updateUrl.hasFragment ||
            !updateUrl.path.toLowerCase().endsWith('.js')) {
          throw _invalidManifest;
        }
      }
      total += length;
      if (row['selected'] == true) {
        selected++;
      }
      sources.add(
        _LocalLxSource(
          name,
          version,
          hash,
          relative as String,
          length,
          row['selected'] == true,
          updateUrl,
        ),
      );
    }
    if (total > 8 * _maxScriptBytes || selected > 1) {
      throw _invalidManifest;
    }
    return _LocalLxManifest(
      root,
      sources,
      decoded['preferSelected'] == true,
      decoded['sourceFirstWhenSelected'] == true,
    );
  }

  Future<File> _safeFile(String root, String relative) async {
    final path = p.joinAll([root, ...relative.split('/')]);
    if (!p.isWithin(root, path)) {
      throw _invalidPath;
    }
    if (relative.startsWith('scripts/') &&
        await FileSystemEntity.type(
              p.join(root, 'scripts'),
              followLinks: false,
            ) !=
            FileSystemEntityType.directory) {
      throw _invalidPath;
    }
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw _invalidPath;
    }
    final resolved = await File(path).resolveSymbolicLinks();
    if (!p.isWithin(root, resolved) || !p.equals(path, resolved)) {
      throw _invalidPath;
    }
    return File(resolved);
  }

  Future<List<int>> _readBytes(File file, int limit) async {
    if (await file.length() > limit) {
      throw const LxSourceException('size', IkLocalLxStrings.oversizedFile);
    }
    final bytes = <int>[];
    await for (final chunk in file.openRead()) {
      if (_disposed) {
        throw const LxSourceException('cancelled', IkLocalLxStrings.cancelled);
      }
      if (bytes.length + chunk.length > limit) {
        throw const LxSourceException('size', IkLocalLxStrings.oversizedFile);
      }
      bytes.addAll(chunk);
    }
    return bytes;
  }

  void _loadReceipts() {
    final raw = settings.preferences.box.get(receiptKey);
    if (raw == null) {
      _receipts = {};
      return;
    }
    try {
      final decoded = jsonDecode(raw as String) as Map;
      if (decoded['schemaVersion'] != 1 || decoded['sources'] is! Map) {
        throw const FormatException();
      }
      final values = <String, Map<String, dynamic>>{};
      for (final row in (decoded['sources'] as Map).entries) {
        if (row.key is! String ||
            !_hash.hasMatch(row.key as String) ||
            row.value is! Map) {
          throw const FormatException();
        }
        final value = Map<String, dynamic>.from(row.value as Map);
        if (!['complete', 'failed'].contains(value['state']) ||
            (value['state'] == 'complete' &&
                (value['scriptSha256'] is! String ||
                    !_hash.hasMatch(value['scriptSha256'] as String))) ||
            (value['errorCode'] != null && value['errorCode'] is! String)) {
          throw const FormatException();
        }
        values[row.key as String] = value;
      }
      _receipts = values;
    } catch (_) {
      throw const LxSourceException(
        'receipt',
        IkLocalLxStrings.unreadableReceipt,
      );
    }
  }

  SourceEntry? _existing(String scriptHash) => settings.value.entries
      .where(
        (entry) =>
            entry.config.sha256 == scriptHash &&
            hashes.sha256
                    .convert(utf8.encode(entry.config.script))
                    .toString() ==
                scriptHash,
      )
      .firstOrNull;

  Future<void> _prepare(
    _LocalLxSource source,
    _LocalLxManifest manifest,
    SourceCollection baseline,
  ) async {
    _checkAvailable();
    final file = await _safeFile(manifest.root, source.relativeFile);
    final bytes = await _readBytes(file, _maxScriptBytes);
    if (bytes.length != source.byteLength ||
        hashes.sha256.convert(bytes).toString() != source.sha256) {
      throw const LxSourceException(
        'integrity',
        IkLocalLxStrings.integrityMismatch,
      );
    }
    String script;
    try {
      script = utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      throw const LxSourceException(
        'invalidEncoding',
        IkLocalLxStrings.invalidEncoding,
      );
    }
    String? field(String key) =>
        RegExp('^\\s*(?:\\*|//)?\\s*@$key\\s+([^\\r\\n]+)', multiLine: true)
            .firstMatch(script)
            ?.group(1)
            ?.replaceFirst(RegExp(r'\s*\*/\s*$'), '')
            .trim();
    if (field('name') != source.name ||
        (field('version') ?? '') != source.version ||
        script.trimLeft().startsWith('<')) {
      throw _invalidManifest;
    }
    final scriptHash = hashes.sha256.convert(utf8.encode(script)).toString();
    final existing = _existing(scriptHash);
    final check = existing == null
        ? null
        : SourceCheckStore(settings.preferences.box).load()[existing.id];
    final initialized =
        existing != null &&
        check?.outcome == 'initialized' &&
        check != null &&
        check.applies(existing, runtimeId);
    _checkAvailable();
    final sources = initialized
        ? existing.config.sources
        : await _inspect(script);
    if (!sources.entries.any(
      (entry) =>
          ['tx', 'wy', 'kg'].contains(entry.key) && entry.value.isNotEmpty,
    )) {
      throw const LxSourceException(
        'platform',
        IkLocalLxStrings.unsupportedPlatform,
      );
    }
    await settings.serialize(() async {
      _checkAvailable();
      final current = settings.value;
      final prior = _existing(scriptHash);
      final id = prior?.id ?? 'local-lx:$scriptHash';
      if (prior == null && current.entries.any((entry) => entry.id == id)) {
        throw const LxSourceException(
          'integrity',
          IkLocalLxStrings.conflictingSource,
        );
      }
      final config =
          prior?.config ??
          LxSourceConfig(
            name: source.name,
            version: source.version,
            origin: file.uri,
            script: script,
            sha256: scriptHash,
            sources: sources,
            enabled: true,
            allowForDownloads: false,
          );
      var next = prior == null
          ? current.copyWith(
              entries: [...current.entries, SourceEntry(id, config)],
            )
          : current;
      final applyPolicy =
          source.selected &&
          config.enabled &&
          identical(current, baseline) &&
          !settings.userPolicyTouched &&
          settings.preferences.customSource?.enabled != true;
      if (applyPolicy) {
        next = next.copyWith(
          preferredId: manifest.preferSelected ? id : next.preferredId,
          sourceFirst: manifest.sourceFirstWhenSelected
              ? true
              : next.sourceFirst,
        );
      }
      if (!identical(next, current)) {
        await settings.persist(
          next,
          settings.managed,
          notifyPlayback: true,
          manual: false,
        );
      }
      final checks = SourceCheckStore(settings.preferences.box).load();
      checks[id] = SourceCheckRecord(
        entryId: id,
        scriptSha256: scriptHash,
        runtimeId: runtimeId,
        outcome: 'initialized',
        checkedAt: DateTime.now(),
      );
      final receipts = {
        ..._receipts,
        source.sha256: <String, dynamic>{
          'state': 'complete',
          'scriptSha256': scriptHash,
          'runtimeId': runtimeId,
          'entryId': id,
          'policyHandled': true,
          if (source.updateUrl != null)
            'updateUrl': source.updateUrl.toString(),
        },
      };
      await settings.preferences.box.putAll({
        receiptKey: jsonEncode({'schemaVersion': 1, 'sources': receipts}),
        SourceCheckStore.key: jsonEncode(
          checks.map((id, record) => MapEntry(id, record.toJson())),
        ),
      });
      _receipts = receipts;
      _set(
        source,
        prior == null ? 'imported' : 'existing',
        prior != null
            ? IkLocalLxStrings.prepared(
                prior.config.name,
                applyPolicy && manifest.preferSelected,
              )
            : applyPolicy && manifest.preferSelected
            ? IkLocalLxStrings.importedPreferred
            : IkLocalLxStrings.importedKeepPolicy,
      );
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
          (_) => throw const LxSourceException(
            'cancelled',
            IkLocalLxStrings.inspectCancelled,
          ),
        ),
      ]);
    } catch (error) {
      if (timedOut) {
        throw const LxSourceException(
          'timeout',
          IkLocalLxStrings.inspectTimeout,
        );
      }
      if (error is LxSourceException) rethrow;
      throw const LxSourceException('script', IkLocalLxStrings.inspectFailed);
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
        final receipts = {
          ..._receipts,
          source.sha256: <String, dynamic>{
            'state': 'failed',
            'errorCode': code,
            'runtimeId': runtimeId,
          },
        };
        await settings.preferences.box.put(
          receiptKey,
          jsonEncode({'schemaVersion': 1, 'sources': receipts}),
        );
        _receipts = receipts;
        return true;
      });
    } catch (_) {
      return false;
    }
  }

  static String _failure(String? code) => switch (code) {
    'timeout' => IkLocalLxStrings.failure('timeout'),
    'platform' || 'unsupported' => IkLocalLxStrings.failure('platform'),
    'integrity' => IkLocalLxStrings.failure('integrity'),
    'path' => IkLocalLxStrings.failure('path'),
    'size' => IkLocalLxStrings.failure('size'),
    'invalidEncoding' => IkLocalLxStrings.failure('invalidEncoding'),
    'metadata' => IkLocalLxStrings.failure('metadata'),
    'receipt' => IkLocalLxStrings.failure('receipt'),
    'storage' => IkLocalLxStrings.failure('storage'),
    'network' ||
    'download' ||
    'rateLimited' => IkLocalLxStrings.failure('network'),
    _ => IkLocalLxStrings.failure(null),
  };
  static const _invalidManifest = LxSourceException(
    'metadata',
    IkLocalLxStrings.invalidManifest,
  );
  static const _invalidPath = LxSourceException(
    'path',
    IkLocalLxStrings.invalidPath,
  );

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
  const _LocalLxManifest(
    this.root,
    this.sources,
    this.preferSelected,
    this.sourceFirstWhenSelected,
  );
  final String root;
  final List<_LocalLxSource> sources;
  final bool preferSelected, sourceFirstWhenSelected;
}

class _LocalLxSource {
  const _LocalLxSource(
    this.name,
    this.version,
    this.sha256,
    this.relativeFile,
    this.byteLength,
    this.selected,
    this.updateUrl,
  );
  final String name, version, sha256, relativeFile;
  final int byteLength;
  final bool selected;
  final Uri? updateUrl;
}

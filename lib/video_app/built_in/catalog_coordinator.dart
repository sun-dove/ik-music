import '../../l10n/ik_source_catalog_strings.dart';

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../lx_source/lx_source.dart';
import '../multi_source/source_collection.dart';
import 'catalog.dart';
import 'fixed_importer.dart';
import 'managed_settings.dart';

enum IkSourceStage {
  waitingNetwork,
  downloading,
  checking,
  ready,
  pendingApply,
  unsupported,
  restricted,
  failed,
  disabled,
  removed,
  cancelled,
  rolledBack,
}

class IkCatalogItem {
  const IkCatalogItem(this.entry, this.stage, {this.message, this.failureCode});
  final IkCatalogEntry entry;
  final IkSourceStage stage;
  final String? message, failureCode;
  bool get retryable =>
      [IkSourceStage.waitingNetwork, IkSourceStage.cancelled].contains(stage) ||
      (stage == IkSourceStage.failed &&
          ![
            'integrity',
            'invalidEncoding',
            'size',
            'platform',
          ].contains(failureCode));
}

final ikSourceCatalogProvider = Provider<IkSourceCatalogCoordinator?>(
  (ref) => null,
);

class IkSourceCatalogCoordinator extends ChangeNotifier {
  IkSourceCatalogCoordinator({
    required this.catalog,
    required this.settings,
    required this.importer,
    required this.runtimeId,
    bool Function()? isPlaybackActive,
  }) : isPlaybackActive = isPlaybackActive ?? (() => false),
       _initialPristine = settings.pristine {
    settings.addListener(_settingsChanged);
    if (settings.managed.catalogVersion > catalog.catalogVersion) {
      settings.writesBlocked = true;
      settings.managedError = IkSourceCatalogStrings.olderCatalog;
    }
    _refresh();
  }
  final IkSourceCatalog catalog;
  final IkManagedSourceSettings settings;
  final IkFixedSourceImporter importer;
  final String runtimeId;
  final bool Function() isPlaybackActive;
  final bool _initialPristine;
  final _items = <String, IkCatalogItem>{};
  final _tokens = <CancelToken>{};
  Future<void>? _running;
  bool _disposed = false;
  int _generation = 0;
  String? error;
  bool get busy => _running != null;
  bool get autoPrepare => settings.managed.autoPrepare;
  List<IkCatalogItem> get items => [
    for (final entry in catalog.entries) _items[entry.sourceKey]!,
  ];
  int get readyCount => items
      .where(
        (e) =>
            e.stage == IkSourceStage.ready ||
            e.stage == IkSourceStage.rolledBack,
      )
      .length;
  int get pendingCount =>
      items.where((e) => e.stage == IkSourceStage.pendingApply).length;

  SourceEntry? _existing(IkManagedRecord? record) =>
      settings.value.entries.where((e) => e.id == record?.entryId).firstOrNull;
  void _set(
    IkCatalogEntry entry,
    IkSourceStage stage, {
    String? message,
    String? code,
  }) {
    if (_disposed) return;
    _items[entry.sourceKey] = IkCatalogItem(
      entry,
      stage,
      message: message,
      failureCode: code,
    );
    notifyListeners();
  }

  void _refresh() {
    for (final entry in catalog.entries) {
      final record = settings.managed.records[entry.sourceKey];
      final existing = _existing(record);
      final blocked = entry.blockReason(runtimeId);
      final item = record?.removed == true
          ? IkCatalogItem(
              entry,
              IkSourceStage.removed,
              message: IkSourceCatalogStrings.removed,
            )
          : record?.disabled == true ||
                (existing != null && !existing.config.enabled)
          ? IkCatalogItem(
              entry,
              IkSourceStage.disabled,
              message: IkSourceCatalogStrings.disabled,
            )
          : record?.pending != null && record?.pendingRuntimeId == runtimeId
          ? IkCatalogItem(
              entry,
              IkSourceStage.pendingApply,
              message: IkSourceCatalogStrings.pending,
            )
          : existing != null &&
                record?.runtimeId == runtimeId &&
                record?.scriptSha256 == existing.config.sha256 &&
                _matchesHash(existing.config, record?.contentSha256) &&
                record?.failureCode == null
          ? IkCatalogItem(
              entry,
              record?.rollbackHold == true
                  ? IkSourceStage.rolledBack
                  : IkSourceStage.ready,
              message: IkSourceCatalogStrings.ready,
            )
          : blocked != null
          ? IkCatalogItem(
              entry,
              entry.licenseEvidence == 'restrictedText'
                  ? IkSourceStage.restricted
                  : IkSourceStage.unsupported,
              message: blocked,
            )
          : record?.failureCode != null
          ? IkCatalogItem(
              entry,
              record!.failureCode == 'network'
                  ? IkSourceStage.waitingNetwork
                  : IkSourceStage.failed,
              message: _failureMessage(record.failureCode!),
              failureCode: record.failureCode,
            )
          : IkCatalogItem(
              entry,
              IkSourceStage.waitingNetwork,
              message: existing == null
                  ? IkSourceCatalogStrings.waiting
                  : IkSourceCatalogStrings.cacheWaiting,
            );
      _items[entry.sourceKey] = item;
    }
  }

  void _settingsChanged() {
    _refresh();
    if (!_disposed) notifyListeners();
  }

  Future<void> prepareOnce() {
    if (_running != null) return _running!;
    if (_disposed || !autoPrepare || settings.writesBlocked) {
      return Future.value();
    }
    return _start(null);
  }

  Future<void> prepareCatalogUpdate() {
    if (_running != null) return _running!;
    if (_disposed || settings.writesBlocked) return Future.value();
    return _start(null);
  }

  String _failureMessage(String code) => switch (code) {
    'network' => IkSourceCatalogStrings.networkWaiting,
    'integrity' => IkSourceCatalogStrings.integrityUpdate,
    'invalidEncoding' => IkSourceCatalogStrings.invalidEncoding,
    'rateLimited' => IkSourceCatalogStrings.rateLimited,
    'timeout' => IkSourceCatalogStrings.initializationTimeout,
    'platform' => IkSourceCatalogStrings.platformUnsupported,
    _ => IkSourceCatalogStrings.retryLast,
  };
  Future<void> retry([String? sourceKey]) {
    if (_running != null) return _running!;
    if (_disposed || settings.writesBlocked) return Future.value();
    final keys = items
        .where(
          (e) =>
              e.retryable &&
              (sourceKey == null || e.entry.sourceKey == sourceKey),
        )
        .map((e) => e.entry.sourceKey)
        .toSet();
    if (keys.isEmpty) return Future.value();
    return _start(keys);
  }

  Future<void> _start(Set<String>? only) {
    final generation = ++_generation;
    error = null;
    late final Future<void> operation;
    operation = _prepare(generation, only)
        .catchError((Object _) {
          error = IkSourceCatalogStrings.catalogSaveFailed;
        })
        .whenComplete(() {
          if (identical(_running, operation)) _running = null;
          if (!_disposed) notifyListeners();
        });
    _running = operation;
    notifyListeners();
    return operation;
  }

  bool _current(int generation) => !_disposed && generation == _generation;

  bool _knownContent(LxSourceConfig config, IkCatalogEntry entry) {
    return _matchesHash(config, entry.contentSha256);
  }

  bool _matchesHash(LxSourceConfig config, String? expected) {
    if (sha256.convert(utf8.encode(config.script)).toString() !=
        config.sha256) {
      return false;
    }
    return config.sha256 == expected ||
        sha256.convert(utf8.encode('\uFEFF${config.script}')).toString() ==
            expected;
  }

  Future<void> _adoptKnownEntries() => settings.serialize(() async {
    if (settings.writesBlocked) return;
    final records = {...settings.managed.records};
    var changed = false;
    for (final entry in catalog.entries) {
      final registered = records[entry.sourceKey];
      if (registered != null) {
        if (registered.entryId != null &&
            !registered.removed &&
            _existing(registered) == null) {
          records[entry.sourceKey] = registered.copyWith(
            removed: true,
            clearPending: true,
          );
          changed = true;
        }
        continue;
      }
      final old = settings.value.entries
          .where(
            (e) =>
                catalog.matchesOrigin(entry, e.config.origin) &&
                _knownContent(e.config, entry),
          )
          .firstOrNull;
      if (old == null) continue;
      records[entry.sourceKey] = IkManagedRecord(
        entryId: old.id,
        contentSha256: entry.contentSha256,
        scriptSha256: old.config.sha256,
        disabled: !old.config.enabled,
        downloadChoice: old.config.allowForDownloads,
      );
      changed = true;
    }
    if (changed) {
      final next = settings.managed.copyWith(
        records: records,
        catalogVersion: catalog.catalogVersion,
      );
      await settings.preferences.box.put(
        IkManagedSourceSettings.managedKey,
        jsonEncode(next.toJson()),
      );
      settings.managed = next;
    }
  });

  Future<void> _prepare(int generation, Set<String>? only) async {
    await _adoptKnownEntries();
    _refresh();
    // 串行获取与初始化，不同时启动多个 WebView2/QuickJS 宿主。
    for (final entry in catalog.entries) {
      if (!_current(generation)) break;
      if (only != null && !only.contains(entry.sourceKey)) continue;
      final record = settings.managed.records[entry.sourceKey];
      if (record?.removed == true ||
          record?.disabled == true ||
          record?.rollbackHold == true ||
          entry.blockReason(runtimeId) != null) {
        continue;
      }
      if (record?.pending != null &&
          record?.pendingRuntimeId == runtimeId &&
          record?.pendingContentSha256 == entry.contentSha256) {
        continue;
      }
      final existing = _existing(record);
      if (existing != null &&
          record?.runtimeId == runtimeId &&
          record?.contentSha256 == entry.contentSha256 &&
          record?.scriptSha256 == existing.config.sha256 &&
          _matchesHash(existing.config, record?.contentSha256) &&
          record?.failureCode == null) {
        continue;
      }
      final token = CancelToken();
      _tokens.add(token);
      try {
        LxSourceConfig config;
        if (existing != null && _knownContent(existing.config, entry)) {
          _set(
            entry,
            IkSourceStage.checking,
            message: IkSourceCatalogStrings.checkingCache,
          );
          final sources = await importer.engine.inspect(
            existing.config.script,
            cancelToken: token,
          );
          if (!sources.entries.any(
            (e) => ['tx', 'wy', 'kg'].contains(e.key) && e.value.isNotEmpty,
          )) {
            throw const LxSourceException(
              'platform',
              IkSourceCatalogStrings.noPlatform,
            );
          }
          config = LxSourceConfig(
            name: existing.config.name,
            version: existing.config.version,
            origin: existing.config.origin,
            script: existing.config.script,
            sha256: existing.config.sha256,
            sources: sources,
            enabled: existing.config.enabled,
            allowForDownloads: existing.config.allowForDownloads,
          );
        } else {
          _set(
            entry,
            IkSourceStage.downloading,
            message: IkSourceCatalogStrings.fetching,
          );
          config = await importer.prepare(
            catalog,
            entry,
            token,
            onChecking: () => _set(
              entry,
              IkSourceStage.checking,
              message: IkSourceCatalogStrings.checking,
            ),
          );
        }
        if (!_current(generation) || token.isCancelled) break;
        await settings.saveMetadata((state) {
          final latest =
              state.records[entry.sourceKey] ?? const IkManagedRecord();
          if (latest.removed || latest.disabled) return state;
          if (!_current(generation) || token.isCancelled) return state;
          return state.copyWith(
            catalogVersion: catalog.catalogVersion,
            records: {
              ...state.records,
              entry.sourceKey: latest.copyWith(
                pendingContentSha256: entry.contentSha256,
                pending: config,
                pendingRuntimeId: runtimeId,
                clearFailure: true,
              ),
            },
          );
        });
        if (!_current(generation)) break;
        _set(
          entry,
          IkSourceStage.pendingApply,
          message: IkSourceCatalogStrings.pending,
        );
      } on LxSourceException catch (failure) {
        if (!_current(generation) ||
            token.isCancelled ||
            failure.code == 'cancelled') {
          break;
        }
        await settings.saveMetadata(
          (state) => state.copyWith(
            records: {
              ...state.records,
              entry.sourceKey:
                  (state.records[entry.sourceKey] ?? const IkManagedRecord())
                      .copyWith(failureCode: failure.code),
            },
          ),
        );
        _set(
          entry,
          failure.code == 'network'
              ? IkSourceStage.waitingNetwork
              : failure.code == 'platform'
              ? IkSourceStage.unsupported
              : IkSourceStage.failed,
          message: failure.message,
          code: failure.code,
        );
      } catch (_) {
        if (!_current(generation)) break;
        _set(
          entry,
          IkSourceStage.failed,
          message: IkSourceCatalogStrings.prepareFailed,
          code: 'unknown',
        );
      } finally {
        _tokens.remove(token);
        token.cancel();
      }
    }
    if (_current(generation) && !isPlaybackActive()) {
      await commitAtPlaybackBoundary(idleOnly: true);
    }
  }

  void suspendPublishing() => settings.beginEditing();
  void resumePublishing() {
    settings.endEditing();
    if (!settings.editing && !isPlaybackActive()) {
      unawaited(
        commitAtPlaybackBoundary(idleOnly: true).catchError((Object _) {
          error = IkSourceCatalogStrings.saveRetry;
          if (!_disposed) notifyListeners();
        }),
      );
    }
  }

  Future<void> commitAtPlaybackBoundary({
    bool idleOnly = false,
  }) => settings.serialize(() async {
    if (_disposed || settings.writesBlocked || settings.editing) return;
    if (idleOnly && isPlaybackActive()) return;
    var collection = settings.value;
    final records = {...settings.managed.records};
    var changed = false;
    for (final entry in catalog.entries) {
      final record = records[entry.sourceKey];
      final pending = record?.pending;
      if (pending == null ||
          record!.pendingRuntimeId != runtimeId ||
          record.removed ||
          (record.disabled && !record.pendingRollback)) {
        continue;
      }
      if (!_matchesHash(pending, record.pendingContentSha256)) {
        _set(
          entry,
          IkSourceStage.failed,
          message: IkSourceCatalogStrings.pendingIntegrity,
          code: 'integrity',
        );
        continue;
      }
      final old = collection.entries
          .where((e) => e.id == record.entryId)
          .firstOrNull;
      final config = pending.copyWith(
        enabled: old?.config.enabled ?? true,
        allowForDownloads: entry.downloadRestricted
            ? false
            : old?.config.allowForDownloads ?? record.downloadChoice,
      );
      final id =
          old?.id ??
          sha256.convert(utf8.encode('ik:${entry.sourceKey}')).toString();
      collection = old == null
          ? collection.copyWith(
              entries: [...collection.entries, SourceEntry(id, config)],
            )
          : collection.replace(id, config);
      records[entry.sourceKey] = record.copyWith(
        entryId: id,
        contentSha256: record.pendingContentSha256,
        scriptSha256: config.sha256,
        runtimeId: runtimeId,
        checkedAt: DateTime.now().toUtc().toIso8601String(),
        previous: old != null && old.config.sha256 != config.sha256
            ? old.config
            : null,
        previousContentSha256: old != null && old.config.sha256 != config.sha256
            ? record.contentSha256
            : null,
        previousRuntimeId: old != null && old.config.sha256 != config.sha256
            ? record.runtimeId
            : null,
        clearPending: true,
        clearFailure: true,
      );
      changed = true;
    }
    if (!changed) return;
    if (collection.entries.fold<int>(
              0,
              (n, e) => n + utf8.encode(e.config.script).length,
            ) +
            records.values.fold<int>(
              0,
              (n, e) => n + utf8.encode(e.previous?.script ?? '').length,
            ) >
        8 * 1024 * 1024) {
      throw const LxSourceException('size', IkSourceCatalogStrings.totalBudget);
    }
    if (_initialPristine &&
        !settings.userPolicyTouched &&
        settings.value.entries.isEmpty &&
        !settings.value.sourceFirst &&
        !settings.value.autoSwitch) {
      collection = collection.copyWith(autoSwitch: true);
    }
    await settings.persist(
      collection,
      settings.managed.copyWith(
        records: records,
        catalogVersion: catalog.catalogVersion,
      ),
    );
    for (final entry in catalog.entries) {
      final record = records[entry.sourceKey];
      if (record?.runtimeId == runtimeId &&
          record?.pending == null &&
          !record!.removed &&
          !record.disabled &&
          record.failureCode == null &&
          record.entryId != null) {
        _set(
          entry,
          record.rollbackHold ? IkSourceStage.rolledBack : IkSourceStage.ready,
          message: record.rollbackHold
              ? IkSourceCatalogStrings.rolledBack(
                  collection.entries
                      .firstWhere((e) => e.id == record.entryId)
                      .config
                      .version,
                )
              : IkSourceCatalogStrings.ready,
        );
      }
    }
  });

  Future<void> rollback([String? sourceKey]) async {
    await settings.saveMetadata((state) {
      final records = {...state.records};
      for (final entry in catalog.entries) {
        if (sourceKey != null && entry.sourceKey != sourceKey) continue;
        final record = records[entry.sourceKey];
        if (record?.previous == null ||
            record!.removed ||
            record.previousRuntimeId != runtimeId ||
            !_matchesHash(record.previous!, record.previousContentSha256)) {
          continue;
        }
        records[entry.sourceKey] = record.copyWith(
          pending: record.previous,
          pendingRuntimeId: record.previousRuntimeId,
          pendingContentSha256: record.previousContentSha256,
          rollbackHold: true,
          pendingRollback: true,
        );
      }
      return state.copyWith(records: records);
    });
    _refresh();
    if (!isPlaybackActive()) await commitAtPlaybackBoundary();
    if (!_disposed) notifyListeners();
  }

  Future<void> setAutoPrepare(bool value) async {
    if (!value) cancel();
    await settings.saveMetadata((state) => state.copyWith(autoPrepare: value));
    if (!_disposed) notifyListeners();
    if (value) await prepareOnce();
  }

  Future<void> restore(String sourceKey) async {
    final entry = catalog.entries
        .where((e) => e.sourceKey == sourceKey)
        .firstOrNull;
    if (entry == null ||
        entry.blockReason(runtimeId) != null ||
        settings.writesBlocked) {
      return;
    }
    await settings.serialize(() async {
      final record =
          settings.managed.records[sourceKey] ?? const IkManagedRecord();
      final old = _existing(record);
      final next = old == null
          ? settings.value
          : settings.value.replace(old.id, old.config.copyWith(enabled: true));
      final state = settings.managed.copyWith(
        records: {
          ...settings.managed.records,
          sourceKey: record.copyWith(
            removed: false,
            disabled: false,
            clearEntryId: old == null,
            clearFailure: true,
            clearPending: true,
            rollbackHold: false,
          ),
        },
      );
      await settings.persist(next, state, notifyPlayback: true);
    });
    _refresh();
    if (!_disposed) await _start({sourceKey});
  }

  Future<void> enableAutomaticFallback() async {
    await settings.save(settings.value.copyWith(autoSwitch: true));
  }

  void cancel() {
    _generation++;
    for (final token in _tokens.toList()) {
      token.cancel();
    }
    for (final item in items) {
      if (item.stage == IkSourceStage.downloading ||
          item.stage == IkSourceStage.checking) {
        _set(
          item.entry,
          IkSourceStage.cancelled,
          message: IkSourceCatalogStrings.cancelledRetry,
        );
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    cancel();
    _disposed = true;
    settings.removeListener(_settingsChanged);
    importer.dispose();
    super.dispose();
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/ik_source_update_strings.dart';
import '../lx_source/lx_source.dart';
import '../multi_source/source_collection.dart';
import 'catalog.dart';
import 'catalog_coordinator.dart';
import 'managed_settings.dart';
import 'source_update_fetcher.dart';

final ikSourceUpdaterProvider = Provider<IkSourceUpdater?>((ref) => null);

/// Windows 新管理入口的更新流程。手动更新只准备草稿，自动更新只在编辑外提交。
class IkSourceUpdater extends ChangeNotifier {
  IkSourceUpdater({
    required this.coordinator,
    required this.engine,
    required this.isResolving,
    this.isLocalImportBusy,
    IkSourceUpdateFetcher? fetcher,
  }) : fetcher = fetcher ?? IkSourceUpdateFetcher();

  static const _autoKey = 'ik.sources.autoUpdate.v1';
  static const _checkedKey = 'ik.sources.lastUpdateCheck.v1';
  static const _automaticSuccessKey = 'ik.sources.lastAutomaticUpdate.v1';
  final IkSourceCatalogCoordinator coordinator;
  final LxSourceEngine engine;
  final IkSourceUpdateFetcher fetcher;
  final bool Function() isResolving;
  final bool Function()? isLocalImportBusy;
  IkManagedSourceSettings get settings => coordinator.settings;
  final _statuses = <String, String>{};
  final _fetched = <String, IkFetchedSourceUpdate>{};
  final _verified = <String, ({String scriptHash, String contentHash})>{};
  Timer? _timer;
  CancelToken? _activeToken;
  DateTime? _snapshotAt, _automaticAttempt;
  String? _catalogError;
  bool _disposed = false, busy = false;
  bool _lastBatchSucceeded = false;
  SourceCollection? _workspaceDraft;
  String? _workspaceBaseline;
  int _workspaceViews = 0;
  bool _workspaceTask = false, _workspaceLease = false;
  bool _workspaceKeepsHttp = false;
  String? message;
  String? _maintenanceIssue;
  String? get workspaceNotice => busy ? message : _maintenanceIssue;

  SourceCollection get workspaceDraft => _workspaceDraft ?? settings.value;
  bool get workspaceDirty =>
      _workspaceDraft != null &&
      jsonEncode(_workspaceDraft!.toJson()) != _workspaceBaseline;

  void openWorkspace() {
    _workspaceViews++;
    _workspaceDraft ??= settings.value;
    _workspaceBaseline ??= jsonEncode(settings.value.toJson());
    _syncWorkspaceLease();
  }

  void closeWorkspace() {
    if (_workspaceViews > 0) _workspaceViews--;
    _syncWorkspaceLease();
  }

  void _syncWorkspaceLease() {
    final needed = _workspaceViews > 0 || _workspaceTask || workspaceDirty;
    if (needed && !_workspaceLease) {
      coordinator.suspendPublishing();
      _workspaceLease = true;
    } else if (!needed && _workspaceLease) {
      _workspaceLease = false;
      _workspaceDraft = null;
      _workspaceBaseline = null;
      coordinator.resumePublishing();
    }
  }

  void editWorkspace(SourceCollection draft) {
    final before = workspaceDraft;
    if (draft.autoSwitch != before.autoSwitch ||
        draft.highestQuality != before.highestQuality ||
        draft.sourceFirst != before.sourceFirst ||
        draft.entries.any(
          (entry) =>
              entry.config.enabled &&
              !before.entries.any(
                (old) => old.id == entry.id && old.config.enabled,
              ),
        )) {
      _workspaceKeepsHttp = false;
    }
    _workspaceBaseline ??= jsonEncode(settings.value.toJson());
    _workspaceDraft = draft;
    _syncWorkspaceLease();
    _notify();
  }

  void cancelWorkspaceOperation() => _activeToken?.cancel();

  void acceptHttpPolicy() {
    if (settings.preferences.customSource?.enabled != true) return;
    _workspaceKeepsHttp = true;
    final draft = _workspaceDraft;
    if (draft == null) return;
    _workspaceDraft = draft.copyWith(
      autoSwitch: false,
      highestQuality: false,
      sourceFirst: false,
      entries: [
        for (final e in draft.entries)
          SourceEntry(e.id, e.config.copyWith(enabled: false)),
      ],
    );
    _syncWorkspaceLease();
    _notify();
  }

  Future<void> _workspaceOperation(
    Future<void> Function(CancelToken) work,
  ) async {
    if (busy) return;
    _workspaceTask = true;
    _syncWorkspaceLease();
    try {
      await work(CancelToken());
    } catch (error) {
      message = _error(error);
    } finally {
      _workspaceTask = false;
      _syncWorkspaceLease();
      _notify();
    }
  }

  Future<void> checkWorkspaceUpdates(SourceCollection draft) {
    editWorkspace(draft);
    return _workspaceOperation((token) => checkDraftUpdates(draft, token));
  }

  Future<void> updateWorkspaceSources(SourceCollection draft) {
    editWorkspace(draft);
    return _workspaceOperation(
      (token) => _run(token, () async {
        await _updateAll(draft, token, onPrepared: _mergeWorkspaceUpdate);
      }),
    );
  }

  Future<void> updateWorkspaceEntry(SourceEntry entry) =>
      _workspaceOperation((token) async {
        final config = await updateEntry(entry, token);
        if (!token.isCancelled) {
          _mergeWorkspaceUpdate(entry, config);
        }
      });

  void _mergeWorkspaceUpdate(SourceEntry original, LxSourceConfig config) {
    final draft = workspaceDraft;
    final current = draft.entries.where((e) => e.id == original.id).firstOrNull;
    if (current == null || current.config.sha256 != original.config.sha256) {
      return;
    }
    final restricted = _catalogEntry(current)?.downloadRestricted == true;
    _workspaceDraft = draft.replace(
      current.id,
      config.copyWith(
        enabled: current.config.enabled,
        allowForDownloads: !restricted && current.config.allowForDownloads,
      ),
    );
    _syncWorkspaceLease();
    _notify();
  }

  Future<void> saveWorkspaceDraft(SourceCollection draft) async {
    await saveDraft(draft, preserveHttpPolicy: _workspaceKeepsHttp);
    _workspaceDraft = settings.value;
    _workspaceBaseline = jsonEncode(settings.value.toJson());
    _syncWorkspaceLease();
    _notify();
  }

  bool get autoUpdate => settings.preferences.box.get(_autoKey) == true;
  DateTime? get lastChecked => DateTime.tryParse(
    settings.preferences.box.get(_checkedKey) as String? ?? '',
  );
  String? statusFor(SourceEntry entry) {
    final status = _statuses[entry.id];
    if (status == IkSourceUpdateStrings.draftReady &&
        _verified[entry.id]?.scriptHash != entry.config.sha256) {
      return IkSourceUpdateStrings.updateAvailable;
    }
    return status;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<T> _run<T>(CancelToken token, Future<T> Function() work) async {
    if (_disposed || token.isCancelled) throw _cancelled;
    if (busy || coordinator.busy || isLocalImportBusy?.call() == true) {
      throw const LxSourceException('busy', IkSourceUpdateStrings.busy);
    }
    busy = true;
    _maintenanceIssue = null;
    message = null;
    _activeToken = token;
    _notify();
    try {
      return await work();
    } catch (error) {
      message = token.isCancelled
          ? IkSourceUpdateStrings.cancelledKeepCurrent
          : _error(error);
      if (!token.isCancelled) _maintenanceIssue = message;
      rethrow;
    } finally {
      busy = false;
      _activeToken = null;
      _notify();
    }
  }

  IkCatalogEntry? _catalogEntry(SourceEntry source) {
    final origin = source.config.origin;
    final parts = origin.pathSegments;
    final knownOrigin =
        origin.scheme == 'https' &&
        origin.userInfo.isEmpty &&
        !origin.hasQuery &&
        !origin.hasFragment &&
        origin.host == 'raw.githubusercontent.com' &&
        parts.length == 5 &&
        parts[0] == 'pdone' &&
        parts[1] == 'lx-music-source' &&
        (parts[2] == 'main' || RegExp(r'^[0-9a-f]{40}$').hasMatch(parts[2])) &&
        parts[4].endsWith('.js');
    for (final entry in coordinator.catalog.entries) {
      if (settings.managed.records[entry.sourceKey]?.entryId == source.id ||
          coordinator.catalog.matchesOrigin(entry, origin) ||
          (knownOrigin && parts[3] == entry.sourceKey.split(':').last)) {
        return entry;
      }
    }
    return null;
  }

  String? _blocked(SourceEntry source, {bool automatic = false}) {
    if (source.config.origin.scheme == 'file') {
      return IkSourceUpdateStrings.noLocalUpdateUrl;
    }
    final entry = _catalogEntry(source);
    if (entry == null) return null;
    final record = settings.managed.records[entry.sourceKey];
    if (automatic && record?.rollbackHold == true) {
      return IkSourceUpdateStrings.rollbackHold;
    }
    return entry.blockReason(coordinator.runtimeId);
  }

  Future<void> _refresh(CancelToken token) async {
    _fetched.clear();
    _snapshotAt = DateTime.now();
    _catalogError = null;
    try {
      await fetcher.refresh(token);
    } catch (error) {
      if (token.isCancelled) rethrow;
      _catalogError = _error(error);
    }
  }

  Future<IkFetchedSourceUpdate> _fetch(
    SourceEntry source,
    CancelToken token,
  ) async {
    if (token.isCancelled || _disposed) throw _cancelled;
    final blocked = _blocked(source);
    if (blocked != null) throw LxSourceException('unsupported', blocked);
    if (_snapshotAt == null ||
        DateTime.now().difference(_snapshotAt!) > const Duration(minutes: 15)) {
      await _refresh(token);
    }
    final cached = _fetched[source.id];
    if (cached != null) return cached;
    final entry = _catalogEntry(source);
    if (entry != null && _catalogError != null) {
      throw LxSourceException('metadata', _catalogError!);
    }
    final result = entry == null
        ? await fetcher.fetchCustom(source.config.origin, token)
        : await fetcher.fetch(entry, token);
    if (token.isCancelled || _disposed) throw _cancelled;
    _fetched[source.id] = result;
    return result;
  }

  Future<void> checkUpdates(CancelToken token) =>
      checkDraftUpdates(settings.value, token);

  Future<void> checkDraftUpdates(SourceCollection draft, CancelToken token) =>
      _run(token, () async {
        message = IkSourceUpdateStrings.checkingUpdates;
        await _refresh(token);
        var changed = 0, failed = 0, checked = 0, skipped = 0;
        for (final entry in draft.entries) {
          if (token.isCancelled || _disposed) break;
          final blocked = _blocked(entry);
          if (blocked != null) {
            _statuses[entry.id] = blocked;
            skipped++;
            continue;
          }
          _statuses[entry.id] = IkSourceUpdateStrings.checking;
          _notify();
          try {
            final next = await _fetch(entry, token);
            final hasUpdate = next.sha256 != entry.config.sha256;
            if (hasUpdate) changed++;
            checked++;
            _statuses[entry.id] = hasUpdate
                ? IkSourceUpdateStrings.availableVersion(next.version)
                : IkSourceUpdateStrings.current;
          } catch (error) {
            if (token.isCancelled) {
              _statuses[entry.id] = IkSourceUpdateStrings.checkCancelled;
              break;
            }
            failed++;
            _statuses[entry.id] = _error(error);
          }
          _notify();
        }
        if (!token.isCancelled && !_disposed && failed == 0 && checked > 0) {
          await settings.preferences.box.put(
            _checkedKey,
            DateTime.now().toUtc().toIso8601String(),
          );
        }
        message = IkSourceUpdateStrings.checkSummary(
          token.isCancelled,
          checked,
          changed,
          failed,
          skipped,
        );
        if (!token.isCancelled && failed > 0) _maintenanceIssue = message;
      });

  Future<LxSourceConfig> _update(SourceEntry entry, CancelToken token) async {
    _statuses[entry.id] = IkSourceUpdateStrings.downloading;
    _notify();
    final next = await _fetch(entry, token);
    if (next.sha256 == entry.config.sha256) {
      _statuses[entry.id] = IkSourceUpdateStrings.current;
      return entry.config;
    }
    _statuses[entry.id] = IkSourceUpdateStrings.inspecting;
    _notify();
    final sources = await engine.inspect(next.script, cancelToken: token);
    if (token.isCancelled || _disposed) throw _cancelled;
    if (!sources.entries.any(
      (e) => ['tx', 'wy', 'kg'].contains(e.key) && e.value.isNotEmpty,
    )) {
      throw const LxSourceException(
        'platform',
        IkSourceUpdateStrings.noSupportedPlatform,
      );
    }
    final catalogEntry = _catalogEntry(entry);
    final config = LxSourceConfig(
      name: catalogEntry?.displayName ?? next.name,
      version: next.version,
      origin: next.origin,
      script: next.script,
      sha256: next.sha256,
      sources: sources,
      enabled: entry.config.enabled,
      allowForDownloads: catalogEntry?.downloadRestricted == true
          ? false
          : entry.config.allowForDownloads,
    );
    _verified[entry.id] = (
      scriptHash: next.sha256,
      contentHash: next.contentSha256,
    );
    _statuses[entry.id] = IkSourceUpdateStrings.draftReady;
    _notify();
    return config;
  }

  Future<LxSourceConfig> updateEntry(SourceEntry entry, CancelToken token) =>
      _run(token, () async {
        try {
          if (_catalogError != null) await _refresh(token);
          final result = await _update(entry, token);
          message = _statuses[entry.id];
          return result;
        } catch (error) {
          _statuses[entry.id] = token.isCancelled
              ? IkSourceUpdateStrings.cancelledKeepVersion
              : _error(error);
          rethrow;
        }
      });

  Future<SourceCollection> updateAll(
    SourceCollection draft,
    CancelToken token,
  ) => _run(token, () => _updateAll(draft, token));

  Future<SourceCollection> _updateAll(
    SourceCollection draft,
    CancelToken token, {
    bool automatic = false,
    void Function(SourceEntry, LxSourceConfig)? onPrepared,
  }) async {
    _lastBatchSucceeded = false;
    await _refresh(token);
    var result = draft;
    var updated = 0, unchanged = 0, failed = 0, skipped = 0;
    final entries = automatic
        ? draft.entries.where((e) => e.config.enabled).toList()
        : draft.entries;
    for (final entry in entries) {
      if (token.isCancelled || _disposed) break;
      final blocked = _blocked(entry, automatic: automatic);
      if (blocked != null) {
        _statuses[entry.id] = blocked;
        skipped++;
        continue;
      }
      message = IkSourceUpdateStrings.updating(
        entry.config.name,
        updated + unchanged + failed + skipped + 1,
        entries.length,
      );
      _notify();
      try {
        final config = await _update(entry, token);
        if (config.sha256 == entry.config.sha256) {
          unchanged++;
        } else {
          result = result.replace(entry.id, config);
          updated++;
          onPrepared?.call(entry, config);
        }
      } catch (error) {
        _statuses[entry.id] = token.isCancelled
            ? IkSourceUpdateStrings.cancelledKeepVersion
            : _error(error);
        if (token.isCancelled) break;
        failed++;
      }
    }
    message = IkSourceUpdateStrings.updateSummary(
      token.isCancelled,
      updated,
      unchanged,
      failed,
      skipped,
    );
    _lastBatchSucceeded = !token.isCancelled && !_disposed && failed == 0;
    if (!token.isCancelled && failed > 0) _maintenanceIssue = message;
    if (_lastBatchSucceeded && updated + unchanged > 0) {
      await settings.preferences.box.put(
        _checkedKey,
        DateTime.now().toUtc().toIso8601String(),
      );
    }
    return result;
  }

  Future<void> saveDraft(
    SourceCollection draft, {
    SourceCollection? expectedBase,
    bool preserveHttpPolicy = false,
  }) async {
    await settings.saveUpdatedDraft(
      draft,
      verified: _verified,
      runtimeId: coordinator.runtimeId,
      expectedBase: expectedBase,
      automatic: expectedBase != null || preserveHttpPolicy,
    );
    for (final entry in draft.entries) {
      if (_verified[entry.id]?.scriptHash == entry.config.sha256) {
        _statuses[entry.id] = IkSourceUpdateStrings.updated;
      }
    }
    message = IkSourceUpdateStrings.saved;
    _notify();
  }

  Future<void> setAutoUpdate(bool value) async {
    try {
      await settings.preferences.box.put(_autoKey, value);
    } catch (_) {
      message = IkSourceUpdateStrings.autoUpdateSaveFailed;
      _maintenanceIssue = message;
      _notify();
      rethrow;
    }
    if (_maintenanceIssue == IkSourceUpdateStrings.autoUpdateSaveFailed) {
      _maintenanceIssue = null;
    }
    if (!value && _automaticRunning) _activeToken?.cancel();
    _notify();
    if (value) unawaited(_automaticTick());
  }

  void start() {
    _timer ??= Timer.periodic(
      const Duration(minutes: 5),
      (_) => unawaited(_automaticTick()),
    );
    unawaited(_automaticTick());
  }

  bool _automaticRunning = false;
  Future<void> _automaticTick() async {
    if (_disposed ||
        !autoUpdate ||
        busy ||
        coordinator.busy ||
        isLocalImportBusy?.call() == true ||
        settings.writesBlocked ||
        settings.editing ||
        isResolving() ||
        settings.value.entries.isEmpty) {
      return;
    }
    final now = DateTime.now();
    if (DateTime.tryParse(
          settings.preferences.box.get(_automaticSuccessKey) as String? ?? '',
        )
        case final DateTime checked) {
      if (now.difference(checked) < const Duration(days: 1)) return;
    }
    if (_automaticAttempt != null &&
        now.difference(_automaticAttempt!) < const Duration(hours: 1)) {
      return;
    }
    _automaticAttempt = now;
    _automaticRunning = true;
    final token = CancelToken();
    final before = settings.value;
    try {
      await _run(token, () async {
        final draft = await _updateAll(before, token, automatic: true);
        if (token.isCancelled || _disposed) return;
        if (settings.editing ||
            !identical(settings.value, before) ||
            isResolving()) {
          message = IkSourceUpdateStrings.autoUpdateDeferred;
          return;
        }
        if (!identical(draft, before)) {
          await saveDraft(draft, expectedBase: before);
        }
        if (_lastBatchSucceeded && !token.isCancelled && !_disposed) {
          await settings.preferences.box.put(
            _automaticSuccessKey,
            DateTime.now().toUtc().toIso8601String(),
          );
        }
      });
    } catch (_) {
      // 失败详情保留在更新面板，自动检查不弹窗。
    } finally {
      _automaticRunning = false;
    }
  }

  static String _error(Object error) => error is LxSourceException
      ? error.message
      : IkSourceUpdateStrings.updateFailed;
  static const _cancelled = LxSourceException(
    'cancelled',
    IkSourceUpdateStrings.updateCancelled,
  );

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _activeToken?.cancel();
    if (_workspaceLease) {
      _workspaceLease = false;
      settings.endEditing();
    }
    fetcher.dispose();
    super.dispose();
  }
}

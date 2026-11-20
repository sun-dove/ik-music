import '../../l10n/ik_source_catalog_strings.dart';

import 'dart:async';
import 'dart:convert';

import '../../models/audio_quality.dart';
import '../custom_source/custom_source_storage.dart';
import '../lx_source/lx_source.dart';
import '../multi_source/source_collection.dart';
import '../multi_source/source_checks.dart';
import '../windows/windows_music_preferences.dart';

class IkManagedRecord {
  const IkManagedRecord({
    this.entryId,
    this.contentSha256,
    this.scriptSha256,
    this.runtimeId,
    this.checkedAt,
    this.disabled = false,
    this.removed = false,
    this.downloadChoice = false,
    this.previous,
    this.pending,
    this.pendingRuntimeId,
    this.pendingContentSha256,
    this.previousContentSha256,
    this.previousRuntimeId,
    this.rollbackHold = false,
    this.pendingRollback = false,
    this.failureCode,
  });
  final String? entryId,
      contentSha256,
      scriptSha256,
      runtimeId,
      checkedAt,
      pendingRuntimeId,
      pendingContentSha256,
      previousContentSha256,
      previousRuntimeId,
      failureCode;
  final bool disabled, removed, downloadChoice, rollbackHold, pendingRollback;
  final LxSourceConfig? previous, pending;
  IkManagedRecord copyWith({
    String? entryId,
    String? contentSha256,
    String? scriptSha256,
    String? runtimeId,
    String? checkedAt,
    bool? disabled,
    bool? removed,
    bool? downloadChoice,
    LxSourceConfig? previous,
    LxSourceConfig? pending,
    String? pendingRuntimeId,
    String? pendingContentSha256,
    String? previousContentSha256,
    String? previousRuntimeId,
    bool? rollbackHold,
    bool? pendingRollback,
    String? failureCode,
    bool clearPending = false,
    bool clearFailure = false,
    bool clearEntryId = false,
  }) => IkManagedRecord(
    entryId: clearEntryId ? null : entryId ?? this.entryId,
    contentSha256: contentSha256 ?? this.contentSha256,
    scriptSha256: scriptSha256 ?? this.scriptSha256,
    runtimeId: runtimeId ?? this.runtimeId,
    checkedAt: checkedAt ?? this.checkedAt,
    disabled: disabled ?? this.disabled,
    removed: removed ?? this.removed,
    downloadChoice: downloadChoice ?? this.downloadChoice,
    previous: previous ?? this.previous,
    pending: clearPending ? null : pending ?? this.pending,
    pendingRuntimeId: clearPending
        ? null
        : pendingRuntimeId ?? this.pendingRuntimeId,
    pendingContentSha256: clearPending
        ? null
        : pendingContentSha256 ?? this.pendingContentSha256,
    previousContentSha256: previousContentSha256 ?? this.previousContentSha256,
    previousRuntimeId: previousRuntimeId ?? this.previousRuntimeId,
    rollbackHold: rollbackHold ?? this.rollbackHold,
    pendingRollback: clearPending
        ? false
        : pendingRollback ?? this.pendingRollback,
    failureCode: clearFailure ? null : failureCode ?? this.failureCode,
  );
  Map<String, dynamic> toJson() => {
    'entryId': entryId,
    'contentSha256': contentSha256,
    'scriptSha256': scriptSha256,
    'runtimeId': runtimeId,
    'checkedAt': checkedAt,
    'disabled': disabled,
    'removed': removed,
    'downloadChoice': downloadChoice,
    if (previous != null) 'previous': previous!.toJson(),
    if (pending != null) 'pending': pending!.toJson(),
    'pendingRuntimeId': pendingRuntimeId,
    'pendingContentSha256': pendingContentSha256,
    'previousContentSha256': previousContentSha256,
    'previousRuntimeId': previousRuntimeId,
    'rollbackHold': rollbackHold,
    'pendingRollback': pendingRollback,
    'failureCode': failureCode,
  };
  factory IkManagedRecord.fromJson(Map<String, dynamic> json) =>
      IkManagedRecord(
        entryId: json['entryId'] as String?,
        contentSha256: json['contentSha256'] as String?,
        scriptSha256: json['scriptSha256'] as String?,
        runtimeId: json['runtimeId'] as String?,
        checkedAt: json['checkedAt'] as String?,
        disabled: json['disabled'] == true,
        removed: json['removed'] == true,
        downloadChoice: json['downloadChoice'] == true,
        previous: json['previous'] == null
            ? null
            : LxSourceConfig.fromJson(
                Map<String, dynamic>.from(json['previous'] as Map),
              ),
        pending: json['pending'] == null
            ? null
            : LxSourceConfig.fromJson(
                Map<String, dynamic>.from(json['pending'] as Map),
              ),
        pendingRuntimeId: json['pendingRuntimeId'] as String?,
        pendingContentSha256: json['pendingContentSha256'] as String?,
        previousContentSha256: json['previousContentSha256'] as String?,
        previousRuntimeId: json['previousRuntimeId'] as String?,
        rollbackHold: json['rollbackHold'] == true,
        pendingRollback: json['pendingRollback'] == true,
        failureCode: json['failureCode'] as String?,
      );
}

class IkManagedState {
  const IkManagedState({
    this.revision = 0,
    this.catalogVersion = 0,
    this.records = const {},
    this.autoPrepare = true,
  });
  final int revision, catalogVersion;
  final Map<String, IkManagedRecord> records;
  final bool autoPrepare;
  IkManagedState copyWith({
    Map<String, IkManagedRecord>? records,
    int? catalogVersion,
    bool? autoPrepare,
  }) => IkManagedState(
    revision: revision + 1,
    catalogVersion: catalogVersion ?? this.catalogVersion,
    records: records ?? this.records,
    autoPrepare: autoPrepare ?? this.autoPrepare,
  );
  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'revision': revision,
    'catalogVersion': catalogVersion,
    'autoPrepare': autoPrepare,
    'records': records.map((key, value) => MapEntry(key, value.toJson())),
  };
  factory IkManagedState.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1) {
      throw const FormatException(IkSourceCatalogStrings.stateUnsupported);
    }
    return IkManagedState(
      revision: json['revision'] as int? ?? 0,
      catalogVersion: json['catalogVersion'] as int? ?? 0,
      autoPrepare: json['autoPrepare'] != false,
      records: (json['records'] as Map).map(
        (key, value) => MapEntry(
          key as String,
          IkManagedRecord.fromJson(Map<String, dynamic>.from(value as Map)),
        ),
      ),
    );
  }
}

/// 只在 IK 装配。手动保存、质量和自动发布共享计算+持久化边界。
class IkManagedSourceSettings extends WindowsSourceSettings {
  IkManagedSourceSettings(super.preferences);
  static const managedKey = 'ik.sources.managed.v1';
  IkManagedState managed = const IkManagedState();
  String? managedError;
  bool writesBlocked = false;
  bool userPolicyTouched = false;
  Future<void> _tail = Future.value();
  SourceCollection? _editBaseline;
  int _editDepth = 0;
  bool get editing => _editDepth > 0;
  bool get pristine =>
      !preferences.box.containsKey(SourceSettings.key) &&
      value.entries.isEmpty &&
      preferences.customSource == null &&
      preferences.lxSource == null;

  @override
  void load() {
    super.load();
    final raw = preferences.box.get(managedKey);
    if (raw == null) return;
    try {
      final json = Map<String, dynamic>.from(jsonDecode(raw as String) as Map);
      if (json['schemaVersion'] != 1) {
        writesBlocked = true;
        managedError = IkSourceCatalogStrings.newerState;
        return;
      }
      managed = IkManagedState.fromJson(json);
    } catch (_) {
      writesBlocked = true;
      managedError = IkSourceCatalogStrings.damagedState;
    }
  }

  Future<T> serialize<T>(Future<T> Function() work) {
    final operation = _tail.then((_) => work());
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  void beginEditing() {
    if (_editDepth++ == 0) _editBaseline = value;
  }

  void endEditing() {
    if (_editDepth > 0 && --_editDepth == 0) _editBaseline = null;
  }

  SourceCollection _mergeDraft(SourceCollection draft) {
    final baseline = _editBaseline;
    if (baseline == null) return draft;
    final known = baseline.entries.map((e) => e.id).toSet();
    return draft.copyWith(
      entries: [
        ...draft.entries,
        ...value.entries.where(
          (e) =>
              !known.contains(e.id) && !draft.entries.any((d) => d.id == e.id),
        ),
      ],
      highestQuality: draft.highestQuality == baseline.highestQuality
          ? value.highestQuality
          : draft.highestQuality,
      autoSwitch: draft.autoSwitch == baseline.autoSwitch
          ? value.autoSwitch
          : draft.autoSwitch,
      sourceFirst: draft.sourceFirst == baseline.sourceFirst
          ? value.sourceFirst
          : draft.sourceFirst,
    );
  }

  @override
  Future<void> save(SourceCollection next) => serialize(() async {
    final merged = _mergeDraft(next);
    final records = {...managed.records};
    for (final key in records.keys.toList()) {
      final record = records[key]!;
      if (record.entryId == null) continue;
      final entry = merged.entries
          .where((e) => e.id == record.entryId)
          .firstOrNull;
      records[key] = entry == null
          ? record.copyWith(removed: true, clearPending: true)
          : record.copyWith(
              disabled: !entry.config.enabled,
              removed: false,
              downloadChoice: entry.config.allowForDownloads,
            );
    }
    final updated = managed.copyWith(records: records);
    await persist(merged, updated, notifyPlayback: true, manual: true);
    userPolicyTouched = true;
    if (_editBaseline != null) _editBaseline = merged;
  });

  /// 调用者必须持有 serialize；集合、镜像、墓碑在一次 Hive putAll 中提交。
  Future<void> persist(
    SourceCollection next,
    IkManagedState state, {
    bool notifyPlayback = false,
    bool manual = false,
  }) async {
    _checkBudget(next, state);
    final keepLegacyHttp = !manual && preferences.customSource?.enabled == true;
    final mirror = keepLegacyHttp
        ? preferences.lxSource
        : next.preferred?.config ??
              preferences.lxSource?.copyWith(enabled: false);
    final http = manual && next.preferred != null
        ? preferences.customSource?.copyWith(enabled: false)
        : preferences.customSource;
    final checks = SourceCheckStore(preferences.box).load();
    for (final record in state.records.values) {
      if (record.entryId == null ||
          record.runtimeId == null ||
          record.checkedAt == null ||
          record.failureCode != null) {
        continue;
      }
      final entry = next.entries
          .where((e) => e.id == record.entryId)
          .firstOrNull;
      if (entry == null || entry.config.sha256 != record.scriptSha256) continue;
      checks[entry.id] = SourceCheckRecord(
        entryId: entry.id,
        scriptSha256: entry.config.sha256,
        runtimeId: record.runtimeId!,
        outcome: 'initialized',
        checkedAt: DateTime.parse(record.checkedAt!),
      );
    }
    await preferences.box.putAll({
      SourceSettings.key: jsonEncode(next.toJson()),
      if (!writesBlocked) managedKey: jsonEncode(state.toJson()),
      SourceCheckStore.key: jsonEncode(
        checks.map((key, record) => MapEntry(key, record.toJson())),
      ),
      if (mirror != null) 'video.lxSource.config': jsonEncode(mirror.toJson()),
      if (http != null)
        HiveCustomSourcePreferenceStore.key: jsonEncode(http.toJson()),
    });
    preferences.lxSource = mirror;
    preferences.customSource = http;
    value = next;
    if (!writesBlocked) managed = state;
    loadError = null;
    if (notifyPlayback) notifyListeners();
  }

  Future<void> saveMetadata(IkManagedState Function(IkManagedState) update) =>
      serialize(() async {
        if (writesBlocked) return;
        final next = update(managed);
        _checkBudget(value, next);
        await preferences.box.put(managedKey, jsonEncode(next.toJson()));
        managed = next;
      });
  void _checkBudget(SourceCollection collection, IkManagedState state) {
    final bytes =
        collection.entries.fold<int>(
          0,
          (n, e) => n + utf8.encode(e.config.script).length,
        ) +
        state.records.values.fold<int>(
          0,
          (n, e) =>
              n +
              utf8.encode(e.previous?.script ?? '').length +
              utf8.encode(e.pending?.script ?? '').length,
        );
    if (bytes > 8 * 1024 * 1024) {
      throw const LxSourceException('size', IkSourceCatalogStrings.totalBudget);
    }
  }
}

class IkManagedMusicPreferences extends WindowsMusicPreferences {
  IkManagedMusicPreferences(
    super.legacy, {
    required IkManagedSourceSettings sources,
  }) : managedSources = sources,
       super(sources: sources);
  final IkManagedSourceSettings managedSources;
  @override
  Future<void> setQuality(
    AudioLevel? level, {
    bool download = false,
    bool highest = false,
  }) => managedSources.serialize(
    () => super.setQuality(level, download: download, highest: highest),
  );
  @override
  Future<void> update(WindowsMusicConfiguration next) =>
      managedSources.serialize(() => super.update(next));
}

import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import 'source_collection.dart';

class SourceCheckRecord {
  const SourceCheckRecord({
    required this.entryId,
    required this.scriptSha256,
    required this.runtimeId,
    required this.outcome,
    required this.checkedAt,
    this.errorCode,
    this.message,
  });
  final String entryId, scriptSha256, runtimeId, outcome;
  final DateTime checkedAt;
  final String? errorCode, message;
  bool applies(SourceEntry entry, String runtime) =>
      entry.id == entryId &&
      entry.config.sha256 == scriptSha256 &&
      runtime == runtimeId;
  Map<String, dynamic> toJson() => {
    'entryId': entryId,
    'scriptSha256': scriptSha256,
    'runtimeId': runtimeId,
    'stage': 'initialization',
    'outcome': outcome,
    'checkedAt': checkedAt.toUtc().toIso8601String(),
    if (errorCode != null) 'errorCode': errorCode,
    if (message != null) 'message': message,
  };
  factory SourceCheckRecord.fromJson(Map<String, dynamic> value) =>
      SourceCheckRecord(
        entryId: value['entryId'] as String,
        scriptSha256: value['scriptSha256'] as String,
        runtimeId: value['runtimeId'] as String,
        outcome: value['outcome'] as String,
        checkedAt: DateTime.parse(value['checkedAt'] as String),
        errorCode: value['errorCode'] as String?,
        message: value['message'] as String?,
      );
}

/// 可丢弃的独立检查记录，损坏时不触碰音源集合与账号。
class SourceCheckStore {
  const SourceCheckStore(this.box);
  static const key = 'video.lxSource.checks.v1';
  final Box box;
  Map<String, SourceCheckRecord> load() {
    final result = <String, SourceCheckRecord>{};
    try {
      final raw = box.get(key);
      if (raw is! String) return result;
      final values = jsonDecode(raw) as Map;
      for (final value in values.values) {
        try {
          final record = SourceCheckRecord.fromJson(
            Map<String, dynamic>.from(value as Map),
          );
          result[record.entryId] = record;
        } catch (_) {
          /* 单条记录损坏不遮蔽其他记录。 */
        }
      }
    } catch (_) {
      /* 检查记录不是源列表的恢复依据。 */
    }
    return result;
  }

  Future<void> save(Map<String, SourceCheckRecord> values) => box.put(
    key,
    jsonEncode(values.map((id, record) => MapEntry(id, record.toJson()))),
  );
}

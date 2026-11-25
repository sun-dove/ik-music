import 'platform_type.dart';
import 'song.dart';

/// 个人日推与旧精选推荐分开，不以公开榜单补齐个人曲目。
enum PersonalDailyStatus {
  signedOut,
  identityIncomplete,
  success,
  empty,
  sessionExpired,
  verificationRequired,
  networkFailure,
  serviceUnavailable,
  invalidResponse,
  unsupported,
  sessionChanged,
}

class PersonalDailyResult {
  const PersonalDailyResult({
    required this.platform,
    required this.status,
    required this.fetchedAt,
    this.songs = const [],
    this.rawCount = 0,
    this.validCount = 0,
    this.sourceDate,
    this.errorCode,
    this._retryable,
  });

  final PlatformType platform;
  final PersonalDailyStatus status;
  final DateTime fetchedAt;
  final List<Song> songs;

  /// 完整服务响应的曲目数量，包含重复及无效身份项。
  final int rawCount;

  /// 完整解析后有效且去重的曲目数量，尚未应用展示上限。
  final int validCount;

  /// 仅服务端明确提供日期时填写；获取时间不冒充推荐日期。
  final DateTime? sourceDate;
  final String? errorCode;
  final bool? _retryable;

  int get displayCount => songs.length;

  bool get retryable =>
      _retryable ??
      (status == PersonalDailyStatus.networkFailure ||
          status == PersonalDailyStatus.serviceUnavailable ||
          status == PersonalDailyStatus.invalidResponse);
}

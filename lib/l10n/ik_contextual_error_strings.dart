/// IK 可选错误呈现使用操作上下文，真实失败原因保持原文。
abstract final class IkContextualErrorStrings {
  static String operationFailed(Object error) => '操作失败：$error';
  static const reconnect = '连接账号';
  static const retrySync = '重新同步';
  static const playbackNotice = '播放提示';
  static const playbackRecoveryIncomplete = '播放恢复未完成';
  static const replay = '重新播放';

  /// 只识别健康监测已经公开的确切提示，不按关键词推测失败原因。
  static const playerResetReason = '播放未能恢复，已重置播放器，请重试';

  static String syncFailed(String platform) => '$platform收藏同步失败';
  static String syncNeedsAccount(String platform) => '$platform收藏同步需要重新连接账号';
}

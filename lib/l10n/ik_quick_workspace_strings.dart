import '../models/platform_type.dart';

/// 搜索平台标签与轻量同步状态的可选展示文案。
abstract final class IkQuickWorkspaceStrings {
  static const syncIssue = '同步异常';
  static const reconnectNeeded = '需要重连';
  static const syncing = '同步中';
  static const accountUnavailable = '账号连接已失效，重新连接后可继续同步收藏。';
  static const closeDetails = '关闭详情';

  static String platformTab(PlatformType platform) => switch (platform) {
    PlatformType.netease => '网易云',
    PlatformType.qq => 'QQ 音乐',
    PlatformType.kugou => '酷狗',
    PlatformType.local => '本地',
  };
}

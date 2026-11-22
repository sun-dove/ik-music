import '../models/platform_type.dart';
import '../models/recommendation_source.dart';

/// IK 发现页的可选改版文案，原页面和平台适配器保持原样。
abstract final class IkDiscoveryRevisionStrings {
  static const recommendations = '推荐';
  static const newSongs = '新歌速递';
  static const toplists = '榜单';
  static const refresh = '刷新';
  static const retry = '重试';
  static const playAll = '播放全部';
  static const login = '登录账号';
  static const platformRecommendation = '平台推荐';
  static const toplistRecommendation = '榜单推荐';
  static const homepageRecommendation = '首页推荐';
  static const unavailable = '暂不可用';
  static const dailyRecommendation = '每日推荐';
  static const privateRecommendation = '今日私享';
  static const noNewSongs = '该平台暂无新歌';
  static const noToplists = '该平台暂无榜单';
  static const noRecommendations = '暂无推荐歌曲';
  static const refreshHint = '可以刷新后再试';
  static const pinnedHot = '固定入口';
  static const browseHot = '查看热歌榜';

  static String songsCount(int count) => '$count 首';
  static String toplistsCount(int count) => '$count 个榜单';
  static String newSongsFailed(PlatformType platform) =>
      '${platform.displayName}新歌加载失败';
  static String recommendationsFailed(PlatformType platform) =>
      '${platform.displayName}推荐加载失败';

  /// 来源枚举不单独证明个人推荐；会话、平台和已知来源必须同时成立。
  static String sourceLabel(
    RecommendationSource? source, {
    required PlatformType platform,
    required bool loggedIn,
  }) {
    if (source == null || source.platform != platform) {
      return platformRecommendation;
    }
    return switch (source.kind) {
      RecommendationKind.fallbackToplist => toplistRecommendation,
      RecommendationKind.fallbackHomepage => homepageRecommendation,
      RecommendationKind.unavailable => unavailable,
      RecommendationKind.personalPrivate =>
        platform == PlatformType.qq && loggedIn
            ? privateRecommendation
            : platformRecommendation,
      RecommendationKind.personalizedDaily =>
        platform == PlatformType.netease && loggedIn
            ? dailyRecommendation
            : platformRecommendation,
    };
  }

  /// 只使用同批次、同平台的真实说明，不再显示未经证实的个人来源标签。
  static String? sourceNote(
    RecommendationSource? source, {
    required PlatformType platform,
  }) => source?.platform == platform ? source?.note : null;
}

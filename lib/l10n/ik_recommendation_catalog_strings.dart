import '../models/platform_type.dart';

abstract final class IkRecommendationCatalogStrings {
  static const heading = '发现音乐';
  static const intro = '从一张歌单，遇见下一首喜欢。';
  static const playlists = '歌单推荐';
  static const refresh = '刷新歌单';
  static const loadMore = '加载更多';
  static const loading = '正在加载';
  static const retry = '重试';
  static const noMore = '没有更多歌单了';
  static const availableOnly = '已展示该来源当前提供的歌单';
  static const empty = '这个来源暂时没有歌单';
  static const failed = '歌单暂时加载失败，请稍后重试。';
  static const nextFailed = '后续歌单加载失败，已有内容仍可浏览。';
  static const invalid = '平台返回的歌单暂时无法读取。';
  static const publicFailed = '公开推荐暂时无法加载，请稍后重试。';
  static const publicLoading = '正在获取同平台公开推荐';
  static const publicRetry = '重试公开推荐';
  static const publicHint = '个人推荐暂不可用，先听听这个平台的公开推荐。';
  static const publicUnavailable = '暂无可用的公开推荐';
  static const publicSource = '公开推荐';
  static const personal = '个人推荐';
  static const qqNew = 'QQ音乐 · 新歌榜';
  static const qqHot = 'QQ音乐 · 热歌榜';
  static const kugouHome = '酷狗音乐 · 首页推荐';

  static String source(PlatformType platform) => switch (platform) {
    PlatformType.qq => 'QQ音乐 · 公开歌单',
    PlatformType.netease => '网易云 · 热门歌单',
    PlatformType.kugou => '酷狗音乐 · 首页歌单',
    PlatformType.local => playlists,
  };

  static String loaded(int count) => '已加载 $count 张';
  static String songs(int count) => '$count 首';
}

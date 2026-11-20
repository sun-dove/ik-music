import '../video_app/ik/ik_version.dart';

/// ik 独立改版的集中中文文案。
abstract final class IkStrings {
  static const home = '首页';
  static const library = '我的音乐';
  static const all = '全部';
  static const more = '更多';
  static const continuePlaying = '继续播放';
  static const recommendations = '为你推荐';
  static const toplists = '榜单';
  static const newSongs = '新歌速递';
  static const playlists = '我的歌单';
  static const history = '最近播放';
  static const localLikes = '本地收藏';
  static const platformLikes = '平台收藏';
  static const stats = '听歌统计';
  static const smart = '智能歌单';
  static const backup = '备份与恢复';
  static const audio = '音效与睡眠定时';
  static const floating = '桌面歌词';
  static const tools = '音乐工具';
  static const nextUp = '接下来播放';
  static const sourceDetails = '音源信息';
  static const searchHint = '搜索歌曲、歌手或专辑';
  static const searchIntro = '一次搜索，本地与三个平台分别呈现';
  static const noResults = '没有找到歌曲';
  static const emptyLikes = '还没有收藏歌曲';
  static const emptyQueue = '队列为空，先选一首歌';
  static const browse = '浏览全部';
  static const pageMissing = '这个页面暂时无法打开';
  static const backHome = '回到首页';
  static const album = '查看专辑';
  static const artist = '查看歌手';
  static const saveLocal = '收藏到本地';
  static const removeLocal = '取消本地收藏';
  static const missingDetail = '这首歌没有可用的详情标识';
  static const sourceUnavailable = '当前没有可用的音源信息';
  static const notAvailable = '当前设备暂不支持';
  static const actionFailed = '操作未完成，请重试';
  static const fade = '淡入淡出';
  static const fadeDuration = '过渡时长';
  static const equalizer = '均衡器';
  static const sleep = '睡眠定时';
  static const timerDuration = '定时时长';
  static const desktopUnavailable = '桌面控制暂不可用';
  static const discoveryHint = '从推荐、新歌和榜单开始探索';
  static const noRecommendations = '当前没有推荐歌曲，可以浏览榜单或新歌';
  static const sourceName = '实际音源';
  static const sourceFormat = '音频格式';
  static const sourceBitrate = '码率';
  static const sourceUnknown = '尚未确认';
  static const changeQuality = '调整音质';
  static const close = '关闭';
  static const playlistJson = 'JSON 歌单';
  static const importPlaylistHint =
      '支持网易云、QQ音乐、酷狗音乐的分享链接；'
      '也可以粘贴 M3U8、JSON 歌单或「歌名 - 歌手」文本';
  static const invalidPlaylistLink = '无法识别歌单链接';
  static const importPlaylistFailed = '导入歌单失败';
  static String results(int loaded, int? total) =>
      total == null ? '$loaded 首' : '$loaded / $total 首';
  static String minutes(int value) => '$value 分钟';
  static String remaining(int minutes, int seconds) =>
      '剩余 $minutes:${seconds.toString().padLeft(2, '0')}';
  static String band(int frequency) => '$frequency Hz';
  static String downloadQueued(int count) => '已按设置音质加入下载队列：$count 首';
  static String sharedPlaylist(String name, int count, String link) =>
      '$name（$count 首）\n来自 ${IkVersion.name}\n$link';
}

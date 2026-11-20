import '../video_app/ik/ik_version.dart';

/// 悦音扩展入口的文案，沿用独立入口的集中管理方式。
class ExpandedStrings {
  static const operationCancelled = '已取消音源操作。';
  static const windowsRuntimeMissing =
      'Windows音源运行环境未就绪。请使用完整发行包，并安装Microsoft Edge WebView2 Runtime后重试。';
  static const windowsCodeLimit = '音源脚本超出Windows运行时大小限制。';
  static const windowsScriptTimeout = '音源脚本执行超时，已结束独立运行进程，可重试或切换音源。';
  static const windowsScriptFailed = 'Windows音源脚本执行失败，请检查兼容范围或切换音源。';
  static const appName = IkVersion.name;
  static const kugouUnavailable = '酷狗服务暂未返回可用数据，请稍后重试。';
  static const kugouInvalid = '酷狗返回数据不完整，请重试。';
  static const positivePage = '页数和数量必须为正数';
  static const kugouLogin = '请先登录酷狗音乐。';
  static const kugouLikesIncomplete = '酷狗收藏尚未同步完整，可重试继续同步。';
  static const kugouPlaylistsIncomplete = '酷狗歌单尚未同步完整，请重试。';
  static const playlistSongsIncomplete = '歌单曲目尚未获取完整，请重试。';
  static const sourcePlatformUnsupported =
      '该音源未声明可用的QQ、网易云或酷狗播放接口；仅支持其他平台的脚本暂不能导入。';
  static const sourceRateLimited = '音源服务限制了请求频率（429），请稍后重试或切换音源。';
  static const sourceHttpUnsupported = '该音源请求使用了HTTP地址，目前仅支持HTTPS请求。';
  static const sourceNetworkFailed = '音源初始化或取流网络请求失败，请稍后重试或切换音源。';
  static const sessionChanged = '登录状态已变化，请返回重新打开歌单。';
  static const kugouPlaylists = '酷狗歌单';
  static const refreshPlaylists = '刷新歌单';
  static const retry = '重试';
  static const playLoaded = '播放已获取歌曲';
  static const downloadLoaded = '下载已获取歌曲';
  static const empty = '这里还没有内容。';
  static const myPlaylists = '我的歌单';
  static const saveFailed = '保存失败，修改已保留，请重试。';
  static const saved = '已保存';
  static const dirty = '有未保存的更改';
  static const saveToApply = '保存后才会改变实际播放使用的音源。';
  static const keepEditing = '继续编辑';
  static const discard = '放弃更改';
  static const saveAndReturn = '保存并返回';
  static const checkSaveFailed = '检查已完成，检查记录保存失败，可重新检查；音源设置仍保留。';
  static const checkFailed = '检查失败，请稍后重试。';
  static const checking = '正在检查初始化…';
  static const notCheckedNow = '本次未检查';
  static const notChecked = '未检查，实际播放待验证';
  static const retryShort = '请重试';
  static const cancel = '取消';
  static const delete = '删除';
  static const allPlatforms = '全部平台';
  static const qq = 'QQ音乐';
  static const netease = '网易云';
  static const kugou = '酷狗音乐';
  static const managerTitle = '音源管理';
  static const httpSettings = 'HTTP音源设置';
  static const scriptLink = '音源脚本链接';
  static const importLink = '从链接导入';
  static const playPolicy = '播放策略';
  static const sourceFirst = '音源优先';
  static const officialFirst = '官方优先';
  static const highest = '最高可用音质';
  static const fixed = '固定音质';
  static const searchName = '查找音源名称';
  static const clearSearch = '清除搜索';
  static const enabled = '已启用';
  static const orderHint = '按播放顺序排列，可拖动或在更多菜单移动';
  static const inspectList = '检查列表';
  static const cancelOperation = '取消当前操作';
  static const noMatches = '没有匹配的音源，可清除筛选。';
  static const settingsSaved = '设置已保存';
  static const saveSettings = '保存设置';
  static const more = '音源更多操作';
  static const prefer = '设为首选';
  static const inspect = '检查初始化';
  static const update = '从原链接更新';
  static const allowDownloads = '允许用于下载';
  static const moveUp = '上移';
  static const moveDown = '下移';
  static const deleteSource = '删除音源';

  static String downloadStatus(int status) =>
      '音源脚本下载失败（HTTP $status），请检查文件链接或稍后重试。';
  static String checkProgress(int done, int total) => '检查进度 $done / $total';
  static String checkSummary(
    bool cancelled,
    int done,
    int total,
    int failures,
  ) =>
      '${cancelled ? '已取消，' : ''}检查完成 $done / $total · $failures 个失败${done < total ? '，其余未检查' : ''}';
  static String initializedFailed(String message) => '初始化失败：$message';
  static String filterCount(int count) => '筛选 $count 项 · 清除筛选后可排序';
  static String version(String version, bool preferred) =>
      '版本 $version${preferred ? ' · 首选' : ''}';
  static String loadedCount(int count, bool complete) =>
      complete ? '已获取全部 $count 项' : '已获取 $count 项，尚未完整';
  static String songCount(int count) => '$count 首';
}

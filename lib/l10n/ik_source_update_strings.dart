abstract final class IkSourceUpdateStrings {
  static const invalidDirectory = '音源目录标识无效';
  static const upstreamSourceMissing = '上游没有该音源的 latest.js';
  static const invalidUpstreamPathEncoding = '上游音源链接不是有效UTF-8路径';
  static const invalidUpstreamLink = '上游音源链接必须指向同目录的单个JS文件';
  static const invalidUpstreamFile = '上游音源不是普通文件，或链接目标无效';
  static const downloadFailed = '音源下载失败，请稍后重试';
  static const invalidCommit = 'GitHub未返回可信主分支提交';
  static const invalidTreeId = 'GitHub未返回可信提交与目录标识';
  static const mismatchedTree = 'GitHub目录不完整或与提交不一致';
  static const invalidTree = 'GitHub目录结构无效';
  static const invalidBlobInfo = 'GitHub目录文件信息无效';
  static const unreadableMetadata = 'GitHub元数据无法解析';
  static const invalidMetadata = 'GitHub元数据结构无效';
  static const invalidFileSize = '音源文件为空或超过1MiB限制';
  static const integrityMismatch = '音源长度或Git blob哈希与上游目录不一致';
  static const invalidUpdateUrl = '音源更新只接受有效的HTTPS地址';
  static const oversizedResponse = '音源文件或元数据超过1MiB限制';
  static const invalidEncoding = '音源文件不是有效UTF-8';
  static const invalidScript = '下载内容不是有效音源脚本头部';
  static const downloadTimeout = '音源更新获取超过30秒，请稍后重试';
  static const networkUnavailable = '音源更新网络不可用，请稍后重试';
  static const downloadCancelled = '音源更新已取消';
  static const editDeferred = '音源正在编辑，自动更新已暂缓';
  static const autoUpdate = '自动更新音源';
  static const updateAvailable = '有更新';
  static const busy = '正在处理音源，请稍后再试';
  static const cancelledKeepCurrent = '已取消，原音源继续可用';
  static const noLocalUpdateUrl = '本地导入音源没有更新地址，可重新导入新版';
  static const rollbackHold = '已回退，自动更新暂停';
  static const checkingUpdates = '正在检查更新…';
  static const checking = '正在检查…';
  static const current = '已是最新';
  static const checkCancelled = '已取消检查';
  static const downloading = '正在获取更新…';
  static const inspecting = '正在检查新版音源…';
  static const noSupportedPlatform = '新版音源不支持当前音乐平台，已保留原版';
  static const draftReady = '新版已准备，保存后生效';
  static const cancelledKeepVersion = '已取消，保留原版';
  static const updated = '已更新';
  static const saved = '已保存；正在播放的歌曲继续播放';
  static const autoUpdateSaveFailed = '自动更新设置未保存，请重试';
  static const autoUpdateDeferred = '更新已暂缓，将在空闲时重新检查';
  static const updateFailed = '更新失败，请稍后重试；原音源继续可用';
  static const updateCancelled = '已取消更新';

  static String rateLimited(bool metadata, String? retryAt) {
    final retry = retryAt == null ? '，请稍后重试' : '，可在$retryAt后重试';
    return metadata ? 'GitHub匿名更新请求已达限额$retry' : '音源下载请求受到限流$retry';
  }

  static String httpFailure(int? status) => '音源更新请求失败（HTTP ${status ?? '未知'}）';

  static String autoUpdateHint(DateTime? checked) =>
      '每天检查一次，编辑音源或正在切歌时暂缓'
      '${checked == null ? '' : ' · 上次检查 ${checked.month}/${checked.day} ${checked.hour.toString().padLeft(2, '0')}:${checked.minute.toString().padLeft(2, '0')}'}';

  static String availableVersion(String version) =>
      '有更新${version.isEmpty ? '' : ' · $version'}';

  static String checkSummary(
    bool cancelled,
    int checked,
    int changed,
    int failed,
    int skipped,
  ) =>
      '${cancelled ? '已取消' : '检查完成'} · $checked 项已检查'
      ' · $changed 项有更新${failed > 0 ? ' · $failed 项失败' : ''}'
      '${skipped > 0 ? ' · $skipped 项不支持更新' : ''}';

  static String updating(String name, int index, int total) =>
      '正在更新 $name · $index/$total';

  static String updateSummary(
    bool cancelled,
    int updated,
    int unchanged,
    int failed,
    int skipped,
  ) =>
      '${cancelled ? '已取消' : '更新完成'} · $updated 项已准备'
      ' · $unchanged 项无需更新${failed > 0 ? ' · $failed 项失败，保留原版' : ''}'
      '${skipped > 0 ? ' · $skipped 项已跳过' : ''}'
      '${updated > 0 ? '；保存后生效' : ''}';
}

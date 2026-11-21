abstract final class IkAlignmentStrings {
  static const song = '歌曲';
  static const album = '专辑';
  static const source = '来源';
  static const duration = '时长';
  static const actions = '操作';
  static const unknownDuration = '—';
  static const folderUnavailable = '当前设备没有可以打开此下载目录的应用';
  static const noFilePath = '此任务尚无可打开的文件路径';
  static String searchResults(String query) => '“$query”的搜索结果';
  static String submission({
    required int added,
    required int existing,
    required int retried,
    required int failed,
  }) => [
    if (added > 0) '新增 $added 首',
    if (existing > 0) '已有 $existing 首',
    if (retried > 0) '已请求重试 $retried 首',
    if (failed > 0) '提交失败 $failed 首',
  ].join(' · ');
  static String listenedAt(DateTime time) {
    final local = time.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}/${two(local.month)}/${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }
}

class IkDownloadsAlignmentStrings {
  static const hint = '手动保存的音乐，都在这里';
  static const current = '进行中';
  static const completed = '已完成';
  static const failed = '失败';
  static const pauseAll = '暂停下载中';
  static const resumeAll = '继续已暂停';
  static const details = '查看详情';
  static const hideDetails = '收起详情';
  static const openFolder = '打开目录';
  static const play = '播放';
  static const source = '来源';
  static const quality = '下载音质';
  static const size = '文件大小';
  static const path = '文件位置';
  static const pathPending = '下载完成后显示文件位置';
  static const processing = '正在处理…';
  static const noCompleted = '还没有已完成的下载';
  static const noFailed = '没有下载失败的任务';
  static String group(String name, int count) => '$name · $count';
  static String operationFailed(Object error) => '操作未完成：$error';
  static String bytes(int value) => value < 1024
      ? '$value B'
      : value < 1024 * 1024
      ? '${(value / 1024).toStringAsFixed(1)} KB'
      : value < 1024 * 1024 * 1024
      ? '${(value / (1024 * 1024)).toStringAsFixed(1)} MB'
      : '${(value / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  static String transferred(int downloaded, int? total) => total == null
      ? bytes(downloaded)
      : '${bytes(downloaded)} / ${bytes(total)}';
}

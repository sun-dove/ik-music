class IkSpatialStrings {
  static const unsupported = '当前音频后端不支持耳机 3D';
  static const waiting = '等待音频处理';
  static const active = '耳机 3D 已生效';
  static String applyFailed(Object error) => '音效应用失败，已请求回滚：$error';
  static String processFailed(Object error) => '音效处理失败：$error';
}

abstract final class IkLocalLxStrings {
  static const storageBlocked = '当前音源存储不可写，迁移未启动';
  static const retryQueued = '已安排重试，保存音源草稿并离开音源设置后自动导入';
  static const retryExpired = '重试等待已结束，空闲后可再次重试';
  static const cancelled = '迁移已取消';
  static const busy = '音源正在编辑或更新，迁移已暂缓';
  static const opening = '正在读取本机LX音源…';
  static const noManifest = '没有本机LX音源迁移文件';
  static const waiting = '等待准备';
  static const removed = '已迁移后移除，不会自动恢复';
  static const waitForIdle = '音源正在编辑或更新，稍后可重试';
  static const preparing = '正在准备本地音源…';
  static const deferred = '迁移已暂缓，稍后可重试';
  static const oversizedFile = '音源文件过大';
  static const unreadableReceipt = '迁移记录无法读取';
  static const integrityMismatch = '本地音源完整性不匹配';
  static const invalidEncoding = '音源不是UTF-8';
  static const unsupportedPlatform = '音源不支持当前平台';
  static const conflictingSource = '本地音源身份冲突';
  static const inspectCancelled = '初始化已取消';
  static const inspectTimeout = '初始化超过5秒';
  static const inspectFailed = '初始化失败';
  static const invalidManifest = '迁移清单无效';
  static const invalidPath = '迁移文件路径无效';
  static const importedPreferred = '已导入并设为首选';
  static const importedKeepPolicy = '已导入，原播放策略保留';
  static const imported = '本机 LX 导入';
  static const title = '来自本机 LX 的音源';
  static const loading = '正在读取…';
  static const retryFailed = '重试未导入的音源';

  static String sourceTitle(String name, String version, bool selected) =>
      '$name · $version${selected ? ' · LX 当前选择' : ''}';

  static String existing(String name, bool enabled) =>
      '已在列表中（$name）${enabled ? '，保留现有设置' : '，当前已停用'}';

  static String failed(String message, bool recorded) =>
      '$message${recorded ? '' : '；状态暂未保存'}';

  static String summary(
    int imported,
    int existing,
    int failed,
    int deferred,
    int removed,
  ) =>
      '本机LX音源 · $imported 项已导入 · $existing 项已有'
      '${failed > 0 ? ' · $failed 项失败，可重试' : ''}'
      '${deferred > 0 ? ' · $deferred 项暂缓' : ''}'
      '${removed > 0 ? ' · $removed 项已移除' : ''}';

  static String prepared(String? existingName, bool preferred) =>
      existingName != null
      ? '已在列表中（$existingName）${preferred ? '，已设为首选' : '，保留原设置'}'
      : preferred
      ? importedPreferred
      : importedKeepPolicy;

  static String failure(String? code) => switch (code) {
    'timeout' => '初始化超过5秒，未启用；可重试',
    'platform' || 'unsupported' => '当前运行时不支持此音源，未启用',
    'integrity' => '本地音源长度或哈希不匹配，未启用',
    'path' => '音源文件缺失或路径不安全，未启用',
    'size' => '音源大小超过限制，未启用',
    'invalidEncoding' => '音源不是有效UTF-8，未启用',
    'metadata' => '迁移清单或音源头部无效，未启用',
    'receipt' => '迁移记录无法读取，已停止导入以保留现有设置',
    'storage' => '迁移保存失败，已有音源保留；可重试',
    'network' || 'download' || 'rateLimited' => '初始化网络请求失败，未启用；可重试',
    _ => '音源初始化失败，未启用；请检查兼容性或激活要求',
  };
}

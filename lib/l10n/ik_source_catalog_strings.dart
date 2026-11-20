import '../video_app/built_in/catalog_coordinator.dart';

abstract final class IkSourceCatalogStrings {
  static const invalidEntry = '固定音源目录条目无效';
  static const invalidCatalog = '固定音源目录版本不支持';
  static const invalidCatalogBudget = '固定音源目录重复或超过容量';
  static const rollbackAction = '恢复上一个已确认版本';
  static const saveFailed = '保存失败，已有音源保持不变，请稍后重试';
  static const olderCatalog = '当前目录早于已保存版本，自动准备已暂停，已有音源保留';
  static const removed = '你已移除此项，自动更新不会恢复';
  static const disabled = '你已停用此项，自动更新不会开启';
  static const pending = '已准备，下一次播放或重启后生效';
  static const ready = '本机初始化通过；不代表每首歌曲均可播放';
  static const waiting = '等待自动准备';
  static const cacheWaiting = '已保留缓存，等待本机重新校验';
  static const networkWaiting = '等待联网，已保存音源仍保留';
  static const integrityUpdate = '文件与固定版本不符，未执行；等待应用目录更新';
  static const invalidEncoding = '固定文件不是有效 UTF-8，未执行';
  static const rateLimited = '来源请求受限，请稍后手动重试';
  static const initializationTimeout = '初始化或获取超时，可稍后重试';
  static const platformUnsupported = '未声明当前支持平台';
  static const retryLast = '上次准备失败，可展开后重试';
  static const catalogSaveFailed = '目录保存失败，已有音源保留；请稍后重试';
  static const checkingCache = '正在校验已保存脚本的本机能力';
  static const noPlatform = '没有当前支持的平台';
  static const fetching = '正在获取固定版本';
  static const checking = '哈希校验通过，正在受限初始化';
  static const prepareFailed = '准备失败，已有版本保留';
  static const saveRetry = '目录保存失败，请稍后重试';
  static const pendingIntegrity = '待生效版本校验失败，未发布';
  static const totalBudget = '音源总内容超过 8 MiB，保留已有配置';
  static const cancelledRetry = '已取消，可稍后重试';
  static const stateUnsupported = '受管目录版本不支持';
  static const newerState = '目录状态来自更高版本，自动准备已暂停，已有音源保留';
  static const damagedState = '目录状态损坏，已暂停自动写入；已有音源和用户数据保留';
  static const cancelled = '已取消准备';
  static const fileBudget = '文件超过 1 MiB 限制';
  static const networkRetry = '等待联网后重试';
  static const integrity = '文件与固定版本不符，未执行';
  static const networkUnavailable = '网络不可达，已保存的音源仍保留';
  static const notScript = '返回内容不是音源脚本';
  static const supportedPlatforms = '未声明 QQ、网易云或酷狗的可用平台';
  static const prepareTimeout = '准备超时，请稍后重试';
  static const title = '内置音源';
  static const description =
      '自动获取固定版本并在本机受限初始化，无需复制链接。初始化可能访问来源服务；通过检查不代表每首歌曲都能播放。';
  static const autoPrepare = '自动准备内置音源';
  static const check = '检查当前目录';
  static const retry = '重试失败项';
  static const cancel = '取消准备';
  static const manage = '管理顺序、开关与自定义音源';
  static const missing = '此入口未启用自动准备，已有手动音源不受影响';
  static const restoreAction = '恢复此内置音源';
  static const enablePolicy = '开启已准备音源的自动尝试';
  static const enablePolicyHttp = '开启自动尝试并停用旧 HTTP 音源';
  static const keptPolicy = '已保留你原来的播放策略。可在管理页调整，或明确开启已准备音源的自动尝试。';
  static String retrySource(String name) => '重试 $name';
  static String fixedVersion(String path, String hash) =>
      '固定版本：$path\nSHA-256：$hash';
  static String fetchStatus(int? status) => '获取固定文件失败（HTTP ${status ?? '未知'}）';
  static String rolledBack(String version) => '已恢复 $version，不会自动升回';
  static String progress(int ready, int pending, int total) =>
      '本机已准备 $ready / $total 项${pending == 0 ? '' : '，$pending 项待安全生效'}';
  static String stage(IkSourceStage stage) => switch (stage) {
    IkSourceStage.waitingNetwork => '等待联网 / 校验',
    IkSourceStage.downloading => '正在获取',
    IkSourceStage.checking => '正在初始化',
    IkSourceStage.ready => '本机已准备',
    IkSourceStage.pendingApply => '等待安全生效',
    IkSourceStage.unsupported => '暂不支持',
    IkSourceStage.restricted => '使用范围受限',
    IkSourceStage.failed => '准备失败',
    IkSourceStage.disabled => '已停用',
    IkSourceStage.removed => '已移除',
    IkSourceStage.cancelled => '已取消',
    IkSourceStage.rolledBack => '已回滚',
  };
}

/// ik 运行时状态与恢复流程文案。
abstract final class IkRuntimeStrings {
  static const audioApplying = '正在应用均衡器…';
  static const audioApplied = '均衡器设置已应用';
  static const audioApplyFailed = '均衡器未生效，请重试';
  static const audioUnsupported = '当前播放后端不支持均衡器';
  static const retry = '重试';
  static const desktopUnavailable = '桌面控制连接失败，可重试连接';
  static const desktopPartial = '部分桌面能力暂不可用';
  static const desktopReady = '托盘和系统媒体控制已连接';
  static const floatingFailed = '桌面歌词未开启，请检查权限后重试';
  static const floatingRetry = '重试桌面歌词';
  static const restoreRestart = '设置已恢复，重新启动应用后全部生效';
  static String backupRecovered(String path) => '导入失败，已恢复导入前的数据。恢复备份：$path';
  static String backupRecoveryFailed(String path) =>
      '导入未完成，自动恢复也失败。请保留并重新导入恢复备份：$path';
  static const backupSnapshotFailed = '无法创建导入前的恢复备份，未开始导入';
}

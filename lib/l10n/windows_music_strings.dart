import '../video_app/windows/windows_music_preferences.dart';
import '../models/audio_quality.dart';
import '../video_app/ik/ik_version.dart';

/// ik Windows 界面的中文资源。
abstract final class WindowsMusicStrings {
  static const brandShortName = IkVersion.name;
  static const playQuality = '播放音质';
  static const downloadQuality = '下载音质';
  static const keepLegacyQuality = '沿用原设置';
  static const highest = '优先最高可用';
  static const balanced = '智能均衡';
  static const balancedHint = '按歌曲和音源动态选择起播音质，只影响下一首';
  static const qualityHint = '实际可用档位取决于歌曲、平台与音源';
  static const appearance = '个性化设置';
  static const background = '更换背景';
  static const defaultBackground = '默认背景';
  static const chooseImage = '选择背景图片';
  static const backgroundPreview = '预览背景';
  static const soften = '背景柔化';
  static const font = '更换字体';
  static const defaultFont = '默认字体';
  static const yaHeiAlias = '微软雅黑';
  static const fontPreview = '字体预览';
  static const fontSample =
      '${IkVersion.name} · 让声音流动\n在旋律里，遇见此刻。Aa 0123456789';
  static const importFont = '导入 TTF / OTF 字体';
  static const refreshFonts = '刷新本机字体';
  static const fontHint = '可选择本机字体，或导入有使用权的字体文件';
  static const restoreDefault = '恢复默认';
  static const apply = '应用';
  static const cancel = '取消';
  static const applied = '已应用';
  static const closeWindow = '关闭主窗口时';
  static const minimize = '最小化并继续播放';
  static const exit = '退出应用';
  static const minimizeHint = '窗口最小化到任务栏，可点击任务栏图标恢复';
  static const exitHint = '关闭主窗口时结束播放并退出应用';
  static const windowSettings = '窗口设置';
  static const returnToLyrics = '回到当前歌词';
  static const plainLyrics = '纯文本歌词';
  static const back = '返回';
  static const brandPronunciation = IkVersion.name;
  static const savedBackground = '已保存的背景';
  static const importedFont = '导入字体';
  static const retryChangedQuality = '已按当前下载音质重新提交';
  static String qualityName(AudioLevel level) => switch (level) {
    AudioLevel.high => '高品质',
    AudioLevel.master => '母带（平台支持时）',
    _ => level.displayName,
  };

  static String failure(DesktopFailure kind) => switch (kind) {
    DesktopFailure.invalidImage => '图片无法解码，请选择 PNG、JPEG 或 WebP；当前背景保留',
    DesktopFailure.invalidFont => '字体无法加载，请选择有效的 TTF / OTF；当前字体保留',
    DesktopFailure.fileMissing => '保存的文件或字体已不可用，已回退默认，可重新选择',
    DesktopFailure.readFailed => '无法读取配置或文件，已沿用原设置，请重试',
    DesktopFailure.saveFailed => '保存失败，当前设置保留，请检查目录权限后重试',
    DesktopFailure.nativeUnavailable => 'Windows 控制暂不可用，请重试；相关选项暂时禁用',
  };
}

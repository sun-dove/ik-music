import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../l10n/windows_music_strings.dart';
import '../../models/audio_quality.dart';
import '../../models/platform_type.dart';
import '../multi_source/source_collection.dart';
import '../video_preferences.dart';

enum WindowsCloseAction { minimize, exit }

enum DesktopFailure {
  invalidImage,
  invalidFont,
  fileMissing,
  readFailed,
  saveFailed,
  nativeUnavailable,
}

class DesktopConfigurationException implements Exception {
  const DesktopConfigurationException(this.kind);
  final DesktopFailure kind;
  @override
  String toString() => WindowsMusicStrings.failure(kind);
}

@immutable
class BackgroundSelection {
  const BackgroundSelection({required this.file, this.soften = 8});
  final String file;
  final double soften;
  Map<String, dynamic> toJson() => {'file': file, 'soften': soften};
  factory BackgroundSelection.fromJson(Map<String, dynamic> json) =>
      BackgroundSelection(
        file: json['file'] as String,
        soften: (json['soften'] as num? ?? 8).toDouble().clamp(0, 20),
      );
}

@immutable
class FontSelection {
  const FontSelection({required this.family, this.file, this.label});
  final String family;
  final String? file, label;
  Map<String, dynamic> toJson() => {
    'family': family,
    if (file != null) 'file': file,
    if (label != null) 'label': label,
  };
  factory FontSelection.fromJson(Map<String, dynamic> json) => FontSelection(
    family: json['family'] as String,
    file: json['file'] as String?,
    label: json['label'] as String?,
  );
}

@immutable
class WindowsMusicConfiguration {
  const WindowsMusicConfiguration({
    this.playQuality,
    this.downloadQuality,
    this.background,
    this.font,
    this.closeAction,
  });
  final AudioLevel? playQuality, downloadQuality;
  final BackgroundSelection? background;
  final FontSelection? font;
  final WindowsCloseAction? closeAction;
  WindowsMusicConfiguration copyWith({
    AudioLevel? playQuality,
    AudioLevel? downloadQuality,
    BackgroundSelection? background,
    FontSelection? font,
    WindowsCloseAction? closeAction,
    bool clearBackground = false,
    bool clearFont = false,
  }) => WindowsMusicConfiguration(
    playQuality: playQuality ?? this.playQuality,
    downloadQuality: downloadQuality ?? this.downloadQuality,
    background: clearBackground ? null : background ?? this.background,
    font: clearFont ? null : font ?? this.font,
    closeAction: closeAction ?? this.closeAction,
  );
  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    if (playQuality != null) 'playQuality': playQuality!.name,
    if (downloadQuality != null) 'downloadQuality': downloadQuality!.name,
    if (background != null) 'background': background!.toJson(),
    if (font != null) 'font': font!.toJson(),
    if (closeAction != null) 'closeAction': closeAction!.name,
  };
  factory WindowsMusicConfiguration.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1) throw const FormatException();
    return WindowsMusicConfiguration(
      playQuality: AudioLevel.values
          .where((e) => e.name == json['playQuality'])
          .firstOrNull,
      downloadQuality: AudioLevel.values
          .where((e) => e.name == json['downloadQuality'])
          .firstOrNull,
      background: json['background'] == null
          ? null
          : BackgroundSelection.fromJson(
              Map<String, dynamic>.from(json['background'] as Map),
            ),
      font: json['font'] == null
          ? null
          : FontSelection.fromJson(
              Map<String, dynamic>.from(json['font'] as Map),
            ),
      closeAction: WindowsCloseAction.values
          .where((e) => e.name == json['closeAction'])
          .firstOrNull,
    );
  }
}

/// 只新增 Windows 事务通知入口；SourceSettings 原方法保持。
class WindowsSourceSettings extends SourceSettings {
  WindowsSourceSettings(super.preferences);
  void publishSavedQuality(SourceCollection next) {
    value = next;
    loadError = null;
    notifyListeners();
  }
}

/// 同一个新读取器覆盖路由、下载、重试和缓存；不改旧平台键。
class WindowsMusicPreferences extends ChangeNotifier {
  WindowsMusicPreferences(
    this.legacy, {
    this.sources,
    Future<void> Function(Map<dynamic, dynamic>)? write,
  }) : _write = write ?? legacy.box.putAll;
  static const key = 'video.windows.appearance.v1';
  final VideoPreferences legacy;
  final WindowsSourceSettings? sources;
  final Future<void> Function(Map<dynamic, dynamic>) _write;
  WindowsMusicConfiguration _value = const WindowsMusicConfiguration();
  WindowsMusicConfiguration get value => _value;
  DesktopFailure? loadError;
  WindowsCloseAction get closeAction =>
      value.closeAction ?? WindowsCloseAction.minimize;

  void load() {
    final raw = legacy.box.get(key);
    if (raw == null) return;
    try {
      _value = WindowsMusicConfiguration.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw as String) as Map),
      );
      loadError = null;
    } catch (_) {
      _value = const WindowsMusicConfiguration();
      loadError = DesktopFailure.readFailed;
    }
  }

  AudioLevel quality(PlatformType platform, {bool download = false}) =>
      (download ? value.downloadQuality : value.playQuality) ??
      legacy.quality(platform, download: download);
  String qualityLabel({bool download = false}) {
    if (!download && sources?.value.highestQuality == true) {
      return WindowsMusicStrings.highest;
    }
    final levels = [
      PlatformType.qq,
      PlatformType.netease,
      PlatformType.kugou,
    ].map((platform) => quality(platform, download: download)).toSet();
    if (levels.length != 1) return WindowsMusicStrings.keepLegacyQuality;
    return qualityName(levels.single);
  }

  @protected
  Map<dynamic, dynamic> qualityPolicyWrites(bool sourceQualityChanged) =>
      const {};

  @protected
  void qualityPolicyWriteCommitted(bool sourceQualityChanged) {}

  static String qualityName(AudioLevel level) =>
      WindowsMusicStrings.qualityName(level);
  Future<void> setQuality(
    AudioLevel? level, {
    bool download = false,
    bool highest = false,
  }) async {
    final next = value.copyWith(
      playQuality: download ? null : level,
      downloadQuality: download ? level : null,
    );
    final nextSources = !download && sources != null
        ? sources!.value.copyWith(highestQuality: highest)
        : null;
    await _commit(next, nextSources: nextSources);
  }

  Future<void> update(WindowsMusicConfiguration next) => _commit(next);
  Future<void> _commit(
    WindowsMusicConfiguration next, {
    SourceCollection? nextSources,
  }) async {
    try {
      // Hive 一次写入两项配置，失败前不发布内存状态，不需要二次回滚写入。
      await _write({
        key: jsonEncode(next.toJson()),
        if (nextSources != null)
          SourceSettings.key: jsonEncode(nextSources.toJson()),
        ...qualityPolicyWrites(nextSources != null),
      });
    } catch (_) {
      throw const DesktopConfigurationException(DesktopFailure.saveFailed);
    }
    _value = next;
    qualityPolicyWriteCommitted(nextSources != null);
    if (nextSources != null) sources!.publishSavedQuality(nextSources);
    loadError = null;
    notifyListeners();
  }
}

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

@immutable
class IkPlayerLyricsStyle {
  const IkPlayerLyricsStyle({
    this.fontFamily,
    this.fontSize,
    this.backgroundColor,
    this.currentLineColor,
    this.otherLineColor,
    this.shadowOpacity = 0,
  });

  final String? fontFamily;
  final double? fontSize;
  final Color? backgroundColor, currentLineColor, otherLineColor;
  final double shadowOpacity;

  IkPlayerLyricsStyle copyWith({
    String? fontFamily,
    bool clearFont = false,
    double? fontSize,
    Color? backgroundColor,
    Color? currentLineColor,
    Color? otherLineColor,
    double? shadowOpacity,
  }) => IkPlayerLyricsStyle(
    fontFamily: clearFont ? null : fontFamily ?? this.fontFamily,
    fontSize: fontSize ?? this.fontSize,
    backgroundColor: backgroundColor ?? this.backgroundColor,
    currentLineColor: currentLineColor ?? this.currentLineColor,
    otherLineColor: otherLineColor ?? this.otherLineColor,
    shadowOpacity: shadowOpacity ?? this.shadowOpacity,
  );

  Map<String, Object?> toJson() => {
    if (fontFamily != null) 'fontFamily': fontFamily,
    if (fontSize != null) 'fontSize': fontSize,
    if (backgroundColor != null) 'backgroundColor': backgroundColor!.toARGB32(),
    if (currentLineColor != null)
      'currentLineColor': currentLineColor!.toARGB32(),
    if (otherLineColor != null) 'otherLineColor': otherLineColor!.toARGB32(),
    'shadowOpacity': shadowOpacity,
  };

  factory IkPlayerLyricsStyle.fromJson(Map<dynamic, dynamic> json) =>
      IkPlayerLyricsStyle(
        fontFamily: json['fontFamily'] as String?,
        fontSize: (json['fontSize'] as num?)?.toDouble().clamp(14, 48),
        backgroundColor: json['backgroundColor'] is int
            ? Color(json['backgroundColor'] as int)
            : null,
        currentLineColor: json['currentLineColor'] is int
            ? Color(json['currentLineColor'] as int)
            : null,
        otherLineColor: json['otherLineColor'] is int
            ? Color(json['otherLineColor'] as int)
            : null,
        shadowOpacity:
            (json['shadowOpacity'] as num?)?.toDouble().clamp(0, 1) ?? 0,
      );
}

/// 新播放器专用，不写旧全局外观或桌面歌词设置。
class IkPlayerLyricsPreferences extends ChangeNotifier {
  IkPlayerLyricsPreferences(this.box) {
    final raw = box.get(key);
    if (raw is Map) {
      try {
        _value = IkPlayerLyricsStyle.fromJson(raw);
      } on Object {
        loadFailed = true;
      }
    }
  }

  static const key = 'ik.player.lyrics.style.v1';
  final Box box;
  IkPlayerLyricsStyle _value = const IkPlayerLyricsStyle();
  IkPlayerLyricsStyle get value => _value;
  bool loadFailed = false;

  Future<void> save(IkPlayerLyricsStyle next) async {
    await box.put(key, next.toJson());
    _value = next;
    loadFailed = false;
    notifyListeners();
  }

  Future<void> reset() async {
    await box.delete(key);
    _value = const IkPlayerLyricsStyle();
    loadFailed = false;
    notifyListeners();
  }
}

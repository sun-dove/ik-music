import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/platform/platform_utils.dart';
import '../../features/floating_lyrics/data/floating_lyrics_models.dart';
import '../../features/floating_lyrics/data/floating_lyrics_service.dart';
import '../../features/floating_lyrics/presentation/providers/floating_lyrics_provider.dart';

/// 只由 IK Windows 入口开启；偏好本身不改变旧入口的呈现。
final ikCompactLyricsEnabledProvider = Provider<bool>((ref) => false);
final ikDesktopLyricsStyleDeliveryFailedProvider = StateProvider<bool>(
  (ref) => false,
);

final ikDesktopLyricsStyleProvider =
    StateNotifierProvider<IkDesktopLyricsStyleNotifier, IkDesktopLyricsStyle>(
      (ref) => IkDesktopLyricsStyleNotifier(),
    );

@immutable
class IkDesktopLyricsStyle {
  const IkDesktopLyricsStyle({
    this.fontFamily,
    this.fontSize,
    this.backgroundColor,
    this.backgroundOpacity,
    this.currentLineColor,
    this.otherLineColor,
    this.shadowOpacity,
  });

  final String? fontFamily;
  final double? fontSize;
  final Color? backgroundColor;
  final double? backgroundOpacity;
  final Color? currentLineColor;
  final Color? otherLineColor;
  final double? shadowOpacity;

  IkResolvedDesktopLyricsStyle resolve(FloatingLyricsSettings settings) {
    return IkResolvedDesktopLyricsStyle(
      fontFamily: fontFamily ?? 'Microsoft YaHei UI',
      fontSize: fontSize ?? settings.fontSize,
      backgroundColor: backgroundColor ?? settings.backgroundColor,
      backgroundOpacity:
          backgroundOpacity ?? (backgroundColor ?? settings.backgroundColor).a,
      currentLineColor: currentLineColor ?? settings.highlightColor,
      otherLineColor: otherLineColor ?? settings.textColor,
      shadowOpacity: shadowOpacity ?? settings.shadowOpacity,
    );
  }

  IkDesktopLyricsStyle copyWith({
    String? fontFamily,
    double? fontSize,
    Color? backgroundColor,
    double? backgroundOpacity,
    Color? currentLineColor,
    Color? otherLineColor,
    double? shadowOpacity,
  }) => IkDesktopLyricsStyle(
    fontFamily: fontFamily ?? this.fontFamily,
    fontSize: fontSize ?? this.fontSize,
    backgroundColor: backgroundColor ?? this.backgroundColor,
    backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
    currentLineColor: currentLineColor ?? this.currentLineColor,
    otherLineColor: otherLineColor ?? this.otherLineColor,
    shadowOpacity: shadowOpacity ?? this.shadowOpacity,
  );

  Map<String, Object?> toJson() => {
    if (fontFamily != null) 'fontFamily': fontFamily,
    if (fontSize != null) 'fontSize': fontSize,
    if (backgroundColor != null) 'backgroundColor': backgroundColor!.toARGB32(),
    if (backgroundOpacity != null) 'backgroundOpacity': backgroundOpacity,
    if (currentLineColor != null)
      'currentLineColor': currentLineColor!.toARGB32(),
    if (otherLineColor != null) 'otherLineColor': otherLineColor!.toARGB32(),
    if (shadowOpacity != null) 'shadowOpacity': shadowOpacity,
  };

  factory IkDesktopLyricsStyle.fromJson(Map<dynamic, dynamic> value) =>
      IkDesktopLyricsStyle(
        fontFamily: value['fontFamily'] as String?,
        fontSize: (value['fontSize'] as num?)?.toDouble(),
        backgroundColor: value['backgroundColor'] is num
            ? Color((value['backgroundColor'] as num).toInt())
            : null,
        backgroundOpacity: (value['backgroundOpacity'] as num?)?.toDouble(),
        currentLineColor: value['currentLineColor'] is num
            ? Color((value['currentLineColor'] as num).toInt())
            : null,
        otherLineColor: value['otherLineColor'] is num
            ? Color((value['otherLineColor'] as num).toInt())
            : null,
        shadowOpacity: (value['shadowOpacity'] as num?)?.toDouble(),
      );

  Map<String, Object?> presentation(FloatingLyricsSettings settings) {
    final value = resolve(settings);
    return {
      'version': 1,
      'style': 'compact',
      'fontFamily': value.fontFamily,
      'fontSize': value.fontSize,
      'backgroundColor': value.backgroundColor
          .withValues(alpha: value.backgroundOpacity.clamp(0.0, 1.0))
          .toARGB32(),
      'currentLineColor': value.currentLineColor.toARGB32(),
      'otherLineColor': value.otherLineColor.toARGB32(),
      'shadowOpacity': value.shadowOpacity,
      'currentLineColorExplicit': currentLineColor != null,
    };
  }
}

@immutable
class IkResolvedDesktopLyricsStyle {
  const IkResolvedDesktopLyricsStyle({
    required this.fontFamily,
    required this.fontSize,
    required this.backgroundColor,
    required this.backgroundOpacity,
    required this.currentLineColor,
    required this.otherLineColor,
    required this.shadowOpacity,
  });
  final String fontFamily;
  final double fontSize;
  final Color backgroundColor;
  final double backgroundOpacity;
  final Color currentLineColor;
  final Color otherLineColor;
  final double shadowOpacity;
}

class IkDesktopLyricsStyleNotifier extends StateNotifier<IkDesktopLyricsStyle> {
  IkDesktopLyricsStyleNotifier() : super(_load());
  static const _key = 'ik_windows_desktop_lyrics_style_v1';
  Future<void> _tail = Future.value();

  static IkDesktopLyricsStyle _load() {
    if (!Hive.isBoxOpen('settings')) return const IkDesktopLyricsStyle();
    final raw = Hive.box('settings').get(_key);
    return raw is Map
        ? IkDesktopLyricsStyle.fromJson(raw)
        : const IkDesktopLyricsStyle();
  }

  Future<void> _commit(
    IkDesktopLyricsStyle Function(IkDesktopLyricsStyle) update,
  ) {
    final operation = _tail.then((_) async {
      final next = update(state);
      final box = await Hive.openBox('settings');
      await box.put(_key, next.toJson());
      if (mounted) state = next;
    });
    _tail = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> setFontFamily(String value) =>
      _commit((s) => s.copyWith(fontFamily: value.trim()));
  Future<void> setFontSize(double value) =>
      _commit((s) => s.copyWith(fontSize: value.clamp(14.0, 48.0)));
  Future<void> setBackgroundColor(Color value) =>
      _commit((s) => s.copyWith(backgroundColor: value));
  Future<void> setBackgroundOpacity(double value) =>
      _commit((s) => s.copyWith(backgroundOpacity: value.clamp(0.0, 1.0)));
  Future<void> setCurrentLineColor(Color value) =>
      _commit((s) => s.copyWith(currentLineColor: value));
  Future<void> setOtherLineColor(Color value) =>
      _commit((s) => s.copyWith(otherLineColor: value));
  Future<void> setShadowOpacity(double value) =>
      _commit((s) => s.copyWith(shadowOpacity: value.clamp(0.0, 1.0)));

  Future<void> reset() {
    final operation = _tail.then((_) async {
      final box = await Hive.openBox('settings');
      await box.delete(_key);
      if (mounted) state = const IkDesktopLyricsStyle();
    });
    _tail = operation.catchError((Object _) {});
    return operation;
  }
}

final ikFloatingLyricsServiceProvider = Provider<FloatingLyricsService>((ref) {
  if (!PlatformUtils.isWindows || !ref.watch(ikCompactLyricsEnabledProvider)) {
    return FloatingLyricsService.instance;
  }
  FloatingLyricsPayload? latestPayload;
  var active = true;
  var deliveryGeneration = 0;
  final service = FloatingLyricsService.withPayloadAdapter((payload, settings) {
    latestPayload = payload;
    return {
      ...payload.toJson(settings),
      'windowsPresentation': ref
          .read(ikDesktopLyricsStyleProvider)
          .presentation(settings),
    };
  });
  final closeSubscription = service.closedByUserStream.listen((_) {
    latestPayload = null;
    deliveryGeneration++;
  });
  ref.listen<IkDesktopLyricsStyle>(ikDesktopLyricsStyleProvider, (_, next) {
    final payload = latestPayload;
    final settings = ref.read(floatingLyricsProvider);
    if (payload == null || !settings.enabled) return;
    final generation = ++deliveryGeneration;
    unawaited(() async {
      var delivered = false;
      try {
        delivered = await service.update(payload, settings);
      } catch (_) {
        delivered = false;
      }
      if (active && generation == deliveryGeneration) {
        ref.read(ikDesktopLyricsStyleDeliveryFailedProvider.notifier).state =
            !delivered;
      }
    }());
  });
  ref.onDispose(() {
    active = false;
    unawaited(closeSubscription.cancel());
  });
  return service;
});

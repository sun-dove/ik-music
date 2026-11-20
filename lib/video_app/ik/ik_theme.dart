import 'package:flutter/material.dart';

import '../ui/video_theme.dart';
export '../ui/video_theme.dart' show IkThemeColors;

abstract final class IkTheme {
  static const accent = Color(0xff087f83);
  static const navy = Color(0xff0b2a6b);
  static const icon = 'assets/branding/dj-music/source/windows/yangyin-256.png';

  static ThemeData from(ThemeData base) {
    final dark = base.brightness == Brightness.dark;
    final background = dark ? const Color(0xff0d1b26) : const Color(0xfff3f7f7);
    final surface = dark ? const Color(0xff172a37) : Colors.white;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: base.brightness,
        ).copyWith(
          surface: surface,
          primary: dark ? const Color(0xff60d8cc) : accent,
        );
    final hasBackground =
        base.extension<WindowsAppearanceTheme>()?.hasBackground ?? false;
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: hasBackground ? Colors.transparent : background,
      textTheme: base.textTheme.copyWith(
        bodySmall: base.textTheme.bodySmall?.copyWith(
          fontSize: 12,
          height: 1.5,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          fontSize: 15,
          height: 1.45,
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 17),
        labelSmall: base.textTheme.labelSmall?.copyWith(fontSize: 12),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontSize: 24,
          fontWeight: FontWeight.w600,
        ),
      ),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: hasBackground ? Colors.transparent : background,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: hasBackground
            ? surface.withValues(alpha: .86)
            : surface,
        indicatorColor: scheme.primaryContainer,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: hasBackground
            ? surface.withValues(alpha: .86)
            : surface,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: scheme.primary,
        selectionColor: scheme.primary.withValues(alpha: .2),
        selectionHandleColor: scheme.primary,
      ),
      extensions: [
        ...base.extensions.values,
        IkThemeColors(
          background: background,
          surface: surface,
          hasBackground: hasBackground,
        ),
      ],
    );
  }
}

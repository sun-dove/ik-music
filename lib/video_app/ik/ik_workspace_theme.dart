import 'package:flutter/material.dart';

import 'ik_theme.dart';

abstract final class IkWorkspaceTheme {
  static ThemeData from(ThemeData original) {
    final base = IkTheme.from(original);
    final dark = base.brightness == Brightness.dark;
    final palette = base.extension<IkThemeColors>()!;
    final background = dark ? const Color(0xff17211f) : const Color(0xfff5f6f7);
    final surface = dark ? const Color(0xff202e2a) : Colors.white;
    final scheme = base.colorScheme.copyWith(
      surface: surface,
      primary: dark ? const Color(0xff7bd9bb) : const Color(0xff168579),
      onSurface: dark ? const Color(0xffe4ece8) : const Color(0xff20292e),
      onSurfaceVariant: dark
          ? const Color(0xffa1b4ad)
          : const Color(0xff748087),
      outlineVariant: dark ? const Color(0xff30423c) : const Color(0xffe8ecee),
    );
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.hasBackground
          ? Colors.transparent
          : background,
      textTheme: base.textTheme.copyWith(
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          fontSize: 14,
          height: 1.5,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(fontSize: 24),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          fontSize: 28,
          fontWeight: FontWeight.w600,
        ),
      ),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: palette.hasBackground
            ? Colors.transparent
            : background,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        constraints: const BoxConstraints(maxWidth: 520),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        textStyle: TextStyle(fontSize: 13, color: scheme.onSurface),
        elevation: 8,
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: surface,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      extensions: [
        ...base.extensions.values.where((value) => value is! IkThemeColors),
        IkThemeColors(
          background: background,
          surface: surface,
          hasBackground: palette.hasBackground,
        ),
      ],
    );
  }
}

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../l10n/windows_music_strings.dart';
import '../ui/video_theme.dart';
import 'windows_music_preferences.dart';
import 'windows_window_controller.dart';

class BackgroundDraft {
  const BackgroundDraft(this.bytes, this.extension);
  final Uint8List bytes;
  final String extension;
}

class FontDraft {
  const FontDraft(this.bytes, this.selection, this.extension);
  final Uint8List bytes;
  final FontSelection selection;
  final String extension;
}

/// 图片与字体先在内存验证，确认后才写入独立目录。
class WindowsAppearance extends ChangeNotifier {
  WindowsAppearance({
    required this.preferences,
    required this.directory,
    this.window = const WindowsWindowController(),
  }) {
    preferences.addListener(_preferencesChanged);
  }
  final WindowsMusicPreferences preferences;
  final Directory directory;
  final WindowsWindowController window;
  List<String> fonts = const [];
  File? backgroundFile;
  String? _fontFamily;
  DesktopFailure? backgroundError, fontError, nativeError;
  bool nativeAvailable = false;
  bool _disposed = false;
  String get defaultFontFamily => fonts.contains('Microsoft YaHei UI')
      ? 'Microsoft YaHei UI'
      : fonts.contains(WindowsMusicStrings.yaHeiAlias)
      ? WindowsMusicStrings.yaHeiAlias
      : 'Microsoft YaHei UI';
  String get fontFamily => _fontFamily ?? defaultFontFamily;
  String get fontLabel =>
      preferences.value.font?.label ??
      preferences.value.font?.family ??
      WindowsMusicStrings.defaultFont;
  String get currentFontLabel =>
      fontError == null ? fontLabel : WindowsMusicStrings.defaultFont;
  static Color backgroundOverlay(Brightness brightness) =>
      (brightness == Brightness.dark
              ? const Color(0xFF17171C)
              : const Color(0xFFF6F3F8))
          .withValues(alpha: brightness == Brightness.dark ? .80 : .82);
  void _preferencesChanged() => notifyListeners();

  Future<void> initialize() async {
    window.connect();
    try {
      await window.setCloseAction(preferences.closeAction);
      nativeAvailable = true;
      nativeError = null;
    } on DesktopConfigurationException catch (error) {
      nativeError = error.kind;
      nativeAvailable = false;
    }
    await refreshFonts();
    backgroundFile = null;
    backgroundError = null;
    final background = preferences.value.background;
    if (background != null) {
      try {
        final file = _asset(background.file);
        if (!await file.exists()) {
          throw const DesktopConfigurationException(DesktopFailure.fileMissing);
        }
        await prepareBackground(file);
        backgroundFile = file;
      } on DesktopConfigurationException catch (error) {
        backgroundError = error.kind;
      }
    }
    final font = preferences.value.font;
    if (font?.file != null) {
      try {
        final file = _asset(font!.file!);
        if (!await file.exists()) {
          throw const DesktopConfigurationException(DesktopFailure.fileMissing);
        }
        await _loadFont(await _read(file), font.family);
        _fontFamily = font.family;
        fontError = null;
      } on DesktopConfigurationException catch (error) {
        _fontFamily = null;
        fontError = error.kind;
      }
    }
    notifyListeners();
  }

  Future<void> refreshFonts() async {
    try {
      fonts = await window.listFonts();
      final selected = preferences.value.font;
      if (selected?.file == null) {
        _fontFamily = selected != null && fonts.contains(selected.family)
            ? selected.family
            : null;
        fontError = selected != null && _fontFamily == null
            ? DesktopFailure.fileMissing
            : null;
      }
    } on DesktopConfigurationException catch (error) {
      fontError = error.kind;
    }
    notifyListeners();
  }

  File _asset(String filename) {
    if (filename != p.basename(filename) ||
        filename == '.' ||
        filename == '..') {
      throw const DesktopConfigurationException(DesktopFailure.readFailed);
    }
    return File(p.join(directory.path, filename));
  }

  Future<Uint8List> _read(File file) async {
    try {
      return await file.readAsBytes();
    } on FileSystemException {
      throw const DesktopConfigurationException(DesktopFailure.readFailed);
    }
  }

  Future<BackgroundDraft> prepareBackground(File file) async {
    final extension = p.extension(file.path).toLowerCase();
    if (!['.png', '.jpg', '.jpeg', '.webp'].contains(extension)) {
      throw const DesktopConfigurationException(DesktopFailure.invalidImage);
    }
    final bytes = await _read(file);
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
    } catch (_) {
      throw const DesktopConfigurationException(DesktopFailure.invalidImage);
    }
    return BackgroundDraft(bytes, extension);
  }

  Future<File> _saveAsset(
    Uint8List bytes,
    String kind,
    String extension,
  ) async {
    final file = _asset('$kind-${const Uuid().v4()}$extension');
    try {
      await directory.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } on FileSystemException {
      await _removeAsset(p.basename(file.path));
      throw const DesktopConfigurationException(DesktopFailure.saveFailed);
    }
  }

  Future<void> _removeAsset(String? filename) async {
    if (filename == null ||
        !(filename.startsWith('background-') || filename.startsWith('font-'))) {
      return;
    }
    final file = _asset(filename);
    imageCache.evict(FileImage(file));
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      /* 已保存配置仍有效；被占用的旧资源留待下一次替换。 */
    }
  }

  Future<void> applyBackground(
    BackgroundDraft draft, {
    double soften = 8,
  }) async {
    final old = preferences.value.background?.file;
    final file = await _saveAsset(draft.bytes, 'background', draft.extension);
    try {
      await preferences.update(
        preferences.value.copyWith(
          background: BackgroundSelection(
            file: p.basename(file.path),
            soften: soften,
          ),
        ),
      );
    } catch (_) {
      await _removeAsset(p.basename(file.path));
      rethrow;
    }
    backgroundFile = file;
    backgroundError = null;
    notifyListeners();
    await _removeAsset(old);
  }

  Future<void> resetBackground() async {
    final old = preferences.value.background?.file;
    await preferences.update(preferences.value.copyWith(clearBackground: true));
    backgroundFile = null;
    backgroundError = null;
    notifyListeners();
    await _removeAsset(old);
  }

  Future<void> _loadFont(Uint8List bytes, String family) async {
    try {
      if (bytes.length < 12) throw const FormatException();
      final data = ByteData.sublistView(bytes);
      final magic = data.getUint32(0);
      if (magic != 0x00010000 && magic != 0x4f54544f) {
        throw const FormatException();
      }
      final count = data.getUint16(4);
      if (count == 0 || 12 + count * 16 > bytes.length) {
        throw const FormatException();
      }
      final tables = <int, ({int offset, int length})>{};
      for (var i = 0; i < count; i++) {
        final tag = data.getUint32(12 + i * 16);
        final offset = data.getUint32(12 + i * 16 + 8);
        final length = data.getUint32(12 + i * 16 + 12);
        if (offset + length > bytes.length) throw const FormatException();
        tables[tag] = (offset: offset, length: length);
      }
      // FontLoader 的 void 返回不证明字体有效，先核对 SFNT 必需表与字形。
      for (final required in <int, int>{
        0x68656164: 54, // head
        0x6d617870: 6, // maxp
        0x636d6170: 4, // cmap
        0x6e616d65: 6, // name
        0x68686561: 36, // hhea
        0x686d7478: 4, // hmtx
      }.entries) {
        final table = tables[required.key];
        if (table == null || table.length < required.value) {
          throw const FormatException();
        }
      }
      if (data.getUint32(tables[0x68656164]!.offset + 12) != 0x5f0f3cf5 ||
          data.getUint16(tables[0x6d617870]!.offset + 4) == 0 ||
          ![
            0x676c7966,
            0x43464620,
            0x43464632,
          ].any((tag) => (tables[tag]?.length ?? 0) > 0)) {
        throw const FormatException();
      }
      final loader = FontLoader(family)..addFont(Future.value(data));
      await loader.load();
    } catch (_) {
      throw const DesktopConfigurationException(DesktopFailure.invalidFont);
    }
  }

  Future<FontDraft> prepareFont(File file) async {
    final extension = p.extension(file.path).toLowerCase();
    if (!['.ttf', '.otf'].contains(extension)) {
      throw const DesktopConfigurationException(DesktopFailure.invalidFont);
    }
    final bytes = await _read(file);
    final family = 'LeyinImported_${const Uuid().v4()}';
    await _loadFont(bytes, family);
    return FontDraft(
      bytes,
      FontSelection(family: family, label: p.basename(file.path)),
      extension,
    );
  }

  Future<void> applyFont(FontDraft draft) async {
    final old = preferences.value.font?.file;
    final file = await _saveAsset(draft.bytes, 'font', draft.extension);
    try {
      await preferences.update(
        preferences.value.copyWith(
          font: FontSelection(
            family: draft.selection.family,
            label: draft.selection.label,
            file: p.basename(file.path),
          ),
        ),
      );
    } catch (_) {
      await _removeAsset(p.basename(file.path));
      rethrow;
    }
    _fontFamily = draft.selection.family;
    fontError = null;
    notifyListeners();
    await _removeAsset(old);
  }

  Future<void> selectSystemFont(String family) async {
    if (!fonts.contains(family)) {
      throw const DesktopConfigurationException(DesktopFailure.fileMissing);
    }
    final old = preferences.value.font?.file;
    await preferences.update(
      preferences.value.copyWith(font: FontSelection(family: family)),
    );
    _fontFamily = family;
    fontError = null;
    notifyListeners();
    await _removeAsset(old);
  }

  Future<void> resetFont() async {
    final old = preferences.value.font?.file;
    await preferences.update(preferences.value.copyWith(clearFont: true));
    _fontFamily = null;
    fontError = null;
    notifyListeners();
    await _removeAsset(old);
  }

  Future<void> setCloseAction(WindowsCloseAction action) async {
    final previous = preferences.closeAction;
    try {
      await window.setCloseAction(action);
    } on DesktopConfigurationException catch (error) {
      nativeError = error.kind;
      nativeAvailable = false;
      notifyListeners();
      rethrow;
    }
    try {
      await preferences.update(preferences.value.copyWith(closeAction: action));
    } catch (_) {
      try {
        await window.setCloseAction(previous);
      } on DesktopConfigurationException catch (error) {
        nativeError = error.kind;
        nativeAvailable = false;
        notifyListeners();
      }
      rethrow;
    }
    nativeAvailable = true;
    nativeError = null;
    notifyListeners();
  }

  ThemeData theme(Brightness brightness, {String? previewFont}) {
    final base = brightness == Brightness.dark
        ? VideoTheme.dark
        : VideoTheme.light;
    final family = previewFont ?? fontFamily;
    final hasBackground = backgroundFile != null;
    return base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: family),
      primaryTextTheme: base.primaryTextTheme.apply(fontFamily: family),
      scaffoldBackgroundColor: hasBackground
          ? Colors.transparent
          : base.scaffoldBackgroundColor,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: hasBackground
            ? Colors.transparent
            : base.appBarTheme.backgroundColor,
        titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(
          fontFamily: family,
        ),
      ),
      navigationRailTheme: base.navigationRailTheme.copyWith(
        backgroundColor: hasBackground
            ? base.colorScheme.surface.withValues(alpha: .86)
            : base.colorScheme.surface,
      ),
      extensions: [WindowsAppearanceTheme(hasBackground: hasBackground)],
    );
  }

  void reportMissingBackground() {
    if (_disposed || backgroundFile == null) return;
    backgroundFile = null;
    backgroundError = DesktopFailure.fileMissing;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    preferences.removeListener(_preferencesChanged);
    super.dispose();
  }
}

class WindowsBackground extends StatelessWidget {
  const WindowsBackground({
    super.key,
    required this.appearance,
    required this.child,
  });
  final WindowsAppearance appearance;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final file = appearance.backgroundFile;
    final soften = appearance.preferences.value.background?.soften ?? 8;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: dark ? const Color(0xFF17171C) : VideoTheme.background,
        ),
        if (file != null) ...[
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: soften, sigmaY: soften),
            child: Image.file(
              file,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => appearance.reportMissingBackground(),
                );
                return const SizedBox.shrink();
              },
            ),
          ),
          ColoredBox(
            color: WindowsAppearance.backgroundOverlay(
              Theme.of(context).brightness,
            ),
          ),
        ],
        child,
      ],
    );
  }
}

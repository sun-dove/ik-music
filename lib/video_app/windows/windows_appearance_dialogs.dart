import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../l10n/windows_music_strings.dart';
import 'windows_appearance.dart';
import 'windows_music_preferences.dart';

String _message(Object value) => value is String
    ? value
    : value is DesktopConfigurationException
    ? value.toString()
    : WindowsMusicStrings.failure(DesktopFailure.readFailed);

void _notice(ScaffoldMessengerState messenger, Object error) {
  if (messenger.mounted) {
    messenger.showSnackBar(SnackBar(content: Text(_message(error))));
  }
}

Future<void> showWindowsBackgroundPicker(
  BuildContext context,
  WindowsAppearance appearance,
) async {
  final messenger = ScaffoldMessenger.of(context);
  var busy = false;
  String? errorText;
  await showDialog<void>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, setState) => AlertDialog(
        title: const Text(WindowsMusicStrings.background),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (errorText != null)
                Text(
                  errorText!,
                  style: TextStyle(color: Theme.of(dialog).colorScheme.error),
                ),
              if (appearance.backgroundError != null)
                Text(WindowsMusicStrings.failure(appearance.backgroundError!)),
              FilledButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        setState(() {
                          busy = true;
                          errorText = null;
                        });
                        try {
                          final selection = await FilePicker.pickFiles(
                            type: FileType.custom,
                            allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
                          );
                          if (selection?.files.single.path == null) return;
                          final draft = await appearance.prepareBackground(
                            File(selection!.files.single.path!),
                          );
                          if (!context.mounted || !dialog.mounted) return;
                          var soften =
                              appearance.preferences.value.background?.soften ??
                              8.0;
                          var applying = false;
                          String? previewError;
                          final applied = await showDialog<bool>(
                            context: dialog,
                            builder: (preview) => StatefulBuilder(
                              builder: (preview, refresh) => AlertDialog(
                                title: const Text(
                                  WindowsMusicStrings.backgroundPreview,
                                ),
                                content: SizedBox(
                                  width: 560,
                                  child: SingleChildScrollView(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          child: SizedBox(
                                            height: 240,
                                            width: 560,
                                            child: Stack(
                                              fit: StackFit.expand,
                                              children: [
                                                ImageFiltered(
                                                  imageFilter:
                                                      ui.ImageFilter.blur(
                                                        sigmaX: soften,
                                                        sigmaY: soften,
                                                      ),
                                                  child: Image.memory(
                                                    draft.bytes,
                                                    fit: BoxFit.cover,
                                                  ),
                                                ),
                                                ColoredBox(
                                                  color:
                                                      WindowsAppearance.backgroundOverlay(
                                                        Theme.of(preview)
                                                            .brightness,
                                                      ),
                                                ),
                                                const Center(
                                                  child: Padding(
                                                    padding: EdgeInsets.all(18),
                                                    child: Text(
                                                      WindowsMusicStrings
                                                          .fontSample,
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: TextStyle(
                                                        fontSize: 20,
                                                        height: 1.6,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        if (previewError != null)
                                          Text(
                                            previewError!,
                                            style: TextStyle(
                                              color: Theme.of(preview)
                                                  .colorScheme
                                                  .error,
                                            ),
                                          ),
                                        const Text(WindowsMusicStrings.soften),
                                        Slider(
                                          value: soften,
                                          max: 20,
                                          divisions: 20,
                                          label: soften.round().toString(),
                                          onChanged: applying
                                              ? null
                                              : (value) => refresh(
                                                  () => soften = value,
                                                ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: applying
                                        ? null
                                        : () => Navigator.pop(preview, false),
                                    child: const Text(
                                      WindowsMusicStrings.cancel,
                                    ),
                                  ),
                                  FilledButton(
                                    onPressed: applying
                                        ? null
                                        : () async {
                                            refresh(() => applying = true);
                                            try {
                                              await appearance.applyBackground(
                                                draft,
                                                soften: soften,
                                              );
                                              if (preview.mounted) {
                                                Navigator.pop(preview, true);
                                              }
                                            } catch (error) {
                                              if (preview.mounted) {
                                                refresh(() {
                                                  applying = false;
                                                  previewError = _message(
                                                    error,
                                                  );
                                                });
                                                _notice(messenger, error);
                                              }
                                            }
                                          },
                                    child: const Text(
                                      WindowsMusicStrings.apply,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                          if (applied == true && dialog.mounted) {
                            Navigator.pop(dialog);
                            _notice(messenger, WindowsMusicStrings.applied);
                          }
                        } catch (error) {
                          if (dialog.mounted) {
                            setState(() => errorText = _message(error));
                          }
                          _notice(messenger, error);
                        } finally {
                          if (dialog.mounted) setState(() => busy = false);
                        }
                      },
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text(WindowsMusicStrings.chooseImage),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        setState(() => busy = true);
                        try {
                          await appearance.resetBackground();
                          if (dialog.mounted) Navigator.pop(dialog);
                        } catch (error) {
                          _notice(messenger, error);
                          if (dialog.mounted) setState(() => busy = false);
                        }
                      },
                child: const Text(WindowsMusicStrings.restoreDefault),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(dialog),
            child: const Text(WindowsMusicStrings.cancel),
          ),
        ],
      ),
    ),
  );
}

Future<void> showWindowsFontPicker(
  BuildContext context,
  WindowsAppearance appearance, {
  bool preserveTheme = false,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  var family = appearance.fontFamily;
  FontDraft? imported;
  var busy = false;
  String? errorText;
  await showDialog<void>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, refresh) => Theme(
        data: preserveTheme
            ? Theme.of(dialog).copyWith(
                textTheme: Theme.of(dialog).textTheme.apply(fontFamily: family),
                primaryTextTheme: Theme.of(dialog).primaryTextTheme
                    .apply(fontFamily: family),
                appBarTheme: Theme.of(dialog).appBarTheme.copyWith(
                  titleTextStyle: Theme.of(dialog).appBarTheme.titleTextStyle
                      ?.copyWith(fontFamily: family),
                ),
              )
            : appearance.theme(
                Theme.of(dialog).brightness,
                previewFont: family,
              ),
        child: AlertDialog(
          title: const Text(WindowsMusicStrings.fontPreview),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (errorText != null)
                    Text(
                      errorText!,
                      style: TextStyle(
                        color: Theme.of(dialog).colorScheme.error,
                      ),
                    ),
                  const Text(
                    WindowsMusicStrings.fontHint,
                    style: TextStyle(fontSize: 12),
                  ),
                  if (appearance.fontError != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        WindowsMusicStrings.failure(appearance.fontError!),
                      ),
                    ),
                  if (appearance.fonts.isNotEmpty)
                    DropdownButtonFormField<String>(
                      initialValue: appearance.fonts.contains(family)
                          ? family
                          : null,
                      isExpanded: true,
                      items: [
                        for (final font in appearance.fonts)
                          DropdownMenuItem(
                            value: font,
                            child: Text(font, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: busy
                          ? null
                          : (value) {
                              if (value != null) {
                                refresh(() {
                                  family = value;
                                  imported = null;
                                });
                              }
                            },
                    ),
                  const SizedBox(height: 20),
                  Text(
                    WindowsMusicStrings.fontSample,
                    style: TextStyle(
                      fontFamily: family,
                      fontSize: 22,
                      height: 1.6,
                    ),
                  ),
                  if (imported != null)
                    Text(
                      imported!.selection.label ??
                          WindowsMusicStrings.importedFont,
                    ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: busy
                        ? null
                        : () async {
                            refresh(() {
                              busy = true;
                              errorText = null;
                            });
                            try {
                              final selection = await FilePicker.pickFiles(
                                type: FileType.custom,
                                allowedExtensions: ['ttf', 'otf'],
                              );
                              if (selection?.files.single.path == null) return;
                              final draft = await appearance.prepareFont(
                                File(selection!.files.single.path!),
                              );
                              if (dialog.mounted) {
                                refresh(() {
                                  imported = draft;
                                  family = draft.selection.family;
                                });
                              }
                            } catch (error) {
                              if (dialog.mounted) {
                                refresh(() => errorText = _message(error));
                              }
                              _notice(messenger, error);
                            } finally {
                              if (dialog.mounted) refresh(() => busy = false);
                            }
                          },
                    icon: const Icon(Icons.file_open_outlined),
                    label: const Text(WindowsMusicStrings.importFont),
                  ),
                  TextButton.icon(
                    onPressed: busy
                        ? null
                        : () async {
                            await appearance.refreshFonts();
                            if (dialog.mounted) refresh(() {});
                          },
                    icon: const Icon(Icons.refresh),
                    label: const Text(WindowsMusicStrings.refreshFonts),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () async {
                            try {
                              await appearance.resetFont();
                              if (dialog.mounted) Navigator.pop(dialog);
                            } catch (error) {
                              _notice(messenger, error);
                            }
                          },
                    child: const Text(WindowsMusicStrings.restoreDefault),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialog),
              child: const Text(WindowsMusicStrings.cancel),
            ),
            FilledButton(
              onPressed:
                  busy ||
                      (imported == null && !appearance.fonts.contains(family))
                  ? null
                  : () async {
                      refresh(() => busy = true);
                      try {
                        if (imported == null) {
                          await appearance.selectSystemFont(family);
                        } else {
                          await appearance.applyFont(imported!);
                        }
                        if (dialog.mounted) Navigator.pop(dialog);
                        _notice(messenger, WindowsMusicStrings.applied);
                      } catch (error) {
                        if (dialog.mounted) {
                          refresh(() => errorText = _message(error));
                        }
                        _notice(messenger, error);
                        if (dialog.mounted) refresh(() => busy = false);
                      }
                    },
              child: const Text(WindowsMusicStrings.apply),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> showWindowsClosePicker(
  BuildContext context,
  WindowsAppearance appearance,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final action = await showModalBottomSheet<WindowsCloseAction>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final value in WindowsCloseAction.values)
            ListTile(
              title: Text(
                value == WindowsCloseAction.minimize
                    ? WindowsMusicStrings.minimize
                    : WindowsMusicStrings.exit,
              ),
              subtitle: Text(
                value == WindowsCloseAction.minimize
                    ? WindowsMusicStrings.minimizeHint
                    : WindowsMusicStrings.exitHint,
              ),
              trailing: appearance.preferences.closeAction == value
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.pop(sheet, value),
            ),
        ],
      ),
    ),
  );
  if (action == null) return;
  try {
    await appearance.setCloseAction(action);
    _notice(messenger, WindowsMusicStrings.applied);
  } catch (error) {
    _notice(messenger, error);
  }
}

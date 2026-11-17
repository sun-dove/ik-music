import 'package:flutter/services.dart';

import 'windows_music_preferences.dart';

class WindowsWindowController {
  const WindowsWindowController({
    this.channel = const MethodChannel('sun-dove.yueyin/desktop'),
    this.beforeExit,
  });
  final MethodChannel channel;
  final Future<void> Function()? beforeExit;
  void connect() {
    if (beforeExit == null) return;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'prepareExit') {
        await beforeExit!();
        return null;
      }
      throw MissingPluginException();
    });
  }

  Future<void> setCloseAction(WindowsCloseAction action) async {
    try {
      final result = await channel.invokeMapMethod<String, dynamic>(
        'setCloseAction',
        {'action': action.name},
      );
      if (result?['applied'] != true || result?['action'] != action.name) {
        throw const DesktopConfigurationException(
          DesktopFailure.nativeUnavailable,
        );
      }
    } on PlatformException {
      throw const DesktopConfigurationException(
        DesktopFailure.nativeUnavailable,
      );
    } on MissingPluginException {
      throw const DesktopConfigurationException(
        DesktopFailure.nativeUnavailable,
      );
    }
  }

  Future<List<String>> listFonts() async {
    try {
      final values = await channel.invokeListMethod<String>('listFonts');
      if (values == null) {
        throw const DesktopConfigurationException(
          DesktopFailure.nativeUnavailable,
        );
      }
      return values.toSet().toList()..sort();
    } on PlatformException {
      throw const DesktopConfigurationException(
        DesktopFailure.nativeUnavailable,
      );
    } on MissingPluginException {
      throw const DesktopConfigurationException(
        DesktopFailure.nativeUnavailable,
      );
    }
  }

  Future<void> exitApplication() async {
    try {
      await channel.invokeMethod<void>('exitApplication');
    } on PlatformException {
      throw const DesktopConfigurationException(
        DesktopFailure.nativeUnavailable,
      );
    } on MissingPluginException {
      throw const DesktopConfigurationException(
        DesktopFailure.nativeUnavailable,
      );
    }
  }
}

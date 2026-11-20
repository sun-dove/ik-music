import 'package:flutter/foundation.dart';

import '../../../core/diagnostics/diagnostics_service.dart';
import '../../../core/platform/platform_utils.dart';
import 'playback_notification_service.dart';

class BackgroundAudioInitializer {
  static Future<void> initialize({DiagnosticsService? diagnostics}) async {
    await _initialize(
      diagnostics: diagnostics,
      initializeController: AudioServicePlayerController.instance.initialize,
    );
  }

  static Future<void> initializeVideoMusic({
    DiagnosticsService? diagnostics,
  }) async {
    await _initialize(
      diagnostics: diagnostics,
      initializeController:
          AudioServicePlayerController.instance.initializeVideoMusic,
    );
  }

  static Future<void> _initialize({
    required DiagnosticsService? diagnostics,
    required Future<void> Function({DiagnosticsService? diagnostics})
    initializeController,
  }) async {
    if (!PlatformUtils.isAndroid) return;
    try {
      await initializeController(diagnostics: diagnostics);
    } catch (error, stack) {
      debugPrint('BackgroundAudioInitializer failed: $error');
      diagnostics?.recordError('background_audio.initialize', error, stack);
    }
  }
}

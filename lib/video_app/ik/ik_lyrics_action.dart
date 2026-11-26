import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/platform/platform_utils.dart';
import '../../features/floating_lyrics/data/floating_lyrics_models.dart';
import '../../features/floating_lyrics/presentation/providers/floating_lyrics_provider.dart';
import '../../features/player/presentation/providers/player_provider.dart';
import '../../l10n/video_strings.dart';
import '../../l10n/ik_lyrics_action_strings.dart';
import 'ik_floating_lyrics.dart';
import 'ik_desktop_lyrics_style.dart';

final ikLyricsActionProvider = StateNotifierProvider<IkLyricsAction, bool>(
  (ref) => IkLyricsAction(ref),
);
final ikLyricsIssueProvider = StateProvider<String?>((ref) => null);

class IkLyricsCapability {
  const IkLyricsCapability(this.supported, this.message);
  final bool supported;
  final String message;
}

final ikLyricsCapabilityProvider = Provider<IkLyricsCapability>(
  (ref) => PlatformUtils.isWindows || PlatformUtils.isAndroid
      ? const IkLyricsCapability(true, '')
      : const IkLyricsCapability(false, IkLyricsActionStrings.unsupported),
);

/// 仅独立入口覆写开关保存顺序；旧通知器仍保持原默认契约。
class IkStrictFloatingLyricsNotifier extends FloatingLyricsNotifier {
  IkStrictFloatingLyricsNotifier({
    Future<void> Function(FloatingLyricsSettings)? save,
  }) : _write = save ?? _saveSettings;
  final Future<void> Function(FloatingLyricsSettings) _write;
  static Future<void> _saveSettings(FloatingLyricsSettings value) async {
    final box = await Hive.openBox('settings');
    await box.put('floating_lyrics_settings', value.toJson());
  }

  Future<void> saveEnabledStrict(bool enabled) async {
    final next = state.copyWith(
      enabled: enabled,
      isLocked: enabled ? state.isLocked : false,
    );
    await _write(next);
    if (mounted) state = next;
  }
}

/// 新工作区共用严格动作：原生成功后才更新开关，旧公开动作保持不变。
class IkLyricsAction extends StateNotifier<bool> {
  IkLyricsAction(this.ref) : super(false);
  final Ref ref;
  Future<void> setEnabled(bool enabled) async {
    if (state) return;
    final capability = ref.read(ikLyricsCapabilityProvider);
    if (!capability.supported) {
      ref.read(ikLyricsIssueProvider.notifier).state = capability.message;
      ref.read(ikFloatingFailureProvider.notifier).state = true;
      return;
    }
    state = true;
    final service = ref.read(ikFloatingLyricsServiceProvider);
    final previous = ref.read(floatingLyricsProvider);
    var nativeChanged = false;
    var issue = enabled
        ? IkLyricsActionStrings.showFailed
        : IkLyricsActionStrings.hideFailed;
    FloatingLyricsPayload payload() {
      final player = ref.read(playerProvider);
      return FloatingLyricsPayload(
        text: VideoStrings.noLyrics,
        nextText: player.currentSong?.name ?? '',
        isPlaying: player.isPlaying,
        hasSong: player.currentSong != null,
      );
    }

    try {
      ref.read(ikLyricsIssueProvider.notifier).state = null;
      if (enabled) {
        var allowed = await service.canDrawOverlays();
        if (!allowed) {
          await service.openOverlaySettings();
          allowed = await service.canDrawOverlays();
        }
        if (!allowed) {
          issue = IkLyricsActionStrings.permission;
          throw StateError('overlay_permission');
        }
        if (!await service.show(
          payload(),
          ref.read(floatingLyricsProvider).copyWith(enabled: true),
        )) {
          throw StateError('overlay_unavailable');
        }
      } else if (!await service.hide()) {
        throw StateError('overlay_hide_failed');
      }
      nativeChanged = true;
      if (!mounted) return;
      issue = IkLyricsActionStrings.saveFailed;
      final notifier = ref.read(floatingLyricsProvider.notifier);
      if (notifier is IkStrictFloatingLyricsNotifier) {
        await notifier.saveEnabledStrict(enabled);
      } else {
        await notifier.setEnabled(enabled);
      }
      ref.read(ikFloatingFailureProvider.notifier).state = false;
      nativeChanged = false;
      if (enabled) {
        issue = IkLyricsActionStrings.syncFailed;
        await ref.read(ikFloatingSyncProvider).sync();
        if (ref.read(ikFloatingFailureProvider)) {
          ref.read(ikLyricsIssueProvider.notifier).state = issue;
        }
      }
    } catch (_) {
      if (nativeChanged) {
        try {
          if (previous.enabled) {
            await service.show(payload(), previous);
          } else {
            await service.hide();
          }
        } catch (_) {
          /* 保留失败状态，用户可以再次重试原生操作。 */
        }
      }
      if (mounted) {
        ref.read(ikFloatingFailureProvider.notifier).state = true;
        ref.read(ikLyricsIssueProvider.notifier).state = issue;
      }
    } finally {
      if (mounted) state = false;
    }
  }
}

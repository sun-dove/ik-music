import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/floating_lyrics/data/floating_lyrics_models.dart';
import '../../features/floating_lyrics/data/floating_lyrics_service.dart';
import '../../features/floating_lyrics/presentation/providers/floating_lyrics_provider.dart';
import '../../features/player/presentation/providers/player_provider.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../l10n/ik_runtime_strings.dart';
import '../../l10n/video_strings.dart';
import 'ik_desktop_lyrics_style.dart';

/// 仅新版入口挂载，路由交由主程序处理，以继续沿用已有编辑离开保护。
class IkFloatingLyricsSettingsBridge extends StatefulWidget {
  const IkFloatingLyricsSettingsBridge({
    super.key,
    required this.child,
    required this.onOpenSettings,
  });

  final Widget child;
  final VoidCallback onOpenSettings;

  @override
  State<IkFloatingLyricsSettingsBridge> createState() =>
      _IkFloatingLyricsSettingsBridgeState();
}

class _IkFloatingLyricsSettingsBridgeState
    extends State<IkFloatingLyricsSettingsBridge> {
  late final StreamSubscription<void> _settingsSubscription;

  @override
  void initState() {
    super.initState();
    _settingsSubscription = FloatingLyricsService.instance
        .settingsRequestedStream
        .listen((_) {
          if (mounted) widget.onOpenSettings();
        });
  }

  @override
  void dispose() {
    unawaited(_settingsSubscription.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

final ikFloatingFailureProvider = StateProvider<bool>((ref) => false);
final ikFloatingSyncProvider = Provider<FloatingLyricsSyncController>((ref) {
  final service = ref.watch(ikFloatingLyricsServiceProvider);
  final controller = FloatingLyricsSyncController(
    ref,
    service: service,
    strictDelivery: true,
    emptyText: VideoStrings.noLyrics,
    onDelivery: (success) {
      ref.read(ikFloatingFailureProvider.notifier).state = !success;
      if (success) {
        ref.read(ikDesktopLyricsStyleDeliveryFailedProvider.notifier).state =
            false;
      }
    },
  );
  ref.listen<bool>(ikDesktopLyricsStyleDeliveryFailedProvider, (_, failed) {
    ref.read(ikFloatingFailureProvider.notifier).state = failed;
  });
  var active = true;
  unawaited(
    Future<void>.microtask(() async {
      if (active) await controller.sync();
    }),
  );
  ref.onDispose(() {
    active = false;
    controller.dispose();
    unawaited(service.hide().catchError((Object _) => false));
  });
  return controller;
});

class IkFloatingLyricsPage extends ConsumerStatefulWidget {
  const IkFloatingLyricsPage({super.key});
  @override
  ConsumerState<IkFloatingLyricsPage> createState() =>
      _IkFloatingLyricsPageState();
}

class _IkFloatingLyricsPageState extends ConsumerState<IkFloatingLyricsPage> {
  bool _busy = false;

  Future<void> _toggle(bool enabled) async {
    if (_busy) return;
    setState(() => _busy = true);
    final service = ref.read(ikFloatingLyricsServiceProvider);
    try {
      if (enabled) {
        var allowed = await service.canDrawOverlays();
        if (!allowed) {
          await service.openOverlaySettings();
          allowed = await service.canDrawOverlays();
        }
        if (!mounted) return;
        if (!allowed) throw StateError('overlay_permission');
        final player = ref.read(playerProvider);
        final shown = await service.show(
          FloatingLyricsPayload(
            text: VideoStrings.noLyrics,
            nextText: player.currentSong?.name ?? '',
            isPlaying: player.isPlaying,
            hasSong: player.currentSong != null,
          ),
          ref.read(floatingLyricsProvider).copyWith(enabled: true),
        );
        if (!shown) throw StateError('overlay_unavailable');
      } else {
        if (!await service.hide()) throw StateError('overlay_hide_failed');
      }
      if (!mounted) return;
      await ref.read(floatingLyricsProvider.notifier).setEnabled(enabled);
      if (!mounted) return;
      ref.read(ikFloatingFailureProvider.notifier).state = false;
      if (enabled) await ref.read(ikFloatingSyncProvider).sync();
    } catch (_) {
      if (mounted) ref.read(ikFloatingFailureProvider.notifier).state = true;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(ikFloatingSyncProvider);
    final failed = ref.watch(ikFloatingFailureProvider);
    return SettingsFloatingLyricsPage(
      enableKey: const Key('ik-floating-toggle'),
      onToggle: _toggle,
      status: _busy
          ? const LinearProgressIndicator()
          : failed
          ? ListTile(
              title: const Text(IkRuntimeStrings.floatingFailed),
              trailing: TextButton(
                onPressed: () => _toggle(true),
                child: const Text(IkRuntimeStrings.floatingRetry),
              ),
            )
          : null,
    );
  }
}

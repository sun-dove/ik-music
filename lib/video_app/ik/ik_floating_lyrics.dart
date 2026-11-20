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

final ikFloatingFailureProvider = StateProvider<bool>((ref) => false);
final ikFloatingSyncProvider = Provider<FloatingLyricsSyncController>((ref) {
  final controller = FloatingLyricsSyncController(
    ref,
    strictDelivery: true,
    emptyText: VideoStrings.noLyrics,
    onDelivery: (success) {
      ref.read(ikFloatingFailureProvider.notifier).state = !success;
    },
  );
  var active = true;
  unawaited(
    Future<void>.microtask(() async {
      if (active) await controller.sync();
    }),
  );
  ref.onDispose(() {
    active = false;
    controller.dispose();
    unawaited(
      FloatingLyricsService.instance.hide().catchError((Object _) => false),
    );
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
    final service = FloatingLyricsService.instance;
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/platform_utils.dart';
import '../../features/audio_effects/presentation/providers/sleep_timer_provider.dart';
import '../../features/library/presentation/providers/history_provider.dart';
import '../../features/library/presentation/providers/likes_provider.dart';
import '../../features/player/presentation/providers/player_provider.dart';
import '../../features/stats/presentation/providers/listening_stats_provider.dart';
import '../../features/widget/widget_actions.dart';
import '../../features/widget/widget_bridge.dart';
import '../../features/widget/widget_state.dart';
import '../../l10n/ik_strings.dart';
import '../../l10n/video_strings.dart';
import 'ik_catalog_pages.dart';
import 'ik_desktop.dart';
import 'ik_audio_runtime.dart';
import 'ik_account_runtime.dart';
import 'ik_link_runtime.dart';
import 'ik_floating_lyrics.dart';

class IkRuntime extends ConsumerStatefulWidget {
  const IkRuntime({super.key, required this.child, required this.onNavigate});
  final Widget child;
  final ValueChanged<String> onNavigate;
  @override
  ConsumerState<IkRuntime> createState() => _IkRuntimeState();
}

class _IkRuntimeState extends ConsumerState<IkRuntime>
    with WidgetsBindingObserver {
  IkDesktopController? _desktop;
  ProviderContainer? _widgetContainer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (PlatformUtils.isWindows) {
      _desktop = IkDesktopController(
        onCommand: (command) async {
          final player = ref.read(playerProvider.notifier);
          switch (command) {
            case 'toggle':
              await player.togglePlay();
            case 'play':
              if (!ref.read(playerProvider).isPlaying) {
                await player.togglePlay();
              }
            case 'pause':
              await player.pause();
            case 'next':
              await player.skipToNext();
            case 'previous':
              await player.skipToPrevious();
          }
        },
      );
      unawaited(_desktop!.update(ref.read(playerProvider)));
      unawaited(_desktop!.connect());
    }
    ref.listenManual(playerProvider, (_, next) {
      unawaited(_desktop?.update(next) ?? Future<void>.value());
      if (PlatformUtils.isAndroid) {
        final song = next.currentSong;
        unawaited(
          WidgetBridge.publish(
            song == null
                ? const WidgetSnapshot.empty()
                : WidgetSnapshot(
                    songName: song.name,
                    artistNames: song.artistNames,
                    coverPath: song.coverUrl,
                    isPlaying: next.isPlaying,
                  ),
          ),
        );
      }
    }, fireImmediately: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(likesProvider.notifier).loadAllLikes());
      unawaited(ref.read(historyProvider.notifier).loadAllHistory());
    });
    if (PlatformUtils.isAndroid) {
      WidgetBridge.navigationHandler = (action) => widget.onNavigate(
        action.kind == WidgetActionKind.openQueue ? '/queue' : '/player',
      );
      WidgetBridge.transportHandler = (action, container) {
        final player = container.read(playerProvider.notifier);
        final future = switch (action.kind) {
          WidgetActionKind.togglePlayPause => player.togglePlay(),
          WidgetActionKind.next => player.skipToNext(),
          WidgetActionKind.previous => player.skipToPrevious(),
          _ => Future<void>.value(),
        };
        unawaited(
          future.catchError((Object error, StackTrace stack) {
            WidgetBridge.reportNotifierMissing(action, error, stack);
          }),
        );
      };
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        _widgetContainer = ProviderScope.containerOf(context);
        WidgetBridge.attach(_widgetContainer!);
        await WidgetBridge.initialize();
        if (!mounted) return;
        await WidgetBridge.deliverInitial();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      unawaited(ref.read(listeningStatsTrackerProvider).flush());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _desktop?.dispose();
    final container = _widgetContainer;
    if (container != null) WidgetBridge.detach(container);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(ikAccountRuntimeProvider);
    ref.watch(ikFloatingSyncProvider);
    ref.watch(listeningStatsTrackerProvider);
    ref.watch(historyProvider);
    ref.watch(sleepTimerProvider);
    ref.watch(ikAudioRuntimeProvider);
    return ProviderScope(
      overrides: [ikDesktopProvider.overrideWithValue(_desktop)],
      child: IkLinkRuntime(onNavigate: widget.onNavigate, child: widget.child),
    );
  }
}

class IkQueuePanel extends ConsumerWidget {
  const IkQueuePanel({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    final notifier = ref.read(playerProvider.notifier);
    return Column(
      children: [
        ListTile(
          title: const Text(IkStrings.nextUp),
          subtitle: Text(VideoStrings.queueCount(player.playlist.length)),
        ),
        if (player.playlist.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(IkStrings.emptyQueue),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: player.playlist.length,
            itemBuilder: (context, index) => IkSongTile(
              song: player.playlist[index],
              playing: index == player.currentIndex,
              onTap: () =>
                  notifier.playPlaylist(player.playlist, startIndex: index),
            ),
          ),
        ),
      ],
    );
  }
}

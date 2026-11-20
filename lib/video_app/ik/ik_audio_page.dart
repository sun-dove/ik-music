import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/audio_effects/presentation/providers/audio_effects_provider.dart';
import '../../features/audio_effects/presentation/providers/sleep_timer_provider.dart';
import '../../l10n/ik_strings.dart';
import '../../l10n/ik_runtime_strings.dart';
import 'ik_audio_runtime.dart';
import 'ik_desktop.dart';

/// 独立播放器工具页，不暴露仅属于 Mconnect 的换源开关。
class IkAudioPage extends ConsumerWidget {
  const IkAudioPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final effects = ref.watch(audioEffectsSettingsProvider);
    final notifier = ref.read(audioEffectsSettingsProvider.notifier);
    final timer = ref.watch(sleepTimerProvider);
    final application = ref.watch(ikAudioRuntimeProvider);
    final equalizerAvailable = application.status != IkAudioStatus.unsupported;
    final desktop = ref.watch(ikDesktopProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(IkStrings.audio)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (desktop != null)
            ListenableBuilder(
              listenable: desktop,
              builder: (context, _) => ListTile(
                title: Text(
                  desktop.complete
                      ? IkRuntimeStrings.desktopReady
                      : desktop.available
                      ? IkRuntimeStrings.desktopPartial
                      : IkRuntimeStrings.desktopUnavailable,
                ),
                trailing: desktop.complete
                    ? null
                    : TextButton(
                        onPressed: desktop.connecting ? null : desktop.connect,
                        child: const Text(IkRuntimeStrings.retry),
                      ),
              ),
            ),
          SwitchListTile(
            title: const Text(IkStrings.fade),
            value: effects.fadeEnabled,
            onChanged: notifier.setFadeEnabled,
          ),
          ListTile(
            title: const Text(IkStrings.fadeDuration),
            subtitle: Text('${effects.fadeDuration.inMilliseconds} ms'),
          ),
          Slider(
            value: effects.fadeDuration.inMilliseconds.toDouble(),
            min: 200,
            max: 3000,
            divisions: 14,
            onChanged: (value) =>
                notifier.setFadeDuration(Duration(milliseconds: value.round())),
          ),
          ListTile(
            title: Text(switch (application.status) {
              IkAudioStatus.idle ||
              IkAudioStatus.applying => IkRuntimeStrings.audioApplying,
              IkAudioStatus.applied => IkRuntimeStrings.audioApplied,
              IkAudioStatus.unsupported => IkRuntimeStrings.audioUnsupported,
              IkAudioStatus.failed => IkRuntimeStrings.audioApplyFailed,
            }),
            trailing: application.status == IkAudioStatus.failed
                ? TextButton(
                    onPressed: ref.read(ikAudioRuntimeProvider.notifier).retry,
                    child: const Text(IkRuntimeStrings.retry),
                  )
                : null,
          ),
          SwitchListTile(
            title: const Text(IkStrings.equalizer),
            value: effects.equalizerEnabled,
            onChanged: equalizerAvailable ? notifier.setEqualizerEnabled : null,
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in EqualizerPreset.values)
                ChoiceChip(
                  label: Text(preset.displayName),
                  selected: effects.equalizerPreset == preset,
                  onSelected: effects.equalizerEnabled && equalizerAvailable
                      ? (_) => notifier.setEqualizerPreset(preset)
                      : null,
                ),
            ],
          ),
          for (final entry in [60, 230, 910, 3600, 14000].indexed)
            ListTile(
              title: Text(
                '${IkStrings.band(entry.$2)} · ${effects.effectiveEqualizerBandGains[entry.$1].toStringAsFixed(0)} dB',
              ),
              subtitle: Slider(
                value: effects.effectiveEqualizerBandGains[entry.$1],
                min: -12,
                max: 12,
                divisions: 24,
                onChanged: effects.equalizerEnabled && equalizerAvailable
                    ? (value) => notifier.setEqualizerBandGain(entry.$1, value)
                    : null,
              ),
            ),
          SwitchListTile(
            title: const Text(IkStrings.sleep),
            subtitle: Text(
              timer.enabled
                  ? IkStrings.remaining(
                      timer.remaining.inMinutes,
                      timer.remaining.inSeconds % 60,
                    )
                  : IkStrings.minutes(effects.sleepTimerDuration.inMinutes),
            ),
            value: timer.enabled,
            onChanged: ref.read(sleepTimerProvider.notifier).setEnabled,
          ),
          ListTile(
            title: const Text(IkStrings.timerDuration),
            subtitle: Slider(
              value: effects.sleepTimerDuration.inMinutes.toDouble(),
              min: 5,
              max: 120,
              divisions: 23,
              onChanged: (value) => notifier.setSleepTimerDuration(
                Duration(minutes: value.round()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

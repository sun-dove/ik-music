import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/audio_effects/presentation/providers/audio_effects_provider.dart';
import '../../features/audio_effects/presentation/providers/sleep_timer_provider.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/backup/data/backup_service.dart';
import '../../features/floating_lyrics/presentation/providers/floating_lyrics_provider.dart';
import '../../features/library/presentation/providers/history_provider.dart';
import '../../features/library/presentation/providers/likes_provider.dart';
import '../../features/library/presentation/providers/my_playlists_provider.dart';
import '../../features/offline_cache/presentation/providers/offline_cache_provider.dart';
import '../../features/player/presentation/providers/player_provider.dart';
import '../../features/smart_playlists/presentation/providers/smart_playlists_provider.dart';
import '../../features/stats/presentation/providers/listening_stats_provider.dart';
import '../../l10n/ik_alignment_settings_strings.dart';
import '../../l10n/ik_runtime_strings.dart';
import '../../l10n/ik_strings.dart';
import '../../l10n/ik_workspace_strings.dart';
import '../../l10n/video_strings.dart';
import '../../l10n/windows_music_strings.dart';
import '../../models/audio_quality.dart';
import '../../models/platform_type.dart';
import '../built_in/catalog_panel.dart';
import '../ui/catalog_pages.dart';
import '../video_preferences.dart';
import '../windows/windows_appearance.dart';
import '../windows/windows_music_preferences.dart';
import '../windows/windows_platform_icon.dart';
import 'ik_audio_runtime.dart';
import 'ik_backup_page.dart';
import 'ik_controls.dart';
import 'ik_floating_lyrics.dart';
import 'ik_lyrics_action.dart';
import 'ik_spatial_runtime.dart';
import 'ik_version.dart';

class IkSettingsWorkspace extends ConsumerStatefulWidget {
  const IkSettingsWorkspace({
    super.key,
    required this.preferences,
    required this.onThemeChanged,
    required this.onAccount,
    required this.onSync,
    required this.onSources,
    required this.onDirectory,
    required this.onDownloads,
    required this.onCache,
    this.appearance,
    this.unified,
    this.initialSection = 'audio',
    this.sectionRequest = 0,
    this.alignToDesign = false,
  });
  final VideoPreferences preferences;
  final WindowsAppearance? appearance;
  final WindowsMusicPreferences? unified;
  final VoidCallback onThemeChanged,
      onSources,
      onDirectory,
      onDownloads,
      onCache;
  final ValueChanged<PlatformType> onAccount, onSync;
  final String initialSection;
  final int sectionRequest;
  final bool alignToDesign;
  @override
  ConsumerState<IkSettingsWorkspace> createState() =>
      _IkSettingsWorkspaceState();
}

class _IkSettingsWorkspaceState extends ConsumerState<IkSettingsWorkspace> {
  static const sections = {
    'audio': IkWorkspaceStrings.audio,
    'appearance': IkWorkspaceStrings.appearance,
    'lyrics': IkStrings.floating,
    'sources': IkWorkspaceStrings.sources,
    'downloads': IkWorkspaceStrings.downloads,
    'accounts': IkWorkspaceStrings.accounts,
    'backup': IkStrings.backup,
  };
  late String _section = sections.containsKey(widget.initialSection)
      ? widget.initialSection
      : 'audio';
  final _busy = <String>{};
  final _errors = <String, String>{};
  BackgroundDraft? _background;
  FontDraft? _font;
  String? _systemFont;
  String? _backupRaw, _backupStatus;
  BackupFileSummary? _backupSummary;
  void _preferencesChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.appearance?.addListener(_preferencesChanged);
    widget.unified?.addListener(_preferencesChanged);
  }

  @override
  void didUpdateWidget(covariant IkSettingsWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appearance != widget.appearance) {
      oldWidget.appearance?.removeListener(_preferencesChanged);
      widget.appearance?.addListener(_preferencesChanged);
    }
    if (oldWidget.unified != widget.unified) {
      oldWidget.unified?.removeListener(_preferencesChanged);
      widget.unified?.addListener(_preferencesChanged);
    }
    if ((oldWidget.initialSection != widget.initialSection ||
            oldWidget.sectionRequest != widget.sectionRequest) &&
        sections.containsKey(widget.initialSection)) {
      _section = widget.initialSection;
    }
  }

  @override
  void dispose() {
    widget.appearance?.removeListener(_preferencesChanged);
    widget.unified?.removeListener(_preferencesChanged);
    super.dispose();
  }

  Future<void> _run(String key, Future<void> Function() action) async {
    if (_busy.contains(key)) return;
    setState(() {
      _busy.add(key);
      _errors.remove(key);
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        _errors[key] = error is DesktopConfigurationException
            ? error.toString()
            : IkWorkspaceStrings.failed;
      }
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  String? _status(String key) =>
      _busy.contains(key) ? IkWorkspaceStrings.busy : _errors[key];
  Widget _alignedSliderSemantics(Widget slider) =>
      widget.alignToDesign ? Semantics(container: true, child: slider) : slider;
  Widget _row(
    String title,
    Widget control, {
    String? description,
    String? key,
  }) => IkSettingRow(
    alignToDesign: widget.alignToDesign,
    title: title,
    control: control,
    description: description,
    status: key == null ? null : _status(key),
  );
  Widget _button(String text, VoidCallback? action) =>
      OutlinedButton(onPressed: action, child: Text(text));

  @override
  Widget build(BuildContext context) {
    final child = LayoutBuilder(
      builder: (context, size) {
        final wide = size.maxWidth >= 850;
        final navigation = [
          for (final item in sections.entries)
            TextButton(
              key: ValueKey('ik-settings-${item.key}'),
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                backgroundColor: _section == item.key
                    ? Theme.of(context).colorScheme.primary
                          .withValues(alpha: .08)
                    : null,
                foregroundColor: _section == item.key
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              onPressed: () => setState(() => _section = item.key),
              child: Text(item.value, style: const TextStyle(fontSize: 13)),
            ),
        ];
        return SingleChildScrollView(
          padding: EdgeInsets.all(
            widget.alignToDesign
                ? 24
                : size.maxWidth < 580
                ? 16
                : 30,
          ),
          child: Align(
            alignment: widget.alignToDesign
                ? Alignment.topLeft
                : Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    IkWorkspaceStrings.settings,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    IkWorkspaceStrings.settingsHint,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 26),
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 145,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: navigation,
                          ),
                        ),
                        const SizedBox(width: 28),
                        Expanded(child: _content()),
                      ],
                    )
                  else ...[
                    Wrap(spacing: 3, runSpacing: 3, children: navigation),
                    const SizedBox(height: 20),
                    _content(),
                  ],
                  const SizedBox(height: 18),
                  Text(
                    '${IkWorkspaceStrings.currentVersion} · ${IkVersion.label}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    return child;
  }

  Widget _content() => switch (_section) {
    'appearance' => _appearance(),
    'lyrics' => _lyrics(),
    'sources' => IkSettingCard(
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: IkSourceCatalogPanel(onManageSources: widget.onSources),
        ),
      ],
    ),
    'downloads' => _downloads(),
    'accounts' => _accounts(),
    'backup' => _backup(),
    _ => _audio(),
  };

  Widget _quality(bool download) {
    final unified = widget.unified;
    final current =
        unified?.qualityLabel(download: download) ??
        widget.preferences
            .quality(PlatformType.qq, download: download)
            .displayName;
    final values = <String, String>{
      current: current,
      if (!download) WindowsMusicStrings.highest: WindowsMusicStrings.highest,
      for (final level in [
        AudioLevel.low,
        AudioLevel.high,
        AudioLevel.lossless,
        AudioLevel.hires,
        AudioLevel.master,
      ])
        WindowsMusicPreferences.qualityName(level):
            WindowsMusicPreferences.qualityName(level),
    };
    final key = download ? 'download-quality' : 'play-quality';
    return _row(
      download
          ? WindowsMusicStrings.downloadQuality
          : WindowsMusicStrings.playQuality,
      IkSelect<String>(
        alignToDesign: widget.alignToDesign,
        label: download
            ? WindowsMusicStrings.downloadQuality
            : WindowsMusicStrings.playQuality,
        value: current,
        items: values,
        enabled: !_busy.contains(key),
        onChanged: (value) => _run(key, () async {
          if (value == current) return;
          final highest = value == WindowsMusicStrings.highest;
          final level = highest
              ? AudioLevel.lossless
              : AudioLevel.values.firstWhere(
                  (item) => WindowsMusicPreferences.qualityName(item) == value,
                );
          if (unified != null) {
            await unified.setQuality(
              level,
              download: download,
              highest: highest,
            );
          } else {
            for (final platform in PlatformType.musicServices) {
              await widget.preferences.setQuality(
                platform,
                level,
                download: download,
              );
            }
          }
          if (!download && mounted) {
            final song = ref.read(playerProvider).currentSong;
            if (song != null && song.platform != PlatformType.local) {
              await ref
                  .read(playerProvider.notifier)
                  .switchQuality(
                    unified?.quality(song.platform) ??
                        widget.preferences.quality(song.platform),
                  );
            }
          }
        }),
      ),
      key: key,
      description: download
          ? IkWorkspaceStrings.downloadQualityHint
          : IkWorkspaceStrings.playQualityHint,
    );
  }

  Widget _audio() {
    final effects = ref.watch(audioEffectsSettingsProvider),
        timer = ref.watch(sleepTimerProvider);
    final notifier = ref.read(audioEffectsSettingsProvider.notifier);
    final audio = ref.watch(ikAudioRuntimeProvider),
        spatial = ref.watch(ikSpatialRuntimeProvider);
    final spatialActions = ref.read(ikSpatialRuntimeProvider.notifier);
    final eqAvailable = audio.status != IkAudioStatus.unsupported;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.alignToDesign)
          _spatialEmphasis(spatial, spatialActions)
        else
          IkSettingCard(
            children: [
              _row(
                IkWorkspaceStrings.spatial,
                Switch(
                  value: spatial.desired.enabled,
                  onChanged:
                      spatial.canEnable &&
                          spatial.status != IkSpatialStatus.applying
                      ? spatialActions.setEnabled
                      : null,
                ),
                description: spatial.message.isEmpty
                    ? IkWorkspaceStrings.spatialHint
                    : spatial.message,
              ),
              if (spatial.status == IkSpatialStatus.failed ||
                  spatial.status == IkSpatialStatus.unsupported)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: spatialActions.retry,
                    child: const Text(IkWorkspaceStrings.retry),
                  ),
                ),
              _row(
                IkWorkspaceStrings.strength,
                SizedBox(
                  width: 220,
                  child: Slider(
                    value: spatial.desired.strength,
                    onChanged: spatial.canEnable && spatial.desired.enabled
                        ? spatialActions.setStrength
                        : null,
                  ),
                ),
                description: '${(spatial.desired.strength * 100).round()}%',
              ),
            ],
          ),
        IkSettingCard(
          children: [
            _quality(false),
            if (widget.alignToDesign)
              _row(
                IkWorkspaceStrings.strength,
                SizedBox(
                  width: 220,
                  child: Semantics(
                    container: true,
                    child: Slider(
                      value: spatial.desired.strength,
                      label: '${(spatial.desired.strength * 100).round()}%',
                      onChanged: spatial.canEnable && spatial.desired.enabled
                          ? spatialActions.setStrength
                          : null,
                    ),
                  ),
                ),
                description:
                    '${IkAlignmentSettingsStrings.strengthHint} · '
                    '${(spatial.desired.strength * 100).round()}%',
              ),
            _row(
              IkStrings.fade,
              Switch(
                value: effects.fadeEnabled,
                onChanged: _busy.contains('effects')
                    ? null
                    : (value) =>
                          _run('effects', () => notifier.setFadeEnabled(value)),
              ),
              key: 'effects',
            ),
            _row(
              IkStrings.fadeDuration,
              SizedBox(
                width: 220,
                child: _alignedSliderSemantics(
                  Slider(
                    value: effects.fadeDuration.inMilliseconds.toDouble(),
                    min: 200,
                    max: 3000,
                    divisions: 14,
                    onChanged: _busy.contains('effects')
                        ? null
                        : (value) => _run(
                            'effects',
                            () => notifier.setFadeDuration(
                              Duration(milliseconds: value.round()),
                            ),
                          ),
                  ),
                ),
              ),
              description: '${effects.fadeDuration.inMilliseconds} ms',
            ),
          ],
        ),
        IkSettingCard(
          children: [
            _row(
              IkStrings.equalizer,
              widget.alignToDesign
                  ? Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _equalizerPreset(effects, notifier, eqAvailable),
                        _equalizerToggle(effects, notifier, eqAvailable),
                      ],
                    )
                  : _equalizerToggle(effects, notifier, eqAvailable),
              description: switch (audio.status) {
                IkAudioStatus.applied => IkRuntimeStrings.audioApplied,
                IkAudioStatus.failed => IkRuntimeStrings.audioApplyFailed,
                IkAudioStatus.unsupported => IkRuntimeStrings.audioUnsupported,
                _ => IkRuntimeStrings.audioApplying,
              },
              key: 'effects',
            ),
            if (!widget.alignToDesign)
              _row(
                IkWorkspaceStrings.eqPreset,
                _equalizerPreset(effects, notifier, eqAvailable),
              ),
            if (widget.alignToDesign)
              _equalizerBands(effects, notifier, eqAvailable)
            else
              for (final frequency in [60, 230, 910, 3600, 14000].indexed)
                _row(
                  IkStrings.band(frequency.$2),
                  SizedBox(
                    width: 220,
                    child: Slider(
                      value: effects.effectiveEqualizerBandGains[frequency.$1],
                      min: -12,
                      max: 12,
                      divisions: 24,
                      onChanged:
                          eqAvailable &&
                              effects.equalizerEnabled &&
                              !_busy.contains('effects')
                          ? (value) => _run(
                              'effects',
                              () => notifier.setEqualizerBandGain(
                                frequency.$1,
                                value,
                              ),
                            )
                          : null,
                    ),
                  ),
                  description:
                      '${effects.effectiveEqualizerBandGains[frequency.$1].toStringAsFixed(0)} dB',
                ),
            if (audio.status == IkAudioStatus.failed)
              TextButton(
                onPressed: ref.read(ikAudioRuntimeProvider.notifier).retry,
                child: const Text(IkWorkspaceStrings.retry),
              ),
          ],
        ),
        IkSettingCard(
          children: [
            _row(
              IkStrings.sleep,
              Switch(
                value: timer.enabled,
                onChanged: _busy.contains('timer')
                    ? null
                    : (value) => _run('timer', () async {
                        await notifier.setSleepTimerState(
                          enabled: value,
                          remaining: value ? timer.duration : Duration.zero,
                        );
                        if (mounted) {
                          ref
                              .read(sleepTimerProvider.notifier)
                              .setEnabled(value);
                        }
                      }),
              ),
              key: 'timer',
              description: timer.enabled
                  ? IkStrings.remaining(
                      timer.remaining.inMinutes,
                      timer.remaining.inSeconds % 60,
                    )
                  : null,
            ),
            _row(
              IkStrings.timerDuration,
              IkSelect<int>(
                alignToDesign: widget.alignToDesign,
                label: IkStrings.timerDuration,
                value: effects.sleepTimerDuration.inMinutes,
                items: {
                  for (final value in {
                    effects.sleepTimerDuration.inMinutes,
                    15,
                    30,
                    45,
                    60,
                    90,
                    120,
                  })
                    value: IkWorkspaceStrings.minutes(value),
                },
                enabled: !_busy.contains('timer'),
                onChanged: (value) => _run(
                  'timer',
                  () =>
                      notifier.setSleepTimerDuration(Duration(minutes: value)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _spatialEmphasis(
    IkSpatialState spatial,
    IkSpatialCoordinator actions,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final foreground = dark ? const Color(0xffd6eee8) : const Color(0xff244c43);
    final status = spatial.message.isNotEmpty
        ? spatial.message
        : spatial.status == IkSpatialStatus.applying
        ? IkWorkspaceStrings.busy
        : IkAlignmentSettingsStrings.spatialOff;
    return Container(
      key: const ValueKey('ik-spatial-emphasis'),
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: dark ? const Color(0xff213b34) : const Color(0xffeaf4ee),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.primary.withValues(alpha: dark ? .24 : .12),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, size) {
          final text = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                IkAlignmentSettingsStrings.immersion,
                style: TextStyle(fontSize: 12, color: foreground),
              ),
              const SizedBox(height: 7),
              Text(
                IkWorkspaceStrings.spatial,
                style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w600,
                  color: foreground,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                IkAlignmentSettingsStrings.spatialDescription,
                style: TextStyle(fontSize: 13, height: 1.6, color: foreground),
              ),
              const SizedBox(height: 15),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Semantics(
                    label: IkWorkspaceStrings.spatial,
                    child: Switch(
                      value: spatial.desired.enabled,
                      onChanged:
                          spatial.canEnable &&
                              spatial.status != IkSpatialStatus.applying
                          ? actions.setEnabled
                          : null,
                    ),
                  ),
                  Text(
                    status,
                    style: TextStyle(
                      fontSize: 12,
                      color: spatial.status == IkSpatialStatus.failed
                          ? scheme.error
                          : foreground,
                    ),
                  ),
                  if (spatial.status == IkSpatialStatus.failed ||
                      spatial.status == IkSpatialStatus.unsupported)
                    TextButton(
                      onPressed: actions.retry,
                      child: const Text(IkWorkspaceStrings.retry),
                    ),
                ],
              ),
            ],
          );
          if (size.maxWidth < 440 ||
              MediaQuery.textScalerOf(context).scale(14) > 19) {
            return text;
          }
          return Row(
            children: [
              Expanded(child: text),
              const SizedBox(width: 24),
              ExcludeSemantics(
                child: Container(
                  width: 124,
                  height: 124,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: .18),
                    ),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.primary.withValues(alpha: .08),
                      border: Border.all(
                        color: scheme.primary.withValues(alpha: .18),
                      ),
                    ),
                    child: Icon(
                      Icons.headphones_rounded,
                      color: foreground,
                      size: 40,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _equalizerToggle(
    AudioEffectsSettings effects,
    AudioEffectsSettingsNotifier notifier,
    bool available,
  ) => Switch(
    value: effects.equalizerEnabled,
    onChanged: available && !_busy.contains('effects')
        ? (value) => _run('effects', () => notifier.setEqualizerEnabled(value))
        : null,
  );

  Widget _equalizerPreset(
    AudioEffectsSettings effects,
    AudioEffectsSettingsNotifier notifier,
    bool available,
  ) => IkSelect<EqualizerPreset>(
    alignToDesign: widget.alignToDesign,
    label: IkWorkspaceStrings.eqPreset,
    value: effects.equalizerPreset,
    items: {
      for (final preset in EqualizerPreset.values) preset: preset.displayName,
    },
    enabled:
        available && effects.equalizerEnabled && !_busy.contains('effects'),
    onChanged: (value) =>
        _run('effects', () => notifier.setEqualizerPreset(value)),
  );

  Widget _equalizerBands(
    AudioEffectsSettings effects,
    AudioEffectsSettingsNotifier notifier,
    bool available,
  ) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
    child: LayoutBuilder(
      builder: (context, size) {
        final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
        final columns = (size.maxWidth / (72 * scale)).floor().clamp(1, 5);
        return Wrap(
          alignment: WrapAlignment.center,
          runSpacing: 18,
          children: [
            for (final frequency in [60, 230, 910, 3600, 14000].indexed)
              SizedBox(
                width: size.maxWidth / columns,
                child: Column(
                  children: [
                    Text(
                      IkAlignmentSettingsStrings.gain(
                        effects.effectiveEqualizerBandGains[frequency.$1],
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      key: ValueKey('ik-eq-slider-${frequency.$2}'),
                      width: 48,
                      height: 148,
                      child: Semantics(
                        label: IkStrings.band(frequency.$2),
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: Slider(
                            value: effects
                                .effectiveEqualizerBandGains[frequency.$1],
                            min: -12,
                            max: 12,
                            divisions: 24,
                            semanticFormatterCallback:
                                IkAlignmentSettingsStrings.gain,
                            onChanged:
                                available &&
                                    effects.equalizerEnabled &&
                                    !_busy.contains('effects')
                                ? (value) => _run(
                                    'effects',
                                    () => notifier.setEqualizerBandGain(
                                      frequency.$1,
                                      value,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      IkAlignmentSettingsStrings.frequency(frequency.$2),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    ),
  );

  Widget _themePreviews() => IkSettingCard(
    children: [
      Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              IkWorkspaceStrings.appearance,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 5),
            Text(
              IkAlignmentSettingsStrings.themeHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, size) {
                final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
                final columns = ((size.maxWidth + 12) / (132 * scale + 12))
                    .floor()
                    .clamp(1, 3);
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final theme in {
                      'light': VideoStrings.lightTheme,
                      'dark': VideoStrings.darkTheme,
                      'system': VideoStrings.systemTheme,
                    }.entries)
                      SizedBox(
                        width: (size.maxWidth - 12 * (columns - 1)) / columns,
                        child: _themePreview(theme.key, theme.value),
                      ),
                  ],
                );
              },
            ),
            if (_status('theme') != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _status('theme')!,
                  style: TextStyle(
                    fontSize: 12,
                    color: _errors.containsKey('theme')
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _themePreview(String mode, String label) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.preferences.theme == mode;
    return Semantics(
      key: ValueKey('ik-theme-preview-$mode'),
      selected: selected,
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: .06)
            : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _busy.contains('theme')
              ? null
              : () => _run('theme', () async {
                  await widget.preferences.setTheme(mode);
                  widget.onThemeChanged();
                }),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                ExcludeSemantics(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      height: 76,
                      child: mode == 'system'
                          ? Row(
                              children: [
                                Expanded(child: _themeMiniature(false)),
                                Expanded(child: _themeMiniature(true)),
                              ],
                            )
                          : _themeMiniature(mode == 'dark'),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(label, style: const TextStyle(fontSize: 13)),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      size: 17,
                      color: selected ? scheme.primary : scheme.outlineVariant,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _themeMiniature(bool dark) {
    final background = dark ? const Color(0xff202723) : const Color(0xfff7f9f6);
    final line = dark ? const Color(0xff4a5650) : const Color(0xffdce5df);
    return ColoredBox(
      color: background,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 22,
            padding: const EdgeInsets.fromLTRB(5, 12, 5, 7),
            color: line.withValues(alpha: .45),
            child: Column(
              children: [
                Container(height: 8, color: const Color(0xff429887)),
                const SizedBox(height: 8),
                Container(height: 3, color: line),
                const SizedBox(height: 6),
                Container(height: 3, color: line),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(height: 5, color: line),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xff429887).withValues(alpha: .22),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(height: 4, color: line),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _appearance() {
    final appearance = widget.appearance;
    final selected =
        _font?.selection.family ?? _systemFont ?? appearance?.fontFamily;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.alignToDesign)
          _themePreviews()
        else
          IkSettingCard(
            children: [
              _row(
                IkWorkspaceStrings.appearance,
                Wrap(
                  spacing: 8,
                  children: [
                    for (final theme in {
                      'light': VideoStrings.lightTheme,
                      'dark': VideoStrings.darkTheme,
                      'system': VideoStrings.systemTheme,
                    }.entries)
                      ChoiceChip(
                        label: Text(theme.value),
                        selected: widget.preferences.theme == theme.key,
                        onSelected: _busy.contains('theme')
                            ? null
                            : (_) => _run('theme', () async {
                                await widget.preferences.setTheme(theme.key);
                                widget.onThemeChanged();
                              }),
                      ),
                  ],
                ),
                key: 'theme',
              ),
            ],
          ),
        IkSettingCard(
          children: [
            _row(
              WindowsMusicStrings.font,
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (appearance != null && appearance.fonts.isNotEmpty)
                    IkSelect<String>(
                      alignToDesign: widget.alignToDesign,
                      label: WindowsMusicStrings.font,
                      value: _systemFont ?? appearance.fontFamily,
                      items: {
                        for (final font in {
                          appearance.fontFamily,
                          ...appearance.fonts,
                        })
                          font: font,
                      },
                      onChanged: (value) => setState(() {
                        _systemFont = value;
                        _font = null;
                      }),
                    ),
                  _button(
                    WindowsMusicStrings.importFont,
                    appearance == null
                        ? null
                        : () => _run('font', () async {
                            final selection = await FilePicker.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: ['ttf', 'otf'],
                            );
                            if (selection?.files.single.path == null) return;
                            final draft = await appearance.prepareFont(
                              File(selection!.files.single.path!),
                            );
                            if (mounted) {
                              setState(() {
                                _font = draft;
                                _systemFont = null;
                              });
                            }
                          }),
                  ),
                ],
              ),
              key: 'font',
              description: appearance == null
                  ? IkWorkspaceStrings.fontUnavailable
                  : IkWorkspaceStrings.fontHint,
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    IkWorkspaceStrings.fontSample,
                    style: TextStyle(
                      fontFamily: selected,
                      fontSize: 22,
                      height: 1.6,
                    ),
                  ),
                  const Text('IK Music · 1234567890 · ABCDEFG'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (_font != null || _systemFont != null) ...[
                        _button(
                          WindowsMusicStrings.apply,
                          _busy.contains('font')
                              ? null
                              : () => _run('font', () async {
                                  if (_font != null) {
                                    await appearance!.applyFont(_font!);
                                  } else {
                                    await appearance!.selectSystemFont(
                                      _systemFont!,
                                    );
                                  }
                                  _font = null;
                                  _systemFont = null;
                                }),
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            _font = null;
                            _systemFont = null;
                          }),
                          child: const Text(WindowsMusicStrings.cancel),
                        ),
                      ],
                      TextButton(
                        onPressed: appearance == null
                            ? null
                            : () => _run('font', appearance.resetFont),
                        child: const Text(WindowsMusicStrings.restoreDefault),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        IkSettingCard(
          children: [
            _row(
              WindowsMusicStrings.background,
              _button(
                WindowsMusicStrings.chooseImage,
                appearance == null
                    ? null
                    : () => _run('background', () async {
                        final selection = await FilePicker.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
                        );
                        if (selection?.files.single.path == null) return;
                        final draft = await appearance.prepareBackground(
                          File(selection!.files.single.path!),
                        );
                        if (mounted) setState(() => _background = draft);
                      }),
              ),
              description: IkWorkspaceStrings.backgroundHint,
              key: 'background',
            ),
            if (_background != null)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: SizedBox(
                        height: 200,
                        width: double.infinity,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.memory(_background!.bytes, fit: BoxFit.cover),
                            ColoredBox(
                              color: WindowsAppearance.backgroundOverlay(
                                Theme.of(context).brightness,
                              ),
                            ),
                            const Center(
                              child: Text(
                                IkWorkspaceStrings.fontSample,
                                style: TextStyle(fontSize: 20),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        _button(
                          WindowsMusicStrings.apply,
                          _busy.contains('background')
                              ? null
                              : () => _run('background', () async {
                                  await appearance!.applyBackground(
                                    _background!,
                                  );
                                  _background = null;
                                }),
                        ),
                        TextButton(
                          onPressed: () => setState(() => _background = null),
                          child: const Text(WindowsMusicStrings.cancel),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            if (appearance?.backgroundFile != null)
              TextButton(
                onPressed: () =>
                    _run('background', appearance!.resetBackground),
                child: const Text(WindowsMusicStrings.restoreDefault),
              ),
          ],
        ),
        if (appearance != null)
          IkSettingCard(
            children: [
              _row(
                WindowsMusicStrings.closeWindow,
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final item in {
                      WindowsCloseAction.minimize: WindowsMusicStrings.minimize,
                      WindowsCloseAction.exit: WindowsMusicStrings.exit,
                    }.entries)
                      ChoiceChip(
                        label: Text(item.value),
                        selected:
                            appearance.preferences.closeAction == item.key,
                        onSelected:
                            !appearance.nativeAvailable ||
                                _busy.contains('close')
                            ? null
                            : (_) => _run(
                                'close',
                                () => appearance.setCloseAction(item.key),
                              ),
                      ),
                  ],
                ),
                description: appearance.nativeAvailable
                    ? IkWorkspaceStrings.closeHint
                    : WindowsMusicStrings.failure(
                        DesktopFailure.nativeUnavailable,
                      ),
                key: 'close',
              ),
            ],
          ),
      ],
    );
  }

  Widget _lyrics() {
    final state = ref.watch(floatingLyricsProvider),
        notifier = ref.read(floatingLyricsProvider.notifier);
    final busy = ref.watch(ikLyricsActionProvider),
        failed = ref.watch(ikFloatingFailureProvider);
    final capability = ref.watch(ikLyricsCapabilityProvider);
    final issue = ref.watch(ikLyricsIssueProvider);
    Widget colors(Color selected, Future<void> Function(Color) change) => Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final color in const [
          Color(0xff8ee1cc),
          Colors.white,
          Color(0xfff2cc75),
          Color(0xff80b8f0),
          Color(0xffe9b5c6),
        ])
          Semantics(
            label: '#${color.toARGB32().toRadixString(16)}',
            selected: selected == color,
            child: InkWell(
              onTap: _busy.contains('lyric-style')
                  ? null
                  : () => _run('lyric-style', () => change(color)),
              borderRadius: BorderRadius.circular(18),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected == color
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey,
                    width: selected == color ? 3 : 1,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    return IkSettingCard(
      children: [
        _row(
          IkStrings.floating,
          Switch(
            key: const ValueKey('ik-workspace-lyrics'),
            value: state.enabled,
            onChanged: busy || !capability.supported
                ? null
                : ref.read(ikLyricsActionProvider.notifier).setEnabled,
          ),
          description: !capability.supported
              ? capability.message
              : failed
              ? issue ?? IkRuntimeStrings.floatingFailed
              : IkWorkspaceStrings.lyricsHint,
        ),
        Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(22),
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xff203b39),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            IkWorkspaceStrings.lyricsLine,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: state.highlightColor,
              fontSize: state.fontSize.clamp(14, 48),
              height: 1.7,
            ),
          ),
        ),
        _row(
          IkWorkspaceStrings.lyricsFontSize,
          SizedBox(
            width: 220,
            child: Slider(
              value: state.fontSize.clamp(14, 48),
              min: 14,
              max: 48,
              divisions: 34,
              onChanged: capability.supported && !_busy.contains('lyric-style')
                  ? (value) =>
                        _run('lyric-style', () => notifier.setFontSize(value))
                  : null,
            ),
          ),
          description: '${state.fontSize.round()} px',
          key: 'lyric-style',
        ),
        _row(
          IkWorkspaceStrings.lyricsColor,
          capability.supported
              ? colors(state.textColor, notifier.setTextColor)
              : const SizedBox.shrink(),
        ),
        _row(
          IkWorkspaceStrings.lyricsHighlight,
          capability.supported
              ? colors(state.highlightColor, notifier.setHighlightColor)
              : const SizedBox.shrink(),
        ),
        _row(
          IkWorkspaceStrings.lyricsLock,
          Switch(
            value: state.isLocked,
            onChanged:
                capability.supported &&
                    state.enabled &&
                    !_busy.contains('lyric-style')
                ? (value) =>
                      _run('lyric-style', () => notifier.setLocked(value))
                : null,
          ),
          description: IkWorkspaceStrings.lyricsLockHint,
        ),
      ],
    );
  }

  Widget _downloads() {
    final cache = ref.watch(offlineCacheSettingsProvider),
        notifier = ref.read(offlineCacheSettingsProvider.notifier);
    return Column(
      children: [
        IkSettingCard(
          children: [
            _quality(true),
            _row(
              VideoStrings.storageLocation,
              _button(VideoStrings.storageLocation, widget.onDirectory),
            ),
            _row(
              VideoStrings.downloadManagement,
              _button(VideoStrings.downloadManagement, widget.onDownloads),
            ),
          ],
        ),
        IkSettingCard(
          children: [
            _row(
              IkWorkspaceStrings.cacheSize,
              IkSelect<int>(
                alignToDesign: widget.alignToDesign,
                label: IkWorkspaceStrings.cacheSize,
                value: cache.sizeLimitMb,
                items: {
                  for (final size in {
                    cache.sizeLimitMb,
                    512,
                    1024,
                    2048,
                    5120,
                    10240,
                  })
                    size: '$size MB',
                },
                enabled: !_busy.contains('cache'),
                onChanged: (value) =>
                    _run('cache', () => notifier.setSizeLimitMb(value)),
              ),
              key: 'cache',
            ),
            _row(
              IkWorkspaceStrings.cacheOffline,
              Switch(
                value: cache.offlineMode,
                onChanged: _busy.contains('cache')
                    ? null
                    : (value) =>
                          _run('cache', () => notifier.setOfflineMode(value)),
              ),
            ),
            _row(
              IkWorkspaceStrings.cacheWifi,
              Switch(
                value: cache.wifiOnly,
                onChanged: _busy.contains('cache')
                    ? null
                    : (value) =>
                          _run('cache', () => notifier.setWifiOnly(value)),
              ),
            ),
            _row(
              IkWorkspaceStrings.cacheRetry,
              Switch(
                value: cache.autoRetry,
                onChanged: _busy.contains('cache')
                    ? null
                    : (value) =>
                          _run('cache', () => notifier.setAutoRetry(value)),
              ),
            ),
            _row(
              IkWorkspaceStrings.cacheCleanup,
              Switch(
                value: cache.autoCleanup,
                onChanged: _busy.contains('cache')
                    ? null
                    : (value) =>
                          _run('cache', () => notifier.setAutoCleanup(value)),
              ),
            ),
            _row(
              VideoStrings.cacheManagement,
              _button(VideoStrings.cacheManagement, widget.onCache),
            ),
          ],
        ),
      ],
    );
  }

  Widget _accounts() {
    final auth = ref.watch(authProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          IkWorkspaceStrings.accountHint,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 18),
        IkSettingCard(
          children: [
            for (final platform in PlatformType.musicServices)
              _row(
                videoPlatformLabel(platform),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (auth.isLoggedIn(platform)) ...[
                      _button(
                        IkWorkspaceStrings.sync,
                        () => widget.onSync(platform),
                      ),
                      TextButton(
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text(IkWorkspaceStrings.logoutTitle),
                              content: const Text(
                                IkWorkspaceStrings.logoutHint,
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text(WindowsMusicStrings.cancel),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text(IkWorkspaceStrings.logout),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            await ref
                                .read(authProvider.notifier)
                                .logout(platform);
                          }
                        },
                        child: const Text(IkWorkspaceStrings.logout),
                      ),
                    ] else
                      _button(
                        IkWorkspaceStrings.connect,
                        () => widget.onAccount(platform),
                      ),
                    WindowsPlatformIcon(platform: platform, size: 28),
                  ],
                ),
                description:
                    auth.userFor(platform)?.nickname ??
                    IkWorkspaceStrings.accountDisconnected,
              ),
          ],
        ),
      ],
    );
  }

  Widget _backup() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      IkSettingCard(
        children: [
          _row(
            IkWorkspaceStrings.exportBackup,
            _button(
              IkWorkspaceStrings.exportBackup,
              _busy.contains('backup')
                  ? null
                  : () => _run('backup', () async {
                      final file = await ref
                          .read(ikBackupServiceProvider)
                          .exportToFile();
                      _backupStatus = file.path;
                    }),
            ),
            description: IkWorkspaceStrings.backupExportHint,
          ),
          _row(
            IkWorkspaceStrings.selectBackup,
            _button(
              IkWorkspaceStrings.selectBackup,
              _busy.contains('backup')
                  ? null
                  : () => _run('backup', () async {
                      final selection = await FilePicker.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['json'],
                        withData: true,
                      );
                      if (selection == null || selection.files.isEmpty) return;
                      final file = selection.files.single;
                      final raw = file.bytes != null
                          ? BackupService.decodeFileBytes(file.bytes!)
                          : await File(file.path!).readAsString();
                      final summary = ref
                          .read(ikBackupServiceProvider)
                          .inspect(raw);
                      _backupRaw = raw;
                      _backupSummary = summary;
                    }),
            ),
            description: IkWorkspaceStrings.backupImportHint,
            key: 'backup',
          ),
          if (_backupSummary != null)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(IkWorkspaceStrings.backupPreview),
                  const SizedBox(height: 12),
                  Text(_backupSummary.toString()),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton(
                        onPressed: _busy.contains('backup')
                            ? null
                            : () => _run('backup', () async {
                                final report = await ref
                                    .read(ikBackupServiceProvider)
                                    .importFromJson(_backupRaw!);
                                await Future.wait([
                                  ref
                                      .read(likesProvider.notifier)
                                      .loadAllLikes(),
                                  ref
                                      .read(historyProvider.notifier)
                                      .loadAllHistory(),
                                  ref.read(myPlaylistsProvider.notifier).load(),
                                  ref
                                      .read(smartPlaylistsProvider.notifier)
                                      .load(),
                                  ref
                                      .read(listeningStatsProvider.notifier)
                                      .load(),
                                ]);
                                _backupRaw = null;
                                _backupSummary = null;
                                _backupStatus =
                                    '${IkWorkspaceStrings.importComplete}\n$report\n${IkRuntimeStrings.restoreRestart}';
                              }),
                        child: const Text(IkWorkspaceStrings.confirmMerge),
                      ),
                      TextButton(
                        onPressed: _busy.contains('backup')
                            ? null
                            : () => setState(() {
                                _backupRaw = null;
                                _backupSummary = null;
                              }),
                        child: const Text(WindowsMusicStrings.cancel),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
      if (_backupStatus != null) SelectableText(_backupStatus!),
      const SizedBox(height: 10),
      Text(
        IkWorkspaceStrings.backupExclude,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}

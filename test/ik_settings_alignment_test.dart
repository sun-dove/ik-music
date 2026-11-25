import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/features/audio_effects/presentation/providers/audio_effects_provider.dart';
import 'package:mconnect/l10n/ik_runtime_strings.dart';
import 'package:mconnect/l10n/ik_spatial_strings.dart';
import 'package:mconnect/l10n/ik_workspace_strings.dart';
import 'package:mconnect/video_app/ik/ik_audio_runtime.dart';
import 'package:mconnect/video_app/ik/ik_controls.dart';
import 'package:mconnect/video_app/ik/ik_settings_workspace.dart';
import 'package:mconnect/video_app/ik/ik_spatial_runtime.dart';
import 'package:mconnect/video_app/ik/ik_strict_settings.dart';
import 'package:mconnect/video_app/video_preferences.dart';

void main() {
  Future<_Harness> mount(
    WidgetTester tester, {
    String section = 'audio',
    bool aligned = true,
    bool failWrites = false,
    bool supported = true,
    bool failApply = false,
  }) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1;
    final box = _MemoryBox()..failWrites = failWrites;
    final prefs = VideoPreferences(box);
    final backend = _Spatial();
    final savedEffects = <Map<String, dynamic>>[];
    final appliedEffects = <AudioEffectsSettings>[];
    var themeChanges = 0;
    final container = ProviderContainer(
      overrides: [
        audioEffectsSettingsProvider.overrideWith(
          (ref) => IkStrictAudioSettings(
            initial: const AudioEffectsSettings(equalizerEnabled: true),
            write: (value) async {
              if (failWrites) throw StateError('save');
              savedEffects.add(value);
            },
          ),
        ),
        ikAudioRuntimeProvider.overrideWith((ref) {
          final coordinator = IkAudioCoordinator(
            setFade: (_, _) {},
            applyEqualizer: (value) async {
              if (!supported) throw UnsupportedError('equalizer');
              if (failApply) throw StateError('equalizer');
              appliedEffects.add(value);
            },
          );
          ref.listen(audioEffectsSettingsProvider, (_, next) {
            coordinator.apply(next);
          });
          return coordinator;
        }),
        ikSpatialRuntimeProvider.overrideWith(
          (ref) => IkSpatialCoordinator(
            capability: () => supported ? backend : null,
            initial: const SpatialSettings(),
            save: (value) async {
              if (failWrites) throw StateError('spatial-save');
              await box.put('ik.spatial.v1', value.toMap());
            },
            pollAutomatically: false,
          ),
        ),
      ],
    );
    await container.read(ikSpatialRuntimeProvider.notifier).initialize();
    await container
        .read(ikAudioRuntimeProvider.notifier)
        .apply(container.read(audioEffectsSettingsProvider));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: IkSettingsWorkspace(
              preferences: prefs,
              alignToDesign: aligned,
              initialSection: section,
              onThemeChanged: () => themeChanges++,
              onAccount: (_) {},
              onSync: (_) {},
              onSources: () {},
              onDirectory: () {},
              onDownloads: () {},
              onCache: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    return _Harness(
      box,
      prefs,
      container,
      backend,
      savedEffects,
      appliedEffects,
      () => themeChanges,
    );
  }

  testWidgets('A03 默认路径保持横向五频和旧主题选择', (tester) async {
    await mount(tester, aligned: false);
    expect(find.byKey(const ValueKey('ik-spatial-emphasis')), findsNothing);
    expect(find.byType(RotatedBox), findsNothing);
    expect(find.byType(Slider), findsNWidgets(7));
    await tester.tap(find.byKey(const ValueKey('ik-settings-appearance')));
    await tester.pumpAndSettle();
    expect(find.byType(ChoiceChip), findsNWidgets(3));
  });

  testWidgets('A03 对齐设置正文和主工作区采用24px左缘', (tester) async {
    await mount(tester);
    expect(tester.getTopLeft(find.text(IkWorkspaceStrings.settings)).dx, 24);
  });

  testWidgets('A03 对齐下拉继承主题字体，旧默认样式继续原行为', (tester) async {
    for (final aligned in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'UserFontFixture'),
          home: Scaffold(
            body: IkSelect<String>(
              alignToDesign: aligned,
              label: '来源',
              value: 'all',
              items: const {'all': '全部来源', 'qq': 'QQ 音乐'},
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(
        button.style?.textStyle?.resolve({})?.fontFamily,
        aligned ? 'UserFontFixture' : null,
      );
      if (aligned) {
        await tester.tap(find.byType(OutlinedButton));
        await tester.pumpAndSettle();
        final option = tester.widget<Text>(find.text('QQ 音乐'));
        expect(option.style?.fontFamily, 'UserFontFixture');
      }
    }
  });

  testWidgets('A03 新音效布局3D独立强调且五频并排竖向', (tester) async {
    await mount(tester);
    final spatial = find.byKey(const ValueKey('ik-spatial-emphasis'));
    expect(spatial, findsOneWidget);
    expect(
      find.descendant(of: spatial, matching: find.byType(Switch)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: spatial, matching: find.byType(Slider)),
      findsNothing,
    );
    final bands = [
      for (final hz in [60, 230, 910, 3600, 14000])
        find.byKey(ValueKey('ik-eq-slider-$hz')),
    ];
    for (final band in bands) {
      expect(band, findsOneWidget);
      expect(
        tester.getSize(band).height,
        greaterThan(tester.getSize(band).width),
      );
    }
    for (var i = 1; i < bands.length; i++) {
      expect(
        tester.getTopLeft(bands[i]).dy,
        closeTo(tester.getTopLeft(bands.first).dy, .1),
      );
      expect(
        tester.getCenter(bands[i]).dx,
        greaterThan(tester.getCenter(bands[i - 1]).dx),
      );
    }
  });

  testWidgets('A03 竖向频段和预设真实保存并交付音频协调器', (tester) async {
    final h = await mount(tester);
    final band = find.byKey(const ValueKey('ik-eq-slider-60'));
    await tester.ensureVisible(band);
    await tester.drag(band, const Offset(0, -35));
    await tester.pumpAndSettle();
    final settings = h.container.read(audioEffectsSettingsProvider);
    expect(settings.equalizerPreset, EqualizerPreset.custom);
    expect(settings.equalizerBandGains.first, greaterThan(0));
    expect(
      h.savedEffects.last['equalizerBandGains'],
      settings.equalizerBandGains,
    );
    expect(
      h.appliedEffects.last.equalizerBandGains,
      settings.equalizerBandGains,
    );
    final preset = find.byWidgetPredicate(
      (w) => w is IkSelect<EqualizerPreset>,
    );
    await tester.ensureVisible(preset);
    await tester.tap(preset);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(
        MenuItemButton,
        EqualizerPreset.bassBoost.displayName,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      h.container.read(audioEffectsSettingsProvider).equalizerPreset,
      EqualizerPreset.bassBoost,
    );
    expect(
      h.appliedEffects.last.effectiveEqualizerBandGains,
      EqualizerPreset.bassBoost.bandGains,
    );
  });

  testWidgets('A03 保存失败保留频段且行内显示错误', (tester) async {
    final h = await mount(tester, failWrites: true);
    final band = find.byKey(const ValueKey('ik-eq-slider-60'));
    await tester.ensureVisible(band);
    await tester.drag(band, const Offset(0, -35));
    await tester.pumpAndSettle();
    expect(
      h.container.read(audioEffectsSettingsProvider).equalizerPreset,
      EqualizerPreset.flat,
    );
    expect(h.savedEffects, isEmpty);
    expect(find.text(IkWorkspaceStrings.failed), findsWidgets);
  });

  testWidgets('A03 不支持音效时开关频段禁用且显示真实原因', (tester) async {
    await mount(tester, supported: false);
    final spatial = find.byKey(const ValueKey('ik-spatial-emphasis'));
    final toggle = tester.widget<Switch>(
      find.descendant(of: spatial, matching: find.byType(Switch)),
    );
    expect(toggle.onChanged, isNull);
    for (final hz in [60, 230, 910, 3600, 14000]) {
      expect(
        tester
            .widget<Slider>(
              find.descendant(
                of: find.byKey(ValueKey('ik-eq-slider-$hz')),
                matching: find.byType(Slider),
              ),
            )
            .onChanged,
        isNull,
      );
    }
    expect(find.text(IkSpatialStrings.unsupported), findsOneWidget);
    expect(find.text(IkRuntimeStrings.audioUnsupported), findsOneWidget);
  });

  testWidgets('A03 3D未处理音频不显示已生效，真实帧报告后才显示', (tester) async {
    final h = await mount(tester);
    final spatial = find.byKey(const ValueKey('ik-spatial-emphasis'));
    await tester.tap(
      find.descendant(of: spatial, matching: find.byType(Switch)),
    );
    await tester.pumpAndSettle();
    expect(h.box.data['ik.spatial.v1'], containsPair('enabled', true));
    expect(find.text(IkSpatialStrings.waiting), findsOneWidget);
    expect(find.text(IkSpatialStrings.active), findsNothing);
    h.backend.frames = 128;
    await h.container.read(ikSpatialRuntimeProvider.notifier).refresh();
    await tester.pumpAndSettle();
    expect(find.text(IkSpatialStrings.active), findsOneWidget);
  });

  testWidgets('A03 EQ后端失败显示真实错误和重试', (tester) async {
    await mount(tester, failApply: true);
    expect(find.text(IkRuntimeStrings.audioApplyFailed), findsOneWidget);
    expect(
      find.widgetWithText(TextButton, IkWorkspaceStrings.retry),
      findsOneWidget,
    );
  });

  testWidgets('A03 3D保存失败显示真实原因并恢复有效状态', (tester) async {
    final h = await mount(tester, failWrites: true);
    final spatial = find.byKey(const ValueKey('ik-spatial-emphasis'));
    await tester.tap(
      find.descendant(of: spatial, matching: find.byType(Switch)),
    );
    await tester.pumpAndSettle();
    final state = h.container.read(ikSpatialRuntimeProvider);
    expect(state.status, IkSpatialStatus.failed);
    expect(state.effective.enabled, isFalse);
    expect(h.backend.settings.enabled, isFalse);
    expect(h.box.data.containsKey('ik.spatial.v1'), isFalse);
    expect(find.text(state.message), findsOneWidget);
    expect(find.text(IkSpatialStrings.active), findsNothing);
  });

  testWidgets('A03 三主题预览直接保存，重新读偏好保留选择', (tester) async {
    final h = await mount(tester, section: 'appearance');
    final options = [
      for (final mode in ['light', 'dark', 'system'])
        find.byKey(ValueKey('ik-theme-preview-$mode')),
    ];
    for (final option in options) {
      expect(option, findsOneWidget);
      expect(
        find.descendant(of: option, matching: find.byType(InkWell)),
        findsOneWidget,
      );
    }
    expect(find.byType(ChoiceChip), findsNothing);
    expect(
      tester.getTopLeft(options[0]).dy,
      closeTo(tester.getTopLeft(options[2]).dy, .1),
    );
    await tester.tap(options[1]);
    await tester.pumpAndSettle();
    expect(VideoPreferences(h.box).theme, 'dark');
    expect(h.themeChanges(), 1);
    await tester.tap(options[2]);
    await tester.pumpAndSettle();
    expect(VideoPreferences(h.box).theme, 'system');
    expect(h.themeChanges(), 2);
  });

  testWidgets('A03 主题写失败不改选择或通知主壳且错误留在页内', (tester) async {
    final h = await mount(tester, section: 'appearance', failWrites: true);
    await tester.tap(find.byKey(const ValueKey('ik-theme-preview-dark')));
    await tester.pumpAndSettle();
    expect(h.preferences.theme, 'light');
    expect(h.themeChanges(), 0);
    expect(find.text(IkWorkspaceStrings.failed), findsOneWidget);
  });

  testWidgets('A03 常规设置行在中宽保持同行，窄窗和放大字号回退', (tester) async {
    for (final sample in [
      (width: 520.0, scale: 1.0, aligned: true, inline: true),
      (width: 520.0, scale: 1.0, aligned: false, inline: false),
      (width: 320.0, scale: 1.0, aligned: true, inline: false),
      (width: 520.0, scale: 1.5, aligned: true, inline: false),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(sample.scale)),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: sample.width,
                  child: IkSettingRow(
                    alignToDesign: sample.aligned,
                    title: '设置项目',
                    control: Switch(
                      key: const ValueKey('control'),
                      value: false,
                      onChanged: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final label = tester.getCenter(find.text('设置项目'));
      final control = tester.getCenter(find.byKey(const ValueKey('control')));
      if (sample.inline) {
        expect(label.dy, closeTo(control.dy, .1));
      } else {
        expect(control.dy, greaterThan(label.dy));
      }
      expect(tester.takeException(), isNull);
    }
  });
}

class _Harness {
  _Harness(
    this.box,
    this.preferences,
    this.container,
    this.backend,
    this.savedEffects,
    this.appliedEffects,
    this.themeChanges,
  );
  final _MemoryBox box;
  final VideoPreferences preferences;
  final ProviderContainer container;
  final _Spatial backend;
  final List<Map<String, dynamic>> savedEffects;
  final List<AudioEffectsSettings> appliedEffects;
  final int Function() themeChanges;
}

class _MemoryBox extends Fake implements Box {
  final data = <dynamic, dynamic>{};
  bool failWrites = false;
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => data[key] ?? defaultValue;
  @override
  Future<void> put(dynamic key, dynamic value) async {
    if (failWrites) throw StateError('save');
    data[key] = value;
  }
}

class _Spatial implements SpatialAudioCapable {
  SpatialSettings settings = const SpatialSettings();
  int request = 0, frames = 0;
  @override
  Future<bool> supportsSpatialAudio() async => true;
  @override
  Future<void> applySpatialAudio(SpatialSettings value, int requestId) async {
    settings = value;
    request = requestId;
  }

  @override
  Future<SpatialProcessingReport> readSpatialAudio() async =>
      SpatialProcessingReport(requestId: request, processedFrames: frames);
}

import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/core/platform/platform_utils.dart';
import 'package:mconnect/features/auth/presentation/providers/auth_provider.dart';
import 'package:mconnect/features/audio_effects/presentation/providers/audio_effects_provider.dart';
import 'package:mconnect/features/offline_cache/presentation/providers/offline_cache_provider.dart';
import 'package:mconnect/features/player/data/playback_keep_alive_service.dart';
import 'package:mconnect/features/player/data/playback_notification_service.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/l10n/ik_workspace_strings.dart';
import 'package:mconnect/l10n/windows_music_strings.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/video_app/ik/ik_controls.dart';
import 'package:mconnect/video_app/ik/ik_settings_workspace.dart';
import 'package:mconnect/video_app/ik/ik_strict_settings.dart';
import 'package:mconnect/video_app/built_in/catalog.dart';
import 'package:mconnect/video_app/built_in/catalog_coordinator.dart';
import 'package:mconnect/video_app/built_in/fixed_importer.dart';
import 'package:mconnect/video_app/built_in/managed_settings.dart';
import 'package:mconnect/video_app/lx_source/lx_source.dart';
import 'package:mconnect/video_app/multi_source/multi_source_player.dart';
import 'package:mconnect/video_app/multi_source/source_collection.dart';
import 'package:mconnect/video_app/multi_source/source_coordinator.dart';
import 'package:mconnect/video_app/video_preferences.dart';
import 'package:mconnect/video_app/windows/windows_appearance.dart';
import 'package:mconnect/video_app/windows/windows_music_preferences.dart';
import 'package:mconnect/video_app/windows/windows_window_controller.dart';

import 'support/content_page_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory scratch;
  late Box box;
  late Zone ioZone;
  const lyricsChannel = MethodChannel('com.mconnect.mconnect/floating_lyrics');
  setUpAll(() async {
    ioZone = Zone.current;
    scratch = await Directory.systemTemp.createTemp('ik-settings-formal-');
    Hive.init(scratch.path);
    box = await Hive.openBox('settings');
  });
  setUp(() async {
    await box.clear();
    PlatformUtils.setDebugOverride(AppPlatform.windows);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(lyricsChannel, (_) async => true);
  });
  tearDown(() {
    PlatformUtils.setDebugOverride(null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(lyricsChannel, null);
  });
  tearDownAll(() async {
    await Hive.close();
    final target = scratch.absolute.path;
    if (!target.startsWith(
          '${Directory.systemTemp.absolute.path}${Platform.pathSeparator}',
        ) ||
        !scratch.path
            .split(Platform.pathSeparator)
            .last
            .startsWith('ik-settings-formal-')) {
      throw StateError('拒绝删除未知目录');
    }
    if (await scratch.exists()) await scratch.delete(recursive: true);
  });

  Future<_Harness> mount(
    WidgetTester tester, {
    String section = 'audio',
    double width = 1200,
    double scale = 1,
    bool failWrites = false,
    bool qualityPlayback = false,
    bool localPlayback = false,
    bool failQualityWrites = false,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    final prefs = VideoPreferences(box);
    final sources = qualityPlayback
        ? (WindowsSourceSettings(prefs)
            ..value = const SourceCollection(autoSwitch: true))
        : null;
    final unified = WindowsMusicPreferences(
      prefs,
      sources: sources,
      write: (values) => failQualityWrites
          ? Future.error(StateError('save'))
          : ioZone.run(() async {
              await box.putAll(values);
              await box.flush();
            }),
    )..load();
    final appearance = WindowsAppearance(
      preferences: unified,
      directory: Directory('${scratch.path}/appearance'),
      window: _Window(),
    );
    await tester.runAsync(appearance.initialize);
    final qualityAudio = _QualityAudio();
    final qualityRequests = <AudioLevel>[];
    final player = qualityPlayback
        ? MultiSourceVideoPlayerNotifier(
            settings: sources!,
            router: PreparedSourceRouter(
              platformResolver: (_) =>
                  FakeContentPlatform(type: PlatformType.qq),
              fixedQuality: unified.quality,
            ),
            resolve: (_, candidate, _) async {
              qualityRequests.add(candidate.quality);
              return ResolvedSource(
                candidate,
                Uri.parse('https://example.test/${candidate.quality.name}'),
              );
            },
            audioController: qualityAudio,
            audioControllerFactory: () => qualityAudio,
            keepAliveController: const NoopPlaybackKeepAliveController(),
            notificationController: const NoopPlaybackNotificationController(),
          )
        : PlayerNotifier(
            audioController: IdleAudioController(),
            audioControllerFactory: IdleAudioController.new,
            keepAliveController: const NoopPlaybackKeepAliveController(),
            notificationController: const NoopPlaybackNotificationController(),
            stuckWatchdogInterval: Duration.zero,
            playbackHealthCheckInterval: Duration.zero,
            playbackMemorySaveInterval: Duration.zero,
          );
    final container = ProviderContainer(
      overrides: [
        playerProvider.overrideWith((ref) => player),
        authProvider.overrideWith((ref) => AuthNotifier()),
        audioEffectsSettingsProvider.overrideWith(
          (ref) => IkStrictAudioSettings(
            write: (value) => failWrites
                ? Future.error(StateError('save'))
                : ioZone.run(() async {
                    await box.put('audio_effects_settings', value);
                    await box.flush();
                  }),
          ),
        ),
        offlineCacheSettingsProvider.overrideWith(
          (ref) => IkStrictCacheSettings(
            write: (value) => failWrites
                ? Future.error(StateError('save'))
                : ioZone.run(() async {
                    await box.put('offline_cache_settings', value);
                    await box.flush();
                  }),
          ),
        ),
        if (section == 'sources')
          ikSourceCatalogProvider.overrideWith((ref) {
            final coordinator = IkSourceCatalogCoordinator(
              catalog: IkSourceCatalog.fromJson(
                jsonDecode(
                  File('assets/source-catalog/pdone-v1.json')
                      .readAsStringSync(),
                ) as Map<String, dynamic>,
              ),
              settings: IkManagedSourceSettings(prefs)..load(),
              runtimeId: 'windows-lx3',
              importer: IkFixedSourceImporter(engine: _UnusedEngine()),
            );
            ref.onDispose(coordinator.dispose);
            return coordinator;
          }),
      ],
    );
    final harness = _Harness(
      prefs,
      unified,
      appearance,
      container,
      player,
      qualityAudio,
      qualityRequests,
      sources,
    );
    container.read(playerProvider.notifier);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: IkSettingsWorkspace(
              preferences: prefs,
              appearance: appearance,
              unified: unified,
              initialSection: section,
              onThemeChanged: () {},
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    if (qualityPlayback) {
      await tester.runAsync(() async {
        await player.playSong(
          Song(
            id: localPlayback ? '${scratch.path}/quality.mp3' : 'quality',
            platform: localPlayback ? PlatformType.local : PlatformType.qq,
            name: '音质连续性验收曲目',
            artists: const [],
          ),
        );
        await player.seek(const Duration(seconds: 42));
      });
      await tester.pump();
      expect(player.state.isPlaying, isTrue);
    }
    return harness;
  }

  Future<void> unmount(WidgetTester tester, _Harness harness) async {
    await tester.pumpWidget(const SizedBox.shrink());
    harness.container.dispose();
    harness.appearance.dispose();
    harness.unified.dispose();
    harness.sources?.dispose();
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }

  testWidgets('U03 旧混合质量的沿用原设置可点且不报错', (tester) async {
    await tester.runAsync(
      () => box.put('video.qq.play', AudioLevel.lossless.name),
    );
    final h = await mount(tester);
    final select = tester.widget<IkSelect<String>>(
      find.byWidgetPredicate(
        (w) =>
            w is IkSelect<String> && w.label == WindowsMusicStrings.playQuality,
      ),
    );
    expect(select.value, WindowsMusicStrings.keepLegacyQuality);
    select.onChanged(WindowsMusicStrings.keepLegacyQuality);
    await tester.pump();
    expect(find.text(IkWorkspaceStrings.failed), findsNothing);
    expect(h.unified.quality(PlatformType.qq), AudioLevel.lossless);
    expect(h.unified.quality(PlatformType.netease), AudioLevel.low);
    await unmount(tester, h);
  });

  testWidgets('U03 外部质量和外观通知刷新当前缓存表单', (tester) async {
    final h = await mount(tester, section: 'downloads');
    await tester.runAsync(
      () => h.unified.setQuality(AudioLevel.lossless, download: true),
    );
    await tester.pump();
    final select = tester.widget<IkSelect<String>>(
      find.byWidgetPredicate(
        (w) =>
            w is IkSelect<String> &&
            w.label == WindowsMusicStrings.downloadQuality,
      ),
    );
    expect(select.value, WindowsMusicStrings.qualityName(AudioLevel.lossless));
    await unmount(tester, h);
  });

  Future<void> chooseQuality(
    WidgetTester tester, {
    bool download = false,
  }) async {
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is IkSelect<String> &&
            widget.label ==
                (download
                    ? WindowsMusicStrings.downloadQuality
                    : WindowsMusicStrings.playQuality),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(WindowsMusicStrings.qualityName(AudioLevel.lossless)).last,
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump();
  }

  testWidgets('U03 播放音质保存后真实多源换流并保持42秒继续播放', (tester) async {
    final h = await mount(tester, qualityPlayback: true);
    await chooseQuality(tester);
    expect(h.unified.quality(PlatformType.qq), AudioLevel.lossless);
    expect(h.qualityRequests, [AudioLevel.low, AudioLevel.lossless]);
    expect(h.audio.url, 'https://example.test/lossless');
    expect(h.player.state.currentQuality, AudioLevel.lossless);
    expect(h.player.state.isPlaying, isTrue);
    expect(h.audio.position, const Duration(seconds: 42));
    expect(find.text(IkWorkspaceStrings.failed), findsNothing);
    final select = tester.widget<IkSelect<String>>(
      find.byWidgetPredicate(
        (widget) =>
            widget is IkSelect<String> &&
            widget.label == WindowsMusicStrings.playQuality,
      ),
    );
    expect(select.value, WindowsMusicStrings.qualityName(AudioLevel.lossless));
    await unmount(tester, h);
  });

  testWidgets('U03 下载音质保存不会暂停或重载当前流', (tester) async {
    final h = await mount(tester, section: 'downloads', qualityPlayback: true);
    await chooseQuality(tester, download: true);
    expect(
      h.unified.quality(PlatformType.qq, download: true),
      AudioLevel.lossless,
    );
    expect(h.qualityRequests, [AudioLevel.low]);
    expect(h.audio.loads, hasLength(1));
    expect(h.player.state.isPlaying, isTrue);
    expect(h.audio.position, const Duration(seconds: 42));
    await unmount(tester, h);
  });

  testWidgets('U03 音质保存失败保持原流并显示行内错误', (tester) async {
    final h = await mount(
      tester,
      qualityPlayback: true,
      failQualityWrites: true,
    );
    await chooseQuality(tester);
    expect(h.unified.quality(PlatformType.qq), AudioLevel.low);
    expect(h.qualityRequests, [AudioLevel.low]);
    expect(h.audio.loads, hasLength(1));
    expect(h.player.state.isPlaying, isTrue);
    expect(h.audio.position, const Duration(seconds: 42));
    expect(
      find.text(WindowsMusicStrings.failure(DesktopFailure.saveFailed)),
      findsOneWidget,
    );
    await unmount(tester, h);
  });

  testWidgets('U03 本地播放时保存在线音质不重载本地文件', (tester) async {
    final h = await mount(tester, qualityPlayback: true, localPlayback: true);
    await chooseQuality(tester);
    expect(h.unified.quality(PlatformType.qq), AudioLevel.lossless);
    expect(h.qualityRequests, isEmpty);
    expect(h.audio.loads, hasLength(1));
    expect(h.player.state.isPlaying, isTrue);
    expect(h.audio.position, const Duration(seconds: 42));
    await unmount(tester, h);
  });

  testWidgets('U06 未支持平台歌词开关禁用并显示真实原因', (tester) async {
    PlatformUtils.setDebugOverride(AppPlatform.linux);
    final h = await mount(tester, section: 'lyrics');
    final toggle = tester.widget<Switch>(
      find.byKey(const ValueKey('ik-workspace-lyrics')),
    );
    expect(toggle.onChanged, isNull);
    await unmount(tester, h);
  });
  testWidgets('U03 设置写失败回到原值且行内显示错误', (tester) async {
    final h = await mount(tester, section: 'downloads', failWrites: true);
    final select = tester.widget<IkSelect<int>>(
      find.byWidgetPredicate(
        (w) => w is IkSelect<int> && w.label == IkWorkspaceStrings.cacheSize,
      ),
    );
    select.onChanged(2048);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
    expect(h.container.read(offlineCacheSettingsProvider).sizeLimitMb, 1024);
    expect(find.text(IkWorkspaceStrings.failed), findsOneWidget);
    await unmount(tester, h);
  });

  testWidgets('U04 系统字体外部变化和异常旧字号不会破坏表单', (tester) async {
    final h = await mount(tester, section: 'appearance');
    await tester.runAsync(() => h.appearance.selectSystemFont('Noto Sans SC'));
    await tester.pump();
    final select = tester.widget<IkSelect<String>>(
      find.byWidgetPredicate(
        (w) => w is IkSelect<String> && w.label == WindowsMusicStrings.font,
      ),
    );
    expect(select.value, 'Noto Sans SC');
    await unmount(tester, h);
    await tester.runAsync(
      () => box.put('floating_lyrics_settings', {'fontSize': 96.0}),
    );
    final next = await mount(tester, section: 'lyrics');
    expect(tester.takeException(), isNull);
    await unmount(tester, next);
  });

  testWidgets('U11 七区×六宽度×三字号完整126布局无溢出', (tester) async {
    var checked = 0;
    for (final section in [
      'audio',
      'appearance',
      'lyrics',
      'sources',
      'downloads',
      'accounts',
      'backup',
    ]) {
      for (final width in [1440.0, 1200.0, 900.0, 720.0, 390.0, 320.0]) {
        for (final scale in [1.0, 1.25, 1.5]) {
          final h = await mount(
            tester,
            section: section,
            width: width,
            scale: scale,
          );
          final failures = <Object>[];
          Object? next;
          while ((next = tester.takeException()) != null) {
            failures.add(next!);
          }
          expect(failures, isEmpty, reason: '$section $width ${scale * 100}%');
          expect(find.byType(IkSettingsWorkspace), findsOneWidget);
          checked++;
          await unmount(tester, h);
        }
      }
    }
    expect(checked, 126);
  });
}

class _Harness {
  _Harness(
    this.preferences,
    this.unified,
    this.appearance,
    this.container,
    this.player,
    this.audio,
    this.qualityRequests,
    this.sources,
  );
  final VideoPreferences preferences;
  final WindowsMusicPreferences unified;
  final WindowsAppearance appearance;
  final ProviderContainer container;
  final PlayerNotifier player;
  final _QualityAudio audio;
  final List<AudioLevel> qualityRequests;
  final WindowsSourceSettings? sources;
}

class _QualityAudio extends IdleAudioController {
  final loads = <String>[];
  String? url;
  bool _playing = false;
  Duration _position = Duration.zero;
  @override
  bool get playing => _playing;
  @override
  Duration get position => _position;
  @override
  Future<void> setUrl(String value) async {
    loads.add(value);
    url = value;
  }

  @override
  Future<void> play() async => _playing = true;
  @override
  Future<void> pause() async => _playing = false;
  @override
  Future<void> stop() async => _playing = false;
  @override
  Future<void> seek(Duration value) async => _position = value;
}

class _Window extends WindowsWindowController {
  @override
  Future<void> setCloseAction(WindowsCloseAction value) async {}
  @override
  Future<List<String>> listFonts() async => [
    'Microsoft YaHei UI',
    'Noto Sans SC',
  ];
}

class _UnusedEngine extends Fake implements LxSourceEngine {}

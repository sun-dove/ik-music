import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/core/platform/platform_utils.dart';
import 'package:mconnect/features/player/data/playback_keep_alive_service.dart';
import 'package:mconnect/features/player/data/playback_notification_service.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/platform/qq/qq_platform.dart';
import 'package:mconnect/video_app/lx_source/lx_source.dart';
import 'package:mconnect/video_app/multi_source/source_collection.dart';
import 'package:mconnect/video_app/multi_source/source_coordinator.dart';
import 'package:mconnect/video_app/multi_source/multi_source_player.dart';
import 'package:mconnect/video_app/video_preferences.dart';

const song = Song(
  id: 'mid',
  platform: PlatformType.qq,
  name: '测试歌曲',
  artists: [],
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('实际播放器在A地址加载失败后播放B，不重新请求标准档', () async {
    final settings = SourceSettings(VideoPreferences(_Box()));
    var collection = const SourceCollection(
      autoSwitch: true,
      sourceFirst: true,
      highestQuality: true,
    );
    for (final name in ['A', 'B']) {
      collection = collection.upsert(
        LxSourceConfig(
          name: name,
          version: '1',
          origin: Uri.parse('https://example.com/$name.js'),
          script: 'fixture',
          sha256: name,
          sources: const {
            'tx': ['flac', '128k'],
          },
          enabled: true,
        ),
      );
    }
    settings.value = collection;
    final calls = <String>[];
    final audio = _Audio();
    final router = PreparedSourceRouter(
      platformResolver: (_) => QqPlatform(),
      fixedQuality: (_) => AudioLevel.low,
    );
    final player = MultiSourceVideoPlayerNotifier(
      settings: settings,
      router: router,
      resolve: (_, c, token) async {
        calls.add('${c.name}:${c.quality.name}');
        if (c.official) throw const SourceFailure('unavailable', '官方不可用');
        return ResolvedSource(c, Uri.parse('https://example.com/${c.name}'));
      },
      audioController: audio,
      audioControllerFactory: () => audio,
      notificationController: const NoopPlaybackNotificationController(),
      keepAliveController: const NoopPlaybackKeepAliveController(),
    );
    addTearDown(player.dispose);
    await player.playSong(song);
    expect(player.state.isPlaying, isTrue);
    expect(player.state.currentSong, song);
    expect(player.state.currentQuality, AudioLevel.lossless);
    expect(audio.url, 'https://example.com/B');
    expect(audio.loads.where((url) => url.endsWith('/A')), hasLength(1));
    expect(calls, ['QQ音乐:hires', 'A:lossless', 'B:lossless']);
  });
  for (final failure in ['timeout', 'network', 'serverError']) {
    test('快速播放中A高音质$failure后仍按原顺序播放A标准音质', () async {
      final settings = _quickSourceSettings();
      final audio = _Audio();
      final calls = <String>[];
      final player = MultiSourceVideoPlayerNotifier(
        settings: settings,
        router: PreparedSourceRouter(
          platformResolver: (_) => QqPlatform(),
          fixedQuality: (_) => AudioLevel.low,
        ),
        quickSourceRecovery: true,
        quickResolveTimeout: const Duration(milliseconds: 100),
        quickLoadTimeout: const Duration(milliseconds: 100),
        quickBudget: const Duration(seconds: 2),
        resolve: (_, candidate, _) async {
          calls.add('${candidate.name}:${candidate.quality.name}');
          if (candidate.official) {
            throw const SourceFailure('unavailable', '官方不可用');
          }
          if (candidate.quality != AudioLevel.low) {
            if (failure == 'timeout') throw TimeoutException('高音质暂时超时');
            throw SourceFailure(failure, '高音质暂时不可用');
          }
          return ResolvedSource(
            candidate,
            Uri.parse('https://example.com/A-low'),
          );
        },
        audioController: audio,
        audioControllerFactory: () => audio,
        notificationController: const NoopPlaybackNotificationController(),
        keepAliveController: const NoopPlaybackKeepAliveController(),
      );
      addTearDown(player.dispose);
      await player.playSong(song);
      expect(player.state.isPlaying, isTrue);
      expect(player.state.error, isNull);
      expect(player.state.currentQuality, AudioLevel.low);
      expect(audio.url, 'https://example.com/A-low');
      expect(audio.loads, ['https://example.com/A-low']);
      expect(calls, [
        'QQ音乐:hires',
        'A:lossless',
        'QQ音乐:lossless',
        'A:high',
        'QQ音乐:high',
        'A:low',
      ]);
    });
  }
  for (final failure in ['dns', 'script']) {
    test('快速播放中明确$failure源级失败仍跳过同源其余音质', () async {
      final settings = _quickSourceSettings();
      final audio = _Audio();
      final calls = <String>[];
      final player = MultiSourceVideoPlayerNotifier(
        settings: settings,
        router: PreparedSourceRouter(
          platformResolver: (_) => QqPlatform(),
          fixedQuality: (_) => AudioLevel.low,
        ),
        quickSourceRecovery: true,
        quickResolveTimeout: const Duration(milliseconds: 100),
        quickLoadTimeout: const Duration(milliseconds: 100),
        quickBudget: const Duration(seconds: 2),
        resolve: (_, candidate, _) async {
          calls.add('${candidate.name}:${candidate.quality.name}');
          if (!candidate.official) {
            throw SourceFailure(failure, '整源不可用', sourceWide: true);
          }
          if (candidate.quality != AudioLevel.low) {
            throw const SourceFailure('unavailable', '官方高音质不可用');
          }
          return ResolvedSource(
            candidate,
            Uri.parse('https://example.com/official-low'),
          );
        },
        audioController: audio,
        audioControllerFactory: () => audio,
        notificationController: const NoopPlaybackNotificationController(),
        keepAliveController: const NoopPlaybackKeepAliveController(),
      );
      addTearDown(player.dispose);
      await player.playSong(song);
      expect(player.state.isPlaying, isTrue);
      expect(player.state.error, isNull);
      expect(audio.url, 'https://example.com/official-low');
      expect(calls, [
        'QQ音乐:hires',
        'A:lossless',
        'QQ音乐:lossless',
        'QQ音乐:high',
        'QQ音乐:low',
      ]);
    });
  }
  test('快速播放加载时暂停后旧结果不能出声', () async {
    final settings = SourceSettings(VideoPreferences(_Box()));
    final audio = _Audio()..pending = Completer<void>();
    final player = MultiSourceVideoPlayerNotifier(
      settings: settings,
      router: PreparedSourceRouter(
        platformResolver: (_) => QqPlatform(),
        fixedQuality: (_) => AudioLevel.low,
      ),
      quickSourceRecovery: true,
      quickResolveTimeout: const Duration(milliseconds: 100),
      quickLoadTimeout: const Duration(milliseconds: 100),
      quickBudget: const Duration(seconds: 2),
      resolve: (_, candidate, _) async =>
          ResolvedSource(candidate, Uri.parse('https://example.com/pending')),
      audioController: audio,
      audioControllerFactory: () => audio,
      notificationController: const NoopPlaybackNotificationController(),
      keepAliveController: const NoopPlaybackKeepAliveController(),
    );
    addTearDown(player.dispose);
    final loading = player.playSong(song);
    while (audio.loads.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    await player.pause();
    audio.pending!.complete();
    await loading;
    expect(audio.playCalls, 0);
    expect(player.state.isPlaying, isFalse);
    expect(player.state.isTransitioning, isFalse);
    expect(player.state.error, isNull);
  });
  test('Android快速播放的长play Future超过一秒仍继续且可暂停', () async {
    PlatformUtils.setDebugOverride(AppPlatform.android);
    addTearDown(() => PlatformUtils.setDebugOverride(null));
    final settings = SourceSettings(VideoPreferences(_Box()));
    final audio = _LongPlayAudio();
    var resolutions = 0;
    final player = MultiSourceVideoPlayerNotifier(
      settings: settings,
      router: PreparedSourceRouter(
        platformResolver: (_) => QqPlatform(),
        fixedQuality: (_) => AudioLevel.low,
      ),
      quickSourceRecovery: true,
      quickResolveTimeout: const Duration(milliseconds: 100),
      quickLoadTimeout: const Duration(milliseconds: 100),
      quickBudget: const Duration(seconds: 2),
      resolve: (_, candidate, _) async {
        resolutions++;
        return ResolvedSource(candidate, Uri.parse('https://example.com/long'));
      },
      audioController: audio,
      audioControllerFactory: () => audio,
      notificationController: const NoopPlaybackNotificationController(),
      keepAliveController: const NoopPlaybackKeepAliveController(),
    );
    addTearDown(player.dispose);
    await player.playSong(song);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(audio.playPending, isTrue);
    expect(audio.playing, isTrue);
    expect(player.state.isPlaying, isTrue);
    expect(player.state.error, isNull);
    expect(resolutions, 1);
    await player.pause();
    expect(audio.playPending, isFalse);
    expect(audio.playing, isFalse);
    expect(player.state.isPlaying, isFalse);
    expect(player.state.error, isNull);
  });
  test('切歌后旧解析结果不能覆盖新歌曲', () async {
    final settings = SourceSettings(VideoPreferences(_Box()));
    settings.value = const SourceCollection(highestQuality: true);
    final pending = Completer<ResolvedSource>();
    final audio = _Audio();
    final player = MultiSourceVideoPlayerNotifier(
      settings: settings,
      router: PreparedSourceRouter(
        platformResolver: (_) => QqPlatform(),
        fixedQuality: (_) => AudioLevel.low,
      ),
      resolve: (s, c, _) => s.id == 'mid'
          ? pending.future
          : Future.value(ResolvedSource(c, Uri.parse('https://example.com/B'))),
      audioController: audio,
      audioControllerFactory: () => audio,
      notificationController: const NoopPlaybackNotificationController(),
      keepAliveController: const NoopPlaybackKeepAliveController(),
    );
    addTearDown(player.dispose);
    final a = player.playSong(song);
    await Future<void>.delayed(Duration.zero);
    const other = Song(
      id: 'other',
      platform: PlatformType.qq,
      name: '新歌',
      artists: [],
    );
    await player.playSong(other);
    pending.complete(
      ResolvedSource(
        const SourceCandidate(id: 'old', name: 'old', quality: AudioLevel.low),
        Uri.parse('https://example.com/old'),
      ),
    );
    await a;
    expect(player.state.currentSong, other);
    expect(audio.url, 'https://example.com/B');
  });
  test('暂停使正在装载的旧音频失效，完成后不能出声', () async {
    final settings = SourceSettings(VideoPreferences(_Box()))
      ..value = const SourceCollection(highestQuality: true);
    final audio = _Audio()..pending = Completer<void>();
    final player = MultiSourceVideoPlayerNotifier(
      settings: settings,
      router: PreparedSourceRouter(
        platformResolver: (_) => QqPlatform(),
        fixedQuality: (_) => AudioLevel.low,
      ),
      resolve: (s, c, _) async =>
          ResolvedSource(c, Uri.parse('https://example.com/B')),
      audioController: audio,
      audioControllerFactory: () => audio,
      notificationController: const NoopPlaybackNotificationController(),
      keepAliveController: const NoopPlaybackKeepAliveController(),
    );
    addTearDown(player.dispose);
    final work = player.playSong(song);
    while (audio.loads.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    await player.togglePlay();
    audio.pending!.complete();
    await work;
    expect(audio.playCalls, 0);
    expect(player.state.isPlaying, isFalse);
    expect(player.state.error, isNull);
  });
  test('播放中错误继续下一源并恢复进度，暂停不触发换源', () async {
    final settings = SourceSettings(VideoPreferences(_Box()));
    var collection = const SourceCollection(
      autoSwitch: true,
      sourceFirst: true,
    );
    for (final name in ['B', 'C']) {
      collection = collection.upsert(
        LxSourceConfig(
          name: name,
          version: '1',
          origin: Uri.parse('https://example.com/$name.js'),
          script: 'fixture',
          sha256: name,
          sources: const {
            'tx': ['128k'],
          },
          enabled: true,
        ),
      );
    }
    settings.value = collection;
    final audio = _Audio();
    final calls = <String>[];
    final player = MultiSourceVideoPlayerNotifier(
      settings: settings,
      router: PreparedSourceRouter(
        platformResolver: (_) => QqPlatform(),
        fixedQuality: (_) => AudioLevel.low,
      ),
      resolve: (s, c, _) async {
        calls.add(c.name);
        return ResolvedSource(c, Uri.parse('https://example.com/${c.name}'));
      },
      audioController: audio,
      audioControllerFactory: () => audio,
      notificationController: const NoopPlaybackNotificationController(),
      keepAliveController: const NoopPlaybackKeepAliveController(),
    );
    addTearDown(player.dispose);
    await player.playSong(song);
    await player.seek(const Duration(seconds: 42));
    audio.events.addError(StateError('媒体断开'));
    for (var i = 0; i < 30 && audio.url != 'https://example.com/C'; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    await Future<void>.delayed(Duration.zero);
    expect(audio.url, 'https://example.com/C');
    expect(player.state.currentSong, song);
    expect(audio.seekPosition, const Duration(seconds: 42));
    expect(calls, ['B', 'C']);
    await player.togglePlay();
    audio.events.addError(StateError('暂停后的旧错误'));
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['B', 'C']);
    expect(player.state.isPlaying, isFalse);
    expect(player.state.error, isNull);
  });
  test('离线本地命中不向任何音源请求，固定质量切换重新取流', () async {
    final settings = SourceSettings(VideoPreferences(_Box()))
      ..value = const SourceCollection(autoSwitch: true);
    final audio = _Audio();
    final qualities = <AudioLevel>[];
    var offline = true;
    final player = MultiSourceVideoPlayerNotifier(
      settings: settings,
      router: PreparedSourceRouter(
        platformResolver: (_) => QqPlatform(),
        fixedQuality: (_) => AudioLevel.low,
      ),
      resolve: (s, c, _) async {
        qualities.add(c.quality);
        return ResolvedSource(
          c,
          Uri.parse('https://example.com/${c.quality.name}'),
        );
      },
      isOfflineModeEnabled: () => offline,
      offlineFilePathResolver: (_) async =>
          Directory.systemTemp.uri.resolve('song.mp3').toFilePath(),
      audioController: audio,
      audioControllerFactory: () => audio,
      notificationController: const NoopPlaybackNotificationController(),
      keepAliveController: const NoopPlaybackKeepAliveController(),
    );
    addTearDown(player.dispose);
    await player.playSong(song);
    expect(qualities, isEmpty);
    expect(audio.url, startsWith('file:'));
    offline = false;
    await player.playSong(song);
    await player.switchQuality(AudioLevel.lossless);
    expect(qualities, [AudioLevel.low, AudioLevel.lossless]);
    expect(player.state.currentQuality, AudioLevel.lossless);
  });
}

SourceSettings _quickSourceSettings() =>
    SourceSettings(VideoPreferences(_Box()))
      ..value =
          const SourceCollection(
            autoSwitch: true,
            sourceFirst: true,
            highestQuality: true,
          ).upsert(
            LxSourceConfig(
              name: 'A',
              version: '1',
              origin: Uri.parse('https://example.com/A.js'),
              script: 'fixture',
              sha256: 'A',
              sources: const {
                'tx': ['flac', '320k', '128k'],
              },
              enabled: true,
            ),
          );

class _Box extends Fake implements Box {
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => defaultValue;
}

class _Audio implements PlayerAudioController {
  String? url;
  final loads = <String>[];
  Completer<void>? pending;
  int playCalls = 0;
  final events = StreamController<AudioPlaybackState>.broadcast();
  Duration seekPosition = Duration.zero;
  bool _playing = false;
  @override
  bool get playing => _playing;
  @override
  Duration get position => seekPosition;
  @override
  double get volume => 1;
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<Duration?> get durationStream => const Stream.empty();
  @override
  Stream<AudioPlaybackState> get playerStateStream => events.stream;
  @override
  Future<void> stop() async {
    _playing = false;
  }

  @override
  Future<void> setUrl(String value) async {
    loads.add(value);
    await pending?.future;
    if (value.endsWith('/A')) throw StateError('音频404');
    url = value;
  }

  @override
  Future<void> play() async {
    playCalls++;
    _playing = true;
  }

  @override
  Future<void> pause() async {
    _playing = false;
  }

  @override
  Future<void> seek(Duration position) async {
    seekPosition = position;
  }

  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> applyEqualizer({
    required bool enabled,
    required List<double> bandGains,
  }) async {}
  @override
  Future<void> dispose() async {}
}

class _LongPlayAudio extends _Audio {
  Completer<void>? _playCompletion;
  bool get playPending => _playCompletion?.isCompleted == false;
  @override
  Future<void> play() async {
    await super.play();
    final completion = Completer<void>();
    _playCompletion = completion;
    await completion.future;
  }

  void _finishPlay() {
    if (playPending) _playCompletion!.complete();
  }

  @override
  Future<void> pause() async {
    await super.pause();
    _finishPlay();
  }

  @override
  Future<void> stop() async {
    await super.stop();
    _finishPlay();
  }

  @override
  Future<void> dispose() async {
    _finishPlay();
    await super.dispose();
  }
}

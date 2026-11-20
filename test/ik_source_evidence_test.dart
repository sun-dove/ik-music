import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/features/player/data/playback_keep_alive_service.dart';
import 'package:mconnect/features/player/data/playback_notification_service.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/platform/qq/qq_platform.dart';
import 'package:mconnect/video_app/multi_source/multi_source_player.dart';
import 'package:mconnect/video_app/multi_source/source_collection.dart';
import 'package:mconnect/video_app/multi_source/source_coordinator.dart';
import 'package:mconnect/video_app/video_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('K06 当前实际音源的信息随切歌/取消清空，迟到旧结果不回填', () async {
    const first = Song(
      id: 'first',
      platform: PlatformType.qq,
      name: '第一首',
      artists: [],
    );
    const next = Song(
      id: 'next',
      platform: PlatformType.qq,
      name: '下一首',
      artists: [],
    );
    final settings = SourceSettings(VideoPreferences(_Box()))
      ..value = const SourceCollection(autoSwitch: true);
    final pending = Completer<ResolvedSource>();
    final events = <SourcePlaybackView>[];
    final audio = _Audio();
    final player = MultiSourceVideoPlayerNotifier(
      settings: settings,
      router: PreparedSourceRouter(
        platformResolver: (_) => QqPlatform(),
        fixedQuality: (_) => AudioLevel.low,
      ),
      resolve: (song, candidate, _) async => song.id == 'next'
          ? pending.future
          : ResolvedSource(
              candidate,
              Uri.parse('https://audio.example/first'),
              format: 'mp3',
              bitrate: 128000,
            ),
      onProgress: events.add,
      audioController: audio,
      audioControllerFactory: () => audio,
      notificationController: const NoopPlaybackNotificationController(),
      keepAliveController: const NoopPlaybackKeepAliveController(),
    );
    addTearDown(player.dispose);
    await player.playSong(first);
    expect(events.last.sourceName, 'QQ音乐');
    expect(events.last.format, 'mp3');
    expect(events.last.bitrate, 128000);
    final loading = player.playSong(next);
    await Future<void>.delayed(Duration.zero);
    expect(events.last.sourceName, isNull);
    expect(events.last.format, isNull);
    expect(events.last.bitrate, isNull);
    player.cancelSourceAttempts();
    pending.complete(
      ResolvedSource(
        const SourceCandidate(
          id: 'late',
          name: '迟到旧源',
          quality: AudioLevel.lossless,
        ),
        Uri.parse('https://audio.example/late'),
        format: 'flac',
        bitrate: 999000,
      ),
    );
    await loading;
    expect(events.last.sourceName, isNull);
    expect(events.last.format, isNull);
    expect(events.last.bitrate, isNull);
  });
}

class _Box extends Fake implements Box {
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => defaultValue;
}

class _Audio implements PlayerAudioController {
  bool _playing = false;
  @override
  bool get playing => _playing;
  @override
  double get volume => 1;
  @override
  Duration get position => Duration.zero;
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<Duration?> get durationStream => const Stream.empty();
  @override
  Stream<AudioPlaybackState> get playerStateStream => const Stream.empty();
  @override
  Future<void> play() async {
    _playing = true;
  }

  @override
  Future<void> pause() async {
    _playing = false;
  }

  @override
  Future<void> stop() async {
    _playing = false;
  }

  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setUrl(String url) async {}
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

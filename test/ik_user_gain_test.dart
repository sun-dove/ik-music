import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;
import 'package:mconnect/core/platform/platform_utils.dart';
import 'package:mconnect/features/player/data/playback_keep_alive_service.dart';
import 'package:mconnect/features/player/data/playback_notification_service.dart';
import 'package:mconnect/features/player/data/spatial_audio_capability.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/l10n/ik_gain_strings.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/video_app/ik/ik_user_gain.dart';
import 'package:mconnect/video_app/multi_source/multi_source_player.dart';
import 'package:mconnect/video_app/multi_source/source_collection.dart';
import 'package:mconnect/video_app/multi_source/source_coordinator.dart';
import 'package:mconnect/video_app/video_preferences.dart';

import 'support/content_page_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('U05 用户增益和淡入相乘，淡入结束仍保持35%，逻辑音量保持1', () async {
    final gain = IkUserGainController();
    addTearDown(gain.dispose);
    var actual = 1.0;
    final binding = gain.attach((value) async => actual = value);
    await gain.setGain(.35);
    await binding.setLogicalVolume(.5);
    expect(actual, closeTo(.175, .000001));
    await binding.setLogicalVolume(1);
    expect(actual, closeTo(.35, .000001));
    expect(binding.volume, 1);
  });

  test('U05 静音不会改变看门狗逻辑音量，恢复静音回到前次音量', () async {
    final gain = IkUserGainController();
    addTearDown(gain.dispose);
    var actual = 1.0;
    final binding = gain.attach((value) async => actual = value);
    await gain.setGain(.42);
    await gain.toggleMute();
    await binding.setLogicalVolume(1);
    expect(actual, 0);
    expect(binding.volume, 1);
    await gain.toggleMute();
    expect(actual, closeTo(.42, .000001));
  });

  test('U05 底层写失败恢复上一实际值、保持确认增益并显示失败，重试可清除', () async {
    final gain = IkUserGainController();
    addTearDown(gain.dispose);
    var actual = 1.0;
    var fail = false;
    gain.attach((value) async {
      actual = value;
      if (fail) {
        fail = false;
        throw StateError('native rejected after write');
      }
    });
    await gain.setGain(.6);
    fail = true;
    await gain.setGain(.2);
    expect(actual, .6);
    expect(gain.state.gain, .6);
    expect(gain.state.error, isNotNull);
    expect(gain.state.busy, isFalse);
    await gain.setGain(.2);
    expect(actual, .2);
    expect(gain.state.error, isNull);
  });

  test('U05 快速增益与淡出串行，合并拖动，最后保持最新逻辑音量乘增益', () async {
    final gain = IkUserGainController();
    addTearDown(gain.dispose);
    final firstWrite = Completer<void>();
    final entered = Completer<void>();
    var active = 0;
    var maximum = 0;
    var actual = 1.0;
    final writes = <double>[];
    final binding = gain.attach((value) async {
      active++;
      if (active > maximum) maximum = active;
      if (!entered.isCompleted) {
        entered.complete();
        await firstWrite.future;
      }
      actual = value;
      writes.add(value);
      active--;
    });
    final request = gain.setGain(.2);
    await entered.future;
    final second = gain.setGain(.4);
    final last = gain.setGain(.7);
    final fade = binding.setLogicalVolume(.5);
    firstWrite.complete();
    await Future.wait([request, second, last, fade]);
    expect(maximum, 1);
    expect(actual, closeTo(.35, .000001));
    expect(gain.state.gain, .7);
    expect(writes, isNot(contains(.4)));
  });

  test('U05 重建绑定继承静音，播放前应用已确认增益', () async {
    final gain = IkUserGainController();
    addTearDown(gain.dispose);
    var oldActual = 1.0;
    final old = gain.attach((value) async => oldActual = value);
    await gain.setGain(0);
    await old.close();
    var newActual = 1.0;
    final fresh = gain.attach((value) async => newActual = value);
    await fresh.preparePlayback();
    expect(oldActual, 0);
    expect(newActual, 0);
    expect(fresh.volume, 1);
    await gain.setGain(.25);
    expect(newActual, .25);
  });

  test('U05 旧绑定写入迟到时重建，新绑定仍应用最新请求而非旧结果', () async {
    final gain = IkUserGainController();
    addTearDown(gain.dispose);
    final entered = Completer<void>();
    final pending = Completer<void>();
    gain.attach((value) async {
      entered.complete();
      await pending.future;
    });
    final request = gain.setGain(.2);
    await entered.future;
    var actual = 1.0;
    final fresh = gain.attach((value) async => actual = value);
    await fresh.preparePlayback();
    final latest = gain.setGain(0);
    pending.complete();
    await Future.wait([request, latest]);
    expect(actual, 0);
    expect(gain.state.gain, 0);
    expect(gain.state.error, isNull);
    expect(gain.state.busy, isFalse);
  });

  test('U05 写入与恢复均失败时明确报告，重试后恢复确认状态', () async {
    final gain = IkUserGainController();
    addTearDown(gain.dispose);
    var fail = false;
    var actual = 1.0;
    gain.attach((value) async {
      if (fail) throw StateError('native unavailable');
      actual = value;
    });
    await gain.setGain(.5);
    fail = true;
    await gain.setGain(.1);
    expect(gain.state.gain, .5);
    expect(gain.state.error, IkGainStrings.restoreFailed);
    expect(gain.state.busy, isFalse);
    fail = false;
    await gain.setGain(.1);
    expect(actual, .1);
    expect(gain.state.error, isNull);
  });

  test('U05 播放前增益写入期间暂停，迟到写入不得恢复旧音频', () async {
    final gain = IkUserGainController();
    final audio = _Audio()
      ..holdVolumeAfterLoad = Completer<void>()
      ..volumeEntered = Completer<void>();
    final player = _player(audio, gain, multi: true);
    addTearDown(() {
      player.dispose();
      gain.dispose();
    });
    final playing = player.playSong(_song('cancel-before-play'));
    await audio.volumeEntered!.future;
    final paused = player.pause();
    audio.holdVolumeAfterLoad!.complete();
    await Future.wait([playing, paused]);
    await pumpEventQueue();
    expect(audio.playVolumes, isEmpty);
    expect(player.state.isPlaying, isFalse);
  });

  test('U05 实际多源链淡入结束和切歌保持用户音量，能力透传不丢失', () async {
    final gain = IkUserGainController();
    final audio = _Audio();
    final player = _player(audio, gain);
    addTearDown(() {
      player.dispose();
      gain.dispose();
    });
    await gain.setGain(.35);
    player.setFadeOptions(enabled: true, duration: Duration.zero);
    await player.playSong(_song('one'));
    await pumpEventQueue();
    expect(audio.volume, closeTo(.35, .000001));
    await player.playSong(_song('two'));
    await pumpEventQueue();
    expect(audio.volume, closeTo(.35, .000001));
    expect(audio.playVolumes, everyElement(lessThanOrEqualTo(.35)));
    await player.spatialAudioCapability!.applySpatialAudio(
      const SpatialSettings(enabled: true),
      12,
    );
    expect(audio.spatialRequest, 12);
    await player.setPlaybackSpeed(1.25);
    expect(audio.playbackSpeed, 1.25);
  });

  test('U05 实际音量守护在静音后保持0，重建前设置与新控制器一致', () async {
    PlatformUtils.setDebugOverride(AppPlatform.android);
    addTearDown(() => PlatformUtils.setDebugOverride(null));
    final gain = IkUserGainController();
    final old = _Audio();
    final fresh = _Audio();
    final player = _player(old, gain, factory: () => fresh);
    addTearDown(() {
      player.dispose();
      gain.dispose();
    });
    await player.playSong(_song('muted'));
    await pumpEventQueue();
    await gain.setGain(0);
    await player.runPlaybackHealthCheckForTest();
    expect(old.volume, 0);
    old.failSeek = true;
    await player.seek(const Duration(seconds: 5));
    await pumpEventQueue(times: 30);
    expect(old.disposed, isTrue);
    await player.playSong(_song('after-rebuild'));
    await pumpEventQueue();
    expect(fresh.volume, 0);
    expect(fresh.playVolumes, everyElement(0));
    await gain.setGain(.4);
    expect(fresh.volume, .4);
  });

  test('U05 旧入口没有增益参数时保持原生音量链', () async {
    final audio = _Audio();
    final player = _player(audio, null);
    addTearDown(player.dispose);
    player.setFadeOptions(enabled: false, duration: Duration.zero);
    await player.playSong(_song('legacy'));
    await pumpEventQueue();
    expect(audio.volume, 1);
    expect(audio.playVolumes, everyElement(1));
  });
}

Song _song(String id) => Song(
  id: id,
  platform: PlatformType.qq,
  name: id,
  artists: const [],
  duration: const Duration(minutes: 2),
);

MultiSourceVideoPlayerNotifier _player(
  _Audio audio,
  IkUserGainController? gain, {
  PlayerAudioController Function()? factory,
  bool multi = false,
}) => MultiSourceVideoPlayerNotifier(
  settings: SourceSettings(VideoPreferences(_Box()))
    ..value = SourceCollection(highestQuality: multi),
  router: PreparedSourceRouter(
    platformResolver: (_) => FakeContentPlatform(type: PlatformType.qq),
    fixedQuality: (_) => AudioLevel.low,
  ),
  resolve: (song, candidate, _) async =>
      ResolvedSource(candidate, Uri.parse('https://example.test/${song.id}')),
  audioController: audio,
  audioControllerFactory: factory ?? _Audio.new,
  userGain: gain,
  keepAliveController: const NoopPlaybackKeepAliveController(),
  notificationController: const NoopPlaybackNotificationController(),
);

class _Box extends Fake implements Box {
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => defaultValue;
}

class _Audio extends IdleAudioController
    implements PlaybackSpeedCapable, SpatialAudioCapable {
  double _volume = 1;
  bool _playing = false;
  bool disposed = false, failSeek = false;
  bool _loaded = false;
  Completer<void>? holdVolumeAfterLoad, volumeEntered;
  final playVolumes = <double>[];
  final _states = StreamController<AudioPlaybackState>.broadcast();
  int spatialRequest = 0;
  @override
  double get volume => _volume;
  @override
  bool get playing => _playing;
  @override
  Stream<AudioPlaybackState> get playerStateStream => _states.stream;
  @override
  Future<void> setVolume(double value) async {
    if (_loaded && holdVolumeAfterLoad != null) {
      if (!volumeEntered!.isCompleted) volumeEntered!.complete();
      await holdVolumeAfterLoad!.future;
    }
    _volume = value;
  }

  @override
  Future<void> setUrl(String url) async => _loaded = true;
  @override
  Future<void> play() async {
    playVolumes.add(_volume);
    _playing = true;
    _states.add(
      const AudioPlaybackState(
        playing: true,
        processingState: ProcessingState.ready,
      ),
    );
  }

  @override
  Future<void> pause() async => _playing = false;
  @override
  Future<void> stop() async => _playing = false;
  @override
  Future<void> seek(Duration value) async {
    if (failSeek) throw PlatformException(code: 'channel_lost');
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _states.close();
  }

  @override
  double playbackSpeed = 1;
  @override
  Future<void> setPlaybackSpeed(double speed) async => playbackSpeed = speed;
  @override
  Future<bool> supportsSpatialAudio() async => true;
  @override
  Future<void> applySpatialAudio(
    SpatialSettings settings,
    int requestId,
  ) async => spatialRequest = requestId;
  @override
  Future<SpatialProcessingReport> readSpatialAudio() async =>
      SpatialProcessingReport(requestId: spatialRequest, processedFrames: 128);
}

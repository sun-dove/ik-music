import '../../l10n/source_strings.dart';

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/player/presentation/providers/player_provider.dart';
import '../../core/platform/platform_utils.dart';
import '../../features/player/data/media_kit_windows_audio_controller.dart';
import '../../features/player/data/playback_notification_service.dart';
import '../../features/player/data/spatial_audio_capability.dart';
import '../../models/audio_quality.dart';
import '../../models/platform_type.dart';
import '../../models/song.dart';
import '../../l10n/ik_source_recovery_strings.dart';
import '../../platform/base/music_platform.dart';
import '../custom_source/custom_source_playback.dart';
import '../playback/video_platforms.dart';
import '../playback/video_player_notifier.dart';
import '../ik/ik_user_gain.dart';
import 'balanced_source_planner.dart';
import 'source_candidates_v3.dart';
import 'source_collection.dart';
import 'source_coordinator.dart';
import 'quick_source_transport.dart';

class SourcePlaybackView {
  const SourcePlaybackView({
    this.message = '',
    this.details = '',
    this.busy = false,
    this.canContinue = false,
    this.sourceName,
    this.format,
    this.bitrate,
  });
  final String message, details;
  final bool busy, canContinue;
  final String? sourceName, format;
  final int? bitrate;
}

final sourcePlaybackViewProvider = StateProvider<SourcePlaybackView>(
  (ref) => const SourcePlaybackView(),
);

class PreparedSourceRouter {
  PreparedSourceRouter({
    required this.platformResolver,
    required this.fixedQuality,
  });
  final MusicPlatform Function(PlatformType) platformResolver;
  final AudioLevel Function(PlatformType) fixedQuality;
  ResolvedSource? prepared;
  Song? song;
  bool guarded = false;
  CancelToken mediaToken = CancelToken();
  CancelToken? _loadedMediaToken;
  void Function(Duration)? _observePosition;
  bool get _hasLoadedMedia =>
      _loadedMediaToken == mediaToken && !mediaToken.isCancelled;
  Duration Function()? timeLeft;
  final failedUrls = <String>{};
  bool seekFailed = false;
  void cancelMedia() {
    _observePosition = null;
    mediaToken.cancel();
    mediaToken = CancelToken();
    _loadedMediaToken = null;
  }

  AudioLevel quality(PlatformType type) =>
      song?.platform == type && prepared != null
      ? prepared!.candidate.quality
      : fixedQuality(type);
  MusicPlatform platform(PlatformType type) =>
      _PreparedPlatform(platformResolver(type), this);
}

class _PreparedPlatform extends VideoPlaybackPlatform {
  _PreparedPlatform(super.platform, this.router)
    : super(requestedQuality: () => router.quality(platform.platformType));
  final PreparedSourceRouter router;
  @override
  Future<String> getSongUrl(
    String songId, {
    AudioLevel quality = AudioLevel.low,
  }) {
    if (router.song?.id == songId &&
        router.song?.platform == platformType &&
        router.prepared != null) {
      return Future.value(router.prepared!.url.toString());
    }
    if (router.guarded) {
      throw const SourceFailure('cancelled', SourceStrings.oldRequestCancelled);
    }
    return delegate.getSongUrl(songId, quality: quality);
  }
}

typedef MultiSourceResolve = Future<ResolvedSource> Function(
  Song,
  SourceCandidate,
  CancelToken,
);

PlayerAudioController _defaultSourceAudio() {
  if (PlatformUtils.isAndroid) return AudioServicePlayerController.instance;
  if (PlatformUtils.isWindows) return MediaKitWindowsAudioController();
  return JustAudioController();
}

/// 只作用于新增入口：拦截重复坏地址和取消后迟到的播放，保留底层重建能力。
class _SourceAudio
    implements
        PlayerAudioController,
        PlaybackSpeedCapable,
        SkipSilenceCapable,
        VerifiedEqualizerCapable,
        SpatialAudioCapable {
  _SourceAudio(
    this.delegate,
    this.router, {
    IkUserGainController? userGain,
    this.isolateRequests = false,
    this.quickRecovery = false,
    this.loadTimeout = const Duration(seconds: 10),
  }) : _gain = userGain?.attach(
         delegate.setVolume,
         initialVolume: delegate.volume,
       );
  final PlayerAudioController delegate;
  final PreparedSourceRouter router;
  final bool isolateRequests;
  final bool quickRecovery;
  final Duration loadTimeout;
  final IkGainBinding? _gain;
  int _gainPlayGeneration = 0;
  bool _disposed = false;
  @override
  Future<bool> supportsSpatialAudio() => delegate is SpatialAudioCapable
      ? (delegate as SpatialAudioCapable).supportsSpatialAudio()
      : Future.value(false);
  @override
  Future<void> applySpatialAudio(SpatialSettings settings, int requestId) {
    if (delegate is! SpatialAudioCapable) throw UnsupportedError('spatial');
    return (delegate as SpatialAudioCapable).applySpatialAudio(
      settings,
      requestId,
    );
  }

  @override
  Future<SpatialProcessingReport> readSpatialAudio() {
    if (delegate is! SpatialAudioCapable) throw UnsupportedError('spatial');
    return (delegate as SpatialAudioCapable).readSpatialAudio();
  }

  CancelToken? _loaded;
  CancelToken? _requestToken;
  bool get _current =>
      (!isolateRequests ||
          (!_disposed &&
              (_requestToken == null ||
                  (_requestToken == router.mediaToken &&
                      _requestToken?.isCancelled == false)))) &&
      (!router.guarded ||
          (_loaded == router.mediaToken && _loaded?.isCancelled == false));
  Stream<T> _events<T>(Stream<T> stream) => stream.transform(
    StreamTransformer<T, T>.fromHandlers(
      handleData: (value, sink) {
        if (_current) sink.add(value);
      },
      handleError: (Object error, StackTrace stack, EventSink<T> sink) {
        if (_current) sink.addError(error, stack);
      },
    ),
  );
  @override
  bool get playing => delegate.playing;
  @override
  Duration get position => delegate.position;
  @override
  double get volume => _gain?.volume ?? delegate.volume;
  @override
  Stream<Duration> get positionStream =>
      _events(delegate.positionStream).map((position) {
        if (router._observePosition != null &&
            _loaded == router.mediaToken &&
            delegate.playing) {
          router._observePosition!(position);
        }
        return position;
      });
  @override
  Stream<Duration?> get durationStream => _events(delegate.durationStream);
  @override
  Stream<AudioPlaybackState> get playerStateStream =>
      _events(delegate.playerStateStream);
  @override
  Future<void> setUrl(String url) async {
    final requestedToken = router.mediaToken;
    _requestToken = requestedToken;
    if (isolateRequests &&
        (_disposed ||
            requestedToken.isCancelled ||
            (router.guarded &&
                (router.prepared?.url.toString() != url ||
                    router.failedUrls.contains(url))))) {
      throw const SourceFailure('load', SourceStrings.invalidAudio);
    }
    final initialRemaining = router.timeLeft?.call() ?? loadTimeout;
    final loadWindow = initialRemaining < loadTimeout
        ? initialRemaining
        : loadTimeout;
    final deadline = isolateRequests && router.guarded
        ? DateTime.now().add(loadWindow)
        : null;
    if (_gain != null) {
      _gainPlayGeneration++;
      if (deadline == null) {
        await _gain.preparePlayback();
      } else {
        try {
          await Future.any<void>([
            _gain.preparePlayback(),
            requestedToken.whenCancel.then(
              (_) => throw const SourceFailure(
                'cancelled',
                SourceStrings.loadCancelled,
              ),
            ),
          ]).timeout(loadWindow);
        } catch (_) {
          _failedLoad(url, requestedToken);
          rethrow;
        }
      }
    }
    if (isolateRequests &&
        (_disposed ||
            requestedToken.isCancelled ||
            requestedToken != router.mediaToken)) {
      throw const SourceFailure('cancelled', SourceStrings.loadCancelled);
    }
    if (!router.guarded) {
      _loaded = null;
      await delegate.setUrl(url);
      if (isolateRequests &&
          (_disposed ||
              requestedToken.isCancelled ||
              requestedToken != router.mediaToken)) {
        throw const SourceFailure('cancelled', SourceStrings.loadCancelled);
      }
      _loaded = requestedToken;
      router._loadedMediaToken = requestedToken;
      return;
    }
    final token = router.mediaToken;
    if (router.prepared?.url.toString() != url ||
        router.failedUrls.contains(url)) {
      throw const SourceFailure('load', SourceStrings.invalidAudio);
    }
    final remaining = router.timeLeft?.call() ?? loadTimeout;
    final loadRemaining = deadline?.difference(DateTime.now()) ?? loadTimeout;
    if (remaining <= Duration.zero || loadRemaining <= Duration.zero) {
      if (isolateRequests) _failedLoad(url, token);
      throw const SourceFailure('timeout', SourceStrings.loadBudgetUsed);
    }
    try {
      await Future.any<void>([
        quickRecovery ? _loadWithFeedback(url, token) : delegate.setUrl(url),
        token.whenCancel.then(
          (_) => throw const SourceFailure(
            'cancelled',
            SourceStrings.loadCancelled,
          ),
        ),
      ]).timeout(remaining < loadRemaining ? remaining : loadRemaining);
      if (token.isCancelled) throw token.cancelError!;
      if (isolateRequests && (_disposed || token != router.mediaToken)) {
        throw const SourceFailure('cancelled', SourceStrings.loadCancelled);
      }
      _loaded = token;
      router._loadedMediaToken = token;
    } catch (_) {
      _failedLoad(url, token);
      rethrow;
    }
  }

  void _failedLoad(String url, CancelToken token) {
    if (!isolateRequests ||
        (!token.isCancelled && token == router.mediaToken)) {
      router.failedUrls.add(url);
    }
    if (isolateRequests) {
      token.cancel(SourceStrings.loadCancelled);
      _loaded = null;
      if (router._loadedMediaToken == token) {
        router._loadedMediaToken = null;
      }
    }
  }

  Future<void> _loadWithFeedback(String url, CancelToken token) async {
    final failure = Completer<void>();
    final ready = Completer<void>();
    final subscription = delegate.playerStateStream.listen(
      (_) {},
      onError: (Object error, StackTrace trace) {
        if (!failure.isCompleted) failure.completeError(error, trace);
      },
    );
    final durationSubscription = delegate is MediaKitWindowsAudioController
        ? delegate.durationStream.listen((duration) {
            if (duration != null &&
                duration > Duration.zero &&
                !ready.isCompleted) {
              ready.complete();
            }
          })
        : null;
    try {
      Future<void> load() async {
        await delegate.setUrl(url);
        if (durationSubscription != null) await ready.future;
      }

      await Future.any<void>([
        load(),
        failure.future,
        token.whenCancel.then(
          (_) => throw const SourceFailure(
            'cancelled',
            SourceStrings.loadCancelled,
          ),
        ),
      ]);
    } finally {
      await subscription.cancel();
      await durationSubscription?.cancel();
    }
  }

  @override
  Future<void> play() {
    if (isolateRequests &&
        (_disposed ||
            _loaded != router.mediaToken ||
            !router._hasLoadedMedia)) {
      return Future.value();
    }
    if (router.guarded &&
        (_loaded != router.mediaToken || _loaded?.isCancelled != false)) {
      return Future.value();
    }
    final gain = _gain;
    final generation = _gainPlayGeneration;
    final token = router.mediaToken;
    if (quickRecovery &&
        router.guarded &&
        delegate is MediaKitWindowsAudioController) {
      return _playReadyForToken(token, generation);
    }
    return _playForToken(token, gain, generation);
  }

  Future<void> _playReadyForToken(CancelToken token, int generation) async {
    try {
      if (generation != _gainPlayGeneration || !_current) return;
      await delegate.play().timeout(const Duration(seconds: 1));
    } catch (_) {
      if (_disposed || token.isCancelled || token != router.mediaToken) return;
      rethrow;
    }
  }

  Future<void> _playForToken(
    CancelToken token,
    IkGainBinding? gain,
    int generation,
  ) async {
    try {
      if (gain != null) {
        await gain.preparePlayback();
        if (generation != _gainPlayGeneration ||
            token != router.mediaToken ||
            !_current) {
          return;
        }
      }
      await delegate.play();
    } catch (_) {
      if (isolateRequests &&
          (_disposed || token.isCancelled || token != router.mediaToken)) {
        return;
      }
      rethrow;
    }
  }

  @override
  Future<void> stop() {
    if (_gain != null) _gainPlayGeneration++;
    final operation = delegate.stop();
    return quickRecovery &&
            router.guarded &&
            delegate is MediaKitWindowsAudioController
        ? operation.timeout(const Duration(seconds: 1))
        : operation;
  }

  @override
  Future<void> pause() {
    if (_gain != null) _gainPlayGeneration++;
    final operation = delegate.pause();
    return quickRecovery &&
            router.guarded &&
            delegate is MediaKitWindowsAudioController
        ? operation.timeout(const Duration(seconds: 1))
        : operation;
  }

  @override
  Future<void> seek(Duration value) async {
    final token = router.mediaToken;
    if (_loaded == token) router._observePosition = null;
    try {
      await delegate.seek(value);
    } catch (_) {
      if (isolateRequests &&
          (_disposed || token.isCancelled || token != router.mediaToken)) {
        return;
      }
      router.seekFailed = true;
      rethrow;
    }
  }

  @override
  Future<void> setVolume(double value) =>
      _gain?.setLogicalVolume(value) ?? delegate.setVolume(value);
  @override
  Future<void> applyEqualizer({
    required bool enabled,
    required List<double> bandGains,
  }) => delegate.applyEqualizer(enabled: enabled, bandGains: bandGains);
  @override
  Future<void> applyEqualizerVerified({
    required bool enabled,
    required List<double> bandGains,
  }) {
    final controller = delegate;
    if (controller is! VerifiedEqualizerCapable) {
      throw UnsupportedError('equalizer');
    }
    return (controller as VerifiedEqualizerCapable).applyEqualizerVerified(
      enabled: enabled,
      bandGains: bandGains,
    );
  }

  @override
  double get playbackSpeed => delegate is PlaybackSpeedCapable
      ? (delegate as PlaybackSpeedCapable).playbackSpeed
      : 1;
  @override
  Future<void> setPlaybackSpeed(double speed) async {
    if (delegate is PlaybackSpeedCapable) {
      await (delegate as PlaybackSpeedCapable).setPlaybackSpeed(speed);
    }
  }

  @override
  Future<void> setSkipSilence(bool enabled) async {
    if (delegate is SkipSilenceCapable) {
      await (delegate as SkipSilenceCapable).setSkipSilence(enabled);
    }
  }

  @override
  Future<void> dispose() {
    _disposed = true;
    if (router._loadedMediaToken == _loaded) {
      router._loadedMediaToken = null;
    }
    if (_gain != null) _gainPlayGeneration++;
    _gain?.close();
    return delegate.dispose();
  }
}

/// 多源解析在旧播放器单次取流计时器外；每次只装载已准备好的候选。
class MultiSourceVideoPlayerNotifier extends VideoPlayerNotifier {
  MultiSourceVideoPlayerNotifier({
    required this.settings,
    required this.router,
    required this.resolve,
    this.onProgress,
    this.preservePlaybackOnSettingsChange = false,
    this.quickSourceRecovery = false,
    this.quickResolveTimeout = const Duration(seconds: 3),
    this.quickLoadTimeout = const Duration(seconds: 3),
    this.quickBudget = const Duration(seconds: 9),
    this.balancedPlanner,
    this.smartBalancedEnabled,
    CustomSourcePlaybackFallback? legacyFallback,
    PlayerAudioController? audioController,
    PlayerAudioController Function()? audioControllerFactory,
    IkUserGainController? userGain,
    super.playbackMemoryStore,
    super.notificationController,
    super.keepAliveController,
    super.isSongLiked,
    super.toggleSongLike,
    super.offlineFilePathResolver,
    super.isOfflineModeEnabled,
  }) : _offlinePath = offlineFilePathResolver,
       _offlineMode = isOfflineModeEnabled,
       _legacyFallback = legacyFallback,
       super(
         platformResolver: router.platform,
         requestedQuality: router.quality,
         audioDisposeTimeout: quickSourceRecovery && PlatformUtils.isWindows
             ? const Duration(milliseconds: 500)
             : const Duration(seconds: 3),
         audioController: audioController == null
             ? null
             : _SourceAudio(
                 audioController,
                 router,
                 userGain: userGain,
                 isolateRequests:
                     preservePlaybackOnSettingsChange || quickSourceRecovery,
                 quickRecovery: quickSourceRecovery,
                 loadTimeout: quickSourceRecovery
                     ? quickLoadTimeout
                     : const Duration(seconds: 10),
               ),
         audioControllerFactory: () => _SourceAudio(
           (audioControllerFactory ?? _defaultSourceAudio)(),
           router,
           userGain: userGain,
           isolateRequests:
               preservePlaybackOnSettingsChange || quickSourceRecovery,
           quickRecovery: quickSourceRecovery,
           loadTimeout: quickSourceRecovery
               ? quickLoadTimeout
               : const Duration(seconds: 10),
         ),
         customSourceFallback: legacyFallback,
       ) {
    settings.addListener(_settingsChanged);
    _unlisten = addListener((value) {
      if (preservePlaybackOnSettingsChange &&
          _settingsPending &&
          !_advancing &&
          !_paused &&
          !router.guarded &&
          _multiEnabled &&
          _song != null &&
          value.currentSong == _song &&
          value.error != null) {
        _advancing = true;
        final generation = _generation;
        scheduleMicrotask(() {
          if (mounted && generation == _generation && !_paused) {
            unawaited(_start(_song!, value.position));
          }
        });
        return;
      }
      final session = _session;
      if (_advancing ||
          _paused ||
          session == null ||
          session.cancelled ||
          _active == null ||
          value.error == null) {
        return;
      }
      if (value.currentSong != _song) return;
      final source = _active!;
      _active = null;
      session.failed(source, SourceFailure('playback', value.error!));
      if (preservePlaybackOnSettingsChange || quickSourceRecovery) {
        router.failedUrls.add(source.url.toString());
        router.cancelMedia();
        router.prepared = null;
      }
      if (preservePlaybackOnSettingsChange && _settingsPending) {
        session.cancel();
        _createSession(_song!);
      }
      _session?.renewBudget();
      _advancing = true;
      final generation = _generation;
      scheduleMicrotask(() => _advance(generation, value.position));
    }, fireImmediately: false);
  }
  final SourceSettings settings;
  final PreparedSourceRouter router;
  final MultiSourceResolve resolve;
  final bool preservePlaybackOnSettingsChange;
  final bool quickSourceRecovery;
  final Duration quickResolveTimeout, quickLoadTimeout, quickBudget;
  final BalancedSourcePlanner? balancedPlanner;
  final bool Function()? smartBalancedEnabled;
  bool get _balanced =>
      balancedPlanner != null && smartBalancedEnabled?.call() == true;
  void Function()? _attemptHeard;
  final void Function(SourcePlaybackView)? onProgress;
  final OfflineFilePathResolver? _offlinePath;
  final bool Function()? _offlineMode;
  final CustomSourcePlaybackFallback? _legacyFallback;
  late final void Function() _unlisten;
  SourceSession? _session;
  ResolvedSource? _active;
  Song? _song;
  int _generation = 0;
  bool _advancing = false, _paused = false;
  Future<void>? _loading;
  AudioLevel? _fixedOverride;
  SourceCollection? _sessionPolicy;
  bool _sessionBalanced = false;
  bool _settingsPending = false;
  Set<String> _failedHosts = {};

  bool get _multiEnabled =>
      _balanced ||
      settings.value.autoSwitch ||
      settings.value.highestQuality ||
      settings.value.sourceFirst;

  bool get _hasStableMedia =>
      !_advancing &&
      _loading == null &&
      !state.isTransitioning &&
      state.error == null &&
      state.currentSong == _song &&
      router._hasLoadedMedia &&
      (!router.guarded || (_active != null && _session?.cancelled == false));

  bool get _usesManagedPlayback =>
      _multiEnabled ||
      (quickSourceRecovery &&
          state.currentSong?.platform != PlatformType.local) ||
      (preservePlaybackOnSettingsChange &&
          router.guarded &&
          state.currentSong == _song);

  /// 可由新版入口扩展平台；旧入口仍使用原候选规则。
  List<SourceCandidate> candidatesFor(Song song, AudioLevel quality) =>
      buildSourceCandidates(song, quality, settings.value);
  List<String> exclusionsFor(Song song, AudioLevel quality) =>
      sourceExclusions(song, quality, settings.value);
  void _settingsChanged() {
    balancedPlanner?.configure(settings.value);
    if (!_balanced) router._observePosition = null;
    if (preservePlaybackOnSettingsChange) {
      _settingsPending = true;
      if (_hasStableMedia) return;
    }
    final wasGuarded = router.guarded;
    cancelSourceAttempts();
    if (wasGuarded) unawaited(super.pause());
  }

  void cancelSourceAttempts() {
    _attemptHeard = null;
    _generation++;
    _session?.cancel();
    router.cancelMedia();
    _active = null;
    _sessionPolicy = null;
    router.prepared = null;
    _advancing = false;
    if (mounted && state.isTransitioning) {
      state = state.copyWith(
        isTransitioning: false,
        isPlaying: false,
        error: () => null,
      );
    }
    onProgress?.call(const SourcePlaybackView());
  }

  @override
  Future<void> playSong(Song song) => _start(song, Duration.zero);

  Future<void> _start(Song song, Duration position) async {
    cancelSourceAttempts();
    final generation = _generation;
    await _loading;
    if (generation != _generation || !mounted) return;
    _paused = false;
    _settingsPending = false;
    _song = song;
    router.song = song;
    router.failedUrls.clear();
    _failedHosts = {};
    router.guarded =
        (_multiEnabled || quickSourceRecovery) &&
        song.platform != PlatformType.local;
    if (!router.guarded) {
      await super.playSong(song);
      if (preservePlaybackOnSettingsChange &&
          mounted &&
          generation == _generation &&
          state.error == null &&
          position > Duration.zero) {
        await super.seek(position);
      }
      return;
    }
    if (_offlineMode?.call() == true && _offlinePath != null) {
      final local = await _offlinePath(song);
      if (generation != _generation || !mounted) return;
      if (local != null) {
        router.guarded = false;
        await super.playSong(song);
        if (preservePlaybackOnSettingsChange &&
            mounted &&
            generation == _generation &&
            state.error == null &&
            position > Duration.zero) {
          await super.seek(position);
        }
        return;
      }
    }
    await super.pause();
    if (generation != _generation || !mounted) return;
    final queue = [...state.playlist];
    var index = queue.indexWhere((s) => s == song);
    if (index < 0) {
      index = queue.length;
      queue.add(song);
    }
    state = state.copyWith(
      currentSong: song,
      playlist: queue,
      currentIndex: index,
      position: position,
      duration: song.duration,
      isPlaying: false,
      isTransitioning: true,
      error: () => null,
    );
    _createSession(song);
    await _advance(generation, position);
  }

  void _createSession(Song song) {
    _sessionPolicy = settings.value;
    _settingsPending = false;
    final failedHosts = _failedHosts;
    final planner = _balanced ? balancedPlanner : null;
    _sessionBalanced = planner != null;
    final policy = settings.value;
    final quality = _fixedOverride ?? router.fixedQuality(song.platform);
    final allTiers = planner == null
        ? null
        : policy.copyWith(highestQuality: true);
    final useLegacyHttp =
        quickSourceRecovery &&
        !policy.autoSwitch &&
        !policy.highestQuality &&
        !policy.sourceFirst &&
        _legacyFallback?.config()?.id != 'lx';
    late final SourceSession session;
    session = SourceSession(
      exclusions: allTiers == null
          ? exclusionsFor(song, quality)
          : sourceExclusionsV3(song, quality, allTiers),
      candidates: planner == null
          ? candidatesFor(song, quality)
          : planner.plan(
              song,
              policy,
              buildSourceCandidatesV3(song, quality, allTiers!),
            ),
      resolve: (candidate, token) {
        _attemptHeard = planner?.beginAttempt(song, candidate);
        return quickSourceRecovery
            ? QuickSourceTransport.run(
                token,
                () => _resolveQuickSource(
                  song,
                  candidate,
                  token,
                  useLegacyHttp: useLegacyHttp,
                ),
                failedHosts: failedHosts,
                timeout: quickResolveTimeout,
              )
            : resolve(song, candidate, token);
      },
      onChanged: () {
        if (identical(_session, session)) _report();
      },
      budget: quickSourceRecovery ? quickBudget : const Duration(seconds: 45),
      resolveTimeout: quickSourceRecovery
          ? quickResolveTimeout
          : const Duration(seconds: 15),
    );
    _session = session;
    router.timeLeft = () => session.timeLeft;
  }

  Future<ResolvedSource> _resolveQuickSource(
    Song song,
    SourceCandidate candidate,
    CancelToken token, {
    required bool useLegacyHttp,
  }) async {
    try {
      return await resolve(song, candidate, token);
    } catch (error) {
      final fallback = _legacyFallback;
      if (!useLegacyHttp ||
          !candidate.official ||
          fallback == null ||
          token.isCancelled) {
        rethrow;
      }
      final result = await fallback.resolve(song, candidate.quality, error);
      if (result == null || token.isCancelled) rethrow;
      _attemptHeard = null;
      return ResolvedSource(
        SourceCandidate(
          id: candidate.id,
          name: result.sourceName,
          quality: candidate.quality,
        ),
        result.url,
        format: result.format,
        bitrate: result.bitrate,
      );
    }
  }

  void _report() {
    if (!mounted || _session?.cancelled == true) return;
    final session = _session;
    if (session == null) return;
    final last = session.attempts.lastOrNull;
    final downgraded =
        !_sessionBalanced &&
        (preservePlaybackOnSettingsChange
            ? (_sessionPolicy?.highestQuality ?? settings.value.highestQuality)
            : settings.value.highestQuality) &&
        last != null &&
        last.candidate.quality != AudioLevel.hires;
    final qualityNotice = downgraded ? SourceStrings.downshift : '';
    final evidence = _active?.bitrate != null
        ? SourceStrings.bitrate(_active!.bitrate! ~/ 1000)
        : SourceStrings.qualityUnverified;
    final message = last == null
        ? SourceStrings.preparing
        : switch (last.stage) {
            SourceStage.resolving => SourceStrings.trying(
              qualityNotice,
              last.candidate.label,
            ),
            SourceStage.resolved => SourceStrings.loading(last.candidate.label),
            SourceStage.playing => SourceStrings.playback(
              qualityNotice,
              _active?.candidate.name ?? last.candidate.name,
              last.candidate.quality.displayName,
              evidence,
              router.seekFailed,
            ),
            _ => SourceStrings.switching,
          };
    onProgress?.call(
      SourcePlaybackView(
        message: message,
        details: session.summary,
        busy: _advancing,
        canContinue:
            (!preservePlaybackOnSettingsChange || _active == null) &&
            session.budgetExpired &&
            session.canContinue,
        sourceName: _active?.candidate.name,
        format: _active?.format,
        bitrate: _active?.bitrate,
      ),
    );
  }

  Future<void> _advance(int generation, Duration position) async {
    if (!mounted || generation != _generation || _paused) return;
    final session = _session;
    final song = _song;
    if (session == null || song == null) return;
    _advancing = true;
    try {
      while (mounted && generation == _generation && !_paused) {
        final resolved = await session.next();
        if (!mounted || generation != _generation || _paused) return;
        if (resolved == null) {
          router.prepared = null;
          final canContinue = session.budgetExpired && session.canContinue;
          final failureMessage = quickSourceRecovery
              ? canContinue
                    ? IkSourceRecoveryStrings.budgetUsed(
                        session.attempts
                            .where(
                              (attempt) => attempt.stage != SourceStage.skipped,
                            )
                            .length,
                        session.remaining,
                      )
                    : session.remaining == 0
                    ? IkSourceRecoveryStrings.unavailable
                    : IkSourceRecoveryStrings.interrupted
              : canContinue
              ? SourceStrings.budgetUsed
              : SourceStrings.noPlayback;
          state = state.copyWith(
            isPlaying: false,
            isTransitioning: false,
            error: () => failureMessage,
          );
          onProgress?.call(
            SourcePlaybackView(
              message: state.error!,
              details: session.summary,
              canContinue: session.canContinue && session.budgetExpired,
            ),
          );
          return;
        }
        if (quickSourceRecovery || preservePlaybackOnSettingsChange) {
          router.cancelMedia();
        }
        router.prepared = resolved;
        if (_attemptHeard != null) router.seekFailed = false;
        _loading = super.playSong(song);
        await _loading;
        _loading = null;
        if (!mounted || generation != _generation || _paused) return;
        if (state.error != null || !state.isPlaying) {
          session.failed(
            resolved,
            SourceFailure('load', state.error ?? SourceStrings.loadFailed),
          );
          router.prepared = null;
          state = state.copyWith(error: () => null, isTransitioning: true);
          continue;
        }
        if (position > Duration.zero) {
          router.seekFailed = false;
          await super.seek(position);
          if (!mounted || generation != _generation || _paused) return;
        }
        _active = resolved;
        final heard = _attemptHeard;
        _attemptHeard = null;
        if (heard != null && _balanced && !router.seekFailed) {
          final baseline = position > state.position
              ? position
              : state.position;
          router._observePosition = (progress) {
            if (progress <= baseline ||
                _paused ||
                !mounted ||
                !_balanced ||
                generation != _generation ||
                !identical(_active, resolved) ||
                state.error != null) {
              return;
            }
            router._observePosition = null;
            heard();
          };
        }
        session.loaded(resolved);
        _advancing = false;
        _report();
        return;
      }
    } finally {
      if (generation == _generation) _advancing = false;
    }
  }

  Future<void> continueSources() async {
    if (_advancing || _session?.canContinue != true) return;
    if (preservePlaybackOnSettingsChange && _settingsPending && _song != null) {
      _session!.cancel();
      _createSession(_song!);
    }
    _session!.renewBudget();
    _paused = false;
    state = state.copyWith(error: () => null, isTransitioning: true);
    await _advance(_generation, state.position);
  }

  @override
  Future<void> pause() async {
    router._observePosition = null;
    _attemptHeard = null;
    if (preservePlaybackOnSettingsChange && _hasStableMedia) {
      _paused = true;
      final generation = _generation;
      await super.pause();
      if (mounted && generation == _generation && _paused) {
        onProgress?.call(
          const SourcePlaybackView(message: SourceStrings.paused),
        );
      }
      return;
    }
    if (!_usesManagedPlayback) {
      await super.pause();
      return;
    }
    _paused = true;
    _session?.cancel();
    router.cancelMedia();
    final generation = ++_generation;
    final loading = _loading;
    _advancing = false;
    await super.pause();
    await loading;
    if (generation != _generation) return;
    if (mounted) {
      state = state.copyWith(
        isTransitioning: false,
        isPlaying: false,
        error: () => null,
      );
    }
    onProgress?.call(const SourcePlaybackView(message: SourceStrings.paused));
  }

  @override
  Future<void> togglePlay() async {
    if (preservePlaybackOnSettingsChange &&
        state.isPlaying &&
        _hasStableMedia) {
      await pause();
      return;
    }
    if (preservePlaybackOnSettingsChange &&
        !state.isPlaying &&
        _hasStableMedia) {
      _paused = false;
      final generation = _generation;
      await super.togglePlay();
      if (mounted && generation == _generation && state.error == null) {
        if (router.guarded) {
          _report();
        } else {
          onProgress?.call(const SourcePlaybackView());
        }
      }
      return;
    }
    if (_usesManagedPlayback && (state.isPlaying || state.isTransitioning)) {
      await pause();
      return;
    }
    if (_usesManagedPlayback && state.currentSong != null && !state.isPlaying) {
      if (_session?.canContinue == true && _session!.budgetExpired) {
        await continueSources();
        return;
      }
      await _start(state.currentSong!, state.position);
      return;
    }
    if (preservePlaybackOnSettingsChange &&
        state.currentSong != null &&
        !state.isPlaying &&
        !state.isTransitioning &&
        !router._hasLoadedMedia) {
      await _start(state.currentSong!, state.position);
      return;
    }
    await super.togglePlay();
  }

  @override
  Future<void> switchQuality(
    AudioLevel quality, {
    bool preferHighest = false,
  }) async {
    if (!_usesManagedPlayback) {
      await _loading;
      router.guarded = false;
      router.prepared = null;
      await super.switchQuality(quality, preferHighest: preferHighest);
      return;
    }
    final song = state.currentSong;
    if (song == null) return;
    _fixedOverride = quality;
    try {
      await _start(song, state.position);
    } finally {
      _fixedOverride = null;
    }
  }

  @override
  Future<void> clearQueue() async {
    cancelSourceAttempts();
    await super.clearQueue();
  }

  @override
  void dispose() {
    settings.removeListener(_settingsChanged);
    _unlisten();
    _session?.cancel();
    router.cancelMedia();
    _generation++;
    super.dispose();
  }
}

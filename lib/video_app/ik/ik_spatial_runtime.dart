import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../features/player/data/spatial_audio_capability.dart';
import '../../features/player/presentation/providers/player_provider.dart';
import '../../l10n/ik_spatial_strings.dart';

export '../../features/player/data/spatial_audio_capability.dart';

enum IkSpatialStatus { off, waiting, applying, active, unsupported, failed }

class IkSpatialState {
  const IkSpatialState({
    this.desired = const SpatialSettings(),
    this.effective = const SpatialSettings(),
    this.status = IkSpatialStatus.off,
    this.message = '',
    this.canEnable = false,
    this.processedFrames = 0,
  });
  final SpatialSettings desired, effective;
  final IkSpatialStatus status;
  final String message;
  final bool canEnable;
  final int processedFrames;
}

final ikSpatialRuntimeProvider =
    StateNotifierProvider<IkSpatialCoordinator, IkSpatialState>((ref) {
      final player = ref.read(playerProvider.notifier);
      final box = Hive.isBoxOpen('settings') ? Hive.box('settings') : null;
      final coordinator = IkSpatialCoordinator(
        capability: () => player.spatialAudioCapability,
        initial: SpatialSettings.fromMap(box?.get('ik.spatial.v1')),
        save: (settings) async {
          final store = box ?? await Hive.openBox('settings');
          await store.put('ik.spatial.v1', settings.toMap());
        },
      );
      unawaited(Future<void>.microtask(coordinator.initialize));
      return coordinator;
    });

class IkSpatialCoordinator extends StateNotifier<IkSpatialState> {
  IkSpatialCoordinator({
    required this.capability,
    required this.initial,
    required this.save,
    this.pollAutomatically = true,
  }) : super(IkSpatialState(desired: initial));

  final SpatialAudioCapable? Function() capability;
  final SpatialSettings initial;
  final Future<void> Function(SpatialSettings) save;
  final bool pollAutomatically;
  SpatialAudioCapable? _backend;
  Timer? _timer;
  Future<void> _pending = Future.value();
  int _request = DateTime.now().microsecondsSinceEpoch;
  bool _refreshing = false;

  Future<void> initialize() async {
    await _apply(initial, persist: false);
    if (mounted && pollAutomatically && state.canEnable) {
      _timer = Timer.periodic(
        const Duration(milliseconds: 700),
        (_) => unawaited(refresh()),
      );
    }
  }

  Future<void> setEnabled(bool enabled) =>
      _queue(state.desired.copyWith(enabled: enabled));
  Future<void> setStrength(double value) =>
      _queue(state.desired.copyWith(strength: value));
  Future<void> setDirection({double azimuth = 0, double elevation = 0}) =>
      _queue(state.desired.copyWith(azimuth: azimuth, elevation: elevation));
  Future<void> retry() => _queue(state.desired);

  Future<void> _queue(SpatialSettings settings) {
    final operation = _pending.then((_) => _apply(settings));
    _pending = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _apply(SpatialSettings desired, {bool persist = true}) async {
    if (!mounted) return;
    final previous = state.effective;
    final backend = capability();
    final request = ++_request;
    state = IkSpatialState(
      desired: desired,
      effective: previous,
      status: IkSpatialStatus.applying,
      canEnable: state.canEnable,
    );
    try {
      if (backend == null || !await backend.supportsSpatialAudio()) {
        if (!mounted) return;
        state = IkSpatialState(
          desired: desired,
          effective: previous.copyWith(enabled: false),
          status: IkSpatialStatus.unsupported,
          message: IkSpatialStrings.unsupported,
        );
        return;
      }
      _backend = backend;
      await backend.applySpatialAudio(desired, request);
      if (persist) await save(desired);
      if (!mounted || request != _request) return;
      state = IkSpatialState(
        desired: desired,
        effective: desired,
        status: desired.enabled ? IkSpatialStatus.waiting : IkSpatialStatus.off,
        message: desired.enabled ? IkSpatialStrings.waiting : '',
        canEnable: true,
      );
    } catch (error) {
      try {
        await backend?.applySpatialAudio(previous, request);
      } catch (_) {}
      if (!mounted || request != _request) return;
      state = IkSpatialState(
        desired: desired,
        effective: previous,
        status: IkSpatialStatus.failed,
        canEnable: backend != null,
        message: IkSpatialStrings.applyFailed(error),
      );
    }
  }

  Future<void> refresh() async {
    if (!mounted || _refreshing || state.status == IkSpatialStatus.applying) {
      return;
    }
    _refreshing = true;
    try {
      final backend = capability();
      if (!identical(backend, _backend)) {
        await _queue(state.desired);
        return;
      }
      if (backend == null || !state.effective.enabled) return;
      final request = _request;
      final report = await backend.readSpatialAudio();
      if (!mounted || request != _request) return;
      if (report.error != null) throw StateError(report.error!);
      final active = report.requestId == request && report.processedFrames > 0;
      state = IkSpatialState(
        desired: state.desired,
        effective: state.effective,
        status: active ? IkSpatialStatus.active : IkSpatialStatus.waiting,
        message: active ? IkSpatialStrings.active : IkSpatialStrings.waiting,
        canEnable: true,
        processedFrames: active ? report.processedFrames : 0,
      );
    } catch (error) {
      try {
        await _backend?.applySpatialAudio(
          state.effective.copyWith(enabled: false),
          ++_request,
        );
      } catch (_) {}
      if (mounted) {
        state = IkSpatialState(
          desired: state.desired,
          effective: state.effective.copyWith(enabled: false),
          status: IkSpatialStatus.failed,
          canEnable: true,
          message: IkSpatialStrings.processFailed(error),
        );
      }
    } finally {
      _refreshing = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

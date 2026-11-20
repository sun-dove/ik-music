import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/ik_gain_strings.dart';

class IkUserGainState {
  const IkUserGainState({this.gain = 1, this.busy = false, this.error});
  final double gain;
  final bool busy;
  final String? error;
}

final ikUserGainProvider =
    StateNotifierProvider<IkUserGainController, IkUserGainState>(
      (ref) => IkUserGainController(),
    );

class IkUserGainController extends StateNotifier<IkUserGainState> {
  IkUserGainController() : super(const IkUserGainState());
  IkGainBinding? _binding;
  double? _requested;
  double _lastAudible = 1;
  Future<void>? _worker;

  Future<void> setGain(double value) {
    if (!mounted || !value.isFinite) return Future.value();
    _requested = value.clamp(0.0, 1.0);
    final running = _worker;
    if (running != null) return running;
    final done = Completer<void>();
    _worker = done.future;
    state = IkUserGainState(gain: state.gain, busy: true);
    unawaited(_drain(done));
    return done.future;
  }

  Future<void> _drain(Completer<void> done) async {
    try {
      while (mounted && _requested != null) {
        final next = _requested!;
        _requested = null;
        final binding = _binding;
        try {
          if (binding != null) await binding._applyGain(next);
          if (!mounted) return;
          if (!identical(binding, _binding)) {
            _requested ??= next;
            continue;
          }
          if (next > 0) _lastAudible = next;
          state = IkUserGainState(gain: next, busy: true);
        } catch (error) {
          if (!mounted) return;
          if (!identical(binding, _binding)) {
            _requested ??= next;
            continue;
          }
          _reportFailure(error);
        }
      }
    } finally {
      _worker = null;
      if (mounted) {
        state = IkUserGainState(gain: state.gain, error: state.error);
      }
      done.complete();
    }
  }

  Future<void> toggleMute() =>
      setGain((_requested ?? state.gain) == 0 ? _lastAudible : 0);

  IkGainBinding attach(
    Future<void> Function(double) write, {
    double initialVolume = 1,
  }) {
    _binding?._closed = true;
    final binding = IkGainBinding._(this, write, initialVolume, state.gain);
    _binding = binding;
    return binding;
  }

  void _reportFailure(Object error) {
    if (!mounted) return;
    state = IkUserGainState(
      gain: state.gain,
      busy: state.busy,
      error: error is _GainWriteFailure && error.restoreFailed
          ? IkGainStrings.restoreFailed
          : IkGainStrings.failed,
    );
  }

  @override
  void dispose() {
    _binding?._closed = true;
    _binding = null;
    _requested = null;
    super.dispose();
  }
}

class IkGainBinding {
  IkGainBinding._(this._owner, this._write, this._volume, this._gain);
  final IkUserGainController _owner;
  final Future<void> Function(double) _write;
  double _volume, _gain;
  bool _closed = false;
  Future<void> _tail = Future.value();

  /// 原淡入淡出及看门狗只读取逻辑音量，用户静音不会被恢复成满音量。
  double get volume => _volume;

  Future<void> _serial(Future<void> Function() operation) {
    final next = _tail.then((_) async {
      if (_closed) throw StateError('gain_binding_closed');
      await operation();
    });
    _tail = next.catchError((Object _) {});
    return next;
  }

  Future<void> _writeValues(double logical, double gain) async {
    final previous = _volume * _gain;
    try {
      await _write(logical * gain);
    } catch (_) {
      if (_closed) rethrow;
      try {
        await _write(previous);
      } catch (_) {
        throw const _GainWriteFailure(true);
      }
      throw const _GainWriteFailure(false);
    }
    if (_closed) throw StateError('gain_binding_closed');
    _volume = logical;
    _gain = gain;
  }

  Future<void> _applyGain(double value) =>
      _serial(() => _writeValues(_volume, value));

  Future<void> setLogicalVolume(double value) => _serial(() async {
    try {
      await _writeValues(value.clamp(0.0, 1.0), _gain);
    } catch (error) {
      if (identical(_owner._binding, this)) _owner._reportFailure(error);
      rethrow;
    }
  });

  Future<void> preparePlayback() => _serial(() => _writeValues(_volume, _gain));

  Future<void> close() async {
    _closed = true;
    if (identical(_owner._binding, this)) _owner._binding = null;
  }
}

class _GainWriteFailure implements Exception {
  const _GainWriteFailure(this.restoreFailed);
  final bool restoreFailed;
}

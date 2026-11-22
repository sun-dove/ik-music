import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/platform_http.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../models/personal_daily_result.dart';
import '../../models/platform_type.dart';
import '../../platform/base/music_platform.dart';
import '../../platform/base/platform_registry.dart';
import 'video_auth_notifier.dart';

final personalDailyClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

final personalDailyProvider = StateNotifierProvider.autoDispose
    .family<PersonalDailyNotifier, PersonalDailyState, PlatformType>((
      ref,
      platform,
    ) {
      final auth = ref.watch(authProvider.notifier);
      final notifier = PersonalDailyNotifier._(
        platform: platform,
        auth: auth is VideoAuthNotifier ? auth : null,
        authState: ref.read(authProvider),
        now: ref.watch(personalDailyClockProvider),
      );
      ref.listen(authProvider, (_, next) => notifier._onAuthState(next));
      return notifier;
    });

class PersonalDailyState {
  const PersonalDailyState({this.isLoading = false, this.result});

  final bool isLoading;
  final PersonalDailyResult? result;
}

class PersonalDailyNotifier extends StateNotifier<PersonalDailyState> {
  PersonalDailyNotifier._({
    required this._platform,
    required this._auth,
    required this._authState,
    required this._now,
  }) : super(const PersonalDailyState(isLoading: true)) {
    try {
      _adapter = PlatformRegistry.get(_platform);
    } on PlatformNotSupportedException {
      _adapter = null;
    }
    _scope = _currentScope();
    _credentialChanges = _adapter?.personalDailySessionChanges;
    _credentialChanges?.addListener(_updateScope);
    _auth?.personalDailyAuthChanges.addListener(_updateScope);
    _queueLoad();
  }

  static const _timeout = Duration(seconds: 12);
  static const _timeoutCode = 'timeout';
  static final _validAccount = RegExp(r'^0*[1-9][0-9]*$');
  final PlatformType _platform;
  final VideoAuthNotifier? _auth;
  final DateTime Function() _now;
  late final MusicPlatform? _adapter;
  late final Listenable? _credentialChanges;
  AuthState _authState;
  late _DailyScope _scope;
  Completer<PersonalDailyResult?>? _pending;
  Timer? _deadline;
  Timer? _midnight;
  bool _queued = false;

  _DailyScope _currentScope() {
    final user = _authState.userFor(_platform);
    final local = _now().toLocal();
    return (
      day: DateTime(local.year, local.month, local.day),
      accountId: user?.id,
      accountPlatform: user?.platform,
      epoch: _auth?.sessionEpoch(_platform) ?? 0,
      revision: _adapter?.personalDailySessionRevision ?? 0,
      changing:
          (_auth?.isPersonalDailyAuthChanging(_platform) ?? false) ||
          (user == null && _authState.isLoading),
    );
  }

  void _onAuthState(AuthState next) {
    _authState = next;
    _updateScope();
  }

  void _updateScope() {
    final next = _currentScope();
    if (_scope == next) return;
    _scope = next;
    _cancelPending();
    state = const PersonalDailyState(isLoading: true);
    _queueLoad();
  }

  void _queueLoad() {
    if (_queued) return;
    _queued = true;
    scheduleMicrotask(() {
      if (mounted && _queued) unawaited(load());
    });
  }

  Future<void> load() async {
    if (!mounted) return;
    _queued = false;
    _cancelPending();
    final scope = _scope = _currentScope();
    _armMidnight(scope.day);
    if (scope.changing) {
      state = const PersonalDailyState(isLoading: true);
      return;
    }
    final adapter = _adapter;
    final accountId = scope.accountId;
    if (adapter == null || !adapter.supportsPersonalDailyRecommendations) {
      state = PersonalDailyState(
        result: _result(PersonalDailyStatus.unsupported),
      );
      return;
    }
    if (accountId == null) {
      state = PersonalDailyState(
        result: _result(PersonalDailyStatus.signedOut),
      );
      return;
    }
    if (scope.accountPlatform != _platform ||
        !_validAccount.hasMatch(accountId)) {
      state = PersonalDailyState(
        result: _result(PersonalDailyStatus.identityIncomplete),
      );
      return;
    }

    final pending = Completer<PersonalDailyResult?>();
    _pending = pending;
    _deadline = Timer(_timeout, () {
      if (!pending.isCompleted) {
        pending.complete(
          _result(PersonalDailyStatus.networkFailure, errorCode: _timeoutCode),
        );
      }
    });
    state = const PersonalDailyState(isLoading: true);
    unawaited(
      _request(adapter, accountId).then((result) {
        if (!pending.isCompleted) pending.complete(result);
      }),
    );

    final result = await pending.future;
    if (!mounted || !identical(_pending, pending)) return;
    _cancelPending();
    if (scope != _currentScope()) {
      _updateScope();
      return;
    }
    state = PersonalDailyState(result: result);
  }

  Future<PersonalDailyResult?> _request(
    MusicPlatform adapter,
    String accountId,
  ) async {
    try {
      final result = await adapter.getPersonalDailyRecommendations(
        expectedAccountId: accountId,
      );
      if (result.platform != _platform) {
        return _result(PersonalDailyStatus.invalidResponse);
      }
      return result;
    } on Object catch (error) {
      if (error is TimeoutException) {
        return _result(
          PersonalDailyStatus.networkFailure,
          errorCode: _timeoutCode,
        );
      }
      return switch (apiExceptionOf(error).code) {
        ApiErrorCode.requestCancelled => null,
        // 只报告给个人页。此异步结果不应清理账号或写入会话存储。
        ApiErrorCode.loginExpired => _result(
          PersonalDailyStatus.sessionExpired,
        ),
        ApiErrorCode.requestTimeout => _result(
          PersonalDailyStatus.networkFailure,
          errorCode: _timeoutCode,
        ),
        ApiErrorCode.network => _result(PersonalDailyStatus.networkFailure),
        ApiErrorCode.unsupportedAction => _result(
          PersonalDailyStatus.unsupported,
        ),
        _ => _result(PersonalDailyStatus.serviceUnavailable),
      };
    }
  }

  PersonalDailyResult _result(
    PersonalDailyStatus status, {
    String? errorCode,
  }) => PersonalDailyResult(
    platform: _platform,
    status: status,
    fetchedAt: _now(),
    errorCode: errorCode,
  );

  void _armMidnight(DateTime day) {
    _midnight?.cancel();
    // 用下个本地自然日零点，避免把夏令时切换日当成固定 24 小时。
    final next = DateTime(day.year, day.month, day.day + 1);
    _midnight = Timer(next.difference(_now()), () {
      _updateScope();
      if (!_queued) _armMidnight(_scope.day);
    });
  }

  void _cancelPending() {
    _deadline?.cancel();
    _deadline = null;
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.complete(null);
  }

  @override
  void dispose() {
    _auth?.personalDailyAuthChanges.removeListener(_updateScope);
    _credentialChanges?.removeListener(_updateScope);
    _midnight?.cancel();
    _cancelPending();
    super.dispose();
  }
}

typedef _DailyScope = ({
  DateTime day,
  String? accountId,
  PlatformType? accountPlatform,
  int epoch,
  int revision,
  bool changing,
});

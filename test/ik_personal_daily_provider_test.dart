import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/network/api_exception.dart';
import 'package:mconnect/features/auth/presentation/providers/auth_provider.dart';
import 'package:mconnect/models/personal_daily_result.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/models/user.dart';
import 'package:mconnect/platform/base/platform_registry.dart';
import 'package:mconnect/video_app/data/personal_daily_provider.dart';
import 'package:mconnect/video_app/data/video_auth_notifier.dart';

import 'support/content_page_fakes.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final platform in PlatformType.musicServices) {
    _testDaily('$platform 未登录或账号无效时不向平台请求', platform, (tester, scenario) async {
      await tester.pump();
      expect(scenario.state.result?.status, PersonalDailyStatus.signedOut);
      expect(scenario.adapter.requests, isEmpty);

      for (final id in ['', '0', '000']) {
        scenario.auth.select(platform, id);
        await tester.pump();
        expect(
          scenario.state.result?.status,
          PersonalDailyStatus.identityIncomplete,
        );
        expect(scenario.adapter.requests, isEmpty);
      }

      scenario.auth.select(platform, '101');
      await tester.pump();
      expect(scenario.adapter.accounts, ['101']);
      scenario.adapter.requests.single.complete(
        scenario.result(PersonalDailyStatus.identityIncomplete),
      );
      await tester.pump();
      expect(
        scenario.state.result?.status,
        PersonalDailyStatus.identityIncomplete,
      );
      expect(scenario.state.isLoading, isFalse);
    });
  }

  _testDaily('同账号换凭证会立即清空旧曲目并拒绝迟到过期', PlatformType.qq, (
    tester,
    scenario,
  ) async {
    await tester.pump();
    scenario.adapter.requests[0].complete(scenario.songs('before'));
    await tester.pump();
    expect(scenario.songIds, ['before']);

    scenario.adapter.rotate();
    expect(scenario.songIds, isEmpty);
    await tester.pump();
    scenario.adapter.rotate();
    await tester.pump();
    expect(scenario.adapter.accounts, ['101', '101', '101']);
    scenario.adapter.requests[2].complete(scenario.songs('current'));
    await tester.pump();
    scenario.adapter.requests[1].completeError(LoginExpiredException());
    await tester.pump();

    expect(scenario.songIds, ['current']);
    expect(scenario.auth.account(PlatformType.qq), '101');
    expect(scenario.auth.expiryCount, 0);
  }, account: '101');

  _testDaily('同一帧账号 A→B→A 也会清空 A 的旧请求', PlatformType.kugou, (
    tester,
    scenario,
  ) async {
    await tester.pump();

    scenario.auth.select(PlatformType.kugou, '202');
    scenario.auth.select(PlatformType.kugou, '101');
    await tester.pump();
    expect(scenario.adapter.accounts, ['101', '101']);
    scenario.adapter.requests[1].complete(scenario.songs('current'));
    await tester.pump();
    scenario.adapter.requests[0].complete(scenario.songs('old'));
    await tester.pump();
    expect(scenario.songIds, ['current']);
  }, account: '101');

  _testDaily('注销开始就清空当前日推，等待旧注销完成时不再发请求', PlatformType.qq, (
    tester,
    scenario,
  ) async {
    final logoutGate = Completer<void>();
    scenario.adapter.logoutGate = logoutGate;
    await tester.pump();
    scenario.adapter.requests[0].complete(scenario.songs('before'));
    await tester.pump();
    expect(scenario.songIds, ['before']);

    final logout = scenario.auth.logout(PlatformType.qq);
    expect(scenario.songIds, isEmpty);
    await tester.pump();
    expect(scenario.adapter.requests, hasLength(1));
    logoutGate.complete();
    await logout;
    await tester.pump();
    expect(scenario.state.result?.status, PersonalDailyStatus.signedOut);
    expect(scenario.adapter.requests, hasLength(1));
  }, account: '101');

  _testDaily('重新扫码核对同账号期间清空旧曲目，确认后才加载', PlatformType.qq, (
    tester,
    scenario,
  ) async {
    final loginGate = Completer<User?>();
    scenario.adapter.loginGate = loginGate;
    await tester.pump();
    scenario.adapter.requests[0].complete(scenario.songs('before'));
    await tester.pump();
    expect(scenario.songIds, ['before']);

    final login = scenario.auth.onQrLoginSuccess(PlatformType.qq);
    expect(scenario.songIds, isEmpty);
    await tester.pump();
    expect(scenario.adapter.requests, hasLength(1));
    loginGate.complete(
      const User(id: '101', nickname: '场景账号', platform: PlatformType.qq),
    );
    expect((await login)?.id, '101');
    await tester.pump();
    expect(scenario.adapter.accounts, ['101', '101']);
    scenario.adapter.requests[1].complete(scenario.songs('after'));
    await tester.pump();
    expect(scenario.songIds, ['after']);
  }, account: '101');

  _testDaily(
    '跨自然日会换请求，昨日的迟到响应不起效',
    PlatformType.netease,
    (tester, scenario) async {
      await tester.pump();
      expect(scenario.adapter.requests, hasLength(1));

      scenario.now = DateTime(2026, 11, 23);
      await tester.pump(const Duration(seconds: 1));
      expect(scenario.adapter.requests, hasLength(2));
      expect(scenario.state.isLoading, isTrue);
      scenario.adapter.requests[0].complete(scenario.songs('yesterday'));
      await tester.pump();
      expect(scenario.songIds, isEmpty);
      expect(scenario.state.isLoading, isTrue);
      scenario.adapter.requests[1].complete(scenario.songs('today'));
      await tester.pump();
      expect(scenario.songIds, ['today']);
    },
    account: '101',
    start: DateTime(2026, 11, 22, 23, 59, 59),
  );

  _testDaily('同平台快速重试只采纳最新请求，保留另一平台的成功', PlatformType.qq, (
    tester,
    scenario,
  ) async {
    final netease = _DailyPlatform(PlatformType.netease);
    addTearDown(netease.revision.dispose);
    PlatformRegistry.register(netease);
    scenario.auth.select(PlatformType.netease, '303');
    final otherProvider = personalDailyProvider(PlatformType.netease);
    scenario.container.listen(otherProvider, (_, _) {});
    await tester.pump();
    final retry = scenario.notifier.load();
    expect(scenario.adapter.requests, hasLength(2));
    expect(netease.accounts, ['303']);
    expect(netease.limits, [30]);
    netease.requests.single.complete(_success(PlatformType.netease, 'netease'));
    scenario.adapter.requests[1].complete(scenario.songs('new'));
    await retry;
    scenario.adapter.requests[0].complete(scenario.songs('old'));
    await tester.pump();

    expect(scenario.songIds, ['new']);
    expect(
      scenario.container.read(otherProvider).result?.songs.single.id,
      'netease',
    );
    expect(netease.requests, hasLength(1));
  }, account: '101');

  _testDaily('平台验证、会话过期、超时保留各自状态且不动账号', PlatformType.kugou, (
    tester,
    scenario,
  ) async {
    await tester.pump();
    scenario.adapter.requests[0].complete(
      scenario.result(PersonalDailyStatus.verificationRequired),
    );
    await tester.pump();
    expect(
      scenario.state.result?.status,
      PersonalDailyStatus.verificationRequired,
    );

    final expired = scenario.notifier.load();
    scenario.adapter.requests[1].completeError(LoginExpiredException());
    await expired;
    expect(scenario.state.result?.status, PersonalDailyStatus.sessionExpired);

    final timeout = scenario.notifier.load();
    await tester.pump(const Duration(seconds: 30));
    await timeout;
    expect(scenario.state.result?.status, PersonalDailyStatus.networkFailure);
    expect(scenario.state.result?.errorCode, 'timeout');
    expect(scenario.state.result?.retryable, isTrue);
    expect(scenario.auth.account(PlatformType.kugou), '101');
    expect(scenario.auth.expiryCount, 0);
    scenario.adapter.requests[2].complete(scenario.songs('late'));
    await tester.pump();
    expect(scenario.songIds, isEmpty);

    for (final error in [
      TimeoutException('adapter timeout'),
      NetworkException(code: ApiErrorCode.requestTimeout),
      NetworkException(),
    ]) {
      final pending = scenario.notifier.load();
      scenario.adapter.requests.last.completeError(error);
      await pending;
      expect(scenario.state.result?.status, PersonalDailyStatus.networkFailure);
      expect(
        scenario.state.result?.errorCode,
        error is NetworkException && error.code == ApiErrorCode.network
            ? isNull
            : 'timeout',
        reason: '区分连接失败与加载超时',
      );
      expect(scenario.state.result?.retryable, isTrue);
      expect(scenario.auth.account(PlatformType.kugou), '101');
      expect(scenario.auth.expiryCount, 0);
    }
  }, account: '101');

  _testDaily('请求取消与销毁后的应答均不会写入后续页面', PlatformType.netease, (
    tester,
    scenario,
  ) async {
    await tester.pump();
    scenario.adapter.requests[0].completeError(RequestCancelledException());
    await tester.pump();
    expect(scenario.state.result, isNull);
    expect(scenario.state.isLoading, isFalse);

    final pending = scenario.notifier.load();
    scenario.disposeContainer();
    scenario.adapter.requests[1].completeError(LoginExpiredException());
    await pending;
    scenario.adapter.rotate();
    await tester.pump();
    expect(tester.takeException(), isNull);
  }, account: '101');
}

void _testDaily(
  String name,
  PlatformType platform,
  Future<void> Function(WidgetTester, _Scenario) body, {
  String? account,
  DateTime? start,
}) {
  testWidgets(name, (tester) async {
    final scenario = _Scenario(platform, account: account, start: start);
    try {
      await body(tester, scenario);
      expect(scenario.adapter.limits, everyElement(30));
    } finally {
      scenario.dispose();
    }
  });
}

PersonalDailyResult _success(PlatformType platform, String id) =>
    PersonalDailyResult(
      platform: platform,
      status: PersonalDailyStatus.success,
      songs: [Song(id: id, platform: platform, name: id, artists: const [])],
      rawCount: 1,
      validCount: 1,
      fetchedAt: DateTime(2026, 11, 22),
    );

class _Scenario {
  _Scenario(this.platform, {String? account, DateTime? start})
    : now = start ?? DateTime(2026, 11, 22, 12),
      adapter = _DailyPlatform(platform) {
    PlatformRegistry.register(adapter);
    auth.select(platform, account);
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((ref) => auth),
        personalDailyClockProvider.overrideWithValue(() => now),
      ],
    );
    container.listen(personalDailyProvider(platform), (_, _) {});
  }

  final PlatformType platform;
  DateTime now;
  final _DailyPlatform adapter;
  final auth = _DailyAuth();
  late final ProviderContainer container;
  bool _disposed = false;

  PersonalDailyState get state =>
      container.read(personalDailyProvider(platform));
  PersonalDailyNotifier get notifier =>
      container.read(personalDailyProvider(platform).notifier);
  List<String> get songIds =>
      state.result?.songs.map((song) => song.id).toList() ?? [];

  PersonalDailyResult result(PersonalDailyStatus status) =>
      PersonalDailyResult(platform: platform, status: status, fetchedAt: now);

  PersonalDailyResult songs(String id) => PersonalDailyResult(
    platform: platform,
    status: PersonalDailyStatus.success,
    songs: [Song(id: id, platform: platform, name: id, artists: const [])],
    rawCount: 1,
    validCount: 1,
    fetchedAt: now,
  );

  void disposeContainer() {
    if (_disposed) return;
    _disposed = true;
    container.dispose();
  }

  void dispose() {
    disposeContainer();
    adapter.revision.dispose();
  }
}

class _DailyAuth extends VideoAuthNotifier {
  int get expiryCount => state.expiryNoticeId;

  String? account(PlatformType platform) => state.userFor(platform)?.id;

  void select(PlatformType platform, String? id) {
    state = state.copyWith(
      loggedUsers: {
        ...state.loggedUsers,
        platform: id == null
            ? null
            : User(id: id, nickname: id, platform: platform),
      },
    );
  }
}

class _DailyPlatform extends FakeContentPlatform {
  _DailyPlatform(PlatformType platform) : super(type: platform);

  final revision = ValueNotifier(0);
  final accounts = <String?>[];
  final limits = <int>[];
  final requests = <Completer<PersonalDailyResult>>[];
  Completer<void>? logoutGate;
  Completer<User?>? loginGate;

  @override
  bool get supportsPersonalDailyRecommendations => true;

  @override
  ValueListenable<int> get personalDailySessionChanges => revision;

  void rotate() => revision.value++;

  @override
  Future<void> logout() async => await logoutGate?.future;

  @override
  Future<User?> getUserInfo() async => await loginGate?.future;

  @override
  Future<PersonalDailyResult> getPersonalDailyRecommendations({
    int limit = 30,
    String? expectedAccountId,
  }) {
    limits.add(limit);
    accounts.add(expectedAccountId);
    final request = Completer<PersonalDailyResult>();
    requests.add(request);
    return request.future;
  }
}

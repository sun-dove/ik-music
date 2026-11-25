import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/network/api_exception.dart';
import 'package:mconnect/core/network/platform_http.dart';
import 'package:mconnect/core/storage/session_storage.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/user.dart';
import 'package:mconnect/platform/qq/qq_api.dart';
import 'package:mconnect/platform/qq/qq_endpoints.dart';
import 'package:mconnect/platform/qq/qq_platform.dart';

const _id = '987654';
const _cookie =
    'uin=o100001; qqmusic_uin=200002; qm_keyst=fictional-key; '
    'qqmusic_encrypt_uin=fictional-encrypted';

void main() {
  test('QQ 日推未登录、缺身份或音乐 ID=0 时不请求', () async {
    final anonymous = await _fixture((_) => throw StateError('unexpected'));
    expect(
      (await anonymous.platform.getPersonalDailyRecommendations()).status.name,
      'signedOut',
    );
    expect(anonymous.adapter.requests, isEmpty);

    for (final cookie in [
      'uin=o100001; qqmusic_uin=200002; qm_keyst=fictional-key',
      _cookie.replaceFirst('qqmusic_uin=200002', 'qqmusic_uin=0'),
      _cookie.replaceFirst('qqmusic_uin=200002', 'qqmusic_uin=0000'),
      _cookie.replaceFirst('qm_keyst=fictional-key', 'qm_keyst='),
    ]) {
      final fixture = await _fixture(
        (_) => throw StateError('unexpected'),
        cookie: cookie,
        userId: '100001',
      );
      final result = await fixture.platform.getPersonalDailyRecommendations();
      expect(result.status.name, 'identityIncomplete');
      expect(result.songs, isEmpty);
      expect(fixture.adapter.requests, isEmpty);
    }
    final mismatched = await _fixture(
      (_) => throw StateError('unexpected'),
      cookie: _cookie,
      userId: '300003',
    );
    expect(
      (await mismatched.platform.getPersonalDailyRecommendations()).status.name,
      'identityIncomplete',
    );
    expect(mismatched.adapter.requests, isEmpty);
  });

  test('QQ 日推从同一私享卡片取 ID，跨页保留平台顺序和实际数量', () async {
    final fixture = await _fixture(
      (request) {
        expect(request.headers['cookie'], _cookie);
        if (request.uri.toString() == QqEndpoints.dailyPrivatePage) {
          return _html('''
          <li class="playlist__item" data-rid="444444">公共歌单</li>
          <!-- <li class="playlist__item" data-rid="111111">今日私享</li> -->
          <script>var html = '<li class="playlist__item" data-rid="222222">今日私享</li>';</script>
          <div class='another playlist__item'><a href="/n/ryqq/playlist/$_id.html"></a>
            <div class="playlist__name" title="今日私享">今日私享</div>
          </div>
          <li class="playlist__item" data-rid="555555">相邻歌单</li>''');
        }
        final params = _detailParams(request);
        expect(params['disstid'], int.parse(_id));
        return switch (params['song_begin']) {
          0 => _detail([_song(1), _song(2)], total: 5),
          2 => _detail([_song(2), _song(3)], total: 5),
          4 => _detail([_song(4)], total: 5),
          _ => throw StateError('wrong page'),
        };
      },
      cookie: _cookie,
      userId: '100001',
    );

    final result = await fixture.platform.getPersonalDailyRecommendations();

    expect(result.status.name, 'success');
    expect(result.platform, PlatformType.qq);
    expect(result.rawCount, 5);
    expect(result.validCount, 4);
    expect(result.songs.map((song) => song.id), [
      'mid1',
      'mid2',
      'mid3',
      'mid4',
    ]);
    expect(result.songs.first.artists.single.name, '艺人 1');
    expect(result.songs.first.duration, const Duration(seconds: 120));
    expect(fixture.adapter.requests, hasLength(4));
  });

  test('QQ 音乐身份切换后旧 OAuth 用户不能读取新账号私享', () async {
    final fixture = await _signedIn((_) => throw StateError('unexpected'));
    fixture.api.restoreCookie(_cookie.replaceAll('200002', '300003'));

    final result = await fixture.platform.getPersonalDailyRecommendations();

    expect(result.status.name, 'identityIncomplete');
    expect(result.songs, isEmpty);
    expect(fixture.adapter.requests, isEmpty);
  });

  test('QQ 恢复的两项 OAuth 账号互相矛盾时不访问私享', () async {
    final fixture = await _fixture(
      (request) =>
          request.method == 'GET' ? _html(_privateCard) : _detail([_song(1)]),
      cookie: '${_cookie.replaceFirst('o100001', 'o200002')}; loginUin=100001',
      userId: '100001',
    );

    final result = await fixture.platform.getPersonalDailyRecommendations(
      expectedAccountId: '100001',
    );

    expect(result.status.name, 'identityIncomplete');
    expect(result.songs, isEmpty);
    expect(fixture.adapter.requests, isEmpty);
  });

  test('QQ 恢复的两项 OAuth 账号一致时可绑定不同的音乐 ID', () async {
    final fixture = await _fixture(
      (request) =>
          request.method == 'GET' ? _html(_privateCard) : _detail([_song(1)]),
      cookie: '$_cookie; loginUin=100001',
      userId: '100001',
    );

    final result = await fixture.platform.getPersonalDailyRecommendations(
      expectedAccountId: '100001',
    );

    expect(result.status.name, 'success');
    expect(result.songs.single.id, 'mid1');
    expect(fixture.adapter.requests, hasLength(2));
  });

  test('QQ 日推预期账号不匹配时不访问平台', () async {
    final fixture = await _signedIn((_) => throw StateError('unexpected'));

    final result = await fixture.platform.getPersonalDailyRecommendations(
      expectedAccountId: '300003',
    );

    expect(result.status.name, 'identityIncomplete');
    expect(result.songs, isEmpty);
    expect(fixture.adapter.requests, isEmpty);
  });

  test('QQ 旧资料入口更新 OAuth 账号后不能读取原音乐身份的私享', () async {
    final fixture = await _signedIn((request) {
      if (request.uri.path.contains('musicu')) {
        return _detail([_song(1)]);
      }
      if (request.uri.toString() == QqEndpoints.dailyPrivatePage) {
        return _html(_privateCard);
      }
      return _json({
        'profile': {'nick': '切换后的账号'},
      });
    });
    fixture.api.restoreCookie(_cookie.replaceFirst('o100001', 'o300003'));
    final refreshed = await fixture.platform.getUserInfo();
    expect(refreshed?.id, '300003');
    final existing = fixture.adapter.requests.length;
    expect(existing, 1);

    final result = await fixture.platform.getPersonalDailyRecommendations(
      expectedAccountId: '300003',
    );

    expect(result.status.name, 'identityIncomplete');
    expect(result.songs, isEmpty);
    expect(fixture.adapter.requests, hasLength(existing));
  });

  test('QQ 会话凭据轮换即刻通知，恢复同一账号也标记新会话', () async {
    final fixture = await _signedIn((_) => throw StateError('unexpected'));
    final changes = fixture.platform.personalDailySessionChanges;
    final start = changes.value;
    final observed = <int>[];
    void onChange() => observed.add(changes.value);
    changes.addListener(onChange);
    addTearDown(() => changes.removeListener(onChange));

    fixture.api.setCookie('qm_keyst=fictional-rotated');
    expect(observed, hasLength(1));
    expect(observed.single, greaterThan(start));
    fixture.api.restoreCookie(_cookie);
    fixture.api.restoreCookie(_cookie);
    expect(observed, hasLength(3));
    expect(observed[2], greaterThan(observed[1]));
    expect(observed[1], greaterThan(observed[0]));
    expect(fixture.adapter.requests, isEmpty);
  });

  for (final count in [0, 1, 29, 30, 31, 32]) {
    test('QQ 私享实际返回 $count 首时最多展示 30 首', () async {
      final fixture = await _signedIn(
        (request) => request.method == 'GET'
            ? _html(_privateCard)
            : _detail(List.generate(count, (i) => _song(i + 1))),
      );

      final result = await fixture.platform.getPersonalDailyRecommendations();

      expect(result.status.name, count == 0 ? 'empty' : 'success');
      expect(result.rawCount, count);
      expect(result.validCount, count);
      expect(
        result.songs.map((song) => song.id),
        List.generate(count > 30 ? 30 : count, (i) => 'mid${i + 1}'),
      );
      expect(fixture.adapter.requests, hasLength(2));
    });
  }

  test('QQ 私享在已去重的有效歌曲上应用调用端展示上限', () async {
    final fixture = await _signedIn(
      (request) => request.method == 'GET'
          ? _html(_privateCard)
          : _detail([_song(1), _song(1), {}, _song(2), _song(3)]),
    );

    final result = await fixture.platform.getPersonalDailyRecommendations(
      limit: 2,
    );

    expect(result.status.name, 'success');
    expect(result.rawCount, 5);
    expect(result.validCount, 3);
    expect(result.songs.map((song) => song.id), ['mid1', 'mid2']);
  });

  test('QQ 显式指定超过 30 首也只展示前 30 首，保留完整原始数量', () async {
    final fixture = await _signedIn(
      (request) => request.method == 'GET'
          ? _html(_privateCard)
          : _detail(List.generate(32, (i) => _song(i + 1))),
    );

    final result = await fixture.platform.getPersonalDailyRecommendations(
      limit: 99,
    );

    expect(result.status.name, 'success');
    expect(result.rawCount, 32);
    expect(result.validCount, 32);
    expect(result.displayCount, 30);
    expect(
      result.songs.map((song) => song.id),
      List.generate(30, (i) => 'mid${i + 1}'),
    );
  });

  final misleadingPages = <String, String>{
    '脚本和注释':
        '''
      <!-- $_privateCard -->
      <script>var unreachable = '$_privateCard';</script>
      <template>$_privateCard</template>
      <li class="playlist__item" data-rid="333333">公开歌单</li>''',
    '相邻公共卡片': '''
      <li class="playlist__item">今日私享</li>
      <li class="playlist__item" data-rid="333333">公开歌单</li>''',
    '嵌套公共卡片': '''
      <div class="playlist__item">今日私享
        <div class="playlist__item" data-rid="333333">公开歌单</div>
      </div>''',
    '同卡片内两个不同 ID':
        '''
      <li class="playlist__item" data-rid="$_id">今日私享
        <a href="/n/ryqq/playlist/333333">去往其他歌单</a>
      </li>''',
    '同标签的重复 ID 属性':
        '<li class="playlist__item" data-rid="$_id" data-rid="333333">今日私享</li>',
    '两张私享卡片':
        '''
      $_privateCard
      <li class="playlist__item" data-rid="333333">今日私享</li>''',
    '歌单 ID 为零': '<li class="playlist__item" data-rid="0">今日私享</li>',
    '正文文字提及私享': '''
      <p>今日私享</p>
      <li class="playlist__item" data-rid="333333">什么是今日私享？</li>''',
  };
  for (final entry in misleadingPages.entries) {
    test('QQ 私享拒绝从${entry.key}推断个人歌单', () async {
      final fixture = await _signedIn((request) {
        expect(request.uri.toString(), QqEndpoints.dailyPrivatePage);
        return _html(entry.value);
      });

      final result = await fixture.platform.getPersonalDailyRecommendations();

      expect(
        result.status.name,
        anyOf('serviceUnavailable', 'invalidResponse'),
      );
      expect(result.songs, isEmpty);
      expect(fixture.adapter.requests, hasLength(1));
    });
  }

  final malformedDetails = <String, ResponseBody Function()>{
    '矛盾的歌单 ID': () => _detail([_song(1)], playlistId: '333333'),
    '空白歌曲身份': () => _detail([
      {},
      {
        'songInfo': {'mid': 0},
      },
      null,
    ]),
    '非 JSON': () => _html('<html>维护中</html>'),
    '成功码缺失': () => _json({
      'req_0': {
        'code': 0,
        'data': {
          'songlist': [_song(1)],
        },
      },
    }),
    '无进展分页': () => _detail([], total: 2),
  };
  for (final entry in malformedDetails.entries) {
    test('QQ 日推将${entry.key}判为响应无效', () async {
      final fixture = await _signedIn(
        (request) =>
            request.method == 'GET' ? _html(_privateCard) : entry.value(),
      );
      final result = await fixture.platform.getPersonalDailyRecommendations();
      expect(result.status.name, 'invalidResponse');
      expect(result.songs, isEmpty);
      expect(fixture.adapter.requests, hasLength(2));
    });
  }

  test('QQ 日推第二页失败不交出第一页，也不调用公共回退', () async {
    final fixture = await _signedIn((request) {
      if (request.method == 'GET') return _html(_privateCard);
      return switch (_detailParams(request)['song_begin']) {
        0 => _detail([_song(1)], total: 2),
        1 => _json({
          'code': 0,
          'req_0': {'code': 9123},
        }),
        _ => throw StateError('wrong page'),
      };
    });

    final result = await fixture.platform.getPersonalDailyRecommendations();

    expect(result.status.name, 'serviceUnavailable');
    expect(result.songs, isEmpty);
    expect(fixture.adapter.requests, hasLength(3));
  });

  test('QQ 私享超时返回网络失败且不泄漏凭据', () async {
    final fixture = await _signedIn((request) {
      if (request.method == 'GET') return _html(_privateCard);
      throw DioException(
        requestOptions: request,
        type: DioExceptionType.receiveTimeout,
        message: _cookie,
      );
    });

    final result = await fixture.platform.getPersonalDailyRecommendations();

    expect(result.status.name, 'networkFailure');
    expect(result.toString(), isNot(contains('fictional-key')));
    expect(result.songs, isEmpty);
  });

  test('QQ 新 403 区分拒绝访问且旧 403 仍报告会话失效', () async {
    final reports = <PlatformType>[];
    final fixture = await _signedIn(
      (_) => _html('<html>Forbidden</html>', status: 403),
      onExpired: reports.add,
    );

    final result = await fixture.platform.getPersonalDailyRecommendations();

    expect(result.status.name, 'serviceUnavailable');
    expect(result.songs, isEmpty);
    expect(fixture.platform.isLoggedIn, isTrue);
    expect(reports, isEmpty);
    await expectLater(
      fixture.api.getDailyPlaylistId(),
      throwsA(
        isA<DioException>().having(
          (error) => error.error,
          '旧路径的类型化错误',
          isA<LoginExpiredException>(),
        ),
      ),
    );
    expect(reports, [PlatformType.qq]);
  });

  test('QQ 详情 HTTP 200 的拒绝访问提示归服务失败', () async {
    final reports = <PlatformType>[];
    final fixture = await _signedIn((request) {
      if (request.method == 'GET') return _html(_privateCard);
      _detailParams(request);
      return ResponseBody.fromString('Access Deny ! No Actions !', 200);
    }, onExpired: reports.add);

    final result = await fixture.platform.getPersonalDailyRecommendations();

    expect(result.status.name, 'serviceUnavailable');
    expect(result.songs, isEmpty);
    expect(fixture.platform.isLoggedIn, isTrue);
    expect(reports, isEmpty);
    expect(fixture.adapter.requests, hasLength(2));
  });

  test('QQ 详情 JSON 歌名含拒绝访问文字时仍是有效曲目', () async {
    const title = 'Access Deny ! No Actions !';
    final fixture = await _signedIn((request) {
      if (request.method == 'GET') return _html(_privateCard);
      return _detail([
        {
          'songInfo': {'mid': 'mid1', 'name': title},
        },
      ]);
    });

    final result = await fixture.platform.getPersonalDailyRecommendations();

    expect(result.status.name, 'success');
    expect(result.songs.single.name, title);
    expect(fixture.adapter.requests, hasLength(2));
  });

  test('QQ 私享 401 只返回对应当前请求的会话过期状态', () async {
    final reports = <PlatformType>[];
    final fixture = await _signedIn(
      (_) => _json({'code': 401}, status: 401),
      onExpired: reports.add,
    );

    final result = await fixture.platform.getPersonalDailyRecommendations();

    expect(result.status.name, 'sessionExpired');
    expect(result.songs, isEmpty);
    expect(reports, isEmpty);
    expect(fixture.adapter.requests, hasLength(1));
  });

  for (final swapTwice in [false, true]) {
    test('QQ 私享丢弃${swapTwice ? 'A→B→A' : '同账号换 key'}前的响应', () async {
      final entered = Completer<void>();
      final pendingPage = Completer<ResponseBody>();
      final reports = <PlatformType>[];
      final fixture = await _signedIn((request) {
        if (request.method == 'GET') return _html(_privateCard);
        entered.complete();
        return pendingPage.future;
      }, onExpired: reports.add);

      final pending = fixture.platform.getPersonalDailyRecommendations();
      await Future.any([
        entered.future,
        pending.then((_) => fail('请求应在音乐会话仍有效时到达详情端点')),
      ]);
      if (swapTwice) {
        fixture.api.restoreCookie(_cookie.replaceAll('200002', '300003'));
        fixture.api.restoreCookie(_cookie);
      } else {
        fixture.api.setCookie('qm_keyst=another-fictional-key');
      }
      pendingPage.complete(
        swapTwice ? _json({'code': 401}, status: 401) : _detail([_song(1)]),
      );
      final result = await pending;

      expect(result.status.name, 'sessionChanged');
      expect(result.songs, isEmpty);
      expect(fixture.platform.isLoggedIn, isTrue);
      expect(reports, isEmpty);
      expect(fixture.adapter.requests, hasLength(2));
    });
  }
}

const _privateCard =
    '<li class="playlist__item"><a data-rid="$_id">今日私享</a></li>';

Map<String, dynamic> _song(int ordinal) => {
  'songInfo': {
    'mid': 'mid$ordinal',
    'name': '歌曲 $ordinal',
    'singer': [
      {'mid': 'artist$ordinal', 'name': '艺人 $ordinal'},
    ],
    'interval': 120,
  },
};

Map<dynamic, dynamic> _detailParams(RequestOptions request) {
  expect(request.uri.toString(), QqEndpoints.musicu);
  final module = (request.data as Map)['req_0'] as Map;
  expect(module['module'], QqEndpoints.modulePlaylistDetail);
  expect(module['method'], QqEndpoints.methodGetPlaylistDetail);
  return module['param'] as Map;
}

ResponseBody _detail(
  List<dynamic> rows, {
  int? total,
  String playlistId = _id,
}) => _json({
  'code': 0,
  'req_0': {
    'code': 0,
    'data': {
      'songlist': rows,
      'dirinfo': {'disstid': playlistId, 'songnum': total ?? rows.length},
    },
  },
});

ResponseBody _json(Object body, {int status = 200}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

ResponseBody _html(String body, {int status = 200}) => ResponseBody.fromString(
  body,
  status,
  headers: {
    Headers.contentTypeHeader: ['text/html; charset=utf-8'],
  },
);

typedef _Fixture = ({QqApi api, QqPlatform platform, _ScriptedAdapter adapter});
typedef _Respond = FutureOr<ResponseBody> Function(RequestOptions);

Future<_Fixture> _signedIn(
  _Respond respond, {
  SessionExpiredHandler? onExpired,
}) =>
    _fixture(respond, cookie: _cookie, userId: '100001', onExpired: onExpired);

Future<_Fixture> _fixture(
  _Respond respond, {
  String? cookie,
  String? userId,
  SessionExpiredHandler? onExpired,
}) async {
  final adapter = _ScriptedAdapter(respond);
  final dio = createPlatformDio(
    platform: PlatformType.qq,
    onSessionExpired: onExpired,
    maxRetries: 0,
  )..httpClientAdapter = adapter;
  addTearDown(() => dio.close(force: true));
  final api = QqApi(dio: dio);
  final platform = QqPlatform(api: api);
  if (userId != null) {
    await platform.restoreSession(_StoredSession(userId, cookie));
  }
  return (api: api, platform: platform, adapter: adapter);
}

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.respond);

  final _Respond respond;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

class _StoredSession extends SessionStorage {
  _StoredSession(this.userId, this.cookie);

  final String userId;
  final String? cookie;

  @override
  Future<String?> loadCookie(PlatformType platform) async => cookie;

  @override
  Future<User?> loadUser(PlatformType platform) async =>
      User(id: userId, nickname: '账号样例', platform: platform);
}

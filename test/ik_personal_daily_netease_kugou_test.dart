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
import 'package:mconnect/platform/base/music_platform.dart';
import 'package:mconnect/platform/kugou/kugou_api.dart';
import 'package:mconnect/platform/kugou/kugou_platform.dart';
import 'package:mconnect/platform/netease/netease_api.dart';
import 'package:mconnect/platform/netease/netease_platform.dart';

void main() {
  for (final source in [PlatformType.netease, PlatformType.kugou]) {
    group('${source.name} 个人每日推荐功能门', () {
      test('未登录、音乐ID无效或缺少凭证时不发个人请求', () async {
        final anonymous = _Scenario(source);
        expect(
          (await anonymous.platform.getPersonalDailyRecommendations())
              .status
              .name,
          'signedOut',
        );
        expect(anonymous.transport.requests, isEmpty);

        for (final id in ['0', '9001']) {
          final scenario = _Scenario(source);
          await scenario.restore(id: id, complete: id == '0');
          expect(
            (await scenario.platform.getPersonalDailyRecommendations())
                .status
                .name,
            'identityIncomplete',
          );
          expect(scenario.transport.requests, isEmpty);
        }
      });

      test('当前页面账号与平台会话不一致时不发送日推请求', () async {
        final scenario = _Scenario(source);
        await scenario.restore();
        final result = await scenario.platform.getPersonalDailyRecommendations(
          expectedAccountId: '9002',
        );
        expect(result.status.name, 'identityIncomplete');
        expect(scenario.transport.requests, isEmpty);
      });

      for (final count in [0, 1, 29, 30, 31, 32]) {
        test('服务端返回$count首时按实际数量展示，上限30', () async {
          final scenario = _Scenario(source);
          await scenario.restore();
          scenario.transport.reply = (_, _) => _json(
            scenario.success([
              for (var i = 1; i <= count; i++) scenario.song(i),
            ]),
          );

          final result = await scenario.platform
              .getPersonalDailyRecommendations();
          final displayed = count > 30 ? 30 : count;
          expect(result.status.name, count == 0 ? 'empty' : 'success');
          expect(result.platform, source);
          expect(result.rawCount, count);
          expect(result.validCount, count);
          expect(result.songs.map((s) => s.id), [
            for (var i = 1; i <= displayed; i++) scenario.songId(i),
          ]);
          expect(result.sourceDate, isNull);
          expect(scenario.transport.dailyRequests, hasLength(1));
        });
      }

      test('稳定去重、丢弃无效身份，解析第30首之后的数量', () async {
        final scenario = _Scenario(source);
        await scenario.restore();
        scenario.transport.reply = (_, _) => _json(
          scenario.success([
            scenario.song(10),
            scenario.song(10, duplicate: true),
            scenario.song(0),
            '非法曲目',
            for (var i = 1; i <= 33; i++)
              if (i != 10) scenario.song(i),
          ]),
        );

        final result = await scenario.platform
            .getPersonalDailyRecommendations();
        expect(result.status.name, 'success');
        expect(result.rawCount, 36);
        expect(result.validCount, 33);
        expect(result.songs.first.name, '歌曲 10');
        expect(result.songs.first.artistNames, '歌手 10');
        expect(result.songs.map((s) => s.id), [
          scenario.songId(10),
          for (var i = 1; i <= 30; i++)
            if (i != 10) scenario.songId(i),
        ]);

        scenario.transport.reply = (_, _) => _json(
          scenario.success([scenario.song(0), null, <String, dynamic>{}]),
        );
        final invalid = await scenario.platform
            .getPersonalDailyRecommendations();
        expect(invalid.status.name, 'invalidResponse');
        expect(invalid.rawCount, 3);
        expect(invalid.songs, isEmpty);
      });

      test('无法解析的数据、未知业务失败和超时返回各自状态', () async {
        final scenario = _Scenario(source);
        await scenario.restore();
        scenario.transport.reply = (_, _) =>
            ResponseBody.fromString('abc', 200);
        expect(
          (await scenario.platform.getPersonalDailyRecommendations())
              .status
              .name,
          'invalidResponse',
        );

        scenario.transport.reply = (_, _) => _json(
          source == PlatformType.netease
              ? {'code': 79999}
              : {'status': 0, 'error_code': 79999},
        );
        final service = await scenario.platform
            .getPersonalDailyRecommendations();
        expect(service.status.name, 'serviceUnavailable');
        expect(service.errorCode.toString(), '79999');
        expect(service.songs, isEmpty);

        final expectedCodes = {
          DioExceptionType.connectionTimeout: ApiErrorCode.requestTimeout.name,
          DioExceptionType.sendTimeout: ApiErrorCode.requestTimeout.name,
          DioExceptionType.receiveTimeout: ApiErrorCode.requestTimeout.name,
          DioExceptionType.connectionError: null,
        };
        final actualCodes = <DioExceptionType, String?>{};
        for (final type in expectedCodes.keys) {
          scenario.transport.reply = (options, _) =>
              throw DioException(requestOptions: options, type: type);
          final network = await scenario.platform
              .getPersonalDailyRecommendations();
          expect(network.status.name, 'networkFailure', reason: type.name);
          expect(network.retryable, isTrue, reason: type.name);
          expect(scenario.expired, isEmpty, reason: type.name);
          actualCodes[type] = network.errorCode;
        }
        expect(actualCodes, expectedCodes);
      });

      test('合法 JSON 中的 Access Deny 歌名和歌手不会被识别为访问拒绝', () async {
        final scenario = _Scenario(source);
        await scenario.restore();
        final song = scenario.song(1);
        if (source == PlatformType.netease) {
          song['name'] = 'Access Deny';
          song['ar'] = [
            {'id': 1, 'name': 'Access Deny 乐队'},
          ];
        } else {
          song['ori_audio_name'] = 'Access Deny';
          song['author_name'] = 'Access Deny 乐队';
        }
        scenario.transport.reply = (_, _) => _json(scenario.success([song]));

        final result = await scenario.platform
            .getPersonalDailyRecommendations();

        expect(result.status.name, 'success');
        expect(result.songs.single.name, 'Access Deny');
        expect(result.songs.single.artistNames, 'Access Deny 乐队');

        scenario.transport.reply = (_, _) =>
            ResponseBody.fromString('Access Deny ! No Actions !', 200);
        final denied = await scenario.platform
            .getPersonalDailyRecommendations();
        expect(denied.status.name, 'serviceUnavailable');
        expect(denied.songs, isEmpty);
        expect(scenario.expired, isEmpty);
      });

      test('个人请求的403不广播退出，旧请求403继续广播', () async {
        final scenario = _Scenario(source);
        await scenario.restore();
        scenario.transport.reply = (_, _) =>
            ResponseBody.fromString('Access Deny ! No Actions !', 403);
        expect(
          (await scenario.platform.getPersonalDailyRecommendations())
              .status
              .name,
          'serviceUnavailable',
        );
        expect(scenario.expired, isEmpty);
        expect(scenario.platform.isLoggedIn, isTrue);
        await expectLater(
          scenario.legacyRequest(),
          throwsA(isA<DioException>()),
        );
        expect(scenario.expired, [source]);
      });

      test('换账号后的迟到401不会让旧请求退出新账号', () async {
        final scenario = _Scenario(source);
        await scenario.restore();
        final started = Completer<void>();
        final reply = Completer<ResponseBody>();
        scenario.transport.reply = (_, _) {
          started.complete();
          return reply.future;
        };
        final pending = scenario.platform.getPersonalDailyRecommendations();
        await _waitForRequest(started, pending);
        await scenario.restore(id: '9002');
        reply.complete(_json({'code': 401}, code: 401));
        final stale = await pending;
        expect(stale.status.name, 'sessionChanged');
        expect(stale.songs, isEmpty);
        expect(scenario.expired, isEmpty);
        expect((await scenario.platform.getUserInfo())?.id, '9002');
      });

      test('明确的401返回会话过期，给当前界面重新连接提示', () async {
        final scenario = _Scenario(source);
        await scenario.restore();
        scenario.transport.reply = (_, _) => _json({'code': 401}, code: 401);
        expect(
          (await scenario.platform.getPersonalDailyRecommendations())
              .status
              .name,
          'sessionExpired',
        );
        expect(scenario.expired, isEmpty);
      });

      test('同一账号凭证轮换后作废旧请求，即使凭证又换回原值', () async {
        final scenario = _Scenario(source);
        await scenario.restore();
        final started = Completer<void>();
        final reply = Completer<ResponseBody>();
        scenario.transport.reply = (_, _) {
          started.complete();
          return reply.future;
        };
        final pending = scenario.platform.getPersonalDailyRecommendations();
        await _waitForRequest(started, pending);
        scenario.changeCredential('fake-other');
        scenario.changeCredential('fake-9001');
        reply.complete(_json(scenario.success([scenario.song(1)])));

        final stale = await pending;
        expect(stale.status.name, 'sessionChanged');
        expect(stale.songs, isEmpty);
      });
    });
  }

  test('网易请求使用当前 MUSIC_U，迟到 Set-Cookie 不污染新账号', () async {
    final scenario = _Scenario(PlatformType.netease);
    await scenario.restore();
    final started = Completer<void>();
    final reply = Completer<ResponseBody>();
    scenario.transport.reply = (request, _) {
      expect(request.uri.path, '/api/v3/discovery/recommend/songs');
      expect(request.method, 'GET');
      expect(request.headers['cookie'], contains('MUSIC_U=fake-9001'));
      started.complete();
      return reply.future;
    };
    final pending = scenario.platform.getPersonalDailyRecommendations();
    await _waitForRequest(started, pending);
    await scenario.platform.logout();
    await scenario.restore(id: '9002');
    reply.complete(
      _json(
        scenario.success([scenario.song(1)]),
        headers: {
          'set-cookie': ['MUSIC_U=fake-late; Path=/'],
        },
      ),
    );
    final stale = await pending;
    expect(stale.status.name, 'sessionChanged');
    expect(stale.songs, isEmpty);
    expect(scenario.netease?.cookie, contains('MUSIC_U=fake-9002'));
    expect(scenario.netease?.cookie, isNot(contains('fake-late')));
  });

  test('网易先用同一个 MUSIC_U 验证归属，资料不符时不请求曲目', () async {
    final scenario = _Scenario(PlatformType.netease);
    await scenario.restore();
    scenario.transport.profileOwner = '9002';
    final result = await scenario.platform.getPersonalDailyRecommendations();
    expect(result.status.name, 'identityIncomplete');
    expect(scenario.transport.dailyRequests, isEmpty);
    final request = scenario.transport.requests.single;
    expect(request.uri.path, '/api/nuser/account/get');
    expect(request.headers['cookie'], contains('MUSIC_U=fake-9001'));
  });

  group('酷狗个人协议', () {
    test('旧 token 单独恢复后再保存，不会给其他账号继承日推身份', () async {
      final legacy = _Scenario(PlatformType.kugou);
      final storage = _MemorySessionStorage(
        user: const User(
          id: '9001',
          nickname: '测试用户',
          platform: PlatformType.kugou,
        ),
        cookie: 'fake-9002',
      );
      legacy.kugou!.setSessionFields(dfid: 'fake-dfid', mid: 'fake-mid');
      await legacy.platform.restoreSession(storage);
      expect(legacy.kugou!.userid, '9001');
      await legacy.platform.saveSession(storage);
      expect(jsonDecode(storage.cookie)['userid'], '9001');

      final fresh = _Scenario(PlatformType.kugou);
      await fresh.platform.restoreSession(storage);
      fresh.transport.profileOwner = '9002';

      final result = await fresh.platform.getPersonalDailyRecommendations();

      expect(result.status.name, 'identityIncomplete');
      expect(result.songs, isEmpty);
      expect(fresh.expired, isEmpty);
      expect(fresh.transport.dailyRequests, isEmpty);
      final identityRequest = fresh.transport.requests.single;
      expect(identityRequest.uri.host, 'wwwapi.kugou.com');
      expect(identityRequest.uri.path, '/uc/userinfo');
      expect(identityRequest.queryParameters['token'], 'fake-9002');
    });

    test('酷狗身份查询失败时不发送日推请求或清除会话', () async {
      final scenario = _Scenario(PlatformType.kugou);
      await scenario.restore();
      scenario.transport.profileResponse = ResponseBody.fromString(
        'Access Deny ! No Actions !',
        403,
      );

      final result = await scenario.platform.getPersonalDailyRecommendations();

      expect(result.status.name, 'serviceUnavailable');
      expect(scenario.expired, isEmpty);
      expect(scenario.platform.isLoggedIn, isTrue);
      expect(scenario.transport.dailyRequests, isEmpty);
      expect(scenario.transport.requests, hasLength(1));
    });

    for (final client in ['android', 'lite']) {
      test('$client 按匹配客户端签名并发送准确的 JSON 字节', () async {
        final scenario = _Scenario(PlatformType.kugou);
        await scenario.restore(client: client);
        scenario.transport.reply = (request, body) {
          expect(
            request.uri.toString(),
            startsWith('https://gateway.kugou.com/everyday_song_recommend?'),
          );
          expect(request.method, 'POST');
          expect(request.headers['x-router'], 'everydayrec.service.kugou.com');
          expect(request.headers['dfid'], 'fake-dfid');
          expect(request.headers['mid'], 'fake-mid');
          expect(body, '{"platform":"android","userid":"9001"}');
          expect(request.queryParameters['userid'], '9001');
          expect(request.queryParameters['token'], 'fake-9001');
          expect(
            request.queryParameters['appid'],
            client == 'lite' ? 3116 : 1005,
          );
          expect(
            request.queryParameters['clientver'],
            client == 'lite' ? 11440 : 20489,
          );
          expect(
            request.queryParameters['signature'],
            matches(RegExp(r'^[a-f0-9]{32}$')),
          );
          return _json(scenario.success([scenario.song(1)]));
        };
        final result = await scenario.platform
            .getPersonalDailyRecommendations();
        expect(result.status.name, 'success');
        expect(result.songs.single.coverUrl, 'https://example.invalid/480.jpg');
      });
    }

    test('凭证用户ID不符、缺失或设备字段空缺时不发请求', () async {
      for (final expected in ['9002', '', '9001']) {
        final scenario = _Scenario(PlatformType.kugou);
        await scenario.restore(
          credentialId: expected,
          deviceComplete: expected != '9001',
        );
        expect(
          (await scenario.platform.getPersonalDailyRecommendations())
              .status
              .name,
          'identityIncomplete',
        );
        expect(scenario.transport.requests, isEmpty);
      }
    });

    test('20028或SSA要求平台验证，WAF拒绝保持服务不可用', () async {
      final scenario = _Scenario(PlatformType.kugou);
      await scenario.restore();
      for (final response in [
        _json({'status': 0, 'error_code': 20028}),
        _json(
          {'status': 0, 'error_code': 22222},
          code: 403,
          headers: {
            'ssa-code': ['required'],
          },
        ),
        _json(
          scenario.success([scenario.song(1)]),
          headers: {
            'ssa-code': ['required'],
          },
        ),
      ]) {
        scenario.transport.reply = (_, _) => response;
        final result = await scenario.platform
            .getPersonalDailyRecommendations();
        expect(result.status.name, 'verificationRequired');
        expect(result.retryable, isFalse);
        expect(result.songs, isEmpty);
      }
      scenario.transport.reply = (_, _) =>
          ResponseBody.fromString('Access Deny ! No Actions !', 200);
      final denied = await scenario.platform.getPersonalDailyRecommendations();
      expect(denied.status.name, 'serviceUnavailable');
      expect(scenario.transport.dailyRequests, hasLength(4));
      expect(scenario.expired, isEmpty);
    });
  });
}

Future<void> _waitForRequest(
  Completer<void> started,
  Future<Object> result,
) async {
  await Future.any([started.future, result.then<void>((_) {})]);
  expect(started.isCompleted, isTrue, reason: '个人请求应抵达运输层');
}

class _Scenario {
  _Scenario(this.source) {
    final dio = createPlatformDio(
      platform: source,
      baseUrl: 'https://music.163.com',
      onSessionExpired: expired.add,
      maxRetries: 0,
    )..httpClientAdapter = transport;
    if (source == PlatformType.netease) {
      final api = NeteaseApi(dio: dio);
      netease = api;
      platform = NeteasePlatform(api: api);
    } else {
      final api = KugouApi(dio: dio);
      kugou = api;
      platform = KugouPlatform(api: api);
    }
  }

  final PlatformType source;
  final _ScriptedTransport transport = _ScriptedTransport();
  final expired = <PlatformType>[];
  NeteaseApi? netease;
  KugouApi? kugou;
  late final MusicPlatform platform;

  Future<void> restore({
    String id = '9001',
    bool complete = true,
    String client = 'android',
    String? credentialId,
    bool deviceComplete = true,
  }) => platform.restoreSession(
    _MemorySessionStorage(
      user: User(id: id, nickname: '测试用户', platform: source),
      cookie: !complete
          ? ''
          : source == PlatformType.netease
          ? 'MUSIC_U=fake-$id'
          : jsonEncode({
              'userid': credentialId ?? id,
              'token': 'fake-$id',
              'client': client,
              if (deviceComplete) 'dfid': 'fake-dfid',
              'mid': 'fake-mid',
              'uuid': 'fake-uuid',
            }),
    ),
  );

  Future<Object> legacyRequest() =>
      netease?.getRecommendSongs() ?? kugou!.getRecommend();

  void changeCredential(String credential) {
    if (netease case final api?) {
      api.setCookie('MUSIC_U=$credential');
    } else {
      kugou!.setSessionFields(token: credential, userid: '9001');
    }
  }

  String songId(int id) => source == PlatformType.netease
      ? '$id'
      : id.toRadixString(16).padLeft(32, '0');

  Map<String, Object> song(int id, {bool duplicate = false}) {
    final name = duplicate ? '重复曲目' : '歌曲 $id';
    if (source == PlatformType.netease) {
      return {
        'id': id,
        'name': name,
        'ar': [
          {'id': id, 'name': '歌手 $id'},
        ],
        'dt': 90000,
      };
    }
    return {
      'hash': duplicate ? songId(id).toUpperCase() : songId(id),
      'ori_audio_name': name,
      'author_name': '歌手 $id',
      'sizable_cover': 'https://example.invalid/{size}.jpg',
    };
  }

  Map<String, Object> success(List<Object?> songs) =>
      source == PlatformType.netease
      ? {
          'code': 200,
          'data': {'dailySongs': songs},
        }
      : {
          'status': 1,
          'error_code': 0,
          'data': {'song_list': songs},
        };
}

ResponseBody _json(
  Map<String, Object> data, {
  int code = 200,
  Map<String, List<String>> headers = const {},
}) => ResponseBody.fromString(
  jsonEncode(data),
  code,
  headers: {
    'content-type': ['application/json'],
    ...headers,
  },
);

class _ScriptedTransport implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  Iterable<RequestOptions> get dailyRequests => requests.where(
    (request) => !const [
      '/api/nuser/account/get',
      '/uc/userinfo',
    ].contains(request.uri.path),
  );
  String? profileOwner;
  ResponseBody? profileResponse;
  late FutureOr<ResponseBody> Function(RequestOptions, String) reply;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (options.uri.path == '/api/nuser/account/get') {
      final cookie = options.headers['cookie'] as String? ?? '';
      final id =
          profileOwner ??
          RegExp(r'MUSIC_U=fake-(\d+)').firstMatch(cookie)?.group(1);
      return _json({
        'code': 200,
        'profile': {'userId': id},
        'account': {'id': id},
      });
    }
    if (options.uri.path == '/uc/userinfo') {
      final token = options.queryParameters['token']?.toString() ?? '';
      final id =
          profileOwner ?? RegExp(r'^fake-(\d+)$').firstMatch(token)?.group(1);
      return profileResponse ??
          _json({
            'status': 1,
            'data': {'userid': id},
          });
    }
    final body = requestStream == null
        ? ''
        : await utf8.decoder.bind(requestStream).join();
    return reply(options, body);
  }

  @override
  void close({bool force = false}) {}
}

class _MemorySessionStorage extends SessionStorage {
  _MemorySessionStorage({required this.user, required this.cookie});

  User user;
  String cookie;

  @override
  Future<User?> loadUser(PlatformType platform) async => user;

  @override
  Future<String?> loadCookie(PlatformType platform) async => cookie;

  @override
  Future<void> saveCookie(PlatformType platform, String cookie) async {
    this.cookie = cookie;
  }

  @override
  Future<void> saveUser(PlatformType platform, User user) async {
    this.user = user;
  }
}

import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/video_app/custom_source/custom_source_models.dart';
import 'package:mconnect/video_app/lx_source/lx_runtime.dart';
import 'package:mconnect/video_app/lx_source/lx_runtime_v3.dart';
import 'package:mconnect/video_app/lx_source/lx_source.dart';
import 'package:mconnect/video_app/multi_source/quick_source_transport.dart';

void main() {
  test('酷狗详情接口临时失败仍允许只依赖原hash的音源取流', () async {
    final sandbox = _Sandbox();
    final engine = LxSourceRuntimeV3(
      sandbox: sandbox,
      vendors: '',
      kugouInfo: (_, _) async => throw StateError('详情暂不可用'),
    );
    final config = LxSourceConfig(
      name: '源',
      version: '1',
      origin: Uri.parse('https://example.com/a.js'),
      script: 'fixture',
      sha256: 'hash',
      sources: const {
        'kg': ['128k'],
      },
    );
    final url = await engine.resolve(
      config,
      const CustomSourceRequest(
        requestId: 'r',
        platform: PlatformType.kugou,
        song: Song(
          id: 'original-hash',
          platform: PlatformType.kugou,
          name: '歌',
          artists: [],
        ),
        quality: AudioLevel.low,
        purpose: CustomSourcePurpose.play,
      ),
    );
    expect(url, 'https://media.example/song.flac');
    final music = (sandbox.request!['info'] as Map)['musicInfo'] as Map;
    expect(music['hash'], 'original-hash');
    expect(music.containsKey('songmid'), isFalse);
  });
  for (final platform in [PlatformType.qq, PlatformType.kugou]) {
    for (final metadataFailure in ['503', 'DNS']) {
      test(
        '快速取流中${platform.displayName}详情$metadataFailure仍允许原ID音源取流',
        () async {
          final source = platform == PlatformType.qq ? 'tx' : 'kg';
          final songId = platform == PlatformType.qq
              ? 'original-mid'
              : 'original-hash';
          final sandbox = _Sandbox(platform: source);
          var metadataRequests = 0;
          final dio = Dio()
            ..httpClientAdapter = _Adapter((options, _) async {
              metadataRequests++;
              if (metadataFailure == 'DNS') {
                throw DioException(
                  requestOptions: options,
                  type: DioExceptionType.connectionError,
                  message: 'Failed host lookup: metadata.example',
                );
              }
              return ResponseBody.fromString('{}', 503);
            });
          QuickSourceTransport.install(dio);
          final token = CancelToken();
          addTearDown(() {
            token.cancel();
            dio.close(force: true);
          });
          Future<Map<String, dynamic>> metadata(
            String _,
            CancelToken token,
          ) async {
            await dio.get(
              'https://metadata.example/detail',
              cancelToken: token,
            );
            return {};
          }

          final engine = LxSourceRuntimeV3(
            sandbox: sandbox,
            vendors: '',
            qqInfoCancellable: platform == PlatformType.qq ? metadata : null,
            kugouInfo: platform == PlatformType.kugou ? metadata : null,
          );
          final config = LxSourceConfig(
            name: '原ID测试源',
            version: '1',
            origin: Uri.parse('https://source.example/source.js'),
            script: 'fixture',
            sha256: 'fixture',
            sources: {
              source: ['128k'],
            },
          );
          final url = await QuickSourceTransport.run(
            token,
            () => engine.resolve(
              config,
              CustomSourceRequest(
                requestId: 'quick-metadata-${platform.name}',
                platform: platform,
                song: Song(
                  id: songId,
                  platform: platform,
                  name: '歌',
                  artists: const [],
                ),
                quality: AudioLevel.low,
                purpose: CustomSourcePurpose.play,
              ),
              cancelToken: token,
            ),
            failedHosts: <String>{},
            timeout: const Duration(seconds: 2),
          );
          expect(url, 'https://media.example/song.flac');
          expect(metadataRequests, 1);
          expect(sandbox.request!['source'], source);
          final music = (sandbox.request!['info'] as Map)['musicInfo'] as Map;
          expect(
            music[platform == PlatformType.qq ? 'songmid' : 'hash'],
            songId,
          );
          expect(music.containsKey('songId'), isFalse);
          expect(sandbox.closed, isTrue);
        },
      );
    }
  }
  test('受控请求保留二进制raw且解析JSON body，不转发Cookie或跟随重定向', () async {
    final sandbox = _NetworkSandbox();
    final dio = Dio()
      ..httpClientAdapter = _Adapter((options, _) async {
        expect(options.followRedirects, isFalse);
        expect(
          options.headers.keys.map((key) => key.toLowerCase()),
          isNot(contains('cookie')),
        );
        return ResponseBody.fromString('{"ok":true}', 200);
      });
    addTearDown(() => dio.close(force: true));
    await LxSourceRuntimeV3(
      sandbox: sandbox,
      vendors: '',
      dio: dio,
    ).inspect('fixture');
    expect(sandbox.response!['body'], {'ok': true});
    expect(
      utf8.decode(base64Decode(sandbox.response!['rawBase64'])),
      '{"ok":true}',
    );
    expect(sandbox.closed, isTrue);
  });
  test('初始化429提示服务限流，取消后关闭沙箱并撤销网络请求', () async {
    final sandbox = _NetworkSandbox(failAfterResponse: true);
    final dio = Dio()
      ..httpClientAdapter = _Adapter(
        (_, _) async => ResponseBody.fromString('{}', 429),
      );
    addTearDown(() => dio.close(force: true));
    await expectLater(
      LxSourceRuntimeV3(
        sandbox: sandbox,
        vendors: '',
        dio: dio,
      ).inspect('fixture'),
      throwsA(
        isA<LxSourceException>().having(
          (error) => error.code,
          '错误分类',
          'rateLimited',
        ),
      ),
    );
    final waiting = Completer<void>();
    final aborted = Completer<void>();
    final pendingDio = Dio()
      ..httpClientAdapter = _Adapter((_, cancel) async {
        waiting.complete();
        await cancel;
        aborted.complete();
        return ResponseBody.fromString('{}', 200);
      });
    addTearDown(() => pendingDio.close(force: true));
    final pendingSandbox = _NetworkSandbox();
    final token = CancelToken();
    final result = LxSourceRuntimeV3(
      sandbox: pendingSandbox,
      vendors: '',
      dio: pendingDio,
    ).inspect('fixture', cancelToken: token);
    final assertion = expectLater(
      result,
      throwsA(
        isA<LxSourceException>().having(
          (error) => error.code,
          '错误分类',
          'cancelled',
        ),
      ),
    );
    await waiting.future;
    token.cancel();
    await assertion;
    await aborted.future;
    expect(pendingSandbox.closed, isTrue);
    expect(pendingSandbox.response, isNull);
  });
  test('只声明酷狗的音源可初始化，只有musicUrl和已知档位进入能力表', () async {
    final sandbox = _Sandbox();
    final engine = LxSourceRuntimeV3(sandbox: sandbox, vendors: '');
    expect(await engine.inspect('fixture'), {
      'kg': ['128k', 'flac'],
    });
    expect(sandbox.closed, isTrue);
  });

  test('酷狗取流保留原hash，不伪造QQ数字ID或高档hash', () async {
    final sandbox = _Sandbox();
    final engine = LxSourceRuntimeV3(sandbox: sandbox, vendors: '');
    final url = await engine.resolve(
      LxSourceConfig(
        name: '酷狗测试源',
        version: '1',
        origin: Uri.parse('https://example.com/source.js'),
        script: 'fixture',
        sha256: 'fixture',
        sources: const {
          'kg': ['128k', 'flac'],
        },
      ),
      const CustomSourceRequest(
        requestId: 'fixture',
        platform: PlatformType.kugou,
        song: Song(
          id: 'real-kugou-hash',
          platform: PlatformType.kugou,
          name: '歌',
          artists: [],
        ),
        quality: AudioLevel.lossless,
        purpose: CustomSourcePurpose.play,
      ),
    );
    expect(url, 'https://media.example/song.flac');
    expect(sandbox.request!['source'], 'kg');
    final music = (sandbox.request!['info'] as Map)['musicInfo'] as Map;
    expect(music['hash'], 'real-kugou-hash');
    expect(music.containsKey('songId'), isFalse);
    expect(music.containsKey('sqhash'), isFalse);
    expect(sandbox.closed, isTrue);
  });
}

class _NetworkSandbox implements LxSandbox {
  _NetworkSandbox({this.failAfterResponse = false});
  final bool failAfterResponse;
  bool queued = false, closed = false;
  Map<String, dynamic>? response;
  @override
  Future<void> create(String id) async {}
  @override
  Future<void> close(String id) async {
    closed = true;
  }

  @override
  Future<String> evaluate(String id, String code) async {
    if (code.startsWith('__lxHost.response(1,')) {
      response = jsonDecode(code.substring(20, code.indexOf(');')));
    }
    if (code == '__lxHost.drain()') {
      final queue = queued
          ? []
          : [
              {
                'id': 1,
                'url': 'https://source.example/init',
                'options': {
                  'headers': {'Cookie': 'must-not-forward'},
                },
              },
            ];
      queued = true;
      return jsonEncode({
        'ready': response != null,
        'queue': queue,
        if (response != null && failAfterResponse) 'error': 'fixture failure',
        'sources': {
          'kg': {
            'type': 'music',
            'actions': ['musicUrl'],
            'qualitys': ['128k'],
          },
        },
      });
    }
    return '';
  }
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handle);
  final Future<ResponseBody> Function(RequestOptions, Future<void>?) handle;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => handle(options, cancelFuture);
  @override
  void close({bool force = false}) {}
}

class _Sandbox implements LxSandbox {
  _Sandbox({this.platform = 'kg'});
  final String platform;
  bool closed = false;
  Map<String, dynamic>? request;
  @override
  Future<void> create(String id) async {}
  @override
  Future<void> close(String id) async {
    closed = true;
  }

  @override
  Future<String> evaluate(String id, String code) async {
    if (code.startsWith('__lxHost.resolve(')) {
      request = jsonDecode(code.substring(17, code.indexOf(');')));
    }
    if (code == '__lxHost.drain()') {
      return jsonEncode({
        'ready': true,
        'sources': {
          platform: {
            'type': 'music',
            'actions': ['musicUrl'],
            'qualitys': ['128k', 'flac', 'unknown', 'flac'],
          },
          'wy': {
            'type': 'music',
            'actions': ['lyric'],
            'qualitys': ['128k'],
          },
        },
        'queue': [],
        'done': request != null,
        'result': 'https://media.example/song.flac',
      });
    }
    return '';
  }
}

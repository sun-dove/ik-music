import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/video_app/custom_source/custom_source_models.dart';
import 'package:mconnect/video_app/lx_source/lx_source.dart';
import 'package:mconnect/video_app/lx_source/lx_importer_v3.dart';

const _script = '\uFEFF// @name 新版音源\n// @version 3\nlx.send("inited", {});';

void main() {
  for (final first in [503, 200]) {
    test('Raw返回${first == 200 ? 'HTML' : 'HTTP503'}时尝试同文件备用线路，保留原链接', () async {
      final visited = <Uri>[];
      final engine = _Engine();
      final dio = Dio()
        ..httpClientAdapter = _Adapter((options, _) async {
          visited.add(options.uri);
          expect(options.followRedirects, isFalse);
          return options.uri.host == 'raw.githubusercontent.com'
              ? ResponseBody.fromString(
                  '<html>upstream unavailable</html>',
                  first,
                )
              : ResponseBody.fromString(_script, 200);
        });
      addTearDown(() => dio.close(force: true));
      final config = await LxSourceImporterV3(
        dio: dio,
        engine: engine,
      ).importLink('https://github.com/a/b/blob/main/kg.js');
      expect(visited.map((uri) => uri.host), [
        'raw.githubusercontent.com',
        'fastly.jsdelivr.net',
      ]);
      expect(
        config.origin.toString(),
        'https://raw.githubusercontent.com/a/b/main/kg.js',
      );
      expect(config.name, '新版音源');
      expect(config.sources, {
        'kg': ['flac'],
      });
      expect(config.sha256, hasLength(64));
      expect(config.enabled, isFalse);
      expect(config.allowForDownloads, isFalse);
    });
  }
  test('仅支持酷我的脚本说明平台不支持，不能提示导入成功', () async {
    final dio = Dio()
      ..httpClientAdapter = _Adapter(
        (_, _) async => ResponseBody.fromString(_script, 200),
      );
    addTearDown(() => dio.close(force: true));
    await expectLater(
      LxSourceImporterV3(
        dio: dio,
        engine: _Engine(other: true),
      ).importLink('https://example.com/kw.js'),
      throwsA(
        isA<LxSourceException>().having(
          (error) => error.code,
          '错误类别',
          'platform',
        ),
      ),
    );
  });
  test('取消下载后不能继续尝试备用线路或初始化脚本', () async {
    final started = Completer<void>();
    var calls = 0;
    final engine = _Engine();
    final dio = Dio()
      ..httpClientAdapter = _Adapter((_, cancel) async {
        calls++;
        started.complete();
        await cancel;
        return ResponseBody.fromString(_script, 200);
      });
    addTearDown(() => dio.close(force: true));
    final token = CancelToken();
    final result = LxSourceImporterV3(dio: dio, engine: engine).importLink(
      'https://raw.githubusercontent.com/a/b/main/kg.js',
      cancelToken: token,
    );
    final assertion = expectLater(
      result,
      throwsA(
        isA<LxSourceException>().having(
          (error) => error.code,
          '错误类别',
          'cancelled',
        ),
      ),
    );
    await started.future;
    token.cancel();
    await assertion;
    expect(calls, 1);
    expect(engine.calls, 0);
  });
}

class _Engine implements LxSourceEngine {
  _Engine({this.other = false});
  final bool other;
  int calls = 0;
  @override
  Future<Map<String, List<String>>> inspect(
    String script, {
    CancelToken? cancelToken,
  }) async {
    calls++;
    return {
      other ? 'kw' : 'kg': ['flac'],
    };
  }

  @override
  Future<String> resolve(
    LxSourceConfig config,
    CustomSourceRequest request, {
    CancelToken? cancelToken,
  }) async => throw UnimplementedError();
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

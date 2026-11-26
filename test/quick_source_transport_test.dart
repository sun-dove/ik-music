import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/video_app/multi_source/quick_source_transport.dart';
import 'package:mconnect/video_app/multi_source/source_coordinator.dart';

void main() {
  for (final acceptedStatus in [false, true]) {
    test('快速取流允许同主机503后备用路由成功（接受状态码：$acceptedStatus）', () async {
      final paths = <String>[];
      final dio = Dio(BaseOptions(responseType: ResponseType.plain))
        ..httpClientAdapter = _Adapter((options, _) async {
          paths.add(options.uri.path);
          return options.uri.path == '/primary'
              ? ResponseBody.fromString('暂时不可用', 503)
              : ResponseBody.fromString('https://media.example/song.mp3', 200);
        });
      QuickSourceTransport.install(dio);
      final token = CancelToken();
      final failedHosts = <String>{};
      addTearDown(() {
        token.cancel();
        dio.close(force: true);
      });
      final url = await QuickSourceTransport.run(
        token,
        () async {
          try {
            final primary = await dio.get<String>(
              'https://routes.example/primary',
              options: Options(
                validateStatus: acceptedStatus ? (_) => true : null,
              ),
            );
            if (primary.statusCode == 200) return primary.data!;
          } on DioException catch (error) {
            if (error.response?.statusCode != 503) rethrow;
          }
          final fallback = await dio.get<String>(
            'https://routes.example/fallback',
          );
          return fallback.data!;
        },
        failedHosts: failedHosts,
        timeout: const Duration(seconds: 2),
      );
      expect(url, 'https://media.example/song.mp3');
      expect(paths, ['/primary', '/fallback']);
      expect(failedHosts, isEmpty);
    });
  }

  test('最终DNS不可达快速结束且同主机不重复联网', () async {
    var requests = 0;
    final dio = Dio()
      ..httpClientAdapter = _Adapter((options, _) async {
        requests++;
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          message: 'Failed host lookup: source.invalid',
        );
      });
    QuickSourceTransport.install(dio);
    final token = CancelToken();
    final failedHosts = <String>{};
    addTearDown(() {
      token.cancel();
      dio.close(force: true);
    });
    final elapsed = Stopwatch()..start();
    await expectLater(
      QuickSourceTransport.run(
        token,
        () => dio.get('https://source.invalid/song'),
        failedHosts: failedHosts,
        timeout: const Duration(seconds: 2),
      ),
      throwsA(
        isA<SourceFailure>()
            .having((failure) => failure.code, '错误分类', 'dns')
            .having((failure) => failure.sourceWide, '源级失败', isTrue),
      ),
    );
    elapsed.stop();
    expect(elapsed.elapsed, lessThan(const Duration(seconds: 1)));
    expect(failedHosts, {'source.invalid'});
    await expectLater(
      QuickSourceTransport.run(
        token,
        () => dio.get('https://source.invalid/other-quality'),
        failedHosts: failedHosts,
        timeout: const Duration(seconds: 2),
      ),
      throwsA(isA<SourceFailure>()),
    );
    expect(requests, 1);
  });

  test('快速取流取消后迟到的合法地址不能回填会话', () async {
    final requested = Completer<void>();
    final lateResponse = Completer<void>();
    final requestFinished = Completer<void>();
    final dio = Dio(BaseOptions(responseType: ResponseType.plain))
      ..httpClientAdapter = _Adapter((_, cancel) async {
        requested.complete();
        await cancel;
        await lateResponse.future;
        return ResponseBody.fromString('https://media.example/late.mp3', 200);
      });
    QuickSourceTransport.install(dio);
    const candidate = SourceCandidate(
      id: 'source',
      name: '测试源',
      quality: AudioLevel.low,
    );
    final session = SourceSession(
      candidates: const [candidate],
      resolve: (candidate, token) => QuickSourceTransport.run(
        token,
        () async {
          try {
            await dio.get('https://source.example/song');
          } on DioException catch (error) {
            if (error.type != DioExceptionType.cancel) rethrow;
            await lateResponse.future;
          } finally {
            requestFinished.complete();
          }
          return ResolvedSource(
            candidate,
            Uri.parse('https://media.example/late.mp3'),
          );
        },
        failedHosts: <String>{},
        timeout: const Duration(seconds: 2),
      ),
      budget: const Duration(seconds: 6),
      resolveTimeout: const Duration(seconds: 2),
      skipUnreachableSources: true,
    );
    addTearDown(() {
      session.cancel();
      if (!lateResponse.isCompleted) lateResponse.complete();
      dio.close(force: true);
    });
    final result = session.next();
    await requested.future;
    session.cancel();
    expect(await result, isNull);
    lateResponse.complete();
    await requestFinished.future;
    expect(session.cancelled, isTrue);
    expect(session.canContinue, isFalse);
    expect(session.attempts.single.stage, SourceStage.cancelled);
    expect(await session.next(), isNull);
  });
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

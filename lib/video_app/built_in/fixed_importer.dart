import '../../l10n/ik_source_catalog_strings.dart';

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../lx_source/lx_http.dart';
import '../lx_source/lx_source.dart';
import 'catalog.dart';

typedef IkCatalogFetch = Future<List<int>> Function(Uri, CancelToken);

/// 哈希门在执行之前；获取只使用签入目录的固定提交与同文件备用地址。
class IkFixedSourceImporter {
  IkFixedSourceImporter({required this.engine, this.fetch, Dio? dio})
    : _dio = dio ?? createLxDio();
  final LxSourceEngine engine;
  final Dio _dio;
  final IkCatalogFetch? fetch;

  Future<List<int>> _download(Uri uri, CancelToken token) async {
    final response = await _dio.getUri<ResponseBody>(
      uri,
      cancelToken: token,
      options: Options(
        responseType: ResponseType.stream,
        followRedirects: false,
        maxRedirects: 0,
        validateStatus: (_) => true,
        receiveTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 10),
      ),
    );
    if (response.statusCode != 200 || response.data == null) {
      await response.data?.stream.listen(null).cancel();
      throw LxSourceException(
        response.statusCode == 429 ? 'rateLimited' : 'download',
        IkSourceCatalogStrings.fetchStatus(response.statusCode),
      );
    }
    final bytes = <int>[];
    await for (final chunk in response.data!.stream) {
      if (token.isCancelled) {
        throw const LxSourceException(
          'cancelled',
          IkSourceCatalogStrings.cancelled,
        );
      }
      if (bytes.length + chunk.length > 1024 * 1024) {
        throw const LxSourceException(
          'size',
          IkSourceCatalogStrings.fileBudget,
        );
      }
      bytes.addAll(chunk);
    }
    return bytes;
  }

  Future<LxSourceConfig> prepare(
    IkSourceCatalog catalog,
    IkCatalogEntry entry,
    CancelToken cancelToken, {
    void Function()? onChecking,
  }) async {
    final token = CancelToken();
    if (cancelToken.isCancelled) {
      throw const LxSourceException(
        'cancelled',
        IkSourceCatalogStrings.cancelled,
      );
    }
    unawaited(cancelToken.whenCancel.then((_) => token.cancel()));
    var timedOut = false;
    final timer = Timer(const Duration(seconds: 30), () {
      timedOut = true;
      token.cancel();
    });
    try {
      List<int>? accepted;
      LxSourceException failure = const LxSourceException(
        'network',
        IkSourceCatalogStrings.networkRetry,
      );
      for (final uri in catalog.downloadUris(entry)) {
        if (token.isCancelled) {
          throw const LxSourceException(
            'cancelled',
            IkSourceCatalogStrings.cancelled,
          );
        }
        try {
          final bytes = await Future.any<List<int>>([
            (fetch ?? _download)(uri, token),
            token.whenCancel.then(
              (_) => throw const LxSourceException(
                'cancelled',
                IkSourceCatalogStrings.cancelled,
              ),
            ),
          ]);
          if (token.isCancelled) {
            throw const LxSourceException(
              'cancelled',
              IkSourceCatalogStrings.cancelled,
            );
          }
          if (bytes.length > 1024 * 1024) {
            throw const LxSourceException(
              'size',
              IkSourceCatalogStrings.fileBudget,
            );
          }
          if (bytes.length != entry.byteLength ||
              sha256.convert(bytes).toString() != entry.contentSha256) {
            failure = const LxSourceException(
              'integrity',
              IkSourceCatalogStrings.integrity,
            );
            continue;
          }
          accepted = bytes;
          break;
        } on LxSourceException catch (error) {
          if (token.isCancelled || error.code == 'size') rethrow;
          failure = error;
          if (error.code == 'rateLimited') break;
        } on DioException {
          if (token.isCancelled) rethrow;
          failure = const LxSourceException(
            'network',
            IkSourceCatalogStrings.networkUnavailable,
          );
        }
      }
      if (accepted == null) throw failure;
      timer.cancel(); // 获取最多30秒；受限初始化另沿用运行时的15秒预算。
      String script;
      try {
        script = utf8
            .decode(accepted, allowMalformed: false)
            .replaceFirst(RegExp('^\uFEFF'), '');
      } on FormatException {
        throw const LxSourceException(
          'invalidEncoding',
          IkSourceCatalogStrings.invalidEncoding,
        );
      }
      if (script.trimLeft().startsWith('<')) {
        throw const LxSourceException(
          'script',
          IkSourceCatalogStrings.notScript,
        );
      }
      onChecking?.call();
      final sources = await engine.inspect(script, cancelToken: token);
      if (token.isCancelled) {
        throw const LxSourceException(
          'cancelled',
          IkSourceCatalogStrings.cancelled,
        );
      }
      if (!sources.entries.any(
        (e) => ['tx', 'wy', 'kg'].contains(e.key) && e.value.isNotEmpty,
      )) {
        throw const LxSourceException(
          'platform',
          IkSourceCatalogStrings.supportedPlatforms,
        );
      }
      return LxSourceConfig(
        name: entry.displayName,
        version: entry.path.split('/').last.replaceFirst(RegExp(r'\.js$'), ''),
        origin: catalog.origin(entry),
        script: script,
        sha256: sha256.convert(utf8.encode(script)).toString(),
        sources: sources,
        enabled: true,
      );
    } on DioException {
      throw LxSourceException(
        timedOut ? 'timeout' : 'cancelled',
        timedOut
            ? IkSourceCatalogStrings.prepareTimeout
            : IkSourceCatalogStrings.cancelled,
      );
    } on LxSourceException {
      if (timedOut) {
        throw const LxSourceException(
          'timeout',
          IkSourceCatalogStrings.prepareTimeout,
        );
      }
      rethrow;
    } finally {
      timer.cancel();
      token.cancel();
    }
  }

  void dispose() => _dio.close(force: true);
}

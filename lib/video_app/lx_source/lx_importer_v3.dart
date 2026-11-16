import '../../l10n/expanded_strings.dart';

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../l10n/video_strings.dart';
import 'lx_source.dart';

/// 新入口接受QQ/网易/酷狗协议。下载失败尝试同文件备用线路。
class LxSourceImporterV3 {
  const LxSourceImporterV3({required this.dio, required this.engine});
  final Dio dio;
  final LxSourceEngine engine;

  Future<LxSourceConfig> importLink(
    String link, {
    CancelToken? cancelToken,
  }) async {
    final origin = lxImportUri(link);
    final token = CancelToken();
    var timedOut = false;
    if (cancelToken?.isCancelled == true) throw _cancelled;
    unawaited(cancelToken?.whenCancel.then((_) => token.cancel()));
    final timer = Timer(const Duration(seconds: 30), () {
      timedOut = true;
      token.cancel();
    });
    try {
      String? script;
      int? status;
      for (final uri in lxDownloadUris(origin)) {
        if (token.isCancelled) throw _cancelled;
        try {
          final response = await dio.getUri<ResponseBody>(
            uri,
            cancelToken: token,
            options: Options(
              responseType: ResponseType.stream,
              followRedirects: false,
              maxRedirects: 0,
              validateStatus: (_) => true,
              sendTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
            ),
          );
          status = response.statusCode;
          if (status != 200 || response.data == null) {
            await response.data?.stream.listen(null).cancel();
            continue;
          }
          final value = (await lxReadBody(
            response.data!,
            1024 * 1024,
            cancelToken: token,
          )).replaceFirst(RegExp('^\uFEFF'), '');
          if (value.trimLeft().startsWith('<')) continue;
          script = value;
          break;
        } on DioException {
          if (token.isCancelled) rethrow;
        }
      }
      if (script == null) {
        throw LxSourceException(
          'download',
          status == null
              ? VideoStrings.lxDownloadFailed
              : ExpandedStrings.downloadStatus(status),
        );
      }
      String? field(String key) =>
          RegExp('^\\s*(?:\\*|//)?\\s*@$key\\s+([^\\r\\n]+)', multiLine: true)
              .firstMatch(script!)
              ?.group(1)
              ?.replaceFirst(RegExp(r'\s*\*/\s*$'), '')
              .trim();
      final name = field('name');
      if (name == null || name.isEmpty || name.length > 160) {
        throw const LxSourceException('script', VideoStrings.lxInvalidScript);
      }
      final sources = await engine.inspect(script, cancelToken: token);
      if (!sources.entries.any(
        (entry) =>
            ['tx', 'wy', 'kg'].contains(entry.key) && entry.value.isNotEmpty,
      )) {
        throw const LxSourceException(
          'platform',
          ExpandedStrings.sourcePlatformUnsupported,
        );
      }
      return LxSourceConfig(
        name: name,
        version: field('version') ?? '',
        origin: origin,
        script: script,
        sha256: sha256.convert(utf8.encode(script)).toString(),
        sources: sources,
      );
    } on LxSourceException {
      if (timedOut) {
        throw const LxSourceException('timeout', VideoStrings.lxTimedOut);
      }
      rethrow;
    } on DioException {
      if (timedOut) {
        throw const LxSourceException('timeout', VideoStrings.lxTimedOut);
      }
      if (token.isCancelled) throw _cancelled;
      throw const LxSourceException('download', VideoStrings.lxDownloadFailed);
    } finally {
      timer.cancel();
      token.cancel();
    }
  }

  static const _cancelled = LxSourceException(
    'cancelled',
    VideoStrings.customSourceRequestCancelled,
  );
}

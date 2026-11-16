import '../../l10n/expanded_strings.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

import '../../l10n/source_strings.dart';
import '../../l10n/video_strings.dart';
import '../../models/platform_type.dart';
import '../custom_source/custom_source_models.dart';
import 'lx_bootstrap_v2.dart';
import 'lx_bootstrap_v3.dart';
import 'lx_http.dart';
import 'lx_runtime.dart';
import 'lx_source.dart';

String lxPlatformV3(PlatformType platform) =>
    platform == PlatformType.kugou ? 'kg' : lxPlatform(platform);

/// 悦音独立入口的扩展协议；旧运行时及其调用方保留原行为。
class LxSourceRuntimeV3 implements LxSourceEngine {
  LxSourceRuntimeV3({
    LxSandbox? sandbox,
    Dio? dio,
    this.vendors,
    this.qqInfo,
    this.qqInfoCancellable,
    this.kugouInfo,
    this.environment = 'mobile',
    this.timeout = const Duration(seconds: 15),
  }) : sandbox = sandbox ?? const MethodChannelLxSandbox(),
       dio = dio ?? createLxDio();

  final LxSandbox sandbox;
  final Dio dio;
  final String? vendors;
  final String environment;
  final Duration timeout;
  final Future<Map<String, dynamic>> Function(String)? qqInfo;
  final Future<Map<String, dynamic>> Function(String, CancelToken)?
  qqInfoCancellable;
  final Future<Map<String, dynamic>> Function(String, CancelToken)? kugouInfo;
  static Future<String>? _assets;
  static int _serial = 0;
  static final _random = Random.secure();

  Future<String> _vendors() => vendors != null
      ? Future.value(vendors!)
      : _assets ??= Future.wait([
          rootBundle.loadString('assets/lx-runtime/forge-1.3.1.min.js'),
          rootBundle.loadString('assets/lx-runtime/pako-2.1.0.min.js'),
        ]).then((values) => values.join('\n'));

  @override
  Future<Map<String, List<String>>> inspect(
    String script, {
    CancelToken? cancelToken,
  }) async => _sources(await _run(script, cancelToken: cancelToken));

  Map<String, List<String>> _sources(Map<String, dynamic> state) {
    final sources = state['sources'];
    if (sources is! Map) {
      throw const LxSourceException('script', VideoStrings.lxInvalidScript);
    }
    return {
      for (final key in ['tx', 'wy', 'kg'])
        if (sources[key] is Map &&
            sources[key]['type'] == 'music' &&
            sources[key]['actions'] is List &&
            (sources[key]['actions'] as List).contains('musicUrl') &&
            sources[key]['qualitys'] is List)
          key: (sources[key]['qualitys'] as List)
              .whereType<String>()
              .where(['128k', '320k', 'flac', 'flac24bit'].contains)
              .toSet()
              .toList(),
    };
  }

  @override
  Future<String> resolve(
    LxSourceConfig config,
    CustomSourceRequest request, {
    CancelToken? cancelToken,
  }) async {
    final platform = lxPlatformV3(request.platform);
    final quality = lxQuality(request.quality);
    if (!(config.sources[platform]?.contains(quality) ?? false)) {
      throw const LxSourceException(
        'quality',
        VideoStrings.customSourceQualityUnsupported,
      );
    }
    final token = cancelToken ?? CancelToken();
    final music = <String, dynamic>{
      if (request.platform != PlatformType.kugou) 'songmid': request.song.id,
      'name': request.song.name,
      'singer': request.song.artistNames,
      'albumName': request.song.album?.name ?? '',
      'source': platform,
      'interval': request.song.duration.inSeconds,
      if (request.platform == PlatformType.kugou) ...{
        'hash': request.song.id,
        'albumId': request.song.albumId ?? request.song.album?.id ?? '',
      },
    };
    if (request.platform == PlatformType.qq) {
      try {
        music.addAll(
          qqInfoCancellable != null
              ? await qqInfoCancellable!(request.song.id, token)
              : await qqInfo?.call(request.song.id) ?? {},
        );
      } catch (_) {
        // 缺详情时仍允许只需songmid的源；不伪造数字songId。
      }
    } else if (request.platform == PlatformType.kugou && kugouInfo != null) {
      try {
        music.addAll(await kugouInfo!(request.song.id, token));
      } catch (_) {
        // 详情临时不可用时保留真实hash，不补造audio_id或高音质hash。
      }
    }
    if (token.isCancelled) throw _cancelled;
    final state = await _run(
      config.script,
      request: {
        'action': 'musicUrl',
        'source': platform,
        'info': {'type': quality, 'musicInfo': music},
      },
      cancelToken: token,
    );
    final value = state['result'];
    if (value is! String || value.length > 8192) {
      throw const LxSourceException('url', SourceStrings.invalidUrl);
    }
    return value;
  }

  static const _cancelled = LxSourceException(
    'cancelled',
    SourceStrings.requestCancelled,
  );

  Future<Map<String, dynamic>> _run(
    String script, {
    Map<String, dynamic>? request,
    CancelToken? cancelToken,
  }) async {
    final id = 'lx3-${DateTime.now().microsecondsSinceEpoch}-${++_serial}';
    var finished = false;
    var resolving = false;
    var requestCount = 0;
    LxSourceException? networkFailure;
    final requests = <int, CancelToken>{};
    final info = <String, dynamic>{
      'name': 'custom',
      'version': '',
      'description': '',
      'author': '',
      'homepage': '',
      'rawScript': '',
    };
    for (final match in RegExp(
      r'^\s*(?:\*|//)?\s*@([a-zA-Z]+)\s+([^\r\n]+)',
      multiLine: true,
    ).allMatches(script)) {
      if (info.containsKey(match[1]) && match[1] != 'rawScript') {
        info[match[1]!] = match[2]!
            .replaceFirst(RegExp(r'\s*\*/\s*$'), '')
            .trim();
      }
    }
    Future<Map<String, dynamic>> execute() async {
      await sandbox.create(id);
      if (finished) return {};
      await sandbox.evaluate(
        id,
        '${lxV2Prelude(await _vendors(), List.generate(65536, (_) => _random.nextInt(256)))}\n;"prepared";',
      );
      await sandbox.evaluate(
        id,
        'globalThis.__lxScriptInfo=${jsonEncode(info)};"info";',
      );
      for (var offset = 0; offset < script.length; offset += 100000) {
        if (finished) return {};
        await sandbox.evaluate(
          id,
          '__lxScriptInfo.rawScript+=${jsonEncode(script.substring(offset, min(offset + 100000, script.length)))};"chunk";',
        );
      }
      await sandbox.evaluate(
        id,
        '${lxV3Bootstrap(environment: environment)}\n;try {\n$script\n} catch (e) { __lxHost.loadError(e); }\n;"loaded";',
      );
      while (!finished) {
        final state = jsonDecode(
          await sandbox.evaluate(id, '__lxHost.drain()'),
        ) as Map<String, dynamic>;
        if (state['error'] != null) {
          final message = '${state['error']}';
          final missing = RegExp(
            r'^(?:unsupported: |(?:ReferenceError: )?)([a-zA-Z_][a-zA-Z0-9_.]*)(?: is not defined)?$',
          ).firstMatch(message);
          if (missing != null &&
              (message.startsWith('unsupported: ') ||
                  message.endsWith(' is not defined'))) {
            throw LxSourceException(
              'script',
              VideoStrings.lxUnsupportedApi(missing[1]!),
            );
          }
          throw networkFailure ??
              LxSourceException(
                resolving ? 'resolve' : 'script',
                resolving
                    ? SourceStrings.resolveFailed
                    : VideoStrings.lxScriptFailed,
              );
        }
        if (state['ready'] == true) {
          if (request == null || (resolving && state['done'] == true)) {
            return state;
          }
          if (!resolving) {
            final qualities = _sources(state)[request['source']];
            if (!(qualities?.contains((request['info'] as Map)['type']) ??
                false)) {
              throw const LxSourceException(
                'quality',
                VideoStrings.customSourceQualityUnsupported,
              );
            }
            await sandbox.evaluate(
              id,
              '__lxHost.resolve(${jsonEncode(request)});"requested";',
            );
            resolving = true;
          }
        }
        final queue = state['queue'];
        if (queue is List) {
          for (final raw in queue) {
            if (raw is! Map || raw['id'] is! int) continue;
            final jobId = raw['id'] as int;
            if (raw['cancel'] == true) {
              requests.remove(jobId)?.cancel();
              continue;
            }
            if (++requestCount > 32 || requests.length >= 4) {
              throw const LxSourceException(
                'script',
                VideoStrings.lxRequestLimit,
              );
            }
            final token = CancelToken();
            requests[jobId] = token;
            unawaited(() async {
              final response = await _http(
                Map<String, dynamic>.from(raw),
                token,
              );
              if (finished || requests[jobId] != token || token.isCancelled) {
                return;
              }
              final status = response['statusCode'];
              if (status == 429) {
                networkFailure = const LxSourceException(
                  'rateLimited',
                  ExpandedStrings.sourceRateLimited,
                );
              } else if (response['error'] == 'https_required') {
                networkFailure = const LxSourceException(
                  'network',
                  ExpandedStrings.sourceHttpUnsupported,
                );
              } else if (response['error'] != null) {
                networkFailure = const LxSourceException(
                  'network',
                  ExpandedStrings.sourceNetworkFailed,
                );
              }
              requests.remove(jobId);
              try {
                await sandbox.evaluate(
                  id,
                  '__lxHost.response($jobId,${jsonEncode(response)});"received";',
                );
              } catch (_) {
                if (!finished) {
                  networkFailure = const LxSourceException(
                    'script',
                    VideoStrings.lxScriptFailed,
                  );
                }
              }
            }());
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      return {};
    }

    try {
      if (cancelToken?.isCancelled == true) throw _cancelled;
      return await Future.any<Map<String, dynamic>>([
        execute(),
        if (cancelToken != null)
          cancelToken.whenCancel.then((_) => throw _cancelled),
      ]).timeout(timeout);
    } on LxSourceException {
      rethrow;
    } on TimeoutException {
      throw networkFailure ??
          const LxSourceException('timeout', VideoStrings.lxTimedOut);
    } on MissingPluginException {
      throw const LxSourceException(
        'unsupported',
        VideoStrings.lxDeviceUnsupported,
      );
    } on PlatformException catch (error) {
      throw LxSourceException(
        error.code == 'unsupported' ? 'unsupported' : 'script',
        error.code == 'unsupported'
            ? VideoStrings.lxDeviceUnsupported
            : VideoStrings.lxScriptFailed,
      );
    } catch (_) {
      throw const LxSourceException('script', VideoStrings.lxScriptFailed);
    } finally {
      finished = true;
      for (final token in requests.values) {
        token.cancel();
      }
      try {
        await sandbox.close(id);
      } catch (_) {}
    }
  }

  Future<Map<String, dynamic>> _http(
    Map<String, dynamic> job,
    CancelToken token,
  ) async {
    try {
      final rawUri = Uri.tryParse('${job['url']}');
      if (rawUri?.scheme == 'http') return {'error': 'https_required'};
      final uri = lxImportUri('${job['url']}');
      final options = job['options'] is Map
          ? Map<String, dynamic>.from(job['options'] as Map)
          : <String, dynamic>{};
      final method = '${options['method'] ?? 'GET'}'.toUpperCase();
      if (!['GET', 'POST', 'HEAD'].contains(method) ||
          options.containsKey('formData')) {
        return {'error': 'unsupported_request'};
      }
      final headers = options['headers'] is Map
          ? Map<String, dynamic>.from(options['headers'] as Map)
          : <String, dynamic>{};
      headers.removeWhere(
        (key, _) => [
          'host',
          'cookie',
          'connection',
          'content-length',
        ].contains(key.toLowerCase()),
      );
      final form = options['form'];
      final data = form is Map
          ? form.entries
                .map(
                  (e) =>
                      '${Uri.encodeQueryComponent('${e.key}')}=${Uri.encodeQueryComponent('${e.value}')}',
                )
                .join('&')
          : options['body'];
      if (utf8.encode(jsonEncode(data)).length > 65536) {
        return {'error': 'request_size'};
      }
      final milliseconds = options['timeout'] is num
          ? (options['timeout'] as num).toInt().clamp(1, 10000)
          : 10000;
      final response = await dio.requestUri<ResponseBody>(
        uri,
        data: data,
        cancelToken: token,
        options: Options(
          method: method,
          headers: headers,
          contentType: form is Map ? Headers.formUrlEncodedContentType : null,
          responseType: ResponseType.stream,
          followRedirects: false,
          maxRedirects: 0,
          validateStatus: (_) => true,
          sendTimeout: Duration(milliseconds: milliseconds),
          receiveTimeout: Duration(milliseconds: milliseconds),
        ),
      );
      final bytes = <int>[];
      await for (final chunk in response.data!.stream) {
        if (token.isCancelled) return {'error': 'cancelled'};
        if (bytes.length + chunk.length > 512 * 1024) {
          return {'error': 'response_size'};
        }
        bytes.addAll(chunk);
      }
      final raw = utf8.decode(bytes, allowMalformed: true);
      Object? body = raw;
      try {
        body = jsonDecode(raw);
      } catch (_) {}
      return {
        'statusCode': response.statusCode,
        'statusMessage': response.statusMessage ?? '',
        'headers': response.headers.map.map(
          (key, value) => MapEntry(key, value.join(', ')),
        ),
        'rawBase64': base64Encode(bytes),
        'body': body,
        'bytes': bytes.length,
      };
    } catch (_) {
      return {'error': 'request_failed'};
    }
  }
}

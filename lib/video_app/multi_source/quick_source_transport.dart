import 'dart:async';

import 'package:dio/dio.dart';

import '../../l10n/source_strings.dart';
import '../../l10n/ik_source_recovery_strings.dart';
import 'source_coordinator.dart';

/// 只约束 quick 播放候选所在调用链，不更改共享 Dio 的账号与下载请求。
abstract final class QuickSourceTransport {
  static final _scopeKey = Object();
  static const _requestScopeKey = 'ik.quickSourceScope';

  static void install(Dio dio) {
    if (dio.interceptors.any((item) => item is _QuickSourceInterceptor)) return;
    dio.interceptors.insert(0, _QuickSourceInterceptor());
  }

  static Future<T> run<T>(
    CancelToken token,
    Future<T> Function() request, {
    required Set<String> failedHosts,
    Duration timeout = const Duration(seconds: 3),
  }) {
    final scope = _QuickSourceScope(token, failedHosts, timeout);
    return runZoned(
      () => Future.any<T>([request(), scope.failure.future]),
      zoneValues: {_scopeKey: scope},
    );
  }
}

class _QuickSourceScope {
  _QuickSourceScope(this.token, this.failedHosts, Duration timeout)
    : deadline = DateTime.now().add(timeout);
  final CancelToken token;
  final Set<String> failedHosts;
  final activeHosts = <String>{};
  final failure = Completer<Never>();
  final DateTime deadline;
}

class _QuickSourceInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final scope = Zone.current[QuickSourceTransport._scopeKey];
    if (scope is! _QuickSourceScope) {
      handler.next(options);
      return;
    }
    final remaining = scope.deadline.difference(DateTime.now());
    if (scope.token.isCancelled || remaining <= Duration.zero) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
          message: SourceStrings.oldRequestCancelled,
        ),
      );
      return;
    }
    if (scope.failedHosts.contains(options.uri.host.toLowerCase())) {
      if (!scope.failure.isCompleted) {
        scope.failure.completeError(
          const SourceFailure(
            'network',
            SourceStrings.sourceUnavailable,
            sourceWide: true,
          ),
        );
      }
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          message: SourceStrings.sourceUnavailable,
        ),
      );
      return;
    }
    final existingToken = options.cancelToken;
    if (existingToken != null && existingToken != scope.token) {
      unawaited(
        scope.token.whenCancel.then((_) => existingToken.cancel()),
      );
    } else {
      options.cancelToken = scope.token;
    }
    Duration limit(Duration? current) =>
        current != null && current > Duration.zero && current < remaining
        ? current
        : remaining;
    options.connectTimeout = limit(options.connectTimeout);
    options.sendTimeout = limit(options.sendTimeout);
    options.receiveTimeout = limit(options.receiveTimeout);
    options.extra[QuickSourceTransport._requestScopeKey] = scope;
    final host = options.uri.host.toLowerCase();
    scope.activeHosts.add(host);
    unawaited(
      scope.token.whenCancel.then((_) {
        if (scope.activeHosts.contains(host) &&
            !DateTime.now().isBefore(scope.deadline)) {
          scope.failedHosts.add(host);
        }
      }),
    );
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final scope = response.requestOptions.extra[
      QuickSourceTransport._requestScopeKey
    ];
    if (scope is _QuickSourceScope) {
      final host = response.requestOptions.uri.host.toLowerCase();
      scope.activeHosts.remove(host);
      if (!scope.token.isCancelled && (response.statusCode ?? 0) >= 500) {
        scope.failedHosts.add(host);
        if (!scope.failure.isCompleted) {
          scope.failure.completeError(
            const SourceFailure(
              'serverError',
              IkSourceRecoveryStrings.connectionFailed,
              sourceWide: true,
            ),
          );
        }
      }
    }
    handler.next(response);
  }

  @override
  void onError(DioException error, ErrorInterceptorHandler handler) {
    final scope = error.requestOptions.extra[
      QuickSourceTransport._requestScopeKey
    ];
    final unreachable = switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.connectionError ||
      DioExceptionType.badCertificate => true,
      DioExceptionType.badResponse =>
        (error.response?.statusCode ?? 0) >= 500,
      _ => false,
    };
    if (scope is _QuickSourceScope) {
      scope.activeHosts.remove(error.requestOptions.uri.host.toLowerCase());
    }
    if (scope is _QuickSourceScope &&
        !scope.token.isCancelled &&
        unreachable) {
      scope.failedHosts.add(error.requestOptions.uri.host.toLowerCase());
      final text = '${error.message ?? ''} ${error.error ?? ''}'.toLowerCase();
      final dns = [
        'failed host lookup',
        'no such host',
        'name or service not known',
        'nodename nor servname',
        'failed to resolve',
        'could not resolve',
      ].any(text.contains);
      if (!scope.failure.isCompleted) {
        scope.failure.completeError(
          SourceFailure(
            dns ? 'dns' : 'network',
            dns
                ? IkSourceRecoveryStrings.dnsFailed
                : IkSourceRecoveryStrings.connectionFailed,
            sourceWide: true,
          ),
          error.stackTrace,
        );
      }
      // 明确不可达不再交给共享 RetryInterceptor 叠加重试和退避。
      handler.reject(error);
      return;
    }
    handler.next(error);
  }
}

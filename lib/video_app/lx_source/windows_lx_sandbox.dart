import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../l10n/expanded_strings.dart';
import 'lx_runtime.dart';
import 'lx_source.dart';

/// 独立WebView2进程；仅传代码与JSON，不继承账号环境或宿主对象。
class WindowsLxSandbox implements LxSandbox {
  WindowsLxSandbox({
    String? hostPath,
    this.evaluationTimeout = const Duration(seconds: 12),
    this.diagnostics,
  }) : hostPath =
           hostPath ??
           p.join(
             p.dirname(Platform.resolvedExecutable),
             'data',
             'lx-host',
             'YueyinLxHost.exe',
           );
  final String hostPath;
  final Duration evaluationTimeout;
  final void Function(String)? diagnostics;
  final _sessions = <String, _WindowsSession>{};
  final _creating = <String, Object>{};

  @override
  Future<void> create(String id) async {
    final marker = Object();
    _creating[id] = marker;
    final previous = _sessions.remove(id);
    Directory? profile;
    Process? process;
    void current() {
      if (!identical(_creating[id], marker)) {
        throw const LxSourceException(
          'cancelled',
          ExpandedStrings.operationCancelled,
        );
      }
    }

    try {
      if (previous != null) await _disposeSession(previous);
      if (!Platform.isWindows || !await File(hostPath).exists()) {
        throw const LxSourceException(
          'runtimeMissing',
          ExpandedStrings.windowsRuntimeMissing,
        );
      }
      current();
      profile = await Directory.systemTemp.createTemp('yueyin-lx-');
      current();
      final random = Random.secure();
      final profileToken = List.generate(
        32,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      process = await Process.start(
        hostPath,
        [profile.path],
        includeParentEnvironment: false,
        environment: {
          if (diagnostics != null) 'YUEYIN_LX_DIAGNOSTICS': '1',
          'YUEYIN_LX_TOKEN': profileToken,
          for (final key in [
            'SystemRoot',
            'WINDIR',
            'TEMP',
            'TMP',
            'LOCALAPPDATA',
            'ProgramFiles',
            'ProgramFiles(x86)',
            'ProgramW6432',
          ])
            key: ?Platform.environment[key],
        },
        mode: ProcessStartMode.normal,
      );
      current();
      final session = _WindowsSession(
        process,
        profile,
        profileToken,
        diagnostics,
      );
      _sessions[id] = session;
      final ready = await session.ready.future.timeout(
        const Duration(seconds: 20),
      );
      current();
      if (ready['state'] != 'ready' || ready['port'] is! int) {
        throw const LxSourceException(
          'runtimeMissing',
          ExpandedStrings.windowsRuntimeMissing,
        );
      }
      session.socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        ready['port'] as int,
        timeout: const Duration(seconds: 3),
      );
      current();
    } catch (error) {
      final cancelled = !identical(_creating[id], marker);
      final session = _sessions[id];
      if (session != null && session.process == process) {
        _sessions.remove(id);
        await _disposeSession(session);
      } else {
        process?.kill();
      }
      if (profile != null && await profile.exists()) {
        await _removeProfile(profile);
      }
      if (cancelled) {
        throw const LxSourceException(
          'cancelled',
          ExpandedStrings.operationCancelled,
        );
      }
      if (error is LxSourceException) rethrow;
      throw const LxSourceException(
        'runtimeMissing',
        ExpandedStrings.windowsRuntimeMissing,
      );
    } finally {
      if (identical(_creating[id], marker)) _creating.remove(id);
    }
  }

  @override
  Future<String> evaluate(String id, String code) async {
    final session = _sessions[id];
    if (session == null || session.closed) {
      throw const LxSourceException(
        'cancelled',
        ExpandedStrings.cancelOperation,
      );
    }
    if (utf8.encode(code).length > 2 * 1024 * 1024) {
      throw const LxSourceException('script', ExpandedStrings.windowsCodeLimit);
    }
    final requestId = ++session.serial;
    final result = Completer<String>();
    session.pending[requestId] = result;
    try {
      final payload = utf8.encode(
        jsonEncode({'id': requestId, 'code': code, 'token': session.token}),
      );
      final header = ByteData(4)..setUint32(0, payload.length, Endian.little);
      session.socket!.add(header.buffer.asUint8List());
      session.socket!.add(payload);
      diagnostics?.call('send-$requestId');
      await session.socket!.flush();
      diagnostics?.call('flushed-$requestId');
      return await result.future.timeout(evaluationTimeout);
    } on TimeoutException {
      session.pending.remove(requestId);
      await close(id);
      throw const LxSourceException(
        'timeout',
        ExpandedStrings.windowsScriptTimeout,
      );
    } finally {
      session.pending.remove(requestId);
    }
  }

  @override
  Future<void> close(String id) async {
    _creating.remove(id);
    final session = _sessions.remove(id);
    if (session == null) return;
    await _disposeSession(session);
  }

  Future<void> _disposeSession(_WindowsSession session) async {
    session.stop();
    try {
      await session.process.exitCode.timeout(const Duration(seconds: 3));
    } catch (_) {}
    await _removeProfile(session.profile);
  }

  static Future<void> _removeProfile(Directory profile) async {
    // profile仅来自本类createTemp返回的精确路径，不接收脚本提供的路径。
    for (var attempt = 0; attempt < 6; attempt++) {
      try {
        if (await profile.exists()) await profile.delete(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }
  }
}

class _WindowsSession {
  _WindowsSession(
    this.process,
    this.profile,
    this.token,
    void Function(String)? diagnostics,
  ) {
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => diagnostics?.call(line));
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            if (line.length > 3 * 1024 * 1024) {
              stop();
              return;
            }
            try {
              final value = jsonDecode(line) as Map;
              diagnostics?.call('receive-${value['id'] ?? value['state']}');
              if (value.containsKey('state')) {
                if (!ready.isCompleted) ready.complete(value);
                return;
              }
              final completer = pending.remove(value['id']);
              if (completer == null) return;
              if (value['error'] != null) {
                completer.completeError(
                  const LxSourceException(
                    'script',
                    ExpandedStrings.windowsScriptFailed,
                  ),
                );
              } else {
                completer.complete('${value['result'] ?? ''}');
              }
            } catch (_) {
              stop();
            }
          },
          onError: (_) => stop(),
          onDone: stop,
        );
  }
  final Process process;
  final Directory profile;
  final String token;
  Socket? socket;
  final ready = Completer<Map>();
  final pending = <int, Completer<String>>{};
  bool closed = false;
  int serial = 0;
  void stop() {
    if (closed) return;
    closed = true;
    socket?.destroy();
    process.kill();
    if (!ready.isCompleted) ready.complete({'state': 'unavailable'});
    for (final result in pending.values) {
      result.completeError(
        const LxSourceException('cancelled', ExpandedStrings.cancelOperation),
      );
    }
    pending.clear();
  }
}

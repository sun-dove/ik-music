import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/video_app/built_in/catalog_sandbox.dart';
import 'package:mconnect/video_app/lx_source/lx_runtime.dart';
import 'package:mconnect/video_app/lx_source/lx_source.dart';

void main() {
  test('S15 关闭时早于flush的取消只通过受控Future返回，不泄漏到全局区', () async {
    final sandbox = IkCatalogSandbox(_EarlyErrorSandbox());
    await expectLater(
      sandbox.evaluate('closing', 'fixture'),
      throwsA(
        isA<LxSourceException>().having((e) => e.code, '取消', 'cancelled'),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(await sandbox.evaluate('next', 'fixture'), 'ok');
  });
}

class _EarlyErrorSandbox implements LxSandbox {
  @override
  Future<void> create(String id) async {}
  @override
  Future<void> close(String id) async {}
  @override
  Future<String> evaluate(String id, String code) async {
    if (id == 'next') return 'ok';
    final pending = Completer<String>();
    scheduleMicrotask(
      () =>
          pending.completeError(const LxSourceException('cancelled', '取消当前操作')),
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return pending.future;
  }
}

import 'dart:async';

import '../lx_source/lx_runtime.dart';

/// IK 独立装配的异步错误边界。旧 Windows 宿主在 socket.flush 完成前
/// 可能先完成 pending 的错误；把该错误交还当前调用，不让它成为全局未处理异常。
/// 不改变宿主取消、超时、权限或脚本执行行为，也不把失败转换成成功。
class IkCatalogSandbox implements LxSandbox {
  const IkCatalogSandbox(this.delegate);
  final LxSandbox delegate;
  Future<T> _guard<T>(Future<T> Function() action) {
    final result = Completer<T>();
    runZonedGuarded(
      () {
        action().then(
          (value) {
            if (!result.isCompleted) result.complete(value);
          },
          onError: (Object error, StackTrace stack) {
            if (!result.isCompleted) result.completeError(error, stack);
          },
        );
      },
      (error, stack) {
        if (!result.isCompleted) result.completeError(error, stack);
      },
    );
    return result.future;
  }

  @override
  Future<void> create(String id) => _guard(() => delegate.create(id));
  @override
  Future<String> evaluate(String id, String code) =>
      _guard(() => delegate.evaluate(id, code));
  @override
  Future<void> close(String id) => _guard(() => delegate.close(id));
}

import '../lx_source/windows_lx_sandbox.dart';
import '../lx_source/lx_source.dart';
import '../../l10n/expanded_strings.dart';

/// Windows 新入口在退出前等待创建请求结束，防止迟到进程遗留。
class ManagedWindowsLxSandbox extends WindowsLxSandbox {
  ManagedWindowsLxSandbox({super.hostPath});
  final _pending = <Future<void>>{};
  final _ids = <String>{};
  bool _closing = false;
  @override
  Future<void> create(String id) async {
    if (_closing) {
      throw const LxSourceException(
        'cancelled',
        ExpandedStrings.cancelOperation,
      );
    }
    _ids.add(id);
    final operation = super.create(id);
    _pending.add(operation);
    try {
      await operation;
    } finally {
      _pending.remove(operation);
    }
  }

  @override
  Future<void> close(String id) async {
    await super.close(id);
    _ids.remove(id);
  }

  Future<void> shutdown() async {
    _closing = true;
    await Future.wait([for (final id in _ids.toList()) super.close(id)]);
    await Future.wait([
      for (final operation in _pending.toList())
        operation.catchError((Object _) {}),
    ]);
    await Future.wait([for (final id in _ids.toList()) super.close(id)]);
    _ids.clear();
  }
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/video_app/lx_source/lx_source.dart';
import 'package:mconnect/video_app/windows/managed_windows_lx_sandbox.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final enabled =
      Platform.isWindows && Platform.environment['YUEYIN_SANDBOX_GATE'] == '1';
  final skip = enabled
      ? false
      : '需要Windows、WebView2和独立宿主；发行脚本必须实际启用，普通主机结果不算原生通过';

  Future<int> hostCount() async {
    final result = await Process.run('powershell.exe', [
      '-NoLogo',
      '-NoProfile',
      '-Command',
      r'''$target=[IO.Path]::GetFullPath($env:YUEYIN_LX_HOST); @(Get-CimInstance Win32_Process -Filter "Name='YueyinLxHost.exe'" | Where-Object { $_.ExecutablePath -eq $target }).Count''',
    ]);
    expect(result.exitCode, 0);
    return int.parse((result.stdout as String).trim());
  }

  test('W10：退出时关闭实际已创建的宿主，拒绝迟到创建且进程数量恢复', () async {
    final before = await hostCount();
    final sandbox = ManagedWindowsLxSandbox(
      hostPath: Platform.environment['YUEYIN_LX_HOST'],
    );
    addTearDown(sandbox.shutdown);
    await sandbox.create('exit-loaded');
    expect(await sandbox.evaluate('exit-loaded', 'String(6*7)'), '42');
    expect(await hostCount(), before + 1);
    await sandbox.shutdown();
    expect(await hostCount(), before);
    await expectLater(
      sandbox.create('after-exit'),
      throwsA(
        isA<LxSourceException>().having(
          (error) => error.code,
          '退出后创建',
          'cancelled',
        ),
      ),
    );
    await expectLater(
      sandbox.evaluate('exit-loaded', '1'),
      throwsA(isA<LxSourceException>()),
    );
  }, skip: skip);

  test('W10：退出与创建并发时等创建清理完毕，不留下迟到宿主', () async {
    final before = await hostCount();
    final sandbox = ManagedWindowsLxSandbox(
      hostPath: Platform.environment['YUEYIN_LX_HOST'],
    );
    addTearDown(sandbox.shutdown);
    final pending = sandbox.create('exit-pending');
    final cancelled = expectLater(
      pending,
      throwsA(
        isA<LxSourceException>().having(
          (error) => error.code,
          '并发取消',
          'cancelled',
        ),
      ),
    );
    await sandbox.shutdown();
    await cancelled;
    expect(await hostCount(), before);
  }, skip: skip);
}

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/video_app/windows/windows_music_preferences.dart';
import 'package:mconnect/video_app/windows/windows_window_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('sun-dove.yueyin/desktop');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    channel.setMethodCallHandler(null);
  });
  test('W10：关闭设置必须收到动作一致的原生确认，不接受假成功', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return {'applied': true, 'action': (call.arguments as Map)['action']};
    });
    const window = WindowsWindowController();
    await window.setCloseAction(WindowsCloseAction.exit);
    expect(calls.single.method, 'setCloseAction');
    expect(calls.single.arguments, {'action': 'exit'});
    for (final result in [
      null,
      {'applied': false, 'action': 'exit'},
      {'applied': true, 'action': 'minimize'},
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => result);
      await expectLater(
        window.setCloseAction(WindowsCloseAction.exit),
        throwsA(
          isA<DesktopConfigurationException>().having(
            (error) => error.kind,
            '未应用',
            DesktopFailure.nativeUnavailable,
          ),
        ),
      );
    }
  });
  test('W05/W10：字体列表只整理原生返回，缺插件与原生失败有明确分类', () async {
    const window = WindowsWindowController();
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => ['Noto Sans SC', 'Microsoft YaHei UI', 'Noto Sans SC'],
    );
    expect(await window.listFonts(), ['Microsoft YaHei UI', 'Noto Sans SC']);
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'unavailable'),
    );
    await expectLater(
      window.listFonts(),
      throwsA(isA<DesktopConfigurationException>()),
    );
    await expectLater(
      window.exitApplication(),
      throwsA(isA<DesktopConfigurationException>()),
    );
    messenger.setMockMethodCallHandler(channel, null);
    await expectLater(
      window.setCloseAction(WindowsCloseAction.minimize),
      throwsA(isA<DesktopConfigurationException>()),
    );
  });
  test('W10：真正退出先等待Dart清理完成，再向原生完成握手', () async {
    final cleanup = Completer<void>();
    var prepared = 0;
    final window = WindowsWindowController(
      beforeExit: () async {
        prepared++;
        await cleanup.future;
      },
    );
    window.connect();
    final reply = Completer<ByteData?>();
    ServicesBinding.instance.channelBuffers.push(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('prepareExit'),
      ),
      reply.complete,
    );
    await Future<void>.delayed(Duration.zero);
    expect(prepared, 1);
    expect(reply.isCompleted, isFalse);
    cleanup.complete();
    final response = await reply.future;
    expect(const StandardMethodCodec().decodeEnvelope(response!), isNull);
    final methods = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      return null;
    });
    await window.exitApplication();
    expect(methods, ['exitApplication']);
  });
}

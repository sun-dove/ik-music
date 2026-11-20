import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/core/platform/platform_utils.dart';
import 'package:mconnect/features/floating_lyrics/presentation/providers/floating_lyrics_provider.dart';
import 'package:mconnect/features/player/data/playback_keep_alive_service.dart';
import 'package:mconnect/features/player/data/playback_notification_service.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/video_app/ik/ik_floating_lyrics.dart';
import 'package:mconnect/video_app/ik/ik_lyrics_action.dart';

import 'support/content_page_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.mconnect.mconnect/floating_lyrics');
  late ProviderContainer container;
  late List<String> calls;
  late bool show, hide, permission, failSave;
  late Directory scratch;
  setUpAll(() async {
    scratch = await Directory.systemTemp.createTemp('ik-lyrics-formal-');
    Hive.init(scratch.path);
    await Hive.openBox('settings');
  });
  tearDownAll(() async {
    await Hive.close();
    if (!scratch.absolute.path.startsWith(
          '${Directory.systemTemp.absolute.path}${Platform.pathSeparator}',
        ) ||
        !scratch.path
            .split(Platform.pathSeparator)
            .last
            .startsWith('ik-lyrics-formal-')) {
      throw StateError('拒绝删除未知目录');
    }
    if (await scratch.exists()) await scratch.delete(recursive: true);
  });
  setUp(() {
    PlatformUtils.setDebugOverride(AppPlatform.windows);
    calls = [];
    show = true;
    hide = true;
    permission = true;
    failSave = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return switch (call.method) {
            'canDrawOverlays' => permission,
            'show' => show,
            'hide' => hide,
            _ => true,
          };
        });
    container = ProviderContainer(
      overrides: [
        floatingLyricsProvider.overrideWith(
          (ref) => IkStrictFloatingLyricsNotifier(
            save: (_) async {
              if (failSave) throw StateError('保存失败');
            },
          ),
        ),
        playerProvider.overrideWith(
          (ref) => PlayerNotifier(
            audioController: IdleAudioController(),
            audioControllerFactory: IdleAudioController.new,
            keepAliveController: const NoopPlaybackKeepAliveController(),
            notificationController: const NoopPlaybackNotificationController(),
            stuckWatchdogInterval: Duration.zero,
            playbackHealthCheckInterval: Duration.zero,
            playbackMemorySaveInterval: Duration.zero,
          ),
        ),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await Future<void>.delayed(Duration.zero);
    PlatformUtils.setDebugOverride(null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test('U06 原生show失败不开假开关，显示具体失败并可重试', () async {
    show = false;
    await container.read(ikLyricsActionProvider.notifier).setEnabled(true);
    expect(container.read(floatingLyricsProvider).enabled, isFalse);
    expect(container.read(ikFloatingFailureProvider), isTrue);
    expect(container.read(ikLyricsIssueProvider), isNotNull);
    show = true;
    await container.read(ikLyricsActionProvider.notifier).setEnabled(true);
    expect(container.read(floatingLyricsProvider).enabled, isTrue);
    expect(container.read(ikLyricsActionProvider), isFalse);
  });
  test('U06 关闭失败仍保留开关，保存失败补偿原生状态', () async {
    await container.read(ikLyricsActionProvider.notifier).setEnabled(true);
    hide = false;
    await container.read(ikLyricsActionProvider.notifier).setEnabled(false);
    expect(container.read(floatingLyricsProvider).enabled, isTrue);
    expect(container.read(ikFloatingFailureProvider), isTrue);
    hide = true;
    await container.read(ikLyricsActionProvider.notifier).setEnabled(false);
    expect(container.read(floatingLyricsProvider).enabled, isFalse);
    calls.clear();
    failSave = true;
    await container.read(ikLyricsActionProvider.notifier).setEnabled(true);
    expect(container.read(floatingLyricsProvider).enabled, isFalse);
    expect(calls, containsAllInOrder(['show', 'hide']));
    expect(container.read(ikLyricsIssueProvider), isNotNull);
  });
  test('U06 不支持平台不调用原生，Android权限拒绝不显示成功', () async {
    PlatformUtils.setDebugOverride(AppPlatform.linux);
    expect(container.read(ikLyricsCapabilityProvider).supported, isFalse);
    await container.read(ikLyricsActionProvider.notifier).setEnabled(true);
    expect(calls, isEmpty);
    PlatformUtils.setDebugOverride(AppPlatform.android);
    container.invalidate(ikLyricsCapabilityProvider);
    permission = false;
    await container.read(ikLyricsActionProvider.notifier).setEnabled(true);
    expect(calls, contains('openOverlaySettings'));
    expect(calls, isNot(contains('show')));
    expect(container.read(floatingLyricsProvider).enabled, isFalse);
  });
  test('U06 原生窗口关闭回传同步按钮且不重新打开', () async {
    await container.read(ikLyricsActionProvider.notifier).setEnabled(true);
    calls.clear();
    final done = Completer<void>();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('closedByUser'),
          ),
          (_) => done.complete(),
        );
    await done.future;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(container.read(floatingLyricsProvider).enabled, isFalse);
    expect(calls, isNot(contains('show')));
  });
}

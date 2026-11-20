import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/floating_lyrics/data/floating_lyrics_models.dart';
import 'package:mconnect/features/floating_lyrics/presentation/providers/floating_lyrics_provider.dart';
import 'package:mconnect/features/player/presentation/providers/lyrics_provider.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/features/smart_playlists/data/smart_playlist_repository.dart';
import 'package:mconnect/features/smart_playlists/data/smart_playlist_snapshot_repository.dart';
import 'package:mconnect/features/smart_playlists/domain/smart_playlist_rule.dart';
import 'package:mconnect/features/smart_playlists/presentation/providers/smart_playlists_provider.dart';
import 'package:mconnect/l10n/ik_runtime_strings.dart';
import 'package:mconnect/l10n/app_localizations.dart';
import 'package:mconnect/video_app/ik/ik_desktop.dart';
import 'package:mconnect/video_app/ik/ik_floating_lyrics.dart';

import 'support/content_page_fakes.dart';

class _RejectRuleWrites extends MemorySmartPlaylistRepository {
  _RejectRuleWrites(super.rules);
  @override
  Future<void> saveRules(List<SmartPlaylistRule> rules) =>
      Future.error(StateError('read-only'));
}

class _MemoryLyricsSettings extends FloatingLyricsNotifier {
  _MemoryLyricsSettings() {
    state = const FloatingLyricsSettings();
  }
  @override
  Future<void> setEnabled(bool enabled) async =>
      state = state.copyWith(enabled: enabled);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('K06 删除规则写失败时保留规则及已保存生成结果', () async {
    final rule = SmartPlaylistRule.create(name: '我的规则');
    final snapshots = MemorySmartPlaylistSnapshotRepository();
    await snapshots.save(rule.id, const []);
    final notifier = SmartPlaylistsNotifier(
      repository: _RejectRuleWrites([rule]),
      snapshotRepository: snapshots,
    );
    addTearDown(notifier.dispose);
    await notifier.ready;
    await notifier.deleteRuleSafely(rule.id);
    expect(notifier.state.error, isNotNull);
    expect(notifier.state.rules.single.id, rule.id);
    expect(notifier.state.snapshotFor(rule.id), isNotNull);
    expect(await snapshots.load(rule.id), isNotNull);
  });

  test('K07 首次连接补发媒体状态，进度不重复发送，可重试部分能力', () async {
    const channel = MethodChannel('ik-desktop-gate');
    var media = false;
    final calls = <MethodCall>[];
    final commands = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'initialize' => true,
            'capabilities' => {
              'tray': true,
              'media': media,
              'windowMemory': true,
              'mediaError': media ? '' : 'smtc_unavailable',
            },
            _ => null,
          };
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final controller = IkDesktopController(
      channel: channel,
      onCommand: (command) async {
        commands.add(command);
      },
    );
    addTearDown(controller.dispose);
    await controller.update(const PlayerState());
    await controller.connect();
    expect(controller.complete, isFalse);
    expect(calls.where((c) => c.method == 'update'), hasLength(1));
    await controller.update(const PlayerState(position: Duration(seconds: 3)));
    expect(calls.where((c) => c.method == 'update'), hasLength(1));
    media = true;
    await controller.connect();
    expect(controller.complete, isTrue);
    const codec = StandardMethodCodec();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          codec.encodeMethodCall(const MethodCall('command', 'next')),
          (_) {},
        );
    expect(commands, ['next']);
  });

  testWidgets('K06 桌面歌词权限拒绝时显示失败，重试成功再开启', (tester) async {
    const channel = MethodChannel('com.mconnect.mconnect/floating_lyrics');
    var allowed = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => switch (call.method) {
            'canDrawOverlays' => allowed,
            'show' || 'update' || 'hide' => true,
            'openOverlaySettings' => false,
            _ => null,
          },
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final player = PlayerNotifier(audioController: IdleAudioController());
    final settings = _MemoryLyricsSettings();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerProvider.overrideWith((ref) => player),
          lyricsProvider.overrideWith((ref) async => null),
          floatingLyricsProvider.overrideWith((ref) => settings),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('zh'),
          home: IkFloatingLyricsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ik-floating-toggle')));
    await tester.pumpAndSettle();
    expect(settings.state.enabled, isFalse);
    expect(find.text(IkRuntimeStrings.floatingFailed), findsOneWidget);
    allowed = true;
    await tester.tap(find.text(IkRuntimeStrings.floatingRetry));
    await tester.pumpAndSettle();
    expect(settings.state.enabled, isTrue);
  });
}

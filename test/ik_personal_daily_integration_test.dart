import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/database/app_database.dart';
import 'package:mconnect/features/auth/presentation/providers/auth_provider.dart';
import 'package:mconnect/features/discovery/presentation/providers/recommendations_provider.dart';
import 'package:mconnect/features/player/data/playback_keep_alive_service.dart';
import 'package:mconnect/features/player/data/playback_notification_service.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/models/personal_daily_result.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/models/user.dart';
import 'package:mconnect/platform/base/platform_registry.dart';
import 'package:mconnect/video_app/data/personal_daily_provider.dart';
import 'package:mconnect/video_app/data/video_auth_notifier.dart';
import 'package:mconnect/video_app/ik/ik_home_page.dart';
import 'package:mconnect/video_app/ik/ik_router.dart';
import 'package:mconnect/video_app/ik/ik_workspace_theme.dart';
import 'package:mconnect/video_app/ui/video_theme.dart';

import 'support/content_page_fakes.dart'
    show FakeContentPlatform, IdleAudioController;

// 正式接线门：真实IK首页、IK路由、个人provider和内存数据库。
// 只替换账号、平台HTTP与音频设备，不读取用户账号或操作原生窗口。
void main() {
  late AppDatabase db;
  setUpAll(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    initializeApplicationDatabase(db);
  });
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDownAll(() => db.close());

  testWidgets('新版发现页每日入口与精选并存，原默认不出现新入口', (tester) async {
    for (final aligned in [false, true]) {
      final navigation = <String>[];
      await tester.pumpWidget(
        ProviderScope(
          key: ValueKey(aligned),
          overrides: [
            authProvider.overrideWith((_) => _Auth()),
            playerProvider.overrideWith((_) => _Player()),
            recommendationsProvider.overrideWith((_) => _Recommendations()),
          ],
          child: MaterialApp(
            theme: IkWorkspaceTheme.aligned(VideoTheme.light),
            home: Scaffold(
              body: IkHomePage(
                workspace: true,
                alignToDesign: aligned,
                onNavigate: navigation.add,
                onPlayer: () {},
                onPlay: (_, _) {},
                onMore: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final entry = find.byKey(const Key('ik-personal-daily-entry'));
      expect(entry, aligned ? findsOneWidget : findsNothing);
      if (aligned) {
        await tester.ensureVisible(entry);
        await tester.tap(entry);
        await tester.pump();
        expect(navigation, ['/daily']);
        expect(find.text('推荐'), findsOneWidget);
        final browse = find.widgetWithText(TextButton, '浏览全部');
        await tester.ensureVisible(browse);
        await tester.pump();
        expect(browse.hitTestable(), findsOneWidget);
        await tester.tap(browse);
        expect(navigation, ['/daily', '/recommendations']);
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('日推路由参数选择对应平台，退出账号立即清曲目并提供同平台连接', (tester) async {
    final adapters = [
      for (final platform in PlatformType.musicServices)
        _DailyPlatform(platform),
    ];
    for (final adapter in adapters) {
      PlatformRegistry.register(adapter);
    }
    final auth = _Auth();
    final router = createIkRouter(
      alignToDesign: true,
      home: (_) => const Text('主区'),
      player: (_) => const Text('播放区'),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((_) => auth),
          playerProvider.overrideWith((_) => _Player()),
          personalDailyClockProvider.overrideWithValue(
            () => DateTime(2026, 11, 22),
          ),
        ],
        child: MaterialApp.router(
          theme: IkWorkspaceTheme.aligned(VideoTheme.light),
          routerConfig: router,
        ),
      ),
    );
    for (final adapter in adapters) {
      final platform = adapter.platformType;
      auth.select(platform, '9001');
      router.go('/daily?platform=${platform.name}');
      await tester.pump();
      await tester.pump();
      await tester.pump();
      final chip = find.byKey(ValueKey('ik-daily-platform-${platform.name}'));
      expect(chip, findsOneWidget);
      expect((tester.widget(chip) as ChoiceChip).selected, isTrue);
      expect(find.text('${platform.name}个人曲目'), findsOneWidget);
      expect(adapter.requests, [('9001', 30)]);
      for (final other in adapters.where((other) => other != adapter)) {
        expect(find.text('${other.platformType.name}个人曲目'), findsNothing);
      }
      auth.select(platform, null);
      await tester.pump();
      await tester.pump();
      expect(find.text('${platform.name}个人曲目'), findsNothing);
      final connect = find.byKey(const Key('ik-daily-state-action'));
      await tester.ensureVisible(connect);
      await tester.tap(connect);
      await tester.pump();
      expect(router.routerDelegate.state.uri.path, '/login/${platform.name}');
      router.pop();
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 2),
      );
      expect(router.routerDelegate.state.uri.path, '/daily');
      expect(chip, findsOneWidget);
      expect((tester.widget(chip) as ChoiceChip).selected, isTrue);
      expect(adapter.requests, hasLength(1));
    }
    for (final value in ['local', 'not-a-platform']) {
      router.go('/daily?platform=$value');
      await tester.pump();
      expect(find.byType(IkRouteError), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}

class _DailyPlatform extends FakeContentPlatform {
  _DailyPlatform(PlatformType type) : super(type: type, loggedIn: true);
  final requests = <(String?, int)>[];
  @override
  bool get supportsPersonalDailyRecommendations => true;
  @override
  Future<PersonalDailyResult> getPersonalDailyRecommendations({
    int limit = 30,
    String? expectedAccountId,
  }) async {
    requests.add((expectedAccountId, limit));
    return PersonalDailyResult(
      platform: platformType,
      status: PersonalDailyStatus.success,
      fetchedAt: DateTime(2026, 11, 22),
      rawCount: 1,
      validCount: 1,
      songs: [
        Song(
          id: 'personal',
          platform: platformType,
          name: '${platformType.name}个人曲目',
          artists: const [],
        ),
      ],
    );
  }
}

class _Auth extends VideoAuthNotifier {
  void select(PlatformType platform, String? id) {
    state = state.copyWith(
      loggedUsers: {
        ...state.loggedUsers,
        platform: id == null
            ? null
            : User(id: id, nickname: '虚构账号', platform: platform),
      },
    );
  }
}

class _Recommendations extends RecommendationsNotifier {
  @override
  Future<void> loadRecommendations() async {}
}

class _Player extends PlayerNotifier {
  _Player()
    : super(
        audioController: IdleAudioController(),
        audioControllerFactory: IdleAudioController.new,
        keepAliveController: const NoopPlaybackKeepAliveController(),
        notificationController: const NoopPlaybackNotificationController(),
        stuckWatchdogInterval: Duration.zero,
      );
}

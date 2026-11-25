import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/personal_daily_result.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/video_app/data/personal_daily_provider.dart';
import 'package:mconnect/video_app/ik/ik_personal_daily_page.dart';
import 'package:mconnect/video_app/ik/ik_router.dart';
import 'package:mconnect/video_app/ik/ik_song_table.dart';
import 'package:mconnect/video_app/ik/ik_workspace_theme.dart';
import 'package:mconnect/video_app/ui/video_theme.dart';

// 正式体验门：真实Flutter页面；平台请求和账号隔离另由功能门验证。
// 此处只记录播放器、收藏、菜单、账号及验证动作的边界，不操作本机账号。
void main() {
  final expectations = <PersonalDailyStatus, (String, String?)>{
    PersonalDailyStatus.signedOut: ('登录后查看每日推荐', '连接账号'),
    PersonalDailyStatus.identityIncomplete: ('需要重新连接账号', '重新连接'),
    PersonalDailyStatus.sessionExpired: ('登录已失效', '重新连接'),
    PersonalDailyStatus.verificationRequired: ('需要完成平台验证', '前往平台验证'),
    PersonalDailyStatus.networkFailure: ('网络连接失败', '重试'),
    PersonalDailyStatus.serviceUnavailable: ('平台暂时无法提供推荐', '重试'),
    PersonalDailyStatus.invalidResponse: ('暂时无法读取推荐', '重试'),
    PersonalDailyStatus.empty: ('今日推荐还没有歌曲', '重试'),
    PersonalDailyStatus.unsupported: ('该平台暂不支持个人日推', null),
    PersonalDailyStatus.sessionChanged: ('账号已更新', '刷新推荐'),
  };

  for (final entry in expectations.entries) {
    testWidgets('日推体验 ${entry.key.name} 三来源的提示和可用动作正确', (tester) async {
      for (final platform in PlatformType.musicServices) {
        final fixture = _Fixture(platform)..setResult(entry.key);
        await _mount(tester, fixture, width: 320, scale: 1.5);
        expect(find.widgetWithText(AppBar, '每日推荐'), findsOneWidget);
        _expectPlatforms(fixture);
        final title = find.text(entry.value.$1);
        await _reveal(tester, title);
        expect(title.hitTestable(), findsOneWidget);
        expect(find.byType(IkSongTableRow), findsNothing);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('ik-daily-play-all')))
              .onPressed,
          isNull,
        );
        if (entry.value.$2 case final action?) {
          final button = find.byKey(const Key('ik-daily-state-action'));
          await _reveal(tester, button);
          expect(
            find.descendant(of: button, matching: find.text(action)),
            findsOneWidget,
          );
          await tester.tap(button);
          await tester.pump();
          switch (entry.key) {
            case PersonalDailyStatus.signedOut:
            case PersonalDailyStatus.identityIncomplete:
            case PersonalDailyStatus.sessionExpired:
              expect(fixture.accounts, [platform]);
              expect(fixture.retries, isEmpty);
            case PersonalDailyStatus.verificationRequired:
              expect(fixture.verifications, [platform]);
              expect(fixture.accounts, isEmpty);
              final retry = find.byKey(
                const Key('ik-daily-verification-retry'),
              );
              await _reveal(tester, retry);
              await tester.tap(retry);
              await tester.pump();
              expect(fixture.retries, [platform]);
            default:
              expect(fixture.retries, [platform]);
              expect(fixture.accounts, isEmpty);
          }
        } else {
          expect(find.byKey(const Key('ik-daily-state-action')), findsNothing);
          expect(
            tester.widget<IconButton>(_iconButton('刷新每日推荐')).onPressed,
            isNull,
          );
        }
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('日推加载中隐藏旧曲目并禁用重复刷新和播放', (tester) async {
    final fixture = _Fixture(PlatformType.qq)..setSongs(30);
    fixture.loading = true;
    await _mount(tester, fixture);
    expect(find.byKey(const Key('ik-daily-progress')), findsOneWidget);
    expect(find.byType(IkSongTableRow), findsNothing);
    expect(tester.widget<IconButton>(_iconButton('刷新每日推荐')).onPressed, isNull);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('ik-daily-play-all')))
          .onPressed,
      isNull,
    );
    expect(fixture.plays, isEmpty);
  });

  testWidgets('日推成功后可刷新当前来源，重新加载立即清旧曲目', (tester) async {
    for (final platform in PlatformType.musicServices) {
      final fixture = _Fixture(platform)..setSongs(1);
      await _mount(tester, fixture);
      final refresh = _iconButton('刷新每日推荐');
      expect(tester.widget<IconButton>(refresh).onPressed, isNotNull);
      await tester.tap(refresh);
      await tester.pump();
      expect(fixture.retries, [platform]);
      fixture.loading = true;
      await _mount(tester, fixture);
      expect(find.byType(IkSongTableRow), findsNothing);
      expect(tester.widget<IconButton>(refresh).onPressed, isNull);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('ik-daily-play-all')))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('日推超时显示具体原因，重试仍作用当前平台', (tester) async {
    final fixture = _Fixture(PlatformType.qq)
      ..setResult(PersonalDailyStatus.networkFailure)
      ..errorCode = 'timeout';
    await _mount(tester, fixture);
    expect(find.text('推荐加载超时'), findsOneWidget);
    final retry = find.byKey(const Key('ik-daily-state-action'));
    await _reveal(tester, retry);
    await tester.tap(retry);
    await tester.pump();
    expect(fixture.retries, [PlatformType.qq]);
  });

  testWidgets('明确不可重试的失败不提供重复请求动作', (tester) async {
    final fixture = _Fixture(PlatformType.kugou)
      ..setResult(PersonalDailyStatus.serviceUnavailable)
      ..retryable = false;
    await _mount(tester, fixture);
    expect(find.byKey(const Key('ik-daily-state-action')), findsNothing);
    expect(tester.widget<IconButton>(_iconButton('刷新每日推荐')).onPressed, isNull);
    _expectPlatforms(fixture);
  });

  testWidgets('三来源0/1/29/30/31/32首保持真实数量，逐曲播放与列表一致', (tester) async {
    var checkedRows = 0;
    for (final platform in PlatformType.musicServices) {
      for (final count in [0, 1, 29, 30, 31, 32]) {
        final fixture = _Fixture(platform)..setSongs(count);
        await _mount(tester, fixture);
        final shown = count > 30 ? 30 : count;
        expect(find.text('共$shown首'), findsOneWidget);
        final playAll = find.byKey(const Key('ik-daily-play-all'));
        if (shown == 0) {
          expect(tester.widget<FilledButton>(playAll).onPressed, isNull);
          expect(find.text('今日推荐还没有歌曲'), findsOneWidget);
          continue;
        }
        await tester.tap(playAll);
        await tester.pump();
        expect(fixture.plays.single.$1, fixture.result!.songs.first.id);
        expect(fixture.plays.single.$2, [
          for (var i = 1; i <= shown; i++) '${platform.name}-$i',
        ]);
        for (var i = 1; i <= shown; i++) {
          final row = find.byKey(ValueKey('ik-daily-song-${platform.name}-$i'));
          await _reveal(tester, row);
          expect(row.hitTestable(), findsOneWidget);
          await tester.tap(
            find.descendant(of: row, matching: find.text('歌曲$i')),
          );
          await tester.pump();
          expect(fixture.plays.last.$1, '${platform.name}-$i');
          expect(fixture.plays.last.$2, fixture.plays.first.$2);
          checkedRows++;
        }
        expect(fixture.plays, hasLength(shown + 1));
        expect(find.text('歌曲31'), findsNothing);
        expect(find.text('歌曲32'), findsNothing);
        expect(tester.takeException(), isNull);
      }
    }
    expect(checkedRows, 360);
  });

  testWidgets('日推收藏和更多绑定当前歌曲，菜单使用按钮上下文', (tester) async {
    final fixture = _Fixture(PlatformType.kugou)..setSongs(1);
    await _mount(tester, fixture);
    final row = find.byKey(const Key('ik-daily-song-kugou-1'));
    await _reveal(tester, row);
    await tester.tap(find.descendant(of: row, matching: find.byTooltip('收藏')));
    await tester.pump();
    expect(fixture.likes, ['kugou-1']);
    fixture.liked.add('kugou:kugou-1');
    await _mount(tester, fixture);
    await _reveal(tester, row);
    expect(
      find.descendant(of: row, matching: find.byTooltip('取消收藏')),
      findsOneWidget,
    );
    await tester.tap(find.descendant(of: row, matching: find.byTooltip('更多')));
    await tester.pump();
    expect(fixture.more, ['kugou-1']);
    expect(fixture.menuContext?.mounted, isTrue);
    final anchor = fixture.menuContext!.findRenderObject()! as RenderBox;
    expect(
      anchor.localToGlobal(Offset.zero),
      tester.getTopLeft(find.descendant(of: row, matching: _iconButton('更多'))),
    );
    expect(
      anchor.size,
      tester.getSize(find.descendant(of: row, matching: _iconButton('更多'))),
    );
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('切来源立即移除上一来源曲目，仍能刷新所选平台', (tester) async {
    final fixture = _Fixture(PlatformType.netease)..setSongs(1);
    await _mount(tester, fixture);
    await tester.tap(find.byKey(const Key('ik-daily-platform-qq')));
    await tester.pump();
    expect(fixture.selected, [PlatformType.qq]);
    fixture.platform = PlatformType.qq;
    await _mount(tester, fixture);
    expect(find.byType(IkSongTableRow), findsNothing);
    expect(find.text('歌曲1'), findsNothing);
    final retry = find.byKey(const Key('ik-daily-state-action'));
    await _reveal(tester, retry);
    await tester.tap(retry);
    await tester.pump();
    expect(fixture.retries, [PlatformType.qq]);
  });

  testWidgets('推荐日期与获取日期分开，旧日期不显示为今日更新', (tester) async {
    final fixture = _Fixture(PlatformType.netease)..setSongs(1);
    await _mount(tester, fixture);
    expect(find.text('2026年11月22日获取'), findsOneWidget);
    expect(find.textContaining('推荐日期'), findsNothing);
    fixture.sourceDate = DateTime(2026, 11, 21);
    await _mount(tester, fixture);
    expect(find.text('推荐日期：2026年11月21日'), findsOneWidget);
    expect(find.textContaining('今日更新'), findsNothing);
  });

  testWidgets('浅深与六宽三字号完整36组合，三来源和歌曲动作均可达', (tester) async {
    var combinations = 0;
    var sourceActions = 0;
    for (final dark in [false, true]) {
      for (final width in [320.0, 390.0, 720.0, 900.0, 1200.0, 1440.0]) {
        for (final scale in [1.0, 1.25, 1.5]) {
          final fixture = _Fixture(PlatformType.qq)..setSongs(1);
          await _mount(tester, fixture, width: width, scale: scale, dark: dark);
          _expectPlatforms(fixture);
          for (final source in PlatformType.musicServices) {
            await tester.tap(
              find.byKey(ValueKey('ik-daily-platform-${source.name}')),
            );
            await tester.pump();
            expect(fixture.selected.last, source);
            fixture.platform = source;
            fixture.setSongs(1);
            await _mount(
              tester,
              fixture,
              width: width,
              scale: scale,
              dark: dark,
            );
            _expectPlatforms(fixture);
            sourceActions++;
          }
          final row = find.byKey(const Key('ik-daily-song-kugou-1'));
          await _reveal(tester, row);
          await tester.tap(
            find.descendant(of: row, matching: find.text('歌曲1')),
          );
          await tester.pump();
          expect(fixture.plays.single.$1, 'kugou-1');
          await tester.tap(
            find.descendant(of: row, matching: find.byTooltip('收藏')),
          );
          await tester.pump();
          expect(fixture.likes, ['kugou-1']);
          await tester.tap(
            find.descendant(of: row, matching: find.byTooltip('更多')),
          );
          await tester.pump();
          expect(fixture.more, ['kugou-1']);
          expect(
            tester.takeException(),
            isNull,
            reason: '$dark / $width / $scale',
          );
          combinations++;
        }
      }
    }
    expect(combinations, 36);
    expect(sourceActions, 108);
  });

  testWidgets('个人入口独立于原精选路由，旧默认不启用新入口', (tester) async {
    for (final aligned in [false, true]) {
      final router = createIkRouter(
        home: (_) => const Text('主区'),
        player: (_) => const Text('播放区'),
        alignToDesign: aligned,
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      expect(
        router.configuration.findMatch(Uri.parse('/recommendations')).isError,
        isFalse,
      );
      for (final platform in PlatformType.musicServices) {
        expect(
          router.configuration
              .findMatch(Uri.parse('/daily?platform=${platform.name}'))
              .isError,
          !aligned,
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
    }
  });
}

class _Fixture {
  _Fixture(this.platform);
  PlatformType platform;
  PersonalDailyResult? result;
  DateTime? sourceDate;
  String? errorCode;
  bool? retryable;
  bool loading = false;
  final selected = <PlatformType>[];
  final retries = <PlatformType>[];
  final accounts = <PlatformType>[];
  final verifications = <PlatformType>[];
  final plays = <(String, List<String>)>[];
  final likes = <String>[];
  final more = <String>[];
  final liked = <String>{};
  BuildContext? menuContext;

  void setResult(PersonalDailyStatus status) => result = PersonalDailyResult(
    platform: platform,
    status: status,
    fetchedAt: DateTime(2026, 11, 22),
  );

  void setSongs(int count) => result = PersonalDailyResult(
    platform: platform,
    status: count == 0
        ? PersonalDailyStatus.empty
        : PersonalDailyStatus.success,
    fetchedAt: DateTime(2026, 11, 22),
    rawCount: count,
    validCount: count,
    songs: [
      for (var i = 1; i <= count && i <= 30; i++)
        Song(
          id: '${platform.name}-$i',
          platform: platform,
          name: '歌曲$i',
          artists: const [Artist(id: 'artist', name: '歌手')],
        ),
    ],
  );

  Widget get page {
    final current = result;
    return IkPersonalDailyWorkspace(
      key: ObjectKey(this),
      platform: platform,
      state: PersonalDailyState(
        isLoading: loading,
        result: current == null
            ? null
            : PersonalDailyResult(
                platform: current.platform,
                status: current.status,
                fetchedAt: current.fetchedAt,
                songs: current.songs,
                rawCount: current.rawCount,
                validCount: current.validCount,
                sourceDate: sourceDate,
                errorCode: errorCode,
                retryable: retryable,
              ),
      ),
      onPlatform: selected.add,
      onRetry: () => retries.add(platform),
      onAccount: () => accounts.add(platform),
      onVerification: () => verifications.add(platform),
      onPlay: (song, songs) =>
          plays.add((song.id, songs.map((s) => s.id).toList())),
      onLike: (song) => likes.add(song.id),
      onMore: (context, song) {
        menuContext = context;
        more.add(song.id);
      },
      likedKeys: liked,
    );
  }
}

Future<void> _mount(
  WidgetTester tester,
  _Fixture fixture, {
  double width = 900,
  double scale = 1,
  bool dark = false,
}) async {
  tester.view.physicalSize = Size(width, 950);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: IkWorkspaceTheme.aligned(
        dark ? VideoTheme.dark : VideoTheme.light,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: fixture.page,
    ),
  );
  await tester.pump();
}

void _expectPlatforms(_Fixture fixture) {
  for (final platform in PlatformType.musicServices) {
    final chip = find.byKey(ValueKey('ik-daily-platform-${platform.name}'));
    expect(chip.hitTestable(), findsOneWidget);
    expect(
      (chip.evaluate().single.widget as ChoiceChip).selected,
      platform == fixture.platform,
    );
  }
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  expect(find.byType(CustomScrollView), findsOneWidget);
  await tester.scrollUntilVisible(
    target,
    250,
    scrollable: find.descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.ensureVisible(target);
  await tester.pump();
}

Finder _iconButton(String tooltip) => find.byWidgetPredicate(
  (widget) => widget is IconButton && widget.tooltip == tooltip,
);

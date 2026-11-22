import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mconnect/core/network/api_exception.dart';
import 'package:mconnect/features/auth/presentation/providers/auth_provider.dart';
import 'package:mconnect/features/discovery/presentation/pages/recommendations_page.dart';
import 'package:mconnect/features/discovery/presentation/providers/recommendations_provider.dart';
import 'package:mconnect/features/new_songs/presentation/pages/new_songs_page.dart';
import 'package:mconnect/features/new_songs/presentation/providers/new_songs_provider.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/features/toplist/presentation/pages/toplists_page.dart';
import 'package:mconnect/features/toplist/presentation/providers/toplists_provider.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/recommendation_source.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/models/toplist.dart';
import 'package:mconnect/models/user.dart';
import 'package:mconnect/platform/base/music_platform.dart';
import 'package:mconnect/video_app/ik/ik_song_table.dart';
import 'package:mconnect/video_app/ik/ik_workspace_theme.dart';
import 'package:mconnect/video_app/ui/video_theme.dart';

import 'support/content_page_fakes.dart';

// 首红证据保留原页面夹具；仅接入可选呈现，以下体验断言保持不变。
Widget _newSongs({bool aligned = true}) => NewSongsPage(alignToDesign: aligned);
Widget _toplists({bool aligned = true}) => ToplistsPage(alignToDesign: aligned);
Widget _recommendations({bool aligned = true}) =>
    RecommendationsPage(alignToDesign: aligned);

void main() {
  group('R03/R04 发现平台入口与原操作', () {
    testWidgets('新歌三平台同时可见，切换只呈现所选来源', (tester) async {
      await tester.pumpWidget(_wrap(_newSongs()));
      await tester.pumpAndSettle();
      _expectPlatformChips(tester, PlatformType.netease);
      expect(find.text('netease-歌曲1'), findsOneWidget);
      expect(find.text('qq-歌曲1'), findsNothing);
      expect(find.text('kugou-歌曲1'), findsNothing);

      for (final platform in PlatformType.musicServices) {
        await tester.tap(_platformChip(platform));
        await tester.pumpAndSettle();
        _expectPlatformChips(tester, platform);
        expect(find.text('${platform.name}-歌曲1'), findsOneWidget);
        for (final other in PlatformType.musicServices.where(
          (p) => p != platform,
        )) {
          expect(find.text('${other.name}-歌曲1'), findsNothing);
        }
      }
    });

    testWidgets('新歌地区沿用原加载，网易港台与酷狗不支持仍有入口和说明', (tester) async {
      final platforms = [
        _FixturePlatform(
          type: PlatformType.netease,
          newSongsError: UnsupportedActionException(
            '网易云音乐',
            details: '新歌速递不提供港台地区',
          ),
        ),
        _FixturePlatform(type: PlatformType.qq),
        _FixturePlatform(type: PlatformType.kugou, supportsNewSongsFlag: false),
      ];
      await tester.pumpWidget(_wrap(_newSongs(), platforms: platforms));
      await tester.pumpAndSettle();
      _expectPlatformChips(tester, PlatformType.netease);
      for (final label in const ['全部', '华语', '欧美', '日本', '韩国', '港台']) {
        expect(find.widgetWithText(ChoiceChip, label), findsOneWidget);
      }
      await tester.tap(find.widgetWithText(ChoiceChip, '港台'));
      await tester.pumpAndSettle();
      expect(
        platforms.first.newSongCalls.last.region,
        NewSongRegion.hongKongTaiwan,
      );
      expect(find.textContaining('新歌速递不提供港台地区'), findsOneWidget);

      await tester.tap(_platformChip(PlatformType.kugou));
      await tester.pumpAndSettle();
      expect(find.text('酷狗音乐暂不支持新歌速递'), findsOneWidget);
      expect(platforms.last.newSongCalls, isEmpty);
      _expectPlatformChips(tester, PlatformType.kugou);
    });

    testWidgets('新歌单源错误不隐藏入口，重试确实重新请求', (tester) async {
      final qq = _FixturePlatform(
        type: PlatformType.qq,
        newSongsError: NetworkException(),
      );
      await tester.pumpWidget(_wrap(_newSongs(), platforms: [qq]));
      await tester.pumpAndSettle();
      await tester.tap(_platformChip(PlatformType.qq));
      await tester.pumpAndSettle();
      expect(find.text('网络连接失败，请检查网络后重试'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, '重试'), findsOneWidget);
      final before = qq.newSongCalls.length;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(qq.newSongCalls.length, before + 1);
      _expectPlatformChips(tester, PlatformType.qq);
    });

    testWidgets('榜单只显示所选平台，QQ26只在QQ标签且沿用真实路由', (tester) async {
      final router = GoRouter(
        initialLocation: '/toplists',
        routes: [
          GoRoute(path: '/toplists', builder: (_, _) => _toplists()),
          GoRoute(
            path: '/toplist/:platform/:id',
            builder: (_, state) => Scaffold(
              appBar: AppBar(title: const Text('榜单详情')),
              body: Text(
                'detail-${state.pathParameters['platform']}-${state.pathParameters['id']}',
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(_wrap(_toplists(), router: router));
      await tester.pumpAndSettle();
      _expectPlatformChips(tester, PlatformType.netease);
      expect(find.text('netease-榜单'), findsOneWidget);
      expect(find.byKey(const Key('ik-toplists-qq-hot')), findsNothing);
      expect(find.text('qq-榜单'), findsNothing);

      await tester.tap(_platformChip(PlatformType.kugou));
      await tester.pumpAndSettle();
      expect(find.text('kugou-榜单'), findsOneWidget);
      expect(find.byKey(const Key('ik-toplists-qq-hot')), findsNothing);

      await tester.tap(_platformChip(PlatformType.qq));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ik-toplists-qq-hot')), findsOneWidget);
      expect(find.text('热歌榜'), findsOneWidget, reason: '目录的26不能重复出现在普通榜单里');
      expect(find.text('qq-榜单'), findsOneWidget);
      await tester.tap(find.byKey(const Key('ik-toplists-qq-hot')));
      await tester.pumpAndSettle();
      expect(find.text('detail-qq-26'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      _expectPlatformChips(tester, PlatformType.qq);
    });

    testWidgets('榜单空与错误都保留三平台，QQ离线仍可见26入口并能重试', (tester) async {
      final qq = _FixturePlatform(
        type: PlatformType.qq,
        toplistsError: Exception('目录加载失败'),
      );
      await tester.pumpWidget(_wrap(_toplists(), platforms: [qq]));
      await tester.pumpAndSettle();
      _expectPlatformChips(tester, PlatformType.netease);
      expect(find.text('该平台暂无榜单'), findsOneWidget);
      await tester.tap(_platformChip(PlatformType.qq));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ik-toplists-qq-hot')), findsOneWidget);
      expect(find.textContaining('目录加载失败'), findsOneWidget);
      final before = qq.toplistLoads;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(qq.toplistLoads, before + 1);
    });
  });

  group('R06 推荐真实来源与会话', () {
    testWidgets('推荐的登录入口沿用原路由，返回后仍在所选来源', (tester) async {
      final router = GoRouter(
        initialLocation: '/recommendations',
        routes: [
          GoRoute(
            path: '/recommendations',
            builder: (_, _) => _recommendations(),
          ),
          GoRoute(
            path: '/login/:platform',
            builder: (_, state) => Scaffold(
              appBar: AppBar(title: const Text('账号登录')),
              body: Text('login-${state.pathParameters['platform']}'),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(_wrap(_recommendations(), router: router));
      await tester.pumpAndSettle();
      await tester.tap(_platformChip(PlatformType.qq));
      await tester.pumpAndSettle();
      await tester.tap(find.text('登录账号'));
      await tester.pumpAndSettle();
      expect(find.text('login-qq'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      _expectPlatformChips(tester, PlatformType.qq);
    });

    testWidgets('推荐标题与三平台入口固定，匿名网易不冒称个人日推', (tester) async {
      await tester.pumpWidget(_wrap(_recommendations()));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, '推荐'), findsOneWidget);
      _expectPlatformChips(tester, PlatformType.netease);
      expect(find.text('平台推荐'), findsOneWidget);
      expect(find.text('每日推荐'), findsNothing);
      expect(find.text('netease-歌曲1'), findsOneWidget);
      expect(find.text('qq-歌曲1'), findsNothing);
    });

    testWidgets('QQ榜单与酷狗首页呈现真实来源和回退说明', (tester) async {
      await tester.pumpWidget(_wrap(_recommendations()));
      await tester.pumpAndSettle();
      await tester.tap(_platformChip(PlatformType.qq));
      await tester.pumpAndSettle();
      expect(find.text('榜单推荐'), findsOneWidget);
      expect(find.text('未登录，已回退到新歌榜'), findsOneWidget);
      expect(find.text('qq-歌曲1'), findsOneWidget);
      expect(find.text('netease-歌曲1'), findsNothing);
      await tester.tap(_platformChip(PlatformType.kugou));
      await tester.pumpAndSettle();
      expect(find.text('首页推荐'), findsOneWidget);
      expect(find.text('官方推荐接口已不可用，来源为首页推荐'), findsOneWidget);
      expect(find.text('每日推荐'), findsNothing);
    });

    testWidgets('推荐已有歌曲时仍显示该来源的错误，不能把部分结果当完整成功', (tester) async {
      await tester.pumpWidget(
        _wrap(
          _recommendations(),
          platforms: [
            _FixturePlatform(
              type: PlatformType.netease,
              recommendations: RecommendationResult(
                songs: _songs(PlatformType.netease),
                source: _source(PlatformType.netease),
                error: '部分推荐加载失败，请重试',
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('部分推荐加载失败，请重试'), findsOneWidget);
      expect(find.text('netease-歌曲1'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, '重试'), findsOneWidget);
    });

    for (final platform in [PlatformType.netease, PlatformType.qq]) {
      testWidgets('${platform.displayName}仅真实会话与对应来源同时成立才显示个人推荐', (
        tester,
      ) async {
        final kind = platform == PlatformType.qq
            ? RecommendationKind.personalPrivate
            : RecommendationKind.personalizedDaily;
        final label = platform == PlatformType.qq ? '今日私享' : '每日推荐';
        for (final loggedIn in [false, true]) {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await tester.pumpWidget(
            _wrap(
              _recommendations(),
              platforms: [
                _FixturePlatform(
                  type: platform,
                  loggedIn: loggedIn,
                  recommendations: RecommendationResult(
                    songs: [song('personal', platform, name: '会话对应歌曲')],
                    source: RecommendationSource(
                      platform: platform,
                      kind: kind,
                      label: label,
                    ),
                  ),
                ),
              ],
              loggedIn: loggedIn ? {platform} : {},
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(_platformChip(platform));
          await tester.pumpAndSettle();
          expect(find.text(loggedIn ? label : '平台推荐'), findsOneWidget);
          if (!loggedIn) expect(find.text(label), findsNothing);
        }
      });
    }

    testWidgets('酷狗无已验证个人响应，即使登录也不能仅凭来源枚举声称日推', (tester) async {
      await tester.pumpWidget(
        _wrap(
          _recommendations(),
          platforms: [
            _FixturePlatform(
              type: PlatformType.kugou,
              loggedIn: true,
              recommendations: RecommendationResult(
                songs: [song('kg', PlatformType.kugou)],
                source: const RecommendationSource(
                  platform: PlatformType.kugou,
                  kind: RecommendationKind.personalizedDaily,
                  label: '每日推荐',
                ),
              ),
            ),
          ],
          loggedIn: {PlatformType.kugou},
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(_platformChip(PlatformType.kugou));
      await tester.pumpAndSettle();
      expect(find.text('平台推荐'), findsOneWidget);
      expect(find.text('每日推荐'), findsNothing);
    });

    testWidgets('匿名失败来源不会消失，原notifier重试可恢复歌曲和来源', (tester) async {
      final qq = _FixturePlatform(
        type: PlatformType.qq,
        recommendations: const RecommendationResult(error: '推荐服务暂不可用'),
      );
      await tester.pumpWidget(_wrap(_recommendations(), platforms: [qq]));
      await tester.pumpAndSettle();
      _expectPlatformChips(tester, PlatformType.netease);
      await tester.tap(_platformChip(PlatformType.qq));
      await tester.pumpAndSettle();
      expect(find.text('推荐服务暂不可用'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, '重试'), findsOneWidget);
      qq.recommendations = RecommendationResult(
        songs: [song('retry', PlatformType.qq, name: '重试后的推荐')],
        source: const RecommendationSource(
          platform: PlatformType.qq,
          kind: RecommendationKind.fallbackToplist,
          label: 'QQ推荐',
          note: '未登录，已回退到热歌榜',
        ),
      );
      final before = qq.recommendationLoads;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(qq.recommendationLoads, before + 1);
      expect(find.text('重试后的推荐'), findsOneWidget);
      expect(find.text('榜单推荐'), findsOneWidget);
      expect(find.text('未登录，已回退到热歌榜'), findsOneWidget);
      _expectPlatformChips(tester, PlatformType.qq);
    });
  });

  group('R03 歌曲表格与真实播放器', () {
    for (final page in {'新歌': _newSongs, '推荐': _recommendations}.entries) {
      testWidgets('${page.key}复用歌曲表格，行播放保留完整来源列表和startIndex', (tester) async {
        final platforms = _fixtures();
        final byType = {for (final p in platforms) p.type: p};
        final player = PlayerNotifier(
          audioController: IdleAudioController(),
          platformResolver: (type) => byType[type]!,
        );
        await tester.pumpWidget(
          _wrap(page.value(), platforms: platforms, player: player),
        );
        await tester.pumpAndSettle();
        await tester.tap(_platformChip(PlatformType.qq));
        await tester.pumpAndSettle();
        expect(find.byType(IkSongTableHeader), findsOneWidget);
        expect(find.byType(IkSongTableRow), findsNWidgets(3));
        expect(find.byTooltip('更多'), findsNWidgets(3));
        await tester.tap(find.text('qq-歌曲2'));
        await tester.pump();
        expect(player.state.playlist.map((s) => s.id), [
          'qq-1',
          'qq-2',
          'qq-3',
        ]);
        expect(player.state.currentIndex, 1);
        expect(player.state.currentSong?.id, 'qq-2');
        await tester.pumpAndSettle();
        await tester.tap(find.text('播放全部'));
        await tester.pump();
        expect(player.state.playlist.map((s) => s.id), [
          'qq-1',
          'qq-2',
          'qq-3',
        ]);
        expect(player.state.currentIndex, 0);
      });

      testWidgets('${page.key}更多沿用原动作，下一首添加所选歌曲', (tester) async {
        final platforms = _fixtures();
        final player = PlayerNotifier(
          audioController: IdleAudioController(),
          platformResolver: (_) => platforms[1],
        );
        await player.playSong(song('current', PlatformType.qq, name: '当前歌曲'));
        await tester.pumpWidget(
          _wrap(page.value(), platforms: platforms, player: player),
        );
        await tester.pumpAndSettle();
        await tester.tap(_platformChip(PlatformType.qq));
        await tester.pumpAndSettle();
        final secondRow = find.widgetWithText(IkSongTableRow, 'qq-歌曲2');
        await tester.tap(
          find.descendant(of: secondRow, matching: find.byTooltip('更多')),
        );
        await tester.pumpAndSettle();
        expect(find.text('下一首播放'), findsOneWidget);
        await tester.tap(find.text('下一首播放'));
        await tester.pump();
        expect(player.state.playlist.map((s) => s.id), ['current', 'qq-2']);
        expect(player.state.currentSong?.id, 'current');
        await tester.pump(const Duration(seconds: 5));
      });
    }
  });

  testWidgets('R09 三页全量浅深×六宽×三字号×数据/错误/空态×三平台体验', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final failures = <String>[];
    var views = 0;
    var platformCells = 0;
    for (final brightness in Brightness.values) {
      for (final width in [320.0, 390.0, 720.0, 900.0, 1200.0, 1440.0]) {
        for (final scale in [1.0, 1.25, 1.5]) {
          for (final state in ['数据', '错误', '空态']) {
            for (final page in {
              '新歌': _newSongs,
              '榜单': _toplists,
              '推荐': _recommendations,
            }.entries) {
              tester.view.physicalSize = Size(width, 960);
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pumpAndSettle();
              await tester.pumpWidget(
                _wrap(
                  page.value(),
                  platforms: _fixtures(state: state),
                  brightness: brightness,
                  scale: scale,
                ),
              );
              await tester.pumpAndSettle();
              views++;
              for (final platform in PlatformType.musicServices) {
                final cell =
                    '${page.key}/$state/${brightness.name}/$width/$scale/${platform.name}';
                platformCells++;
                final chip = _platformChip(platform);
                if (chip.evaluate().length != 1) {
                  failures.add('$cell 平台入口缺失或重复');
                } else {
                  await tester.tap(chip);
                  await tester.pumpAndSettle();
                  if (!tester.widget<ChoiceChip>(chip).selected) {
                    failures.add('$cell 选中状态缺失');
                  }
                  final rect = tester.getRect(chip);
                  if (rect.left < 0 ||
                      rect.right > width ||
                      rect.bottom > 960) {
                    failures.add('$cell 平台入口超出视口');
                  }
                }
                final exception = tester.takeException();
                if (exception != null) failures.add('$cell $exception');
                if (state == '数据' && page.key != '榜单') {
                  if (find.byType(IkSongTableRow).evaluate().length != 3) {
                    failures.add('$cell 未使用完整三行歌曲表格');
                  }
                  if (find.byTooltip('更多').evaluate().length != 3) {
                    failures.add('$cell 更多操作不可达');
                  } else {
                    await tester.ensureVisible(find.byTooltip('更多').last);
                    await tester.pumpAndSettle();
                    final rect = tester.getRect(find.byTooltip('更多').last);
                    if (rect.left < 0 ||
                        rect.right > width ||
                        rect.bottom > 960) {
                      failures.add('$cell 最后一行更多操作无法滚入视口');
                    }
                  }
                }
                if (state == '错误' &&
                    find
                            .widgetWithText(ElevatedButton, '重试')
                            .evaluate()
                            .length !=
                        1) {
                  failures.add('$cell 失败重试不可达');
                }
              }
            }
          }
        }
      }
    }
    debugPrint(
      'R09 完整运行：$views 个视图，$platformCells 个平台单元，${failures.length} 项失败。',
    );
    expect(views, 324, reason: '全部页面、主题、宽度、字号和状态均执行，不抽样');
    expect(platformCells, 972, reason: '每个视图遍历全部三个平台');
    // 汇总后才判失败，红门也完整执行矩阵，不能首个失败后静默停止覆盖。
    expect(failures, isEmpty, reason: failures.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 10)));

  testWidgets('兼容：三页缺省与显式关闭保持既有呈现', (tester) async {
    for (final page in {
      '新歌': _newSongs,
      '榜单': _toplists,
      '推荐': _recommendations,
    }.entries) {
      final snapshots = <List<String>>[];
      for (final aligned in [null, false]) {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        final original = switch (page.key) {
          '新歌' => const NewSongsPage(),
          '榜单' => const ToplistsPage(),
          _ => const RecommendationsPage(),
        };
        await tester.pumpWidget(
          _wrap(aligned == null ? original : page.value(aligned: false)),
        );
        await tester.pumpAndSettle();
        snapshots.add(
          tester
              .widgetList<Text>(find.byType(Text))
              .map((t) => t.data ?? '')
              .toList(),
        );
        expect(find.byType(IkSongTableRow), findsNothing);
        for (final platform in PlatformType.musicServices) {
          expect(_platformChip(platform), findsNothing);
        }
      }
      expect(
        snapshots[1],
        snapshots[0],
        reason: '${page.key}显式false不得改变缺省可见文本',
      );
    }
  });
}

Finder _platformChip(PlatformType platform) =>
    find.widgetWithText(ChoiceChip, platform.displayName);

void _expectPlatformChips(WidgetTester tester, PlatformType selected) {
  for (final platform in PlatformType.musicServices) {
    expect(
      _platformChip(platform),
      findsOneWidget,
      reason: '${platform.displayName}入口必须保留',
    );
    expect(
      tester.widget<ChoiceChip>(_platformChip(platform)).selected,
      platform == selected,
    );
  }
}

Widget _wrap(
  Widget page, {
  List<_FixturePlatform>? platforms,
  Set<PlatformType> loggedIn = const {},
  PlayerNotifier? player,
  GoRouter? router,
  Brightness brightness = Brightness.light,
  double scale = 1,
}) {
  final implementations = platforms ?? _fixtures();
  for (final platform in implementations) {
    registerFake(platform);
  }
  final byType = {for (final p in implementations) p.type: p};
  final types = implementations.map((p) => p.type).toList();
  final theme = IkWorkspaceTheme.from(
    brightness == Brightness.light ? VideoTheme.light : VideoTheme.dark,
  );
  return ProviderScope(
    overrides: [
      authProvider.overrideWith((_) => _FixtureAuth(loggedIn)),
      playerProvider.overrideWith(
        (_) =>
            player ??
            PlayerNotifier(
              audioController: IdleAudioController(),
              platformResolver: (type) => byType[type]!,
            ),
      ),
      newSongsProvider.overrideWith(
        (_) => NewSongsNotifier(
          supportedTypes: types,
          platformResolver: (type) => byType[type]!,
        ),
      ),
      toplistsProvider.overrideWith(
        (_) => ToplistsNotifier(
          supportedTypes: types,
          platformResolver: (type) => byType[type]!,
        ),
      ),
      recommendationsProvider.overrideWith(
        (_) => RecommendationsNotifier(
          supportedTypes: types,
          platformResolver: (type) => byType[type]!,
        ),
      ),
    ],
    child: router == null
        ? MaterialApp(
            theme: theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: page,
          )
        : MaterialApp.router(theme: theme, routerConfig: router),
  );
}

List<_FixturePlatform> _fixtures({String state = '数据'}) => [
  for (final platform in PlatformType.musicServices)
    _FixturePlatform(
      type: platform,
      newSongs: state == '数据' ? _songs(platform) : const [],
      newSongsError: state == '错误' ? NetworkException() : null,
      toplists: state == '数据'
          ? [
              if (platform == PlatformType.qq)
                const Toplist(id: '26', name: '热歌榜', songCount: 300),
              Toplist(
                id: '${platform.name}-chart',
                name: '${platform.name}-榜单',
                groupName: '热门榜单',
              ),
            ]
          : const [],
      toplistsError: state == '错误' ? Exception('榜单加载失败，请稍后重试') : null,
      recommendations: RecommendationResult(
        songs: state == '数据' ? _songs(platform) : const [],
        error: state == '错误' ? '推荐加载失败，请稍后重试' : null,
        source: state == '数据' ? _source(platform) : null,
      ),
    ),
];

List<Song> _songs(PlatformType platform) => [
  for (var i = 1; i <= 3; i++)
    song('${platform.name}-$i', platform, name: '${platform.name}-歌曲$i'),
];

RecommendationSource _source(PlatformType platform) => RecommendationSource(
  platform: platform,
  kind: switch (platform) {
    PlatformType.qq => RecommendationKind.fallbackToplist,
    PlatformType.kugou => RecommendationKind.fallbackHomepage,
    _ => RecommendationKind.personalizedDaily,
  },
  label: platform == PlatformType.netease
      ? '每日推荐'
      : '${platform.displayName}推荐',
  note: switch (platform) {
    PlatformType.qq => '未登录，已回退到新歌榜',
    PlatformType.kugou => '官方推荐接口已不可用，来源为首页推荐',
    _ => null,
  },
);

class _FixturePlatform extends FakeContentPlatform {
  _FixturePlatform({
    required super.type,
    super.newSongs,
    super.newSongsError,
    super.toplists,
    super.toplistsError,
    super.supportsNewSongsFlag,
    super.loggedIn,
    this.recommendations = const RecommendationResult(),
  });
  RecommendationResult recommendations;
  int recommendationLoads = 0;
  int toplistLoads = 0;
  @override
  bool get supportsDailyRecommendations => true;
  @override
  Future<RecommendationResult> getDailyRecommendation() async {
    recommendationLoads++;
    return recommendations;
  }

  @override
  Future<List<Toplist>> getToplists() async {
    toplistLoads++;
    return super.getToplists();
  }
}

class _FixtureAuth extends AuthNotifier {
  _FixtureAuth(Set<PlatformType> loggedIn) {
    state = AuthState(
      loggedUsers: {
        for (final platform in loggedIn)
          platform: User(
            id: 'session-${platform.name}',
            nickname: '验收账号',
            platform: platform,
          ),
      },
    );
  }
}

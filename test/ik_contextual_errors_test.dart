import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/floating_lyrics/data/floating_lyrics_models.dart';
import 'package:mconnect/features/floating_lyrics/presentation/providers/floating_lyrics_provider.dart';
import 'package:mconnect/features/library/presentation/providers/likes_provider.dart';
import 'package:mconnect/features/player/data/playback_keep_alive_service.dart';
import 'package:mconnect/features/player/data/playback_notification_service.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/video_app/data/video_catalog.dart';
import 'package:mconnect/video_app/ik/ik_library_workspace.dart';
import 'package:mconnect/video_app/ik/ik_playback_bar.dart';
import 'package:mconnect/video_app/ik/ik_workspace_theme.dart';
import 'package:mconnect/video_app/ui/catalog_pages.dart';
import 'package:mconnect/video_app/ui/video_theme.dart';

import 'support/content_page_fakes.dart' show IdleAudioController;

const _reset = '播放未能恢复，已重置播放器，请重试';
const _retryLabel = '重新同步';
const _accountLabel = '连接账号';
const _replayLabel = '重新播放';
const _playerIssueKey = ValueKey('ik-playback-error');
const _playerReasonKey = ValueKey('ik-playback-error-reason');
const _playerReasonScrollKey = ValueKey('ik-playback-error-reason-scroll');
const _track = Song(
  id: 'contextual-track',
  name: '仍然保留的当前歌曲',
  platform: PlatformType.qq,
  artists: [],
  duration: Duration(minutes: 3),
);
const _localTrack = Song(
  id: 'contextual-local',
  name: '仍然保留的本地收藏',
  platform: PlatformType.local,
  artists: [],
);
const _errorKinds = {
  VideoFailureKind.notLoggedIn: '尚未登录账号',
  VideoFailureKind.sessionExpired: '登录信息已失效',
  VideoFailureKind.permission: '当前账号没有访问权限',
  VideoFailureKind.network: '网络连接失败',
  VideoFailureKind.unavailable: '内容不存在或已被删除',
  VideoFailureKind.storageFull: '存储空间不足',
  VideoFailureKind.storagePermission: '没有存储访问权限',
  VideoFailureKind.invalidResponse: '平台返回的数据无法读取',
  VideoFailureKind.incomplete: '平台只返回了部分收藏',
  VideoFailureKind.cancelled: '请求已取消',
  VideoFailureKind.unknown: '尚未确认原因的错误',
};

Finder _libraryIssue(PlatformType platform) =>
    find.byKey(ValueKey('ik-library-error-${platform.name}'));

Finder _expiredIssue(PlatformType platform) =>
    find.byKey(ValueKey('ik-library-expired-${platform.name}'));

Finder _textInside(Finder parent, String text) =>
    find.descendant(of: parent, matching: find.text(text));

Finder _buttonInside(Finder parent, String text) => find.descendant(
  of: parent,
  matching: find.widgetWithText(TextButton, text),
);

bool _needsAccount(VideoFailureKind kind) =>
    kind == VideoFailureKind.notLoggedIn ||
    kind == VideoFailureKind.sessionExpired;

Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  _Player? player,
  double width = 1200,
  double scale = 1,
  bool dark = false,
}) async {
  tester.view.physicalSize = Size(width, 960);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        playerProvider.overrideWith((ref) => player ?? _Player()),
        likesProvider.overrideWith((ref) => _Likes()),
        floatingLyricsProvider.overrideWith((ref) => _FloatingLyrics()),
      ],
      child: MaterialApp(
        theme: IkWorkspaceTheme.from(dark ? VideoTheme.dark : VideoTheme.light),
        builder: (context, content) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: content!,
        ),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

Widget _bar({bool? enabled = true, bool aligned = true}) => Align(
  alignment: Alignment.bottomCenter,
  child: !aligned
      ? IkPlaybackBar(onOpen: () {}, onAudio: () {})
      : enabled == null
      ? IkPlaybackBar.aligned(onOpen: () {}, onAudio: () {})
      : IkPlaybackBar.aligned(
          contextualErrors: enabled,
          onOpen: () {},
          onAudio: () {},
        ),
);

void _expectFullText(WidgetTester tester, Finder finder, String reason) {
  expect(finder, findsOneWidget);
  final text = tester.widget<Text>(finder);
  expect(text.data, reason);
  expect(text.maxLines, isNull);
  expect(text.overflow, isNot(TextOverflow.ellipsis));
  expect(tester.getSemantics(finder).label, contains(reason));
}

Rect _tailRect(WidgetTester tester, Finder finder, String text) {
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: text.length - 8, extentOffset: text.length),
  );
  expect(boxes, isNotEmpty);
  return boxes.last.toRect().shift(tester.getTopLeft(finder));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('E07 错误枚举场景表完整不遗漏', () {
    expect(_errorKinds.keys, unorderedEquals(VideoFailureKind.values));
  });

  for (final platform in PlatformType.musicServices) {
    for (final entry in _errorKinds.entries) {
      for (final canRetry in [false, true]) {
        testWidgets(
          'E07 ${platform.name} ${entry.key.name} retry=$canRetry 标明同步并保留真实原因',
          (tester) async {
            final semantics = tester.ensureSemantics();
            try {
              final fixture = _Library(
                libraries: {
                  platform: VideoLibrary(
                    songs: [_platformTrack(platform)],
                    error: VideoFailure(
                      entry.key,
                      entry.value,
                      canRetry: canRetry,
                    ),
                  ),
                },
                loggedIn: {platform},
              );
              await _mount(tester, fixture.widget());
              final issue = _libraryIssue(platform);
              expect(issue, findsOneWidget);
              expect(
                _textInside(issue, '${videoPlatformLabel(platform)}收藏同步失败'),
                findsOneWidget,
              );
              _expectFullText(
                tester,
                _textInside(issue, entry.value),
                entry.value,
              );
              expect(find.text(_localTrack.name), findsOneWidget);
              expect(find.text(_platformTrack(platform).name), findsOneWidget);
              final account = _buttonInside(issue, _accountLabel);
              final retry = _buttonInside(issue, _retryLabel);
              expect(
                account,
                _needsAccount(entry.key) ? findsOneWidget : findsNothing,
              );
              expect(
                retry,
                !_needsAccount(entry.key) && canRetry
                    ? findsOneWidget
                    : findsNothing,
              );
              if (_needsAccount(entry.key)) {
                expect(tester.widget<TextButton>(account).onPressed, isNotNull);
                await tester.tap(account);
                expect(fixture.accounts, 1);
                expect(fixture.syncs, isEmpty);
              } else if (canRetry) {
                expect(tester.widget<TextButton>(retry).onPressed, isNotNull);
                await tester.tap(retry);
                expect(fixture.syncs, [platform]);
                expect(fixture.accounts, 0);
              } else {
                expect(fixture.accounts, 0);
                expect(fixture.syncs, isEmpty);
              }
              expect(fixture.localRetries, 0);
              expect(tester.takeException(), isNull);
            } finally {
              semantics.dispose();
            }
          },
        );
      }
    }
  }

  for (final entry in _errorKinds.entries) {
    for (final canRetry in [false, true]) {
      testWidgets('E07 同步中${entry.key.name} retry=$canRetry 不重复进入动作', (
        tester,
      ) async {
        final fixture = _Library(
          libraries: {
            PlatformType.kugou: VideoLibrary(
              error: VideoFailure(entry.key, entry.value, canRetry: canRetry),
            ),
          },
          loggedIn: {PlatformType.kugou},
          syncing: {PlatformType.kugou},
        );
        await _mount(tester, fixture.widget());
        final issue = _libraryIssue(PlatformType.kugou);
        expect(issue, findsOneWidget);
        expect(_textInside(issue, entry.value), findsOneWidget);
        final action = _buttonInside(
          issue,
          _needsAccount(entry.key) ? _accountLabel : _retryLabel,
        );
        if (_needsAccount(entry.key) || canRetry) {
          expect(action, findsOneWidget);
          expect(tester.widget<TextButton>(action).onPressed, isNull);
          await tester.tap(action);
          await tester.pump();
        } else {
          expect(action, findsNothing);
        }
        expect(fixture.accounts, 0);
        expect(fixture.syncs, isEmpty);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final platform in PlatformType.musicServices) {
    for (final reconnected in [false, true]) {
      testWidgets('E07 ${platform.name}失效记录 reconnected=$reconnected 只引导当前账号', (
        tester,
      ) async {
        final fixture = _Library(
          expiredPlatform: platform,
          loggedIn: reconnected ? {platform} : {},
          libraries: {
            platform: VideoLibrary(songs: [_platformTrack(platform)]),
          },
        );
        await _mount(tester, fixture.widget());
        final issue = _expiredIssue(platform);
        expect(issue, reconnected ? findsNothing : findsOneWidget);
        expect(
          find.text(_platformTrack(platform).name),
          reconnected ? findsOneWidget : findsNothing,
        );
        expect(find.text(_localTrack.name), findsOneWidget);
        if (!reconnected) {
          expect(
            _textInside(issue, '${videoPlatformLabel(platform)}收藏同步需要重新连接账号'),
            findsOneWidget,
          );
          expect(_buttonInside(issue, _retryLabel), findsNothing);
          await tester.tap(_buttonInside(issue, _accountLabel));
          expect(fixture.accounts, 1);
          expect(fixture.syncs, isEmpty);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('E07 local不是账号平台，失效参数不造连接提示', (tester) async {
    final fixture = _Library(expiredPlatform: PlatformType.local);
    await _mount(tester, fixture.widget());
    for (final platform in PlatformType.values) {
      expect(_expiredIssue(platform), findsNothing);
    }
    expect(find.text(_localTrack.name), findsOneWidget);
    expect(fixture.accounts, 0);
    expect(tester.takeException(), isNull);
  });

  for (final enabled in <bool?>[null, false]) {
    testWidgets('E07 音乐库contextualErrors=$enabled 保持原错误与默认动作', (tester) async {
      final fixture = _Library(
        libraries: const {
          PlatformType.kugou: VideoLibrary(
            error: VideoFailure(VideoFailureKind.unavailable, '内容不存在或已被删除'),
          ),
        },
        loggedIn: {PlatformType.kugou},
        expiredPlatform: PlatformType.qq,
      );
      await _mount(tester, fixture.widget(enabled: enabled));
      expect(find.text('酷狗 · 内容不存在或已被删除'), findsOneWidget);
      expect(_libraryIssue(PlatformType.kugou), findsNothing);
      expect(_expiredIssue(PlatformType.qq), findsNothing);
      expect(find.text(_retryLabel), findsNothing);
      expect(fixture.accounts, 0);
      expect(fixture.syncs, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('E07 本地收藏读取失败维持原动作，不混称平台同步失败', (tester) async {
    final fixture = _Library(localError: '本地收藏读取失败');
    await _mount(tester, fixture.widget());
    expect(find.text('本地收藏读取失败'), findsOneWidget);
    for (final platform in PlatformType.values) {
      expect(_libraryIssue(platform), findsNothing);
    }
    await tester.tap(find.widgetWithText(TextButton, '重试'));
    expect(fixture.localRetries, 1);
    expect(fixture.accounts, 0);
    expect(fixture.syncs, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final hasSong in [false, true]) {
    for (final transitioning in [false, true]) {
      for (final playing in [false, true]) {
        testWidgets(
          'E07 重置song=$hasSong transitioning=$transitioning playing=$playing 只显式重播同曲',
          (tester) async {
            final semantics = tester.ensureSemantics();
            try {
              final player = _Player(
                PlayerState(
                  currentSong: hasSong ? _track : null,
                  error: _reset,
                  isPlaying: playing,
                  isTransitioning: transitioning,
                ),
              );
              await _mount(tester, _bar(), player: player);
              expect(find.byKey(_playerIssueKey), findsOneWidget);
              expect(find.text('播放恢复未完成'), findsOneWidget);
              _expectFullText(tester, find.byKey(_playerReasonKey), _reset);
              expect(player.replays, isEmpty);
              expect(player.toggles, 0);
              final replay = _buttonInside(
                find.byKey(_playerIssueKey),
                _replayLabel,
              );
              if (!hasSong) {
                expect(replay, findsNothing);
              } else {
                expect(replay, findsOneWidget);
                expect(
                  tester.widget<TextButton>(replay).onPressed,
                  transitioning ? isNull : isNotNull,
                );
                await tester.tap(replay);
                await tester.pump();
                if (transitioning) {
                  expect(player.replays, isEmpty);
                } else {
                  expect(player.replays, hasLength(1));
                  expect(player.replays.single, same(_track));
                  expect(tester.widget<TextButton>(replay).onPressed, isNull);
                  await tester.tap(replay);
                  expect(player.replays, hasLength(1));
                }
              }
              expect(player.toggles, 0);
              expect(player.skips, 0);
              expect(tester.takeException(), isNull);
            } finally {
              semantics.dispose();
            }
          },
        );
      }
    }
  }

  for (final reason in [
    '播放超时，请稍后重试',
    'Playback is taking longer than expected.',
    '当前账号无此音质权限',
    '当前歌曲不可播放，已跳到下一首',
    '$_reset（第三方返回）',
    '来源返回：$_reset',
  ]) {
    for (final playing in [false, true]) {
      testWidgets('E07 其他错误playing=$playing 保持中性且不猜原因 $reason', (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          final player = _Player(
            PlayerState(currentSong: _track, error: reason, isPlaying: playing),
          );
          await _mount(tester, _bar(), player: player);
          expect(find.text('播放提示'), findsOneWidget);
          expect(find.text('播放恢复未完成'), findsNothing);
          expect(find.text('这首歌暂时无法播放'), findsNothing);
          _expectFullText(tester, find.byKey(_playerReasonKey), reason);
          expect(find.text(_replayLabel), findsNothing);
          expect(player.replays, isEmpty);
          expect(player.toggles, 0);
          expect(player.state.isPlaying, playing);
          expect(player.state.currentSong, same(_track));
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      });
    }
  }

  for (final error in <String?>[null, '']) {
    testWidgets('E07 播放错误为${error == null ? 'null' : '空串'}时不造提示', (
      tester,
    ) async {
      final player = _Player(PlayerState(currentSong: _track, error: error));
      await _mount(tester, _bar(), player: player);
      expect(find.byKey(_playerIssueKey), findsNothing);
      expect(find.text(_replayLabel), findsNothing);
      expect(player.replays, isEmpty);
      expect(player.toggles, 0);
      expect(tester.takeException(), isNull);
    });
  }

  for (final config in <(bool, bool?)>[
    (false, null),
    (true, null),
    (true, false),
  ]) {
    testWidgets('E07 播放条aligned=${config.$1} contextual=${config.$2}旧默认保持', (
      tester,
    ) async {
      final player = _Player(
        const PlayerState(currentSong: _track, error: _reset),
      );
      await _mount(
        tester,
        _bar(aligned: config.$1, enabled: config.$2),
        player: player,
      );
      final text = tester.widget<Text>(find.text(_reset));
      expect(text.maxLines, 2);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(find.byKey(_playerIssueKey), findsNothing);
      expect(find.text('播放恢复未完成'), findsNothing);
      expect(find.text(_replayLabel), findsNothing);
      expect(player.replays, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  final longReason = List.filled(
    18,
    '平台返回了完整但较长的失败说明，需要保留原因供用户判断，不能据此删除收藏或宣称歌曲永久失效。',
  ).join('\n');
  for (final width in [320.0, 390.0, 720.0, 900.0, 1200.0, 1440.0, 1920.0]) {
    for (final scale in [1.0, 1.25, 1.5]) {
      for (final dark in [false, true]) {
        testWidgets('E07 库完整尺寸$width/$scale/dark=$dark 长原因可读且动作可达', (
          tester,
        ) async {
          final semantics = tester.ensureSemantics();
          try {
            final fixture = _Library(
              libraries: {
                PlatformType.kugou: VideoLibrary(
                  songs: [_platformTrack(PlatformType.kugou)],
                  error: VideoFailure(
                    VideoFailureKind.network,
                    longReason,
                    canRetry: true,
                  ),
                ),
              },
              loggedIn: {PlatformType.kugou},
            );
            await _mount(
              tester,
              fixture.widget(),
              width: width,
              scale: scale,
              dark: dark,
            );
            final issue = _libraryIssue(PlatformType.kugou);
            expect(issue, findsOneWidget);
            final reason = _textInside(issue, longReason);
            final retry = _buttonInside(issue, _retryLabel);
            _expectFullText(tester, reason, longReason);
            await tester.ensureVisible(retry);
            await tester.pumpAndSettle();
            expect(retry.hitTestable(), findsOneWidget);
            final tail = _tailRect(tester, reason, longReason);
            expect(tail.top, greaterThanOrEqualTo(0));
            expect(tail.bottom, lessThanOrEqualTo(960));
            await tester.tap(retry);
            expect(fixture.syncs, [PlatformType.kugou]);
            expect(fixture.accounts, 0);
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        });

        testWidgets('E07 播放条完整尺寸$width/$scale/dark=$dark 长原因原位滚动可读', (
          tester,
        ) async {
          final semantics = tester.ensureSemantics();
          try {
            final player = _Player(
              PlayerState(currentSong: _track, error: longReason),
            );
            await _mount(
              tester,
              _bar(),
              player: player,
              width: width,
              scale: scale,
              dark: dark,
            );
            expect(find.text('播放提示'), findsOneWidget);
            final reason = find.byKey(_playerReasonKey);
            _expectFullText(tester, reason, longReason);
            final scroll = find.byKey(_playerReasonScrollKey);
            expect(scroll.hitTestable(), findsOneWidget);
            await tester.drag(scroll, const Offset(0, -5000));
            await tester.pumpAndSettle();
            final clip = tester.getRect(scroll);
            final tail = _tailRect(tester, reason, longReason);
            expect(tail.top, greaterThanOrEqualTo(clip.top - 1));
            expect(tail.bottom, lessThanOrEqualTo(clip.bottom + 1));
            expect(
              tester.getRect(find.byType(IkPlaybackBar)).height,
              lessThan(700),
            );
            expect(find.byTooltip('播放').hitTestable(), findsOneWidget);
            expect(find.text(_replayLabel), findsNothing);
            expect(player.replays, isEmpty);
            expect(player.toggles, 0);
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        });
      }
    }
  }
}

Song _platformTrack(PlatformType platform) => Song(
  id: 'partial-${platform.name}',
  name: '${platform.name}已经取得的收藏',
  platform: platform,
  artists: const [],
);

class _Library {
  _Library({
    this.libraries = const {},
    this.loggedIn = const {},
    this.syncing = const {},
    this.expiredPlatform,
    this.localError,
  });

  final Map<PlatformType, VideoLibrary> libraries;
  final Set<PlatformType> loggedIn, syncing;
  final PlatformType? expiredPlatform;
  final String? localError;
  final syncs = <PlatformType>[];
  int accounts = 0;
  int localRetries = 0;

  IkLibraryWorkspace widget({bool? enabled = true}) {
    if (enabled == null) {
      return IkLibraryWorkspace(
        alignToDesign: true,
        stableCategoryTabs: true,
        libraries: libraries,
        loggedIn: loggedIn,
        syncing: syncing,
        expiredPlatform: expiredPlatform,
        localLikes: const [_localTrack],
        localLoading: false,
        localError: localError,
        onSync: syncs.add,
        onPlay: (_, _) {},
        onMore: (_) {},
        onNavigate: (_) {},
        onDownloads: () {},
        onAccounts: () => accounts++,
        onRetryLocal: () => localRetries++,
      );
    }
    return IkLibraryWorkspace(
      alignToDesign: true,
      stableCategoryTabs: true,
      contextualErrors: enabled,
      expiredPlatform: expiredPlatform,
      libraries: libraries,
      loggedIn: loggedIn,
      syncing: syncing,
      localLikes: const [_localTrack],
      localLoading: false,
      localError: localError,
      onSync: syncs.add,
      onPlay: (_, _) {},
      onMore: (_) {},
      onNavigate: (_) {},
      onDownloads: () {},
      onAccounts: () => accounts++,
      onRetryLocal: () => localRetries++,
    );
  }
}

// 只替代未参与本门的收藏/歌词服务，不触数据库、Hive或原生插件。
class _Likes extends StateNotifier<LikesState> implements LikesNotifier {
  _Likes() : super(const LikesState());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FloatingLyrics extends StateNotifier<FloatingLyricsSettings>
    implements FloatingLyricsNotifier {
  _FloatingLyrics() : super(const FloatingLyricsSettings());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Player extends PlayerNotifier {
  _Player([PlayerState initial = const PlayerState()])
    : super(
        audioController: IdleAudioController(),
        audioControllerFactory: IdleAudioController.new,
        keepAliveController: const NoopPlaybackKeepAliveController(),
        notificationController: const NoopPlaybackNotificationController(),
        stuckWatchdogInterval: Duration.zero,
        playbackHealthCheckInterval: Duration.zero,
        playbackMemorySaveInterval: Duration.zero,
      ) {
    state = initial;
  }

  final replays = <Song>[];
  int toggles = 0;
  int skips = 0;

  @override
  Future<void> playSong(Song song) async {
    replays.add(song);
    state = state.copyWith(isTransitioning: true);
  }

  @override
  Future<void> togglePlay() async => toggles++;

  @override
  Future<void> skipToNext() async => skips++;
}

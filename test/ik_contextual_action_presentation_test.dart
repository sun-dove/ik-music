import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/share/song_actions.dart';
import 'package:mconnect/core/theme/app_theme.dart';
import 'package:mconnect/core/widgets/song_actions_sheet.dart';
import 'package:mconnect/features/artist/presentation/pages/artist_page.dart';
import 'package:mconnect/features/download/data/download_task_store.dart';
import 'package:mconnect/features/download/domain/entities/download_task.dart';
import 'package:mconnect/features/download/presentation/providers/download_provider.dart';
import 'package:mconnect/features/download/presentation/widgets/download_button.dart';
import 'package:mconnect/features/library/data/my_playlists_repository.dart';
import 'package:mconnect/features/library/presentation/pages/playlist_detail_page.dart';
import 'package:mconnect/features/library/presentation/providers/my_playlists_provider.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/playlist.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/models/user.dart';
import 'package:mconnect/platform/base/platform_registry.dart';
import 'package:mconnect/video_app/ik/ik_workspace_theme.dart';

import 'support/content_page_fakes.dart';

/// 正式验收门 R07/R09，见中文修订票据。
/// 无标记的共享默认、原动作值和取消保持；IK 显式标记才启用菜单/居中选择。
/// 四类真实入口各遍历浅深 × 六宽度 × 三字号，共 144 个体验组合，不抽样。
/// 仅显式设置截图目录时输出正式渲染证据，普通 CI 不写额外文件。
void main() {
  final captureFont = Platform.environment['IK_CAPTURE_UI_FONT'];
  if (captureFont != null && captureFont.isNotEmpty) {
    _ReadableCaptureBinding();
  } else {
    TestWidgetsFlutterBinding.ensureInitialized();
  }

  setUpAll(() async {
    if (captureFont == null || captureFont.isEmpty) return;
    final data = ByteData.sublistView(await File(captureFont).readAsBytes());
    for (final family in [
      'sans-serif',
      'Roboto',
      'Microsoft YaHei UI',
      'Ahem',
    ]) {
      await (FontLoader(family)..addFont(Future.value(data))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  setUp(() {
    PlatformRegistry.register(FakeContentPlatform(type: PlatformType.qq));
    PlatformRegistry.register(FakeContentPlatform(type: PlatformType.netease));
  });

  testWidgets('R07 无标记与关闭标记保持原底部菜单和全部动作值', (tester) async {
    for (final enabled in [null, false]) {
      for (final action in SongAction.values) {
        final fixture = _Fixture(enabled: enabled);
        await fixture.open(tester, _Surface.menu);
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(_menuEntries(), findsNothing);
        await tester.ensureVisible(find.text(_labels[action]!));
        await tester.tap(find.text(_labels[action]!));
        await tester.pumpAndSettle();
        expect(fixture.selectedAction, action);
        expect(find.byKey(_pageKey), findsOneWidget);
      }
    }
  });

  testWidgets('R07 IK 歌曲菜单返回全部原动作并保留当前页面', (tester) async {
    for (final action in SongAction.values) {
      final fixture = _Fixture();
      await fixture.open(tester, _Surface.menu);
      expect(find.byType(BottomSheet), findsNothing);
      expect(_menuEntries(), findsNWidgets(SongAction.values.length));
      await tester.ensureVisible(find.text(_labels[action]!));
      await tester.tap(find.text(_labels[action]!));
      await tester.pumpAndSettle();
      expect(fixture.selectedAction, action);
      expect(find.byKey(_pageKey), findsOneWidget);
    }
  });

  testWidgets('R07 IK 本地歌曲隐藏网络动作且已下载选项仍禁用', (tester) async {
    final local = _Fixture(isLocal: true);
    await local.open(tester, _Surface.menu);
    expect(_menuEntries(), findsNWidgets(2));
    expect(find.text('下一首播放'), findsOneWidget);
    expect(find.text('复制链接'), findsOneWidget);
    for (final label in ['添加到歌单', '下载', '喜欢', '分享']) {
      expect(find.text(label), findsNothing);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(local.selectedAction, isNull);

    final downloaded = _Fixture(isDownloaded: true);
    await downloaded.open(tester, _Surface.menu);
    final disabled = tester.widget<PopupMenuItem<SongAction>>(
      find.byWidgetPredicate(
        (widget) =>
            widget is PopupMenuItem<SongAction> &&
            widget.value == SongAction.download,
      ),
    );
    expect(disabled.enabled, isFalse);
    await tester.tap(find.text('已下载'));
    await tester.pumpAndSettle();
    expect(_menuEntries(), findsNWidgets(SongAction.values.length));
    expect(downloaded.selectedAction, isNull);
  });

  testWidgets('R07 IK 菜单在嵌套 Navigator 中取消只关闭菜单', (tester) async {
    final fixture = _Fixture(nested: true);
    await fixture.open(tester, _Surface.menu);
    expect(_menuEntries(), findsNWidgets(SongAction.values.length));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_menuEntries(), findsNothing);
    expect(fixture.selectedAction, isNull);
    expect(find.byKey(_pageKey), findsOneWidget);
    expect(find.byKey(_openKey), findsOneWidget);
  });

  testWidgets('R07 IK 菜单锚定实际更多按钮且键盘取消后可再次打开', (tester) async {
    for (final alignment in [
      Alignment.topLeft,
      Alignment.topRight,
      Alignment.bottomLeft,
      Alignment.bottomRight,
    ]) {
      final fixture = _Fixture(alignment: alignment);
      await fixture.open(tester, _Surface.menu, keyboard: true);
      expect(_menuEntries(), findsNWidgets(SongAction.values.length));
      final button = tester.getRect(find.byKey(_openKey));
      final first = tester.getRect(_menuEntries().first);
      final last = tester.getRect(_menuEntries().last);
      if (alignment.y < 0) {
        expect(first.top, greaterThanOrEqualTo(button.top));
        expect(first.top, lessThan(button.bottom + 144));
      } else {
        expect(last.bottom, closeTo(button.bottom, 24));
      }
      if (alignment.x < 0) {
        expect(first.left, closeTo(button.left, 8));
      } else {
        expect(first.right, closeTo(button.right, 8));
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(fixture.selectedAction, isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(_menuEntries(), findsNWidgets(SongAction.values.length));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    }
  });

  testWidgets('R07 无标记与关闭标记保持原歌单、音质和批量目标选择', (tester) async {
    for (final enabled in [null, false]) {
      for (final surface in [
        _Surface.playlist,
        _Surface.download,
        _Surface.batch,
      ]) {
        final fixture = _Fixture(enabled: enabled);
        await fixture.open(tester, surface);
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(find.byType(Dialog), findsNothing);
        await tester.tapAt(const Offset(4, 4));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        expect(fixture.downloads.started, isEmpty);
        expect(fixture.playlists.added, isEmpty);
      }
    }
  });

  testWidgets('R07 IK 添加到歌单居中且原目标平台只写一次', (tester) async {
    final platform = _PresentationPlatform(
      playlists: const [
        Playlist(id: 'qq-target', name: 'QQ 目标歌单', platform: PlatformType.qq),
      ],
    );
    final fixture = _Fixture(platform: platform, song: _networkSong);
    await fixture.open(tester, _Surface.playlist);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(Dialog), findsOneWidget);
    expect(_dragDecorations(), findsNothing);
    await tester.tap(find.text('QQ 目标歌单'));
    await tester.pumpAndSettle();
    expect(fixture.playlistAdded, isTrue);
    expect(platform.added, [('qq-target', _networkSong.id)]);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byKey(_pageKey), findsOneWidget);
  });

  testWidgets('R07 IK 歌单加载失败可重试且关闭仍返回 false', (tester) async {
    final platform = _PresentationPlatform()
      ..loadFailure = StateError('场景：平台歌单读取失败');
    final fixture = _Fixture(platform: platform, song: _networkSong);
    await fixture.open(tester, _Surface.playlist);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('加载歌单失败'), findsOneWidget);
    expect(platform.loadCalls, 1);
    platform.loadFailure = null;
    platform.playlists = const [
      Playlist(id: 'retry-target', name: '重试后的歌单', platform: PlatformType.qq),
    ];
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(platform.loadCalls, 2);
    expect(find.text('重试后的歌单'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(fixture.playlistAdded, isFalse);
    expect(platform.added, isEmpty);
    expect(find.byKey(_pageKey), findsOneWidget);
  });

  testWidgets('R07 IK 歌单添加超时恢复操作并在当前对话框显示错误', (tester) async {
    final platform = _PresentationPlatform(
      playlists: const [
        Playlist(id: 'pending', name: '等待添加的歌单', platform: PlatformType.qq),
      ],
    )..pendingAdd = Completer<bool>();
    final fixture = _Fixture(platform: platform, song: _networkSong);
    await fixture.open(tester, _Surface.playlist);
    expect(find.byType(Dialog), findsOneWidget);
    await tester.tap(find.text('等待添加的歌单'));
    await tester.pump();
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, '等待添加的歌单')).enabled,
      isFalse,
    );
    await tester.pump(const Duration(seconds: 9));
    await tester.pump();
    expect(find.text('添加失败或请求超时，请重试'), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, '等待添加的歌单')).enabled,
      isTrue,
    );
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(fixture.playlistAdded, isFalse);
    platform.pendingAdd!.complete(true);
    await tester.pump();
  });

  testWidgets('R07 IK 下载音质居中且选择原音质只提交一次', (tester) async {
    final fixture = _Fixture();
    await fixture.open(tester, _Surface.download);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(Dialog), findsOneWidget);
    expect(_dragDecorations(), findsNothing);
    await tester.scrollUntilVisible(
      find.text('SQ无损品质'),
      140,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('SQ无损品质'));
    await tester.pumpAndSettle();
    expect(fixture.downloads.started, [(_qqSong.id, AudioLevel.lossless)]);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byKey(_pageKey), findsOneWidget);
  });

  testWidgets('R07 IK 下载音质取消不提交且旧缺省仍有底部选择', (tester) async {
    final fixture = _Fixture();
    await fixture.open(tester, _Surface.download);
    expect(find.byType(Dialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(fixture.downloads.started, isEmpty);

    final legacy = _Fixture(enabled: null);
    await legacy.open(tester, _Surface.download);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(_dragDecorations(), findsOneWidget);
  });

  testWidgets('R07 IK 歌单批量目标居中并沿用原写入结果', (tester) async {
    final fixture = _Fixture();
    await fixture.open(tester, _Surface.batch);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(Dialog), findsOneWidget);
    expect(_dragDecorations(), findsNothing);
    await tester.tap(find.text('目标歌单 01'));
    await tester.pumpAndSettle();
    expect(fixture.playlists.added, [('target-1', _localSong.id)]);
    expect(find.text('已添加 1 首到「目标歌单 01」'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('R07 IK 歌单详情更多按钮精准展开且取消仍在详情', (tester) async {
    final fixture = _Fixture();
    await fixture.open(tester, _Surface.menu, detailMenu: true);
    expect(find.byType(BottomSheet), findsNothing);
    expect(_menuEntries(), findsNWidgets(2));
    final button = tester.getRect(find.byTooltip('歌曲操作'));
    final first = tester.getRect(_menuEntries().first);
    expect(first.top, greaterThanOrEqualTo(button.top));
    expect(first.top, lessThan(button.bottom + 144));
    expect(first.right, closeTo(button.right, 8));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_menuEntries(), findsNothing);
    expect(find.text('歌单详情'), findsOneWidget);
    expect(find.text(_localSong.name), findsOneWidget);
    expect(fixture.playlists.added, isEmpty);
  });

  testWidgets('R07 IK 小屏大字与输入占位下选择可滚动并可取消', (tester) async {
    for (final width in [320.0, 390.0]) {
      for (final dark in [false, true]) {
        for (final surface in [
          _Surface.playlist,
          _Surface.download,
          _Surface.batch,
        ]) {
          tester.view.physicalSize = Size(width, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final fixture = _Fixture(dark: dark, scale: 1.5, keyboardInset: 280);
          await fixture.open(tester, surface);
          expect(find.byType(Dialog), findsOneWidget);
          expect(tester.takeException(), isNull);
          final rect = tester.getRect(_dialogMaterial());
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(width));
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.bottom, lessThanOrEqualTo(360));
          await tester.scrollUntilVisible(
            find.text(surface == _Surface.download ? '臻品母带2.0' : '目标歌单 20'),
            140,
            scrollable: find.byType(Scrollable).last,
          );
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.byType(Dialog), findsNothing);
          expect(fixture.downloads.started, isEmpty);
          expect(fixture.playlists.added, isEmpty);
          expect(tester.takeException(), isNull);
        }
      }
    }
  });

  testWidgets('R07 IK 真实歌单状态刷新不在 Dialog 构建期通知页面', (tester) async {
    final repository = _ReadingPlaylistRepository();
    final notifier = MyPlaylistsNotifier(repository: repository);
    bool? result;
    final base = IkWorkspaceTheme.from(AppTheme.light());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [myPlaylistsProvider.overrideWith((_) => notifier)],
        child: MaterialApp(
          theme: base.copyWith(
            extensions: [
              ...base.extensions.values,
              const ContextualActionTheme(enabled: true),
            ],
          ),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => Column(
                children: [
                  Text(
                    '后台歌单 ${ref.watch(myPlaylistsProvider).playlists.length}',
                  ),
                  IconButton(
                    key: _openKey,
                    onPressed: () async {
                      result = await liveSongActionDeps(
                        ref,
                        context: context,
                      ).pickPlaylist(_localSong);
                    },
                    icon: const Icon(Icons.more_horiz),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.readCalls, 1);
    await tester.tap(find.byKey(_openKey));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(repository.readCalls, 2);
    expect(find.text('真实状态目标'), findsOneWidget);
    expect(find.text('后台歌单 1'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(repository.addCalls, 0);
    expect(find.byKey(_openKey), findsOneWidget);
  });

  testWidgets('R07 IK 歌手页长按锚定目标歌曲行且取消仍在歌手页', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final downloads = _RecordingDownloads();
    await _pumpArtistPage(tester, downloads: downloads);
    for (final song in _artistSongs) {
      final row = find.widgetWithText(ListTile, song.name);
      final rowRect = tester.getRect(row);
      await tester.longPress(row);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(_menuEntries(), findsNWidgets(SongAction.values.length));
      final header = find.byWidgetPredicate(
        (widget) => widget is PopupMenuItem<SongAction> && widget.value == null,
      );
      expect(
        find.descendant(of: header, matching: find.text(song.name)),
        findsOneWidget,
      );
      final headerRect = tester.getRect(header);
      expect(
        headerRect.top,
        inInclusiveRange(rowRect.bottom, rowRect.bottom + 16),
        reason: '菜单应锚定当前歌曲行底边，不能使用整页底边',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_menuEntries(), findsNothing);
      expect(find.byType(ArtistPage), findsOneWidget);
      expect(find.widgetWithText(ListTile, song.name), findsOneWidget);
      expect(downloads.started, isEmpty);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('R07 无标记与关闭标记保持歌手页原底部菜单', (tester) async {
    for (final enabled in [null, false]) {
      final downloads = _RecordingDownloads();
      await _pumpArtistPage(tester, downloads: downloads, enabled: enabled);
      for (final song in _artistSongs) {
        final row = find.widgetWithText(ListTile, song.name);
        await tester.ensureVisible(row);
        await tester.longPress(row);
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(_menuEntries(), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.byType(ArtistPage), findsOneWidget);
        expect(downloads.started, isEmpty);
        expect(tester.takeException(), isNull);
      }
    }
  });

  for (final surface in _Surface.values) {
    for (final dark in [false, true]) {
      for (final width in [320.0, 390.0, 720.0, 900.0, 1200.0, 1440.0]) {
        for (final scale in [1.0, 1.25, 1.5]) {
          final name =
              'R09 ${surface.name} ${dark ? '深' : '浅'} ${width.toInt()} ${scale * 100}%';
          testWidgets(name, (tester) async {
            final height = width == 320 ? 640.0 : 900.0;
            tester.view.physicalSize = Size(width, height);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final fixture = _Fixture(dark: dark, scale: scale);
            await fixture.open(tester, surface);
            expect(find.byType(BottomSheet), findsNothing);
            expect(_dragDecorations(), findsNothing);
            expect(tester.takeException(), isNull);
            final Finder last;
            if (surface == _Surface.menu) {
              expect(_menuEntries(), findsNWidgets(SongAction.values.length));
              for (final entry in _menuEntries().evaluate()) {
                final parent = find.byWidget(entry.widget);
                final icon = tester.getRect(
                  find.descendant(of: parent, matching: find.byType(Icon)),
                );
                final label = tester.getRect(
                  find.descendant(of: parent, matching: find.byType(Text)),
                );
                expect(icon.center.dy, closeTo(label.center.dy, 1));
                expect(icon.right, lessThan(label.left));
                expect(label.right, lessThanOrEqualTo(width));
              }
              last = find.text('分享');
            } else {
              expect(find.byType(Dialog), findsOneWidget);
              last = surface == _Surface.download
                  ? find.text('臻品母带2.0')
                  : find.text('目标歌单 20');
              final rect = tester.getRect(_dialogMaterial());
              expect(rect.left, greaterThanOrEqualTo(0));
              expect(rect.right, lessThanOrEqualTo(width));
              expect(rect.top, greaterThan(0));
              expect(rect.bottom, lessThan(height));
              expect(rect.center.dx, closeTo(width / 2, 1));
              expect(rect.center.dy, closeTo(height / 2, 1));
            }
            await tester.scrollUntilVisible(
              last,
              140,
              scrollable: find.byType(Scrollable).last,
            );
            await tester.pumpAndSettle();
            final lastRect = tester.getRect(last);
            expect(lastRect.top, greaterThanOrEqualTo(0));
            expect(lastRect.bottom, lessThanOrEqualTo(height));
            expect(tester.takeException(), isNull);
            await fixture.capture(tester, surface, width, scale);
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
            expect(find.byType(Dialog), findsNothing);
            expect(_menuEntries(), findsNothing);
            expect(fixture.downloads.started, isEmpty);
            expect(fixture.playlists.added, isEmpty);
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  }
}

enum _Surface { menu, playlist, download, batch }

Future<void> _pumpArtistPage(
  WidgetTester tester, {
  required _RecordingDownloads downloads,
  bool? enabled = true,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  PlatformRegistry.register(
    FakeContentPlatform(
      type: PlatformType.qq,
      artist: const Artist(id: 'anchor-artist', name: '验收歌手'),
      artistTopSongs: _artistSongs,
    ),
  );
  final base = IkWorkspaceTheme.from(AppTheme.light());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [downloadProvider.overrideWith((_) => downloads)],
      child: MaterialApp(
        theme: enabled == null
            ? base
            : base.copyWith(
                extensions: [
                  ...base.extensions.values,
                  ContextualActionTheme(enabled: enabled),
                ],
              ),
        home: const ArtistPage(
          platform: PlatformType.qq,
          artistId: 'anchor-artist',
          artistName: '验收歌手页面',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(
    ProviderScope.containerOf(
      tester.element(find.byType(ArtistPage)),
      listen: false,
    ).read(downloadProvider.notifier),
    same(downloads),
    reason: '夹具必须绑定本轮下载记录器，不能复用上一轮通知器',
  );
}

const _artistSongs = [
  Song(
    id: 'artist-anchor-1',
    name: '第一首锚点歌曲',
    platform: PlatformType.qq,
    artists: [Artist(id: 'anchor-artist', name: '验收歌手')],
  ),
  Song(
    id: 'artist-anchor-2',
    name: '第二首锚点歌曲',
    platform: PlatformType.qq,
    artists: [Artist(id: 'anchor-artist', name: '验收歌手')],
  ),
];

const _pageKey = ValueKey('R07-原页面');
const _openKey = ValueKey('R07-打开呈现');
const _imageKey = ValueKey('R09-完整呈现');
const _networkSong = Song(
  id: 'netease-source',
  name: '验收来源歌曲',
  platform: PlatformType.netease,
  artists: [Artist(id: 'artist', name: '验收歌手')],
);
const _qqSong = Song(
  id: 'qq-download',
  name: '验收下载歌曲',
  platform: PlatformType.qq,
  artists: [Artist(id: 'artist', name: '验收歌手')],
);
const _localSong = Song(
  id: 'local-selected',
  name: '选择曲目',
  platform: PlatformType.local,
  artists: [Artist(id: 'artist', name: '验收歌手')],
);
const _labels = {
  SongAction.playNext: '下一首播放',
  SongAction.addToPlaylist: '添加到歌单',
  SongAction.download: '下载',
  SongAction.toggleLike: '喜欢',
  SongAction.copyLink: '复制链接',
  SongAction.share: '分享',
};

Finder _menuEntries() => find.byWidgetPredicate(
  (widget) => widget is PopupMenuItem<SongAction> && widget.value != null,
);

Finder _dragDecorations() => find.byWidgetPredicate(
  (widget) =>
      widget is Container &&
      widget.constraints?.maxWidth == 40 &&
      widget.constraints?.maxHeight == 4,
);

Finder _dialogMaterial() => find
    .descendant(
      of: find.byType(Dialog),
      matching: find.byWidgetPredicate(
        (widget) => widget is Material && widget.type == MaterialType.card,
      ),
    )
    .first;

class _Fixture {
  _Fixture({
    this.enabled = true,
    this.isLocal = false,
    this.isDownloaded = false,
    this.nested = false,
    this.dark = false,
    this.scale = 1,
    this.keyboardInset = 0,
    this.alignment = Alignment.center,
    this.song = _localSong,
    _PresentationPlatform? platform,
  }) : platform = platform ?? _PresentationPlatform(),
       playlists = _MemoryPlaylists(
         includeLocal: song.platform == PlatformType.local,
       );

  final bool? enabled;
  final bool isLocal, isDownloaded, nested, dark;
  final double scale, keyboardInset;
  final Alignment alignment;
  final Song song;
  final _PresentationPlatform platform;
  final _MemoryPlaylists playlists;
  final downloads = _RecordingDownloads();
  SongAction? selectedAction;
  bool? playlistAdded;

  Future<void> open(
    WidgetTester tester,
    _Surface surface, {
    bool keyboard = false,
    bool detailMenu = false,
  }) async {
    PlatformRegistry.register(platform);
    final base = IkWorkspaceTheme.from(
      dark ? AppTheme.dark() : AppTheme.light(),
    );
    final theme = enabled == null
        ? base
        : base.copyWith(
            extensions: [
              ...base.extensions.values,
              ContextualActionTheme(enabled: enabled!),
            ],
          );
    Widget content;
    if (surface == _Surface.batch || detailMenu) {
      content = const PlaylistDetailPage(
        platform: PlatformType.local,
        playlistId: 'source',
        playlistName: '验收来源歌单',
      );
    } else {
      content = Scaffold(
        key: _pageKey,
        body: Align(
          alignment: alignment,
          child: Consumer(
            builder: (context, ref, _) => surface == _Surface.download
                ? const DownloadButton(song: _qqSong)
                : IconButton(
                    key: _openKey,
                    onPressed: () async {
                      if (surface == _Surface.menu) {
                        selectedAction = await showSongActionsSheet(
                          context,
                          song: _networkSong,
                          isLocal: isLocal,
                          isDownloaded: isDownloaded,
                        );
                      } else {
                        playlistAdded = await liveSongActionDeps(
                          ref,
                          context: context,
                        ).pickPlaylist(song);
                      }
                    },
                    icon: const Icon(Icons.more_horiz),
                  ),
          ),
        ),
      );
    }
    if (nested) {
      final page = content;
      content = Navigator(
        onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => page),
      );
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myPlaylistsProvider.overrideWith((ref) => playlists),
          downloadProvider.overrideWith((ref) => downloads),
        ],
        child: RepaintBoundary(
          key: _imageKey,
          child: MaterialApp(
            theme: theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                viewInsets: EdgeInsets.only(bottom: keyboardInset),
              ),
              child: child!,
            ),
            home: content,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (detailMenu) {
      await tester.tap(find.byTooltip('歌曲操作'));
    } else if (surface == _Surface.download) {
      await tester.tap(find.byIcon(Icons.file_download_outlined));
    } else if (surface == _Surface.batch) {
      await tester.scrollUntilVisible(
        find.text(_localSong.name),
        140,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.longPress(find.text(_localSong.name));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('批量加入歌单'));
    } else if (keyboard) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
    } else {
      await tester.tap(find.byKey(_openKey));
    }
    await tester.pumpAndSettle();
  }

  Future<void> capture(
    WidgetTester tester,
    _Surface surface,
    double width,
    double scale,
  ) async {
    final directory =
        Platform.environment['IK_CONTEXTUAL_SCREENSHOT_DIRECTORY'];
    if (directory == null || directory.isEmpty) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_imageKey),
    );
    final file = File(
      '$directory/${surface.name}-${dark ? 'dark' : 'light'}-${width.toInt()}-${(scale * 100).toInt()}.png',
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    });
  }
}

class _MemoryPlaylists extends MyPlaylistsNotifier {
  _MemoryPlaylists({bool includeLocal = true})
    : known = includeLocal
          ? [
              const Playlist(
                id: 'source',
                name: '验收来源歌单',
                platform: PlatformType.local,
              ),
              for (var i = 1; i <= 20; i++)
                Playlist(
                  id: 'target-$i',
                  name: '目标歌单 ${i.toString().padLeft(2, '0')}',
                  platform: PlatformType.local,
                ),
            ]
          : [];

  final added = <(String, String)>[];
  final List<Playlist> known;

  @override
  Future<void> load() async {
    await Future<void>.value();
    state = MyPlaylistsState(playlists: known);
  }

  @override
  Future<List<Song>> getSongs(String playlistId) async =>
      playlistId == 'source' ? [_localSong] : [];

  @override
  Future<bool> addSong(String playlistId, Song song) async {
    added.add((playlistId, song.id));
    return true;
  }
}

class _PresentationPlatform extends FakeContentPlatform {
  _PresentationPlatform({this.playlists = const []})
    : super(type: PlatformType.qq, loggedIn: true);

  List<Playlist> playlists;
  Object? loadFailure;
  Completer<bool>? pendingAdd;
  final added = <(String, String)>[];
  int loadCalls = 0;

  @override
  Future<List<Playlist>> getUserPlaylists() async {
    loadCalls++;
    if (loadFailure != null) throw loadFailure!;
    return playlists;
  }

  @override
  Future<bool> addSongToPlaylist(String playlistId, Song song) async {
    added.add((playlistId, song.id));
    final pending = pendingAdd;
    if (pending != null) return await pending.future;
    return true;
  }

  @override
  Future<VipLevel> getVipStatus() async => VipLevel.svip;

  @override
  Future<List<AudioQuality>> getAvailableQualities(
    String songId,
  ) async => const [
    AudioQuality(level: AudioLevel.low, bitrate: 128000, format: 'mp3'),
    AudioQuality(level: AudioLevel.medium, bitrate: 320000, format: 'mp3'),
    AudioQuality(level: AudioLevel.lossless, bitrate: 999000, format: 'flac'),
    AudioQuality(level: AudioLevel.hires, bitrate: 2400000, format: 'flac'),
    AudioQuality(level: AudioLevel.spatial, bitrate: 999000, format: 'flac'),
    AudioQuality(level: AudioLevel.master, bitrate: 999000, format: 'flac'),
  ];
}

class _RecordingDownloads extends DownloadNotifier {
  _RecordingDownloads() : super(taskStore: _MemoryTasks());

  final started = <(String, AudioLevel)>[];

  @override
  Future<void> startDownload(Song song, AudioLevel quality) async {
    started.add((song.id, quality));
  }
}

class _MemoryTasks implements DownloadTaskStore {
  @override
  Future<List<DownloadTask>> load() async => [];

  @override
  Future<void> save(List<DownloadTask> tasks) async {}
}

class _ReadingPlaylistRepository extends MyPlaylistsRepository {
  int readCalls = 0, addCalls = 0;

  @override
  Future<List<Playlist>> getPlaylists() async {
    readCalls++;
    return const [
      Playlist(id: 'real-local', name: '真实状态目标', platform: PlatformType.local),
    ];
  }

  @override
  Future<bool> addSong(String playlistId, Song song) async {
    addCalls++;
    return true;
  }
}

/// 仅显式审阅字体模式恢复真实阴影；普通 CI 仍用原自动测试绑定。
class _ReadableCaptureBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get disableShadows => false;
}

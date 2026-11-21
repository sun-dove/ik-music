import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/l10n/ik_strings.dart';
import 'package:mconnect/l10n/ik_workspace_strings.dart';
import 'package:mconnect/l10n/video_strings.dart';
import 'package:mconnect/models/album.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/video_app/data/video_catalog.dart';
import 'package:mconnect/video_app/ik/ik_library_workspace.dart';
import 'package:mconnect/video_app/ik/ik_search.dart';
import 'package:mconnect/video_app/ik/ik_search_workspace.dart';
import 'package:mconnect/video_app/ik/ik_song_table.dart';
import 'package:mconnect/video_app/ik/ik_workspace_theme.dart';

Song song(PlatformType platform, String id) => Song(
  id: id,
  platform: platform,
  name: '歌曲$id',
  artists: const [Artist(id: 'a', name: '歌手名字')],
  album: const Album(id: 'b', name: '专辑名称'),
  duration: const Duration(minutes: 3, seconds: 42),
);

void main() {
  Future<void> mount(
    WidgetTester tester,
    Widget page, {
    double width = 1200,
    double scale = 1,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: IkWorkspaceTheme.from(ThemeData(brightness: brightness)),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 900),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(body: page),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('A05 共用搜索时无第二输入框，分源列式歌曲保留真实队列和操作', (tester) async {
    final controller = IkSearchController(
      platforms: [PlatformType.qq],
      search: (p, q, page) async => VideoPage(
        songs: [song(p, '1'), song(p, '2')],
        page: 1,
        hasMore: false,
      ),
    );
    addTearDown(controller.dispose);
    await controller.submit('搜索词');
    List<Song>? played;
    Song? liked, more;
    await mount(
      tester,
      IkSearchWorkspace(
        alignToDesign: true,
        useSharedSearch: true,
        search: controller,
        onPlay: (s, queue) => played = queue,
        onLike: (s) => liked = s,
        onMore: (s) => more = s,
      ),
    );
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('搜索词'), findsOneWidget);
    expect(find.text('时长'), findsOneWidget);
    expect(find.text('3:42'), findsNWidgets(2));
    await tester.tap(find.text('歌曲1'));
    expect(played?.map((s) => s.id), ['1', '2']);
    await tester.tap(find.byTooltip(VideoStrings.like).first);
    expect(liked?.id, '1');
    await tester.tap(find.byTooltip(IkStrings.more).first);
    expect(more?.id, '1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('A05 独立失败继续显示其他来源，重试只作用失败来源', (tester) async {
    var failQq = true;
    final calls = <PlatformType>[];
    final controller = IkSearchController(
      platforms: [PlatformType.qq, PlatformType.netease],
      search: (p, q, page) async {
        calls.add(p);
        if (p == PlatformType.qq && failQq) {
          throw const VideoFailure(
            VideoFailureKind.network,
            '该来源连接失败',
            canRetry: true,
          );
        }
        return VideoPage(songs: [song(p, p.name)], page: 1, hasMore: false);
      },
    );
    addTearDown(controller.dispose);
    await controller.submit('歌');
    await mount(
      tester,
      IkSearchWorkspace(
        alignToDesign: true,
        useSharedSearch: true,
        search: controller,
        onPlay: (_, _) {},
        onLike: (_) {},
        onMore: (_) {},
      ),
    );
    expect(find.text('歌曲netease'), findsOneWidget);
    expect(find.text('该来源连接失败'), findsOneWidget);
    calls.clear();
    failQq = false;
    await tester.tap(find.text(VideoStrings.retry));
    await tester.pumpAndSettle();
    expect(calls, [PlatformType.qq]);
    expect(find.text('歌曲qq'), findsOneWidget);
    expect(find.text('时长'), findsNWidgets(2));
  });

  testWidgets('A05 视觉复核 当前喜欢分类明确选中而不是禁用按钮', (tester) async {
    final semantics = tester.ensureSemantics();
    await mount(
      tester,
      IkLibraryWorkspace(
        alignToDesign: true,
        libraries: const {},
        syncing: const {},
        loggedIn: const {},
        onSync: (_) {},
        onPlay: (_, _) {},
        onMore: (_) {},
        onNavigate: (_) {},
        onDownloads: () {},
        onAccounts: () {},
        localLikes: [song(PlatformType.qq, '1')],
        localLoading: false,
        onRetryLocal: () {},
      ),
      width: 320,
      scale: 1.5,
    );
    final selected = find.text(IkWorkspaceStrings.likes);
    final node = tester.getSemantics(selected);
    expect(node.flagsCollection.isSelected, Tristate.isTrue);
    expect(node.flagsCollection.isEnabled, Tristate.none);
    expect(
      find.widgetWithText(TextButton, IkWorkspaceStrings.likes),
      findsNothing,
    );
    final text = tester.widget<Text>(selected);
    final color = Theme.of(tester.element(selected)).colorScheme.primary;
    expect(text.style?.color, color);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('A05 视觉复核 320窗口150%长标题保留两行和独立来源标签', (tester) async {
    const title = '同名歌曲的完整标题现场特别版本';
    const artist = '名称特别长而且联合多位演奏者的歌手名称';
    final songs = [
      for (final platform in [PlatformType.qq, PlatformType.netease])
        Song(
          id: 'same',
          platform: platform,
          name: title,
          artists: const [Artist(id: 'artist', name: artist)],
        ),
    ];
    final more = <String>[];
    await mount(
      tester,
      SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              for (final song in songs)
                IkSongTableRow(
                  song: song,
                  index: 0,
                  onPlay: () {},
                  onMore: () => more.add(song.platform.name),
                ),
            ],
          ),
        ),
      ),
      width: 320,
      scale: 1.5,
    );
    for (final row in find.byType(IkSongTableRow).evaluate()) {
      final rowFinder = find.byWidget(row.widget);
      final name = find.descendant(of: rowFinder, matching: find.text(title));
      expect(tester.widget<Text>(name).maxLines, 2);
      expect(tester.getSize(name).width, greaterThanOrEqualTo(132));
      final source = find.descendant(
        of: rowFinder,
        matching: find.text(
          (row.widget as IkSongTableRow).song.platform == PlatformType.qq
              ? 'QQ 音乐'
              : '网易云',
        ),
      );
      expect(source, findsOneWidget);
      expect(
        tester.renderObject<RenderParagraph>(source).didExceedMaxLines,
        isFalse,
      );
      final singer = find.descendant(
        of: rowFinder,
        matching: find.text(artist),
      );
      expect(
        tester.getTopLeft(source).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(singer).dy),
      );
      final moreButton = find.descendant(
        of: rowFinder,
        matching: find.byTooltip(IkStrings.more),
      );
      expect(moreButton.hitTestable(), findsOneWidget);
      expect(tester.getSize(moreButton).width, greaterThanOrEqualTo(40));
      expect(tester.getSize(moreButton).height, greaterThanOrEqualTo(40));
      await tester.tap(moreButton);
    }
    expect(more, ['qq', 'netease']);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    for (final width in [320.0, 390.0, 720.0, 900.0, 1200.0, 1440.0]) {
      for (final scale in [1.0, 1.25, 1.5]) {
        testWidgets('A05/A07 搜索与曲库 ${dark ? '深' : '浅'} $width/$scale', (
          tester,
        ) async {
          final songs = [
            song(PlatformType.qq, '同ID'),
            song(PlatformType.netease, '同ID'),
          ];
          List<Song>? played;
          final controller = IkSearchController(
            platforms: [PlatformType.qq],
            search: (p, q, page) async =>
                VideoPage(songs: songs, page: 1, hasMore: false),
          );
          addTearDown(controller.dispose);
          await controller.submit('原曲名称');
          final pages = [
            IkSearchWorkspace(
              alignToDesign: true,
              useSharedSearch: true,
              search: controller,
              onPlay: (_, queue) => played = queue,
              onLike: (_) {},
              onMore: (_) {},
            ),
            IkLibraryWorkspace(
              alignToDesign: true,
              libraries: const {},
              syncing: const {},
              loggedIn: const {},
              onSync: (_) {},
              onPlay: (_, queue) => played = queue,
              onMore: (_) {},
              onNavigate: (_) {},
              onDownloads: () {},
              onAccounts: () {},
              localLikes: songs,
              localLoading: false,
              onRetryLocal: () {},
            ),
          ];
          for (final page in pages) {
            await mount(
              tester,
              page,
              width: width,
              scale: scale,
              brightness: dark ? Brightness.dark : Brightness.light,
            );
            final title = find.text('歌曲同ID').first;
            await tester.ensureVisible(title);
            await tester.tap(title);
            expect(played?.length, 2);
            expect(
              tester.takeException(),
              isNull,
              reason: page.runtimeType.toString(),
            );
          }
        });
      }
    }
  }
}

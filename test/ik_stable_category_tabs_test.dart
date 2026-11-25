import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/library/data/my_playlists_repository.dart';
import 'package:mconnect/features/library/presentation/providers/my_playlists_provider.dart';
import 'package:mconnect/features/library/presentation/providers/platform_playlists_provider.dart';
import 'package:mconnect/features/local_music/data/local_lyrics_store.dart';
import 'package:mconnect/features/local_music/data/local_scan_root_store.dart';
import 'package:mconnect/features/local_music/data/local_track_store.dart';
import 'package:mconnect/features/local_music/data/online_library_snapshot.dart';
import 'package:mconnect/features/local_music/data/track_ratings_store.dart';
import 'package:mconnect/features/local_music/presentation/providers/local_music_provider.dart';
import 'package:mconnect/features/smart_playlists/data/smart_playlist_repository.dart';
import 'package:mconnect/features/smart_playlists/presentation/providers/smart_playlists_provider.dart';
import 'package:mconnect/models/playlist.dart';
import 'package:mconnect/video_app/ik/ik_library_workspace.dart';
import 'package:mconnect/video_app/ik/ik_workspace_theme.dart';

// 正式 E02：真实五分类页面与内存存储边界，不加载真实账号、文件或音频。
const _categories = ['likes', 'playlists', 'local', 'downloads', 'smart'];

void main() {
  testWidgets('E02 首红 五标签逐选后文字基线和全部外框保持不动', (tester) async {
    await _mount(tester);
    await _checkEverySelection(tester, report: true);
  });

  for (final brightness in Brightness.values) {
    for (final width in [320.0, 390.0, 720.0, 900.0, 1200.0, 1440.0, 1920.0]) {
      for (final scale in [1.0, 1.25, 1.5]) {
        testWidgets('E02 ${brightness.name} 宽$width 字号$scale 五标签几何与空态无溢出', (
          tester,
        ) async {
          await _mount(
            tester,
            width: width,
            scale: scale,
            brightness: brightness,
          );
          await _checkEverySelection(tester);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('E02 选中语义保持非按钮，未选中可鼠标及键盘激活', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _mount(tester);
      for (final category in [..._categories.skip(1), 'likes']) {
        final tab = _tab(category);
        final node = tester.getSemantics(tab);
        expect(node.flagsCollection.isSelected, Tristate.isFalse);
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        final gesture = find.descendant(
          of: tab,
          matching: find.byType(GestureDetector),
        );
        Focus.of(tester.element(gesture.first)).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(
          category == 'local' || category == 'smart'
              ? LogicalKeyboardKey.space
              : LogicalKeyboardKey.enter,
        );
        await tester.pumpAndSettle();
        _expectSelected(tester, category);
        final selected = tester.getSemantics(_tab(category));
        expect(selected.flagsCollection.isEnabled, Tristate.none);
        expect(selected.flagsCollection.isButton, isFalse);
        expect(
          selected.getSemanticsData().hasAction(SemanticsAction.tap),
          isFalse,
        );
        await tester.tap(_tab(category));
        await tester.pumpAndSettle();
        _expectSelected(tester, category);
      }
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('E02 没有嵌入下载时仅回调，不改变选择或创建空下载页', (tester) async {
    var requests = 0;
    await _mount(tester, downloads: false, onDownloads: () => requests++);
    final original = _geometry(tester);
    await tester.tap(_tab('downloads'));
    await tester.pumpAndSettle();
    expect(requests, 1);
    _expectSelected(tester, 'likes');
    expect(
      find.byKey(const ValueKey('ik-library-content-downloads')),
      findsNothing,
    );
    _expectGeometry(_geometry(tester), original, '下载回退');
    expect(tester.takeException(), isNull);
  });

  testWidgets('E02 新开关缺省和显式false均保留旧布局与下载回调', (tester) async {
    Map<String, _TabGeometry>? original;
    for (final stable in <bool?>[null, false]) {
      var requests = 0;
      await _mount(
        tester,
        stable: stable,
        downloads: false,
        onDownloads: () => requests++,
      );
      expect(
        tester
            .widget<IkLibraryWorkspace>(find.byType(IkLibraryWorkspace))
            .stableCategoryTabs,
        isFalse,
      );
      expect(tester.widget(_tab('likes')), isA<Container>());
      for (final category in _categories.skip(1)) {
        expect(tester.widget(_tab(category)), isA<TextButton>());
      }
      final current = _geometry(tester);
      if (original != null) _expectGeometry(current, original, '旧缺省');
      original = current;
      await tester.tap(_tab('downloads'));
      await tester.pumpAndSettle();
      expect(requests, 1);
      _expectSelected(tester, 'likes');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('E02 非对齐旧入口不因新开关改变布局', (tester) async {
    for (final stable in [false, true]) {
      await _mount(tester, stable: stable, aligned: false);
      for (final category in _categories) {
        expect(_tab(category), findsNothing);
      }
      expect(find.byType(IkLibraryWorkspace), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}

Finder _tab(String category) =>
    find.byKey(ValueKey('ik-library-category-$category'));

Finder _label(String category) =>
    find.descendant(of: _tab(category), matching: find.byType(Text));

void _expectSelected(WidgetTester tester, String selected) {
  for (final category in _categories) {
    final owner = find
        .ancestor(
          of: _tab(category),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.selected != null,
          ),
        )
        .first;
    expect(
      tester.widget<Semantics>(owner).properties.selected,
      category == selected,
    );
  }
  expect(find.byKey(ValueKey('ik-library-content-$selected')), findsOneWidget);
}

Future<void> _checkEverySelection(
  WidgetTester tester, {
  bool report = false,
}) async {
  final original = _geometry(tester);
  for (final category in _categories) {
    expect(
      original[category]!.baseline,
      closeTo(original['likes']!.baseline, .01),
      reason: '$category 与其他标签共享基线',
    );
  }
  for (final category in [..._categories.skip(1), 'likes']) {
    await tester.ensureVisible(_tab(category));
    await tester.pumpAndSettle();
    final before = _geometry(tester);
    await tester.tap(_tab(category));
    await tester.pumpAndSettle();
    final after = _geometry(tester);
    if (report) {
      debugPrint('E02 $category 选择前 $before；选择后 $after');
    }
    _expectSelected(tester, category);
    _expectGeometry(after, before, '$category 切换不移动');
    for (final item in _categories) {
      expect(
        after[item]!.rect.size,
        original[item]!.rect.size,
        reason: '$item 字重不改变宽高',
      );
    }
    expect(tester.takeException(), isNull);
  }
}

Map<String, _TabGeometry> _geometry(WidgetTester tester) => {
  for (final category in _categories) category: _measureTab(tester, category),
};

_TabGeometry _measureTab(WidgetTester tester, String category) {
  final paragraph = tester.renderObject<RenderParagraph>(_label(category));
  return _TabGeometry(
    tester.getRect(_tab(category)),
    paragraph.localToGlobal(Offset.zero).dy +
        paragraph.getDryBaseline(
          paragraph.constraints,
          TextBaseline.alphabetic,
        )!,
  );
}

void _expectGeometry(
  Map<String, _TabGeometry> actual,
  Map<String, _TabGeometry> expected,
  String reason,
) {
  for (final category in _categories) {
    final current = actual[category]!;
    final previous = expected[category]!;
    expect(
      current.baseline,
      closeTo(previous.baseline, .01),
      reason: '$reason / $category 文字基线',
    );
    expect(
      current.rect.left,
      closeTo(previous.rect.left, .01),
      reason: '$reason / $category 左边界',
    );
    expect(
      current.rect.top,
      closeTo(previous.rect.top, .01),
      reason: '$reason / $category 上边界',
    );
    expect(
      current.rect.width,
      closeTo(previous.rect.width, .01),
      reason: '$reason / $category 宽度',
    );
    expect(
      current.rect.height,
      closeTo(previous.rect.height, .01),
      reason: '$reason / $category 高度',
    );
  }
}

class _TabGeometry {
  const _TabGeometry(this.rect, this.baseline);
  final Rect rect;
  final double baseline;
  @override
  String toString() => '框=$rect 基线=$baseline';
}

Future<void> _mount(
  WidgetTester tester, {
  bool? stable = true,
  bool aligned = true,
  bool downloads = true,
  VoidCallback? onDownloads,
  double width = 1200,
  double scale = 1,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final scope = ProviderContainer(
    overrides: [
      myPlaylistsProvider.overrideWith(
        (_) => MyPlaylistsNotifier(repository: const _EmptyPlaylists()),
      ),
      platformPlaylistsProvider.overrideWith(
        (_) => PlatformPlaylistsNotifier(supportedTypes: const []),
      ),
      smartPlaylistsProvider.overrideWith(
        (_) =>
            SmartPlaylistsNotifier(repository: MemorySmartPlaylistRepository()),
      ),
      localMusicProvider.overrideWith(
        (_) => LocalMusicNotifier(
          trackStore: MemoryLocalTrackStore(),
          lyricsStore: MemoryLocalLyricsStore(),
          rootStore: MemoryLocalScanRootStore(),
          onlineSnapshot: MemoryOnlineLibrarySnapshot(),
          ratingsStore: MemoryTrackRatingsStore(),
        ),
      ),
    ],
  );
  addTearDown(scope.dispose);
  final page = stable == null
      ? IkLibraryWorkspace(
          alignToDesign: aligned,
          simplifySources: true,
          libraries: const {},
          syncing: const {},
          loggedIn: const {},
          onSync: (_) {},
          onPlay: (_, _) {},
          onMore: (_) {},
          onNavigate: (_) {},
          onDownloads: onDownloads ?? () {},
          onAccounts: () {},
          onRetryLocal: () {},
          localLikes: const [],
          localLoading: false,
          downloadsBuilder: downloads
              ? (_) => const Center(child: Text('下载内容'))
              : null,
        )
      : IkLibraryWorkspace(
          alignToDesign: aligned,
          simplifySources: true,
          stableCategoryTabs: stable,
          libraries: const {},
          syncing: const {},
          loggedIn: const {},
          onSync: (_) {},
          onPlay: (_, _) {},
          onMore: (_) {},
          onNavigate: (_) {},
          onDownloads: onDownloads ?? () {},
          onAccounts: () {},
          onRetryLocal: () {},
          localLikes: const [],
          localLoading: false,
          downloadsBuilder: downloads
              ? (_) => const Center(child: Text('下载内容'))
              : null,
        );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: scope,
      child: MaterialApp(
        theme: IkWorkspaceTheme.aligned(ThemeData(brightness: brightness)),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(body: page),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _EmptyPlaylists extends MyPlaylistsRepository {
  const _EmptyPlaylists();
  @override
  Future<List<Playlist>> getPlaylists() async => const [];
}

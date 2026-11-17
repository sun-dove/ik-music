import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/video_app/ui/catalog_pages.dart';
import 'package:mconnect/video_app/ui/my_page.dart';
import 'package:mconnect/video_app/ui/video_shell.dart';
import 'package:mconnect/video_app/ui/video_theme.dart';
import 'package:mconnect/video_app/video_preferences.dart';
import 'package:mconnect/video_app/windows/windows_appearance.dart';
import 'package:mconnect/video_app/windows/windows_music_preferences.dart';
import 'package:mconnect/video_app/windows/windows_my_page.dart';
import 'package:mconnect/video_app/windows/windows_platform_icon.dart';
import 'package:mconnect/video_app/windows/windows_player_page.dart';
import 'package:mconnect/video_app/windows/windows_window_controller.dart';
import 'package:path/path.dart' as p;

const _baseline = bool.fromEnvironment('LEYIN_BASELINE');

class _Fonts extends WindowsWindowController {
  @override
  Future<void> setCloseAction(WindowsCloseAction action) async {}
  @override
  Future<List<String>> listFonts() async => [
    'Microsoft YaHei UI',
    'Noto Sans SC',
  ];
}

VideoMyPage _settings({
  Map<PlatformType, VideoAccountSummary> accounts = const {},
}) => VideoMyPage(
  platforms: const [PlatformType.qq, PlatformType.netease, PlatformType.kugou],
  accounts: accounts,
  cacheLabel: '0 MB',
  downloadLabel: '0 项',
  themeLabel: '浅色',
  onAccount: (_) {},
  onQuality: (_, _) {},
  onCache: () {},
  onDownloads: () {},
  onDirectory: () {},
  onTheme: () {},
  onLocal: () {},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late WindowsMusicPreferences preferences;
  late WindowsAppearance appearance;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('leyin-theme-gate-');
    Hive.init(root.path);
    preferences = WindowsMusicPreferences(
      VideoPreferences(await Hive.openBox('settings')),
    )..load();
    appearance = WindowsAppearance(
      preferences: preferences,
      directory: Directory(p.join(root.path, 'appearance')),
      window: _Fonts(),
    );
    await appearance.initialize();
  });
  tearDown(() async {
    appearance.dispose();
    preferences.dispose();
    await Hive.close();
    expect(
      p.isWithin(Directory.systemTemp.absolute.path, root.absolute.path),
      isTrue,
    );
    await root.delete(recursive: true);
  });

  testWidgets('W04/W11：未装配扩展时深浅主题颜色精确保持，配置字体只作用于新主题', (tester) async {
    for (final brightness in Brightness.values) {
      final theme = brightness == Brightness.dark
          ? VideoTheme.dark
          : VideoTheme.light;
      Color? canvas;
      Color? surface;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) {
              canvas = VideoTheme.canvas(context);
              surface = VideoTheme.surface(context);
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        canvas,
        brightness == Brightness.dark
            ? const Color(0xFF17171C)
            : VideoTheme.background,
      );
      expect(
        surface,
        brightness == Brightness.dark
            ? const Color(0xFF25242C)
            : VideoTheme.card,
      );
      expect(theme.textTheme.bodyMedium?.fontFamily, 'sans-serif');
    }
    await tester.runAsync(() => appearance.selectSystemFont('Noto Sans SC'));
    final desktop = appearance.theme(Brightness.light);
    expect(desktop.textTheme.bodyMedium?.fontFamily, 'Noto Sans SC');
    expect(desktop.primaryTextTheme.titleLarge?.fontFamily, 'Noto Sans SC');
    expect(desktop.appBarTheme.titleTextStyle?.fontFamily, 'Noto Sans SC');
    expect(VideoTheme.light.textTheme.bodyMedium?.fontFamily, 'sans-serif');
  });

  testWidgets('W04：背景在搜索、三平台收藏、设置及播放器透出，深浅主题均可读', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await appearance.applyBackground(
        await appearance.prepareBackground(
          File('design/platform-icons-010/qq-music.jpg'),
        ),
      );
    });
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final pages = <Widget>[
      VideoSearchPage(
        controller: controller,
        onSearch: (_) {},
        platform: PlatformType.qq,
        onPlatformChanged: (_) {},
        result: const VideoCatalogViewState(),
        onSongTap: (_) {},
      ),
      for (final platform in [
        PlatformType.qq,
        PlatformType.netease,
        PlatformType.kugou,
      ])
        VideoLibraryPage(
          platform: platform,
          result: const VideoCatalogViewState(),
          loggedIn: false,
          onLogin: () {},
          onRefresh: () {},
          onPlayAll: () {},
          onDownloadAll: () {},
          onSongTap: (_) {},
        ),
      WindowsMyPage(
        settings: _settings(),
        playQuality: '标准',
        downloadQuality: '标准',
        onQuality: (_) {},
      ),
    ];
    for (final brightness in Brightness.values) {
      for (var index = 0; index < 6; index++) {
        final page = index == 5
            ? WindowsPlayerPage(
                song: const Song(
                  id: 'theme',
                  platform: PlatformType.local,
                  name: '背景验收',
                  artists: [],
                ),
                position: Duration.zero,
                duration: const Duration(minutes: 1),
                isPlaying: false,
                onToggle: () {},
                onPrevious: () {},
                onNext: () {},
                onSeek: (_) {},
                onQueue: () {},
                onMode: () {},
              )
            : VideoShell(
                index: index,
                onSelect: (_) {},
                pages: pages,
                expandedPlatforms: true,
                platformIcons: true,
                miniPlayer: const Text('播放控制'),
              );
        Color? canvas;
        Color? surface;
        await tester.pumpWidget(
          MaterialApp(
            theme: _baseline
                ? (brightness == Brightness.dark
                      ? VideoTheme.dark
                      : VideoTheme.light)
                : appearance.theme(brightness),
            builder: (context, child) =>
                WindowsBackground(appearance: appearance, child: child!),
            home: Builder(
              builder: (context) {
                canvas = VideoTheme.canvas(context);
                surface = VideoTheme.surface(context);
                return page;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          canvas,
          Colors.transparent,
          reason: '$brightness，页面$index背景不能被不透明画布挡住',
        );
        expect(surface!.a, closeTo(.86, .005));
        expect(
          tester
              .widgetList<Scaffold>(find.byType(Scaffold))
              .every(
                (scaffold) => scaffold.backgroundColor == Colors.transparent,
              ),
          isTrue,
        );
        expect(
          find
              .byType(Image)
              .evaluate()
              .any((element) => (element.widget as Image).image is FileImage),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      }
    }
  });

  test('W06：三张官方图标离线解码与逐字节哈希正确，平台映射一致', () async {
    for (final entry in <PlatformType, String>{
      PlatformType.qq:
          '768b6fb8b36e0e64782c3b275ac3b6761cfe9ebfc54dc8ed586ed98c3c3431c1',
      PlatformType.netease:
          'e003afd6c851195bb09a8e7acb70ae006228c8f21ffa414ac36f8e626563fd2a',
      PlatformType.kugou:
          'fc8119b4130614ae95debcec6ed0e104938c023537db7a39febd3773f40dbd3d',
    }.entries) {
      final data = await rootBundle.load(WindowsPlatformIcon.asset(entry.key));
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      expect(sha256.convert(bytes).toString(), entry.value);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      expect([frame.image.width, frame.image.height], [512, 512]);
      frame.image.dispose();
      codec.dispose();
    }
  });

  testWidgets('W06：登录账号保留用户头像，未登录账号用对应平台图标', (tester) async {
    const url = 'https://avatar.example/user.jpg';
    // 使用已解码离线像素填充头像缓存；此门只验已登录界面，不请求账号。
    final avatar = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(
        File('assets/platform-icons/qq-music.jpg').readAsBytesSync(),
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    });
    PaintingBinding.instance.imageCache.putIfAbsent(
      const NetworkImage(url),
      () =>
          OneFrameImageStreamCompleter(Future.value(ImageInfo(image: avatar!))),
    );
    addTearDown(
      () => PaintingBinding.instance.imageCache.evict(const NetworkImage(url)),
    );
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: appearance.theme(Brightness.light),
        home: Scaffold(
          body: WindowsMyPage(
            settings: _settings(
              accounts: {
                PlatformType.qq: VideoAccountSummary(
                  nickname: '用户头像验收',
                  avatarUrl: url,
                  loaded: 2,
                  total: 2,
                  complete: true,
                ),
              },
            ),
            playQuality: '标准',
            downloadQuality: '标准',
            onQuality: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      (tester.widget<CircleAvatar>(find.byType(CircleAvatar)).backgroundImage!
              as NetworkImage)
          .url,
      url,
    );
    expect(find.text('用户头像验收'), findsOneWidget);
    expect(
      tester
          .widgetList<WindowsPlatformIcon>(find.byType(WindowsPlatformIcon))
          .map((icon) => icon.platform)
          .toSet(),
      {PlatformType.netease, PlatformType.kugou},
    );
    expect(tester.takeException(), isNull);
  });
}

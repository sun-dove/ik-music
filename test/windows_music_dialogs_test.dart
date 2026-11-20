import 'dart:async';
import 'dart:io';

// 插件提供的通道实现用于离线驱动文件选择，避免验收时打开系统选择窗口。
// ignore: implementation_imports
import 'package:file_picker/src/platform/file_picker_method_channel.dart';
// ignore: implementation_imports
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/l10n/windows_music_strings.dart';
import 'package:mconnect/video_app/ik/ik_theme.dart';
import 'package:mconnect/video_app/video_preferences.dart';
import 'package:mconnect/video_app/windows/windows_appearance.dart';
import 'package:mconnect/video_app/windows/windows_appearance_dialogs.dart';
import 'package:mconnect/video_app/windows/windows_music_preferences.dart';
import 'package:mconnect/video_app/windows/windows_window_controller.dart';
import 'package:path/path.dart' as p;

class _Window extends WindowsWindowController {
  @override
  Future<void> setCloseAction(WindowsCloseAction action) async {}
  @override
  Future<List<String>> listFonts() async => [
    'Microsoft YaHei UI',
    'Noto Sans SC',
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pickerChannel = MethodChannel('miguelruivo.flutter.plugins.filepicker');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory root;
  late WindowsMusicPreferences preferences;
  late WindowsAppearance appearance;
  late FilePickerPlatform originalPicker;
  String? selection;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('leyin-dialog-gate-');
    Hive.init(root.path);
    preferences = WindowsMusicPreferences(
      VideoPreferences(await Hive.openBox('settings')),
    )..load();
    appearance = WindowsAppearance(
      preferences: preferences,
      directory: Directory(p.join(root.path, 'appearance')),
      window: _Window(),
    );
    await appearance.initialize();
    originalPicker = FilePickerPlatform.instance;
    FilePickerPlatform.instance = MethodChannelFilePicker();
    selection = null;
    messenger.setMockMethodCallHandler(
      pickerChannel,
      (_) async => selection == null
          ? null
          : [
              {
                'path': selection,
                'name': p.basename(selection!),
                'size': File(selection!).lengthSync(),
              },
            ],
    );
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(pickerChannel, null);
    FilePickerPlatform.instance = originalPicker;
    appearance.dispose();
    preferences.dispose();
    await Hive.close();
    expect(
      p.isWithin(Directory.systemTemp.absolute.path, root.absolute.path),
      isTrue,
    );
    await root.delete(recursive: true);
  });

  Future<void> open(
    WidgetTester tester,
    Future<void> Function(BuildContext) picker, {
    Size size = const Size(1200, 800),
    double scale = 1,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? appearance.theme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => unawaited(picker(context)),
              child: const Text('打开设置'),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() => tester.tap(find.text('打开设置')));
    await tester.pumpAndSettle();
  }

  Future<void> until(WidgetTester tester, bool Function() condition) async {
    for (var i = 0; i < 60 && !condition(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(condition(), isTrue, reason: '设置异步操作应完成并显示结果');
    await tester.pumpAndSettle();
  }

  Future<void> tapFileAction(WidgetTester tester, Finder finder) async {
    await tester.runAsync(() => tester.tap(finder));
  }

  testWidgets('W04：图片预览取消不写配置，应用后成功反馈并可恢复默认', (tester) async {
    selection = File('assets/platform-icons/qq-music.jpg').absolute.path;
    await open(
      tester,
      (context) => showWindowsBackgroundPicker(context, appearance),
    );
    await tapFileAction(tester, find.text('选择背景图片'));
    await until(tester, () => find.text('预览背景').evaluate().isNotEmpty);
    expect(preferences.value.background, isNull);
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    expect(preferences.value.background, isNull);
    await until(
      tester,
      () =>
          tester
              .widget<FilledButton>(
                find
                    .ancestor(
                      of: find.text('选择背景图片'),
                      matching: find.byWidgetPredicate(
                        (widget) => widget is FilledButton,
                      ),
                    )
                    .first,
              )
              .onPressed !=
          null,
    );
    await tapFileAction(tester, find.text('选择背景图片'));
    await until(tester, () => find.text('预览背景').evaluate().isNotEmpty);
    await tapFileAction(tester, find.text('应用'));
    await until(tester, () => find.text('已应用').evaluate().isNotEmpty);
    expect(appearance.backgroundFile, isNotNull);
    await tester.tap(find.text('打开设置'));
    await tester.pumpAndSettle();
    await tapFileAction(tester, find.text('恢复默认'));
    await until(tester, () => appearance.backgroundFile == null);
    expect(preferences.value.background, isNull);
  });

  testWidgets('W04：无效图片显示明确原因且允许重新选择，取消保持原设置', (tester) async {
    selection = (await tester.runAsync(
      () => File(p.join(root.path, 'invalid.png')).writeAsBytes([1, 2, 3]),
    ))!.path;
    await open(
      tester,
      (context) => showWindowsBackgroundPicker(context, appearance),
    );
    await tapFileAction(tester, find.text('选择背景图片'));
    final message = WindowsMusicStrings.failure(DesktopFailure.invalidImage);
    await until(tester, () => find.text(message).evaluate().isNotEmpty);
    expect(find.text('选择背景图片').hitTestable(), findsOneWidget);
    expect(preferences.value.background, isNull);
    expect(find.text('已应用'), findsNothing);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(preferences.value.background, isNull);
  });

  testWidgets('W04：系统文件选择失败显示中文可恢复提示，保留已有背景', (tester) async {
    messenger.setMockMethodCallHandler(
      pickerChannel,
      (_) async => throw PlatformException(
        code: 'read_failed',
        message: 'native picker detail',
      ),
    );
    await open(
      tester,
      (context) => showWindowsBackgroundPicker(context, appearance),
    );
    await tapFileAction(tester, find.text('选择背景图片'));
    await tester.pumpAndSettle();
    expect(
      find.text(WindowsMusicStrings.failure(DesktopFailure.readFailed)),
      findsWidgets,
    );
    expect(find.textContaining('PlatformException'), findsNothing);
    expect(find.text('选择背景图片').hitTestable(), findsOneWidget);
    expect(preferences.value.background, isNull);
  });

  testWidgets('W05：字体预览取消不改变配置，明确应用后页面与标题同步', (tester) async {
    await open(tester, (context) => showWindowsFontPicker(context, appearance));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Noto Sans SC').last);
    await tester.pumpAndSettle();
    final sample = tester.widget<Text>(
      find.text(WindowsMusicStrings.fontSample),
    );
    expect(sample.style!.fontFamily, 'Noto Sans SC');
    expect(preferences.value.font, isNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(appearance.fontFamily, 'Microsoft YaHei UI');
    await tester.tap(find.text('打开设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Noto Sans SC').last);
    await tester.pumpAndSettle();
    await tapFileAction(tester, find.text('应用'));
    await until(tester, () => find.text('已应用').evaluate().isNotEmpty);
    expect(appearance.fontFamily, 'Noto Sans SC');
    expect(
      appearance.theme(Brightness.light).appBarTheme.titleTextStyle!.fontFamily,
      'Noto Sans SC',
    );
  });

  for (final preserve in [false, true]) {
    testWidgets('K08 字体预览保持新版主题=$preserve，切换字体不改变对应配色', (tester) async {
      final legacy = appearance.theme(Brightness.light);
      final modern = IkTheme.from(legacy);
      await open(
        tester,
        (context) =>
            showWindowsFontPicker(context, appearance, preserveTheme: preserve),
        theme: modern,
      );
      final before = Theme.of(tester.element(find.byType(AlertDialog)));
      if (preserve) {
        expect(before.textTheme.bodyMedium!.fontSize, 15);
      }
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Noto Sans SC').last);
      await tester.pumpAndSettle();

      final preview = Theme.of(tester.element(find.byType(AlertDialog)));
      expect(
        preview.colorScheme.primary,
        (preserve ? modern : legacy).colorScheme.primary,
      );
      expect(preview.textTheme.bodyMedium!.fontFamily, 'Noto Sans SC');
      expect(
        preview.textTheme.bodyMedium!.fontSize,
        before.textTheme.bodyMedium!.fontSize,
      );
      expect(
        tester
            .widget<Text>(find.text(WindowsMusicStrings.fontSample))
            .style!
            .fontFamily,
        'Noto Sans SC',
      );
      expect(preferences.value.font, isNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(appearance.fontFamily, 'Microsoft YaHei UI');
    });
  }

  for (final scale in [1.0, 1.25, 1.5]) {
    testWidgets('W05/W09：900×600，缩放$scale，字体预览和关闭选项无溢出', (tester) async {
      await open(
        tester,
        (context) => showWindowsFontPicker(context, appearance),
        size: const Size(900, 600),
        scale: scale,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('应用').hitTestable(), findsOneWidget);
      expect(find.text('取消').hitTestable(), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await open(
        tester,
        (context) => showWindowsClosePicker(context, appearance),
        size: const Size(900, 600),
        scale: scale,
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('退出应用'));
      await tapFileAction(tester, find.text('退出应用'));
      await until(
        tester,
        () => preferences.closeAction == WindowsCloseAction.exit,
      );
      expect(find.text('已应用'), findsOneWidget);
    });
  }
}

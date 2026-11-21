import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/l10n/video_strings.dart';
import 'package:mconnect/l10n/expanded_strings.dart';
import 'package:mconnect/l10n/windows_music_strings.dart';

void main() {
  test('品牌：IK Music在独立入口文案与Windows预览中统一', () {
    expect(VideoStrings.appName, 'IK Music');
    expect(ExpandedStrings.appName, 'IK Music');
    expect(VideoStrings.appVersion, 'IK Music · 0.6.1');
    expect(WindowsMusicStrings.brandShortName, 'IK Music');
    expect(WindowsMusicStrings.fontSample, contains('IK Music'));
  });

  test('品牌：Windows主题字体与品牌标识接线正确，保留字号复核项', () {
    final appearance = File('lib/video_app/windows/windows_appearance.dart')
        .readAsStringSync();
    expect(appearance, contains('fontFamily: family'));
    expect(
      appearance,
      contains('textTheme: base.textTheme.apply(fontFamily: family)'),
    );
    expect(
      appearance,
      contains(
        'primaryTextTheme: base.primaryTextTheme.apply(fontFamily: family)',
      ),
    );
    final defaults = File('lib/video_app/ui/video_theme.dart')
        .readAsStringSync();
    expect(appearance, contains("'Microsoft YaHei UI'"));
    expect(defaults, contains("fontFamily: 'sans-serif'"));
    final labels = File('lib/l10n/windows_music_strings.dart')
        .readAsStringSync();
    expect(labels, contains('static const brandShortName = IkVersion.name;'));
    expect(labels, contains('ik'));
    final search = File('lib/video_app/ui/video_shell.dart').readAsStringSync();
    final mine = File('lib/video_app/windows/windows_my_page.dart')
        .readAsStringSync();
    expect(mine, contains('VideoStrings.appVersion'));
    expect(
      mine,
      contains('assets/branding/dj-music/source/windows/yangyin-256.png'),
    );
    expect(
      search,
      contains('assets/branding/dj-music/source/windows/yangyin-256.png'),
    );
    expect(search, contains('fontSize: 10'));
    expect(search, matches(RegExp(r'\?\s*11\s*:\s*12')));
    expect(mine, contains('fontSize: showBrandSubtitle ? 11 : 12'));
  });

  test('品牌：Android启动器、媒体通知与Windows窗口/安装器同步', () {
    final installer = File('installer/yueyin.iss').readAsStringSync();
    expect(installer, contains('#include "ik_version.iss"'));
    final version = File('installer/ik_version.iss').readAsStringSync();
    expect(version, contains('MyAppName "IK Music"'));
    expect(version, contains('MyAppVersion "0.6.1"'));
    expect(installer, contains('MZ Music.lnk'));
    expect(installer, contains('DJ Music.lnk'));
    expect(installer, contains("'{autodesktop}\\ik.lnk'"));
    expect(installer, contains("'{userprograms}\\ik"));
    expect(installer, contains('乐音音乐.lnk'));
    expect(installer, contains('悦音音乐.lnk'));
    expect(installer, contains('54A778C9-2261-4E1F-BA89-EE68844DA7AA'));
    expect(installer, contains(r'Programs\ik-music'));
    expect(installer, contains('UsePreviousAppDir=yes'));
    expect(installer, contains('PrepareToInstall'));
    expect(installer, contains('UsePreviousGroup=no'));
    expect(
      installer,
      contains(
        "CompareText(Shortcut.TargetPath, ExpandConstant('{app}\\{#MyAppExeName}')) = 0",
      ),
    );
    final main = File('windows/runner/main.cpp').readAsStringSync();
    expect(main, contains('L"IK Music"'));
    expect(main, contains('sun-dove.YueyinMusic'));
    final closeDialog = File('windows/runner/win32_window.cpp')
        .readAsStringSync();
    expect(closeDialog, contains('关闭 IK Music'));
    final floating = File('windows/runner/floating_lyrics_window.cpp')
        .readAsStringSync();
    expect(floating, contains('L"IK Music Floating Lyrics"'));
    final android = File('android/app/build.gradle.kts').readAsStringSync();
    expect(android, contains('"app.videomusic.player"'));
    expect(
      android,
      contains(
        'if (videoAppBuild) videoVersion["name"] as String else "Mconnect"',
      ),
    );
    expect(
      android,
      contains(
        'versionCode = if (videoAppBuild) (videoVersion["build"] as Number).toInt() else flutter.versionCode',
      ),
    );
    expect(
      android,
      contains(
        'versionName = if (videoAppBuild) videoVersion["version"] as String else flutter.versionName',
      ),
    );
    expect(android, contains('res.srcDir("src/yueyin/res")'));
    expect(
      File('android/app/src/yueyin/res/drawable/ic_stat_music.xml')
          .readAsStringSync(),
      contains('M6.2,14.1'),
    );
    expect(
      File('android/app/src/main/res/drawable/ic_stat_music.xml')
          .readAsStringSync(),
      contains('M12,3v10.55'),
    );
    final widgetStrings = File('android/app/src/yueyin/res/values/strings.xml')
        .readAsStringSync();
    expect(widgetStrings, contains('IK Music playback controls'));
    expect(widgetStrings, contains('mconnect_widget_idle">IK Music<'));
    final notification = File(
      'lib/features/player/data/playback_notification_service.dart',
    ).readAsStringSync();
    expect(
      notification,
      contains('androidNotificationChannelId: _playbackNotificationChannelId'),
    );
    expect(
      notification,
      contains(
        "_playbackNotificationChannelId = 'com.mconnect.mconnect.audio'",
      ),
    );
    expect(notification, contains("channelName: 'IK Music playback'"));
    expect(notification, contains("channelName: 'Mconnect playback'"));
    expect(notification, contains('initializeVideoMusic'));
    final initializer = File(
      'lib/features/player/data/background_audio_initializer.dart',
    ).readAsStringSync();
    expect(initializer, contains('initializeVideoMusic'));
    final mainActivity = File(
      'android/app/src/main/kotlin/com/mconnect/mconnect/MainActivity.kt',
    ).readAsStringSync();
    expect(mainActivity, contains('IK Music playback'));
    expect(mainActivity, contains('NotificationManager'));
    expect(mainActivity, contains('com.mconnect.mconnect.audio'));
    expect(
      mainActivity,
      contains('Build.VERSION.SDK_INT >= Build.VERSION_CODES.O'),
    );
  });

  test('品牌：Windows安装身份与Android默认Mconnect入口保持', () {
    final windowsWorkflow = File('scripts/build_video_windows.ps1')
        .readAsStringSync();
    expect(
      windowsWorkflow,
      contains(r'build-name $version.version --build-number $version.build'),
    );
    expect(
      windowsWorkflow,
      contains(r'ik-$($version.version)-windows-x64.zip'),
    );
    expect(windowsWorkflow, contains('ik 061 使用与构建.md'));
    final releaseWorkflow = File('scripts/build_video_apk.ps1')
        .readAsStringSync();
    expect(
      releaseWorkflow,
      contains(r'--build-name $version.version --build-number $version.build'),
    );
    expect(releaseWorkflow, contains("VIDEO_MUSIC_BUILD = '1'"));
    final main = File('windows/runner/main.cpp').readAsStringSync();
    expect(main, contains('L"Mconnect"'));
    final floating = File('windows/runner/floating_lyrics_window.cpp')
        .readAsStringSync();
    expect(floating, contains('L"Mconnect Floating Lyrics"'));
    final android = File('android/app/build.gradle.kts').readAsStringSync();
    expect(android, contains('else "Mconnect"'));
    final resource = File('windows/runner/Yueyin.rc').readAsStringSync();
    expect(resource, contains('VERSION_AS_NUMBER IK_VERSION_NUMBER'));
    final version = File('windows/runner/ik_version.h').readAsStringSync();
    expect(version, contains('IK_VERSION_NUMBER 0,6,1,12'));
    expect(version, contains('IK_VERSION_STRING "0.6.1"'));
    // path_provider_windows 从 CompanyName/ProductName 推导账号和数据库目录。
    expect(resource, contains('"CompanyName", "sun-dove"'));
    expect(resource, contains('"ProductName", "YueyinMusic"'));
    expect(resource, contains('"FileDescription", IK_APP_NAME'));
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('version: 1.5.0+16'),
    );
  });

  test('图标包：Windows、Android、iOS和Linux资源均完整', () {
    final requiredAssets = [
      'assets/branding/dj-music/source/windows/yangyin.ico',
      'assets/branding/dj-music/source/windows/yangyin-256.png',
      'assets/branding/dj-music/source/android/play-store-512.png',
      'assets/branding/dj-music/source/android/res/mipmap-anydpi-v26/ic_launcher.xml',
      'assets/branding/dj-music/source/android/res/mipmap-anydpi-v26/ic_launcher_round.xml',
      'assets/branding/dj-music/source/android/res/drawable/ic_launcher_foreground.xml',
      'assets/branding/dj-music/source/android/res/drawable/ic_launcher_background.xml',
      'assets/branding/dj-music/source/ios/AppIcon.appiconset/Contents.json',
      'assets/branding/dj-music/source/ios/AppIcon.appiconset/icon-1024.png',
      'assets/branding/dj-music/source/linux/yangyin.desktop',
      'assets/branding/dj-music/source/linux/hicolor/scalable/apps/yangyin.svg',
    ];
    for (final path in requiredAssets) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
    final androidFiles = Directory('android/app/src/yueyin/res')
        .listSync(recursive: true)
        .whereType<File>()
        .map((file) => file.path.replaceAll('\\', '/'))
        .toSet();
    for (final density in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
      expect(
        androidFiles,
        contains('android/app/src/yueyin/res/mipmap-$density/ic_launcher.png'),
      );
      expect(
        androidFiles,
        contains(
          'android/app/src/yueyin/res/mipmap-$density/ic_launcher_round.png',
        ),
      );
      expect(
        androidFiles,
        contains(
          'android/app/src/yueyin/res/drawable/dj_music_launcher_foreground.xml',
        ),
      );
    }
    expect(
      androidFiles,
      contains('android/app/src/yueyin/res/mipmap-anydpi-v26/ic_launcher.xml'),
    );
    expect(
      androidFiles,
      contains(
        'android/app/src/yueyin/res/mipmap-anydpi-v26/ic_launcher_round.xml',
      ),
    );
    final adaptive = File(
      'android/app/src/yueyin/res/mipmap-anydpi-v26/ic_launcher.xml',
    ).readAsStringSync();
    expect(adaptive, contains('@drawable/dj_music_launcher_background'));
    expect(adaptive, contains('@drawable/dj_music_launcher_foreground'));
    final adaptiveRound = File(
      'android/app/src/yueyin/res/mipmap-anydpi-v26/ic_launcher_round.xml',
    ).readAsStringSync();
    expect(adaptiveRound, contains('@drawable/dj_music_launcher_background'));
    expect(adaptiveRound, contains('@drawable/dj_music_launcher_foreground'));
    final launch = File(
      'android/app/src/yueyin/res/drawable/launch_background.xml',
    ).readAsStringSync();
    expect(launch, contains('@color/dj_music_background'));
    expect(launch, contains('@drawable/dj_music_launcher_foreground'));
    expect(
      File('android/app/src/yueyin/res/values/colors.xml').readAsStringSync(),
      contains('<color name="dj_music_background">'),
    );
    final android = File('android/app/build.gradle.kts').readAsStringSync();
    expect(
      android,
      contains(
        'versionCode = if (videoAppBuild) (videoVersion["build"] as Number).toInt()',
      ),
    );
    expect(
      android,
      contains(
        'versionName = if (videoAppBuild) videoVersion["version"] as String',
      ),
    );
    expect(
      android,
      contains(
        'if (videoAppBuild) videoVersion["name"] as String else "Mconnect"',
      ),
    );
    expect(android, contains('"@mipmap/ic_launcher_round"'));
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(manifest, contains(r'android:roundIcon="${roundIcon}"'));
    final scopedLaunch = File(
      'android/app/src/yueyin/res/drawable-v21/launch_background.xml',
    ).readAsStringSync();
    expect(scopedLaunch, contains('@color/dj_music_background'));
    expect(scopedLaunch, contains('@drawable/dj_music_launcher_foreground'));
    final splash = File(
      'android/app/src/yueyin/res/drawable/android12splash.xml',
    ).readAsStringSync();
    expect(splash, contains('@drawable/dj_music_android12_splash'));
    expect(
      File('android/app/src/yueyin/res/values-v31/styles.xml')
          .readAsStringSync(),
      contains('@drawable/dj_music_android12_splash'),
    );
    expect(
      File('android/app/src/yueyin/res/values-night-v31/styles.xml')
          .readAsStringSync(),
      contains('@drawable/dj_music_android12_splash'),
    );
    expect(
      File(
        'android/app/src/yueyin/res/drawable-night/dj_music_launcher_background.xml',
      ).existsSync(),
      isTrue,
    );
    expect(
      File(
        'android/app/src/yueyin/res/drawable-night-v31/dj_music_android12_splash.xml',
      ).existsSync(),
      isTrue,
    );
    final rounds = File(
      'android/app/src/yueyin/res/mipmap-anydpi-v26/ic_launcher_round.xml',
    ).readAsStringSync();
    expect(rounds, contains('@drawable/dj_music_launcher_foreground'));
    final windowsIcons = Directory('windows/runner/resources')
        .listSync()
        .whereType<File>()
        .map((file) => file.path.replaceAll('\\', '/'))
        .toSet();
    expect(windowsIcons, contains('windows/runner/resources/yueyin_icon.ico'));
    expect(windowsIcons, contains('windows/runner/resources/app_icon.ico'));
    expect(
      File('windows/runner/resources/yueyin_icon.ico').readAsBytesSync(),
      File('assets/branding/dj-music/source/windows/yangyin.ico')
          .readAsBytesSync(),
    );
    expect(
      File('windows/runner/CMakeLists.txt').readAsStringSync(),
      contains('if(YUEYIN_BUILD)'),
    );
    expect(
      File('installer/yueyin.iss').readAsStringSync(),
      contains(r'CompareText(Shortcut.TargetPath, ExpandConstant'),
    );
  });

  test('品牌：GitHub仓库统一ik-music，独立产品显示IK Music', () {
    expect(
      File('README.md').readAsStringSync(),
      contains('https://github.com/sun-dove/ik-music'),
    );
    final labels = File('lib/l10n/video_strings.dart').readAsStringSync();
    expect(labels, contains("static const appName = IkVersion.name;"));
    expect(
      File('android/app/build.gradle.kts').readAsStringSync(),
      contains(
        'if (videoAppBuild) videoVersion["name"] as String else "Mconnect"',
      ),
    );
    final readme = File('README.md').readAsStringSync();
    expect(readme, contains('sun-dove/ik-music'));
    expect(readme, contains('IK Music'));
    expect(readme, contains('https://github.com/sun-dove/ik-music'));
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('assets/branding/dj-music/source/windows/yangyin-256.png'),
    );
    expect(File('docs/交付文档/ik 061 使用与构建.md').existsSync(), isTrue);
    expect(
      File('lib/video_app/ui/video_shell.dart').readAsStringSync(),
      contains('assets/branding/dj-music/source/windows/yangyin-256.png'),
    );
    expect(
      File('lib/video_app/windows/windows_my_page.dart').readAsStringSync(),
      contains('assets/branding/dj-music/source/windows/yangyin-256.png'),
    );
  });
}

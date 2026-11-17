import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/l10n/video_strings.dart';
import 'package:mconnect/l10n/expanded_strings.dart';

void main() {
  test('W12：乐音（yuè）音乐显示品牌、独立版本一致，升级身份保留', () {
    expect(VideoStrings.appName, '乐音音乐');
    expect(ExpandedStrings.appName, '乐音音乐');
    expect(VideoStrings.appVersion, '乐音音乐 · 0.5.0');
    final installer = File('installer/yueyin.iss').readAsStringSync();
    expect(installer, contains('MyAppName "乐音音乐"'));
    expect(installer, contains('MyAppVersion "0.5.0"'));
    expect(installer, contains('54A778C9-2261-4E1F-BA89-EE68844DA7AA'));
    expect(installer, contains(r'Programs\YueyinMusic'));
    expect(installer, contains('UsePreviousGroup=no'));
    expect(
      installer,
      contains(
        "CompareText(Shortcut.TargetPath, ExpandConstant('{app}\\{#MyAppExeName}')) = 0",
      ),
    );
    final main = File('windows/runner/main.cpp').readAsStringSync();
    expect(main, contains('L"乐音音乐"'));
    expect(main, contains('sun-dove.YueyinMusic'));
    final android = File('android/app/build.gradle.kts').readAsStringSync();
    expect(android, contains('"app.videomusic.player"'));
    expect(android, contains('if (videoAppBuild) "乐音音乐" else "Mconnect"'));
    expect(
      android,
      contains('versionCode = if (videoAppBuild) 8 else flutter.versionCode'),
    );
    expect(
      android,
      contains(
        'versionName = if (videoAppBuild) "0.5.0" else flutter.versionName',
      ),
    );
    final resource = File('windows/runner/Yueyin.rc').readAsStringSync();
    expect(resource, contains('VERSION_AS_NUMBER 0,5,0,8'));
    // path_provider_windows 从 CompanyName/ProductName 推导账号和数据库目录。
    expect(resource, contains('"CompanyName", "sun-dove"'));
    expect(resource, contains('"ProductName", "YueyinMusic"'));
    expect(resource, contains('"FileDescription", "乐音音乐"'));
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('version: 1.5.0+16'),
    );
  });
}

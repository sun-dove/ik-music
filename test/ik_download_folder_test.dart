import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/platform/platform_utils.dart';
import 'package:mconnect/features/download/data/download_directory_service.dart';
import 'package:mconnect/video_app/ik/ik_download_folder.dart';

class _DirectoryService extends DownloadDirectoryService {
  int opens = 0;
  bool result = true;
  Object? error;

  @override
  Future<bool> openSafDirectory() async {
    opens++;
    if (error != null) throw error!;
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const launcher = MethodChannel('plugins.flutter.io/url_launcher');
  const fileOpener = MethodChannel('com.mconnect.mconnect/file_opener');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final launched = <MethodCall>[];
  final nativeCalls = <MethodCall>[];
  var launchResult = true;
  Object? launchError;
  Object? nativeError;
  late _DirectoryService service;

  setUp(() {
    PlatformUtils.setDebugOverride(AppPlatform.windows);
    launched.clear();
    nativeCalls.clear();
    launchResult = true;
    launchError = null;
    nativeError = null;
    service = _DirectoryService();
    messenger.setMockMethodCallHandler(launcher, (call) async {
      launched.add(call);
      if (launchError != null) throw launchError!;
      return launchResult;
    });
    messenger.setMockMethodCallHandler(fileOpener, (call) async {
      nativeCalls.add(call);
      if (nativeError != null) throw nativeError!;
      return true;
    });
  });

  tearDown(() {
    PlatformUtils.setDebugOverride(null);
    messenger.setMockMethodCallHandler(launcher, null);
    messenger.setMockMethodCallHandler(fileOpener, null);
  });

  test('A06 Windows通过已有URL插件打开父目录，正确编码中文空格井号与百分号', () async {
    await openIkDownloadFolder(service, r'C:\Music\中文 空格#%\歌曲.flac');
    expect(nativeCalls, isEmpty);
    expect(launched, hasLength(1));
    final call = launched.single;
    expect(call.method, 'launch');
    final arguments = call.arguments as Map;
    final uri = Uri.parse(arguments['url'] as String);
    expect(uri.scheme, 'file');
    expect(uri.toFilePath(windows: true), 'C:\\Music\\中文 空格#%\\');
    expect(uri.hasFragment, isFalse);
    expect(uri.hasQuery, isFalse);
    expect(arguments['useWebView'], isFalse);
    expect(arguments['useSafariVC'], isFalse);
    expect(service.opens, 0);
  });

  test('A06 Windows盘符正斜线及UNC共享目录保持路径身份', () async {
    for (final paths in [
      ('D:/音 乐/专辑/歌曲.mp3', 'D:\\音 乐\\专辑\\'),
      (r'\\server\share\Music\歌曲.flac', '\\\\server\\share\\Music\\'),
    ]) {
      await openIkDownloadFolder(service, paths.$1);
      final uri = Uri.parse((launched.last.arguments as Map)['url'] as String);
      expect(uri.toFilePath(windows: true), paths.$2);
    }
    expect(launched, hasLength(2));
    expect(nativeCalls, isEmpty);
  });

  test('A06 Windows系统拒绝或插件异常不能报告目录打开成功', () async {
    launchResult = false;
    await expectLater(
      openIkDownloadFolder(service, r'C:\Music\歌曲.flac'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('没有可以打开'),
        ),
      ),
    );
    launchError = PlatformException(code: 'OPEN_FAILED', message: '资源管理器拒绝');
    await expectLater(
      openIkDownloadFolder(service, r'C:\Music\歌曲.flac'),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'OPEN_FAILED',
        ),
      ),
    );
    expect(nativeCalls, isEmpty);
  });

  test('A06 Android普通路径沿用原通道，POSIX文件名中的反斜线不是目录', () async {
    PlatformUtils.setDebugOverride(AppPlatform.android);
    await openIkDownloadFolder(service, r'/storage/emulated/0/音乐/文件\名.flac');
    expect(launched, isEmpty);
    expect(nativeCalls, hasLength(1));
    expect(nativeCalls.single.method, 'openFolder');
    expect(nativeCalls.single.arguments, '/storage/emulated/0/音乐');
    nativeError = PlatformException(code: 'OPEN_FAILED', message: '目录权限已失效');
    await expectLater(
      openIkDownloadFolder(service, '/storage/emulated/0/音乐/歌曲.flac'),
      throwsA(
        isA<Exception>().having(
          (error) => '$error',
          'message',
          contains('目录权限已失效'),
        ),
      ),
    );
  });

  test('A06 SAF继续走已选目录服务，失败不回退到普通文件通道', () async {
    PlatformUtils.setDebugOverride(AppPlatform.android);
    const uri = 'content://documents/tree/primary%3AMusic/document/track';
    await openIkDownloadFolder(service, uri);
    expect(service.opens, 1);
    service.result = false;
    await expectLater(openIkDownloadFolder(service, uri), throwsStateError);
    service.error = StateError('SAF授权读取失败');
    await expectLater(
      openIkDownloadFolder(service, uri),
      throwsA(same(service.error)),
    );
    expect(service.opens, 3);
    expect(launched, isEmpty);
    expect(nativeCalls, isEmpty);
  });

  test('A06 空路径显式失败且不调用系统服务', () async {
    for (final path in [null, '', '  ']) {
      await expectLater(openIkDownloadFolder(service, path), throwsStateError);
    }
    expect(launched, isEmpty);
    expect(nativeCalls, isEmpty);
    expect(service.opens, 0);
  });
}

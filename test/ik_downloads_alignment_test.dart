import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/download/domain/entities/download_failure.dart';
import 'package:mconnect/features/download/domain/entities/download_task.dart';
import 'package:mconnect/l10n/video_strings.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/video_app/ik/ik_downloads_workspace.dart';
import 'package:mconnect/video_app/ik/ik_workspace_theme.dart';

DownloadTask _task(
  String id,
  DownloadStatus status, {
  bool cache = false,
  String? error,
  String? path,
  DownloadFailureKind? failure,
}) => DownloadTask(
  id: id,
  song: Song(
    id: id,
    name: '歌曲 $id',
    platform: PlatformType.qq,
    artists: const [Artist(id: 'artist', name: '歌手')],
  ),
  quality: AudioLevel.lossless,
  status: status,
  progress: .4,
  downloadedBytes: 4096,
  totalBytes: 10240,
  createdAt: DateTime(2026, 11, 21),
  filePath: path,
  error: error,
  failureKind: failure,
  isOfflineCache: cache,
);

void main() {
  Future<void> mount(
    WidgetTester tester,
    List<DownloadTask> tasks, {
    double width = 1200,
    double scale = 1,
    Brightness brightness = Brightness.light,
    String? blocked,
    List<String>? actions,
    Future<void> Function(DownloadTask)? onPause,
    Future<void> Function(DownloadTask)? onOpenFolder,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: IkWorkspaceTheme.from(ThemeData(brightness: brightness)),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: IkDownloadsWorkspace(
            tasks: tasks,
            queueBlockedReason: blocked,
            onDirectory: () => actions?.add('directory'),
            onPause:
                onPause ?? (task) async => actions?.add('pause:${task.id}'),
            onResume: (task) async => actions?.add('resume:${task.id}'),
            onResolve: (task) async => actions?.add('resolve:${task.id}'),
            onCancel: (task) async => actions?.add('cancel:${task.id}'),
            onPlay: (task) async => actions?.add('play:${task.id}'),
            onOpenFolder:
                onOpenFolder ??
                (task) async => actions?.add('folder:${task.id}'),
            canResolve: (task) => ![
              DownloadFailureKind.notFound,
              DownloadFailureKind.unsupported,
              DownloadFailureKind.cancelled,
              DownloadFailureKind.unknown,
            ].contains(task.failureKind),
            actionLabel: (task) => switch (task.failureKind) {
              DownloadFailureKind.auth => VideoStrings.loginAgain,
              DownloadFailureKind.vip => VideoStrings.chooseDownloadQuality,
              DownloadFailureKind.storagePermission =>
                VideoStrings.chooseStorageAgain,
              DownloadFailureKind.disk => VideoStrings.freeStorageRetry,
              DownloadFailureKind.notFound || DownloadFailureKind.unsupported =>
                VideoStrings.resourceCannotDownload,
              DownloadFailureKind.cancelled ||
              DownloadFailureKind.unknown => VideoStrings.taskCannotRetry,
              _ => VideoStrings.retryDownload,
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder key(String value) => find.byKey(ValueKey(value));
  Future<void> tap(WidgetTester tester, String value) async {
    await tester.ensureVisible(key(value));
    await tester.pumpAndSettle();
    expect(key(value).hitTestable(), findsOneWidget);
    await tester.tap(key(value));
    await tester.pumpAndSettle();
  }

  testWidgets('A06 手动任务分三组准确计数，离线缓存不混入', (tester) async {
    await mount(tester, [
      _task('waiting', DownloadStatus.waiting),
      _task('active', DownloadStatus.downloading),
      _task('paused', DownloadStatus.paused),
      _task('done', DownloadStatus.completed, path: 'C:/Music/done.flac'),
      _task('fail', DownloadStatus.failed, error: '网络中断'),
      _task('cache', DownloadStatus.downloading, cache: true),
    ]);
    expect(find.text('进行中 · 3'), findsOneWidget);
    expect(find.text('已完成 · 1'), findsOneWidget);
    expect(find.text('失败 · 1'), findsOneWidget);
    expect(find.text('歌曲 cache'), findsNothing);
    expect(find.text('歌曲 waiting'), findsOneWidget);
    await tap(tester, 'ik-downloads-group-completed');
    expect(find.text('歌曲 done'), findsOneWidget);
    expect(find.text('歌曲 waiting'), findsNothing);
    await tap(tester, 'ik-downloads-group-failed');
    expect(find.text('歌曲 fail'), findsOneWidget);
    expect(find.text('网络中断'), findsOneWidget);
  });

  testWidgets('A06 批量暂停仅下载中、继续仅暂停且保留等待取消', (tester) async {
    final actions = <String>[];
    await mount(tester, [
      _task('waiting', DownloadStatus.waiting),
      _task('active', DownloadStatus.downloading),
      _task('paused', DownloadStatus.paused),
      _task('fail', DownloadStatus.failed),
      _task('cache', DownloadStatus.downloading, cache: true),
    ], actions: actions);
    await tap(tester, 'ik-downloads-pause-all');
    expect(actions, ['pause:active']);
    await tap(tester, 'ik-downloads-resume-all');
    expect(actions, ['pause:active', 'resume:paused']);
    expect(key('ik-download-pause-waiting'), findsNothing);
    await tap(tester, 'ik-download-cancel-waiting');
    expect(actions.last, 'cancel:waiting');
    await tap(tester, 'ik-downloads-directory');
    expect(actions.last, 'directory');
  });

  testWidgets('A06 失败动作采用真实权限和文案，没有统一盲目重试', (tester) async {
    final actions = <String>[];
    await mount(tester, [
      _task(
        'login',
        DownloadStatus.failed,
        failure: DownloadFailureKind.auth,
        error: '登录已过期',
      ),
      _task(
        'missing',
        DownloadStatus.failed,
        failure: DownloadFailureKind.notFound,
        error: '资源不存在',
      ),
    ], actions: actions);
    await tap(tester, 'ik-downloads-group-failed');
    expect(find.text(VideoStrings.loginAgain), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(key('ik-download-resolve-missing'))
          .onPressed,
      isNull,
    );
    await tap(tester, 'ik-download-resolve-login');
    expect(actions, ['resolve:login']);
    expect(key('ik-downloads-retry-all'), findsNothing);
  });

  testWidgets('A06 完成任务详情原位展开，真实路径质量播放与目录可用', (tester) async {
    final actions = <String>[];
    await mount(tester, [
      _task('done', DownloadStatus.completed, path: 'C:/Music/done.flac'),
    ], actions: actions);
    await tap(tester, 'ik-downloads-group-completed');
    await tap(tester, 'ik-download-details-done');
    expect(find.text('C:/Music/done.flac'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    await tap(tester, 'ik-download-play-done');
    await tap(tester, 'ik-download-folder-done');
    expect(actions, ['play:done', 'folder:done']);
  });

  testWidgets('A06 全部九类失败原因原样可见，动作权限逐类保留', (tester) async {
    final expected = {
      DownloadFailureKind.network: VideoStrings.retryDownload,
      DownloadFailureKind.auth: VideoStrings.loginAgain,
      DownloadFailureKind.vip: VideoStrings.chooseDownloadQuality,
      DownloadFailureKind.disk: VideoStrings.freeStorageRetry,
      DownloadFailureKind.storagePermission: VideoStrings.chooseStorageAgain,
      DownloadFailureKind.notFound: VideoStrings.resourceCannotDownload,
      DownloadFailureKind.unsupported: VideoStrings.resourceCannotDownload,
      DownloadFailureKind.cancelled: VideoStrings.taskCannotRetry,
      DownloadFailureKind.unknown: VideoStrings.taskCannotRetry,
    };
    final forbidden = {
      DownloadFailureKind.notFound,
      DownloadFailureKind.unsupported,
      DownloadFailureKind.cancelled,
      DownloadFailureKind.unknown,
    };
    var checked = 0;
    for (final failure in DownloadFailureKind.values) {
      final actions = <String>[];
      await mount(tester, [
        _task(
          failure.name,
          DownloadStatus.failed,
          failure: failure,
          error: '真实失败：${failure.name}',
        ),
      ], actions: actions);
      await tap(tester, 'ik-downloads-group-failed');
      expect(find.text('真实失败：${failure.name}'), findsOneWidget);
      expect(find.text(expected[failure]!), findsOneWidget);
      final button = key('ik-download-resolve-${failure.name}');
      expect(
        tester.widget<OutlinedButton>(button).onPressed,
        forbidden.contains(failure) ? isNull : isNotNull,
      );
      if (!forbidden.contains(failure)) {
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(actions, ['resolve:${failure.name}']);
      }
      checked++;
      await tester.pumpWidget(const SizedBox.shrink());
    }
    expect(checked, 9);
  });

  testWidgets('A06 批量中单项失败不吞错且继续处理其他下载', (tester) async {
    final actions = <String>[];
    await mount(
      tester,
      [
        _task('first', DownloadStatus.downloading),
        _task('second', DownloadStatus.downloading),
        _task('waiting', DownloadStatus.waiting),
      ],
      onPause: (task) async {
        actions.add(task.id);
        if (task.id == 'first') throw StateError('暂停失败');
      },
    );
    await tap(tester, 'ik-downloads-pause-all');
    expect(actions, ['first', 'second']);
    expect(find.textContaining('暂停失败'), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(key('ik-downloads-pause-all')).onPressed,
      isNotNull,
    );
  });

  testWidgets('A06 任务缺文件路径不提供假目录动作', (tester) async {
    await mount(tester, [_task('done', DownloadStatus.completed)]);
    await tap(tester, 'ik-downloads-group-completed');
    expect(
      tester.widget<OutlinedButton>(key('ik-download-folder-done')).onPressed,
      isNull,
    );
    await tap(tester, 'ik-download-details-done');
    expect(find.text(VideoStrings.downloadMissing), findsOneWidget);
  });

  testWidgets('A06 队列阻塞和回调失败留在页内，失败后允许重试', (tester) async {
    var attempts = 0;
    await mount(
      tester,
      [_task('done', DownloadStatus.completed, path: 'C:/Music/done.flac')],
      blocked: '目录权限已失效',
      onOpenFolder: (_) async {
        attempts++;
        throw StateError('系统无法打开目录');
      },
    );
    expect(find.text('目录权限已失效'), findsOneWidget);
    await tap(tester, 'ik-downloads-group-completed');
    await tap(tester, 'ik-download-folder-done');
    expect(find.textContaining('系统无法打开目录'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      tester.widget<OutlinedButton>(key('ik-download-folder-done')).onPressed,
      isNotNull,
    );
    expect(attempts, 1);
  });

  testWidgets('A06 正在操作不重复派发，同一行显示忙碌', (tester) async {
    final pending = Completer<void>();
    var count = 0;
    await mount(
      tester,
      [_task('active', DownloadStatus.downloading)],
      onPause: (_) {
        count++;
        return pending.future;
      },
    );
    await tester.tap(key('ik-download-pause-active'));
    await tester.pump();
    expect(
      tester.widget<OutlinedButton>(key('ik-download-pause-active')).onPressed,
      isNull,
    );
    expect(count, 1);
    pending.complete();
    await tester.pumpAndSettle();
    expect(
      tester.widget<OutlinedButton>(key('ik-download-pause-active')).onPressed,
      isNotNull,
    );
  });

  testWidgets('A06 长列表按需构建且末项可滚达', (tester) async {
    await mount(tester, [
      for (var i = 0; i < 180; i++) _task('item-$i', DownloadStatus.waiting),
    ]);
    expect(key('ik-download-row-item-0'), findsNothing);
    expect(key('ik-download-row-item-179'), findsOneWidget);
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      key('ik-download-row-item-0'),
      500,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 100,
    );
    expect(key('ik-download-row-item-0'), findsOneWidget);
  });

  testWidgets('A06 空组显示明确空态且批量按钮禁用', (tester) async {
    await mount(tester, [
      _task('cache', DownloadStatus.downloading, cache: true),
    ]);
    expect(find.text(VideoStrings.noDownloads), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(key('ik-downloads-pause-all')).onPressed,
      isNull,
    );
    expect(
      tester.widget<OutlinedButton>(key('ik-downloads-resume-all')).onPressed,
      isNull,
    );
  });

  testWidgets('A06/A07 浅深×六宽×三字号×三组完整108布局包含详情无溢出', (tester) async {
    var checked = 0;
    final tasks = [
      _task('waiting', DownloadStatus.waiting),
      _task('active', DownloadStatus.downloading),
      _task('paused', DownloadStatus.paused),
      _task(
        'done',
        DownloadStatus.completed,
        path: 'C:/Music/很长的音乐文件目录/专辑/歌曲 [lossless].flac',
      ),
      _task(
        'fail',
        DownloadStatus.failed,
        failure: DownloadFailureKind.auth,
        error: '登录已过期，请重新登录后继续下载，此处显示完整的真实失败原因',
      ),
    ];
    for (final brightness in Brightness.values) {
      for (final width in [1440.0, 1200.0, 900.0, 720.0, 390.0, 320.0]) {
        for (final scale in [1.0, 1.25, 1.5]) {
          await mount(
            tester,
            tasks,
            width: width,
            scale: scale,
            brightness: brightness,
            blocked: '下载目录不可写，请重新选择目录',
          );
          for (final group in ['current', 'completed', 'failed']) {
            await tap(tester, 'ik-downloads-group-$group');
            final task = group == 'current'
                ? 'paused'
                : group == 'completed'
                ? 'done'
                : 'fail';
            await tap(tester, 'ik-download-details-$task');
            expect(
              tester.takeException(),
              isNull,
              reason: '$brightness $width $scale $group',
            );
            checked++;
          }
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    }
    expect(checked, 108);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/playlist.dart';
import 'package:mconnect/video_app/data/video_catalog.dart';
import 'package:mconnect/video_app/data/video_kugou_catalog.dart';
import 'package:mconnect/video_app/ui/kugou_playlists_page.dart';

void main() {
  testWidgets('歌单失败可重试，未完整曲目不显示已获取全部，会话失效后禁止播放', (tester) async {
    var fail = true, current = true;
    var plays = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: VideoKugouPlaylistsPage(
          isSessionCurrent: () => current,
          loadPlaylists: () async => fail
              ? const VideoKugouPlaylists(
                  error: VideoFailure(
                    VideoFailureKind.network,
                    '网络失败，请重试。',
                    canRetry: true,
                  ),
                )
              : const VideoKugouPlaylists(
                  items: [
                    Playlist(
                      id: 'p',
                      name: '我的歌单',
                      platform: PlatformType.kugou,
                    ),
                  ],
                  complete: true,
                ),
          loadSongs: (_) async => const VideoLibrary(
            total: 10,
            error: VideoFailure(
              VideoFailureKind.incomplete,
              '歌曲尚未获取完整，请重试。',
              canRetry: true,
            ),
          ),
          onPlay: (_, _) {
            plays++;
          },
          onDownload: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('网络失败，请重试。'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的歌单'));
    await tester.pumpAndSettle();
    expect(find.text('歌曲尚未获取完整，请重试。'), findsOneWidget);
    expect(find.textContaining('已获取全部'), findsNothing);
    current = false;
    await tester.tap(find.byTooltip('刷新歌单'));
    await tester.pumpAndSettle();
    expect(find.text('登录状态已变化，请返回重新打开歌单。'), findsOneWidget);
    expect(plays, 0);
  });
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/video_app/data/video_catalog.dart';
import 'package:mconnect/video_app/ik/ik_search.dart';

Song song(PlatformType platform, String id) =>
    Song(id: id, platform: platform, name: id, artists: const <Artist>[]);

void main() {
  test('K03 四来源同时开始，单源失败保留其余结果且只重试该源', () async {
    final calls = <PlatformType>[];
    var fail = true;
    final controller = IkSearchController(
      search: (platform, query, page) async {
        calls.add(platform);
        if (platform == PlatformType.qq && fail) {
          throw const VideoFailure(
            VideoFailureKind.network,
            '网络错误',
            canRetry: true,
          );
        }
        return VideoPage(
          songs: [song(platform, query)],
          page: page,
          hasMore: false,
        );
      },
    );
    addTearDown(controller.dispose);
    await controller.submit('音乐');
    expect(calls.toSet(), controller.platforms.toSet());
    expect(controller.groups[PlatformType.qq]!.error!.canRetry, isTrue);
    expect(controller.songs.length, 3);
    calls.clear();
    fail = false;
    await controller.retry(PlatformType.qq);
    expect(calls, [PlatformType.qq]);
    expect(controller.songs.length, 4);
  });

  test('K03 迟到的旧查询不能覆盖新查询', () async {
    final old = Completer<VideoPage>();
    final controller = IkSearchController(
      platforms: const [PlatformType.qq],
      search: (platform, query, page) => query == '旧'
          ? old.future
          : Future.value(
              VideoPage(
                songs: [song(platform, query)],
                page: 1,
                hasMore: false,
              ),
            ),
    );
    addTearDown(controller.dispose);
    final pending = controller.submit('旧');
    await controller.submit('新');
    old.complete(
      VideoPage(songs: [song(PlatformType.qq, '旧')], page: 1, hasMore: false),
    );
    await pending;
    expect(controller.songs.single.id, '新');
  });

  test('K03 独立分页保留旧行，失败重试同页且去重不跨平台', () async {
    final calls = <(PlatformType, int)>[];
    var fail = true;
    final controller = IkSearchController(
      platforms: const [PlatformType.qq, PlatformType.netease],
      search: (platform, query, page) async {
        calls.add((platform, page));
        if (page == 2 && fail) {
          throw const VideoFailure(
            VideoFailureKind.network,
            '超时',
            canRetry: true,
          );
        }
        return VideoPage(
          songs: [song(platform, '共同ID'), if (page == 2) song(platform, '第二页')],
          page: page,
          hasMore: page == 1,
        );
      },
    );
    addTearDown(controller.dispose);
    await controller.submit('歌');
    await controller.loadMore(PlatformType.qq);
    expect(controller.songs.length, 2);
    fail = false;
    await controller.retry(PlatformType.qq);
    expect(calls, [
      (PlatformType.qq, 1),
      (PlatformType.netease, 1),
      (PlatformType.qq, 2),
      (PlatformType.qq, 2),
    ]);
    expect(controller.groups[PlatformType.qq]!.page, 2);
    expect(controller.groups[PlatformType.netease]!.page, 1);
    expect(controller.songs.length, 3);
  });
}

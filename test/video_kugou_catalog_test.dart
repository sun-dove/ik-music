import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/platform/base/platform_registry.dart';
import 'package:mconnect/platform/kugou/kugou_api.dart';
import 'package:mconnect/platform/kugou/kugou_platform.dart';
import 'package:mconnect/video_app/data/video_kugou_catalog.dart';
import 'package:mconnect/video_app/data/video_catalog.dart';

void main() {
  test('酷狗搜索保留平台hash与总数，不能把未支持的平台当空结果', () async {
    final api = _Api();
    PlatformRegistry.register(KugouPlatform(api: api));
    final catalog = ExpandedVideoCatalog();
    final page = await catalog.search(PlatformType.kugou, '验收');
    expect(page.total, 51);
    expect(page.hasMore, isTrue);
    expect(page.songs.single.id, 'hash-0');
    expect(page.songs.single.platform, PlatformType.kugou);
  });
  test('酷狗喜欢遍历全部分页，后页失败保留已获取歌曲并明确不完整', () async {
    final api = _Api()..failPage = 3;
    PlatformRegistry.register(KugouPlatform(api: api));
    final catalog = ExpandedVideoCatalog();
    final library = await catalog.syncLikes(PlatformType.kugou, userId: 'u');
    expect(api.pages, [1, 2, 3]);
    expect(library.songs, hasLength(100));
    expect(library.complete, isFalse);
    expect(library.error, isNotNull);
  });
  test('酷狗收藏写入返回空对象不能提示收藏成功', () async {
    final api = _Api();
    final catalog = VideoKugouCatalog(api: api);
    final song = (await catalog.search('歌')).songs.single;
    await expectLater(
      catalog.setLiked(song, true),
      throwsA(
        isA<VideoFailure>().having(
          (error) => error.kind,
          '错误类别',
          VideoFailureKind.invalidResponse,
        ),
      ),
    );
  });
  test('用户歌单逐页合并创建与收藏，详情用原listid完整翻页', () async {
    final api = _Api();
    final catalog = VideoKugouCatalog(api: api);
    final playlists = await catalog.playlists(userId: 'u');
    expect(api.playlistPages, [1, 2]);
    expect(playlists.complete, isTrue);
    expect(playlists.items, hasLength(51));
    expect(playlists.items.first.id, 'collection-0');
    expect(playlists.items.first.editableId, 'list-0');
    final songs = await catalog.playlistSongs(
      playlists.items.first,
      userId: 'u',
    );
    expect(api.songPages, [1, 2]);
    expect(songs.songs, hasLength(101));
    expect(songs.complete, isTrue);
  });
  test('未登录与服务端返回结构缺失不能伪装为空歌单', () async {
    final catalog = VideoKugouCatalog(api: _Api()..invalidPlaylists = true);
    expect(
      (await catalog.playlists(userId: '')).error?.kind,
      VideoFailureKind.notLoggedIn,
    );
    expect(
      (await catalog.playlists(userId: 'u')).error?.kind,
      VideoFailureKind.invalidResponse,
    );
  });
}

class _Api extends KugouApi {
  int? failPage;
  final pages = <int>[];
  final playlistPages = <int>[];
  final songPages = <int>[];
  bool invalidPlaylists = false;
  @override
  Future<Map<String, dynamic>> collectSong(String hash) async => {};
  @override
  Future<Map<String, dynamic>> getUserPlaylists({
    int page = 1,
    int limit = 50,
  }) async {
    playlistPages.add(page);
    if (invalidPlaylists) return {'status': 1, 'data': {}};
    return {
      'status': 1,
      'data': {
        'total': 51,
        'list_create_list': [
          for (var i = (page - 1) * 50; i < page * 50 && i < 51; i++)
            {
              'global_collection_id': 'collection-$i',
              'listid': 'list-$i',
              'listname': '歌单$i',
              'song_num': 101,
            },
        ],
        'list_collect_list': [],
      },
    };
  }

  @override
  Future<Map<String, dynamic>> getUserPlaylistSongs(
    String listid, {
    int page = 1,
    int limit = 100,
  }) async {
    expect(listid, 'list-0');
    songPages.add(page);
    return {
      'status': 1,
      'data': {
        'total': 101,
        'songs': [
          for (var i = (page - 1) * limit; i < page * limit && i < 101; i++)
            _song(i),
        ],
      },
    };
  }

  Map<String, dynamic> _song(int index) => {
    'hash': 'hash-$index',
    'songname': '歌$index',
    'singername': '歌手',
    'album_id': 'album-1',
    'HQFileHash': 'hq-$index',
  };
  @override
  Future<Map<String, dynamic>> search(
    String keyword, {
    int page = 1,
    int limit = 30,
  }) async => {
    'status': 1,
    'data': {
      'total': 51,
      'info': [_song(0)],
    },
  };
  @override
  Future<Map<String, dynamic>> getLikedSongs({
    int page = 1,
    int limit = 50,
  }) async {
    pages.add(page);
    if (page == failPage) throw StateError('fixture');
    return {
      'status': 1,
      'data': {
        'total': 121,
        'info': [
          for (var i = (page - 1) * 50; i < page * 50 && i < 121; i++) _song(i),
        ],
      },
    };
  }
}

import '../../l10n/expanded_strings.dart';

import 'package:dio/dio.dart';

import '../../core/network/api_exception.dart';
import '../../models/album.dart';
import '../../models/artist.dart';
import '../../models/platform_type.dart';
import '../../models/playlist.dart';
import '../../models/song.dart';
import '../../platform/base/platform_registry.dart';
import '../../platform/kugou/kugou_api.dart';
import '../../platform/kugou/kugou_platform.dart';
import 'video_catalog.dart';

class VideoKugouPlaylists {
  const VideoKugouPlaylists({
    this.items = const [],
    this.total,
    this.complete = false,
    this.error,
  });
  final List<Playlist> items;
  final int? total;
  final bool complete;
  final VideoFailure? error;
}

class VideoKugouCatalog {
  VideoKugouCatalog({KugouApi? api}) : _injected = api;
  final KugouApi? _injected;
  KugouApi get _api =>
      _injected ??
      (PlatformRegistry.get(PlatformType.kugou) as KugouPlatform).api;
  final _metadata = <String, Map<String, dynamic>>{};

  static int? _int(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value');
  static Map _map(Object? value) => value is Map ? value : const {};
  static String? _text(Iterable<Object?> values) {
    for (final value in values) {
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty && text != 'null') return text;
    }
    return null;
  }

  static void _check(Map response) {
    if (response.isEmpty) throw _invalid;
    final code = _int(
      response['error_code'] ?? response['errcode'] ?? response['errno'],
    );
    if (code == 20010 || code == 20011 || code == 401) {
      throw LoginExpiredException();
    }
    if ((code != null && code != 0) || response['status'] == 0) {
      throw const VideoFailure(
        VideoFailureKind.unavailable,
        ExpandedStrings.kugouUnavailable,
        canRetry: true,
      );
    }
  }

  static VideoFailure get _invalid => const VideoFailure(
    VideoFailureKind.invalidResponse,
    ExpandedStrings.kugouInvalid,
    canRetry: true,
  );

  Future<VideoPage> search(String query, {int page = 1, int limit = 30}) async {
    if (page < 1 || limit < 1) {
      throw ArgumentError(ExpandedStrings.positivePage);
    }
    if (query.trim().isEmpty) {
      return VideoPage(songs: const [], page: page, hasMore: false, total: 0);
    }
    try {
      final response = await _api.search(
        query.trim(),
        page: page,
        limit: limit,
      );
      _check(response);
      final data = _map(response['data']);
      final total = _int(data['total'] ?? data['total_count'] ?? data['count']);
      final rows = data['info'] ?? data['lists'] ?? data['list'];
      if (rows is! List) throw _invalid;
      final songs = <String, Song>{};
      for (final row in rows) {
        final song = _song(row);
        songs[song.id] = song;
      }
      return VideoPage(
        songs: songs.values.toList(),
        page: page,
        total: total,
        hasMore:
            rows.isNotEmpty &&
            (total == null ? rows.length >= limit : page * limit < total),
      );
    } catch (error) {
      throw VideoFailure.from(error);
    }
  }

  Future<VideoLibrary> syncLikes({
    required String userId,
    void Function(VideoLibrary)? onProgress,
  }) async {
    if (userId.trim().isEmpty) {
      return const VideoLibrary(
        error: VideoFailure(
          VideoFailureKind.notLoggedIn,
          ExpandedStrings.kugouLogin,
        ),
      );
    }
    final songs = <String, Song>{};
    int? total;
    try {
      for (var page = 1; ; page++) {
        final response = await _api.getLikedSongs(page: page, limit: 50);
        _check(response);
        final data = _map(response['data']);
        total =
            _int(data['total'] ?? data['total_count'] ?? data['count']) ??
            total;
        final rows = data['info'] ?? data['songs'] ?? data['list'];
        if (rows is! List) throw _invalid;
        final previous = songs.length;
        for (final row in rows) {
          final song = _song(row);
          songs[song.id] = song;
        }
        final complete = total == null
            ? rows.length < 50
            : songs.length >= total;
        final snapshot = VideoLibrary(
          songs: List.unmodifiable(songs.values),
          total: total,
          complete: complete,
        );
        onProgress?.call(snapshot);
        if (complete) return snapshot;
        if (rows.isEmpty || songs.length == previous) {
          throw const VideoFailure(
            VideoFailureKind.incomplete,
            ExpandedStrings.kugouLikesIncomplete,
            canRetry: true,
          );
        }
      }
    } catch (error) {
      return VideoLibrary(
        songs: List.unmodifiable(songs.values),
        total: total,
        error: VideoFailure.from(error),
      );
    }
  }

  Future<void> setLiked(Song song, bool liked) async {
    try {
      final response = liked
          ? await _api.collectSong(song.id)
          : await _api.uncollectSong(song.id);
      _check(response);
      if (_int(response['status']) != 1 &&
          _int(
                response['error_code'] ??
                    response['errcode'] ??
                    response['errno'],
              ) !=
              0) {
        throw _invalid;
      }
    } catch (error) {
      throw VideoFailure.from(error);
    }
  }

  Future<VideoKugouPlaylists> playlists({required String userId}) async {
    if (userId.trim().isEmpty) {
      return const VideoKugouPlaylists(
        error: VideoFailure(
          VideoFailureKind.notLoggedIn,
          ExpandedStrings.kugouLogin,
        ),
      );
    }
    final items = <String, Playlist>{};
    int? total;
    try {
      for (var page = 1; ; page++) {
        final response = await _api.getUserPlaylists(page: page, limit: 50);
        _check(response);
        final data = _map(response['data']);
        total =
            _int(data['total'] ?? data['count'] ?? response['total']) ?? total;
        final rows = <Map>[];
        var found = false;
        void collect(Object? container) {
          if (container is List) {
            found = true;
            for (final row in container) {
              if (row is! Map) throw _invalid;
              rows.add(row);
            }
          } else if (container is Map) {
            for (final key in [
              'list_create_list',
              'list_collect_list',
              'list',
              'info',
              'lists',
              'data',
            ]) {
              collect(container[key]);
            }
          }
        }

        collect(response);
        if (!found) throw _invalid;
        final previous = items.length;
        for (final row in rows) {
          final id = _text([
            row['global_collection_id'],
            row['global_specialid'],
            row['specialid'],
            row['listid'],
            row['id'],
          ]);
          final name = _text([
            row['specialname'],
            row['name'],
            row['playlistname'],
            row['listname'],
          ]);
          if (id == null || name == null) throw _invalid;
          final listid = _text([row['listid'], row['list_create_listid']]);
          items[id] = Playlist(
            id: id,
            name: name,
            platform: PlatformType.kugou,
            songCount:
                _int(
                  row['songcount'] ??
                      row['song_count'] ??
                      row['song_num'] ??
                      row['count'],
                ) ??
                0,
            coverUrl: _text([
              row['imgurl'],
              row['image'],
              row['pic'],
              row['cover'],
            ])?.replaceAll('{size}', '480'),
            editId: listid,
            editable: listid != null,
          );
        }
        final complete = total == null
            ? rows.length < 50
            : items.length >= total;
        if (complete) {
          return VideoKugouPlaylists(
            items: List.unmodifiable(items.values),
            total: total,
            complete: true,
          );
        }
        if (rows.isEmpty || items.length == previous) {
          throw const VideoFailure(
            VideoFailureKind.incomplete,
            ExpandedStrings.kugouPlaylistsIncomplete,
            canRetry: true,
          );
        }
      }
    } catch (error) {
      return VideoKugouPlaylists(
        items: List.unmodifiable(items.values),
        total: total,
        error: VideoFailure.from(error),
      );
    }
  }

  Future<VideoLibrary> playlistSongs(
    Playlist playlist, {
    required String userId,
  }) async {
    if (userId.trim().isEmpty) {
      return const VideoLibrary(
        error: VideoFailure(
          VideoFailureKind.notLoggedIn,
          ExpandedStrings.kugouLogin,
        ),
      );
    }
    final songs = <String, Song>{};
    int? total = playlist.songCount > 0 ? playlist.songCount : null;
    try {
      for (var page = 1; ; page++) {
        final response = playlist.editId != null
            ? await _api.getUserPlaylistSongs(
                playlist.editableId,
                page: page,
                limit: 100,
              )
            : playlist.id.startsWith('collection_')
            ? await _api.getSharedPlaylistSongs(
                playlist.id,
                page: page,
                limit: 100,
              )
            : await _api.getPlaylistSongs(playlist.id, page: page, limit: 100);
        _check(response);
        final data = _map(response['data']);
        total =
            _int(
              data['total'] ??
                  data['total_count'] ??
                  data['count'] ??
                  response['total'],
            ) ??
            total;
        final rows =
            data['info'] ??
            data['songs'] ??
            data['list'] ??
            data['lists'] ??
            (response['data'] is List ? response['data'] : null);
        if (rows is! List) throw _invalid;
        final previous = songs.length;
        for (final row in rows) {
          final song = _song(row);
          songs[song.id] = song;
        }
        final complete = total == null
            ? rows.length < 100
            : songs.length >= total;
        if (complete) {
          return VideoLibrary(
            songs: List.unmodifiable(songs.values),
            total: total,
            complete: true,
          );
        }
        if (rows.isEmpty || songs.length == previous) {
          throw const VideoFailure(
            VideoFailureKind.incomplete,
            ExpandedStrings.playlistSongsIncomplete,
            canRetry: true,
          );
        }
      }
    } catch (error) {
      return VideoLibrary(
        songs: List.unmodifiable(songs.values),
        total: total,
        error: VideoFailure.from(error),
      );
    }
  }

  Song _song(Object? value) {
    final row = _map(value);
    final hash = _text([
      row['hash'],
      row['FileHash'],
      _map(row['audio_info'])['hash'],
    ]);
    var name = _text([
      row['songname'],
      row['song_name'],
      row['OriSongName'],
      row['name'],
    ]);
    var singer =
        _text([row['singername'], row['singer_name'], row['SingerName']]) ?? '';
    final file = _text([row['filename'], row['FileName']]) ?? '';
    if ((name == null || singer.isEmpty) && file.contains(' - ')) {
      final parts = file.split(' - ');
      singer = singer.isEmpty ? parts.first : singer;
      name ??= parts.skip(1).join(' - ');
    }
    if (hash == null || name == null) throw _invalid;
    name = name.replaceAll(RegExp(r'<[^>]*>'), '');
    singer = singer.replaceAll(RegExp(r'<[^>]*>'), '');
    final albumId = _text([row['album_id'], row['AlbumID']]);
    final albumName = _text([row['album_name'], row['AlbumName']]);
    final cover = _text([
      _map(row['trans_param'])['union_cover'],
      row['album_img'],
      row['image'],
      row['cover'],
    ])?.replaceAll('{size}', '480');
    final song = Song(
      id: hash,
      platform: PlatformType.kugou,
      name: name,
      artists: [Artist(id: '${row['singerid'] ?? ''}', name: singer)],
      album: albumName == null
          ? null
          : Album(id: albumId ?? '', name: albumName, coverUrl: cover),
      albumId: albumId,
      coverUrl: cover,
      duration: Duration(
        milliseconds:
            _int(row['timelen']) ??
            ((_int(row['duration'] ?? row['Duration']) ?? 0) * 1000),
      ),
    );
    _metadata[hash] = _info(row, hash);
    return song;
  }

  Map<String, dynamic> _info(Map row, String hash) {
    final audio = _map(row['audio_info']);
    final types = <String, Map<String, dynamic>>{};
    void add(String quality, Iterable<Object?> values) {
      final value = _text(values);
      if (value != null && value != '0') types[quality] = {'hash': value};
    }

    add('128k', [audio['hash'], row['hash'], row['FileHash'], hash]);
    add('320k', [
      audio['hash_320'],
      row['320hash'],
      row['HQFileHash'],
      row['hash320'],
    ]);
    add('flac', [
      audio['hash_flac'],
      row['sqhash'],
      row['SQFileHash'],
      row['hash_flac'],
    ]);
    add('flac24bit', [
      audio['hash_high'],
      row['hrhash'],
      row['ResFileHash'],
      row['hash_high'],
    ]);
    final numeric = _int(
      audio['audio_id'] ?? row['audio_id'] ?? row['Audioid'],
    );
    return {
      'hash': hash,
      'source': 'kg',
      'songmid': ?numeric,
      'albumId': ?_text([row['album_id'], row['AlbumID']]),
      'albumAudioId': ?_text([
        audio['audio_group_id'],
        row['album_audio_id'],
        row['MixSongID'],
        row['mixsongid'],
      ]),
      '_types': types,
      'types': [
        for (final entry in types.entries) {'type': entry.key, ...entry.value},
      ],
      'typeUrl': <String, dynamic>{},
    };
  }

  Future<Map<String, dynamic>> musicInfo(String hash, CancelToken token) async {
    if (token.isCancelled) throw token.cancelError!;
    final cached = _metadata[hash];
    if (cached != null) return cached;
    final response = await _api.getSongInfo(hash);
    if (token.isCancelled) throw token.cancelError!;
    _check(response);
    final data = response['data'] is Map ? response['data'] as Map : response;
    return _metadata[hash] = _info(data, hash);
  }
}

class ExpandedVideoCatalog extends VideoCatalog {
  ExpandedVideoCatalog({VideoKugouCatalog? kugou})
    : kugou = kugou ?? VideoKugouCatalog();
  final VideoKugouCatalog kugou;
  @override
  Future<VideoPage> search(
    PlatformType platform,
    String query, {
    int page = 1,
    int limit = 30,
  }) => platform == PlatformType.kugou
      ? kugou.search(query, page: page, limit: limit)
      : super.search(platform, query, page: page, limit: limit);
  @override
  Future<VideoLibrary> syncLikes(
    PlatformType platform, {
    required String userId,
    void Function(VideoLibrary)? onProgress,
  }) => platform == PlatformType.kugou
      ? kugou.syncLikes(userId: userId, onProgress: onProgress)
      : super.syncLikes(platform, userId: userId, onProgress: onProgress);
  @override
  Future<void> setLiked(Song song, bool liked) =>
      song.platform == PlatformType.kugou
      ? kugou.setLiked(song, liked)
      : super.setLiked(song, liked);
}

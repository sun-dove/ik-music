import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/library/presentation/providers/my_playlists_provider.dart';
import '../../models/platform_type.dart';
import '../../models/playlist.dart';
import '../../models/song.dart';
import '../../platform/base/platform_registry.dart';
import '../../platform/kugou/kugou_platform.dart';
import '../../platform/netease/netease_platform.dart';
import '../../platform/qq/qq_endpoints.dart';
import '../../platform/qq/qq_platform.dart';

String? playlistSongCover(Song? song) => _text([
  song?.coverUrl,
  song?.album?.coverUrl,
]);

final _coverQueueProvider = Provider((ref) => _CoverQueue());

/// 只在可见封面需要首曲回退时订阅，不读取整份平台歌单。
final playlistFirstCoverProvider = FutureProvider.autoDispose
    .family<String?, Playlist>((ref, playlist) async {
      final account = ref.watch(
        authProvider.select((state) => state.userFor(playlist.platform)),
      );
      var current = true;
      ref.onDispose(() => current = false);
      if (playlist.songCount <= 0) return null;
      if (playlist.platform != PlatformType.local && account == null) return null;
      final adapter = playlist.platform == PlatformType.local
          ? null
          : PlatformRegistry.get(playlist.platform);
      final revision = adapter?.personalDailySessionRevision;
      void onSessionChanged() => ref.invalidateSelf();
      adapter?.personalDailySessionChanges?.addListener(onSessionChanged);
      ref.onDispose(() =>
          adapter?.personalDailySessionChanges?.removeListener(onSessionChanged));
      bool scopeIsCurrent() => current &&
          adapter?.personalDailySessionRevision == revision &&
          ref.read(authProvider).userFor(playlist.platform) == account;
      final local = playlist.platform == PlatformType.local
          ? ref.read(myPlaylistsProvider.notifier)
          : null;
      final cover = await ref.read(_coverQueueProvider).run(() async {
        if (local != null) {
          final songs = await local.getSongs(playlist.id);
          return playlistSongCover(songs.isEmpty ? null : songs.first);
        }
        if (adapter is KugouPlatform) {
          return _kugouCover(adapter, playlist, scopeIsCurrent);
        }
        if (adapter is QqPlatform) {
          final response = await adapter.api.getPlaylistDetail(
            playlist.id,
            songBegin: 0,
            songNum: 1,
          );
          _check(response);
          final module = _map(response['req_0']);
          _check(module);
          final row = _first(_map(module['data'])['songlist']);
          final song = _qqSong(row);
          final album = _map(song['album']);
          final mid = _text([album['mid'], song['albummid'], song['albumMid']]);
          return mid == null
              ? _text([album['cover'], song['cover'], song['pic']])
              : '${QqEndpoints.songCover}$mid.jpg';
        }
        if (adapter is NeteasePlatform) {
          final response = await adapter.api.getPlaylistDetail(playlist.id, n: 1);
          _check(response);
          final song = _first(_map(response['playlist'])['tracks']);
          return _text([_map(song['al'])['picUrl'], _map(song['album'])['picUrl']]);
        }
        return null;
      }, scopeIsCurrent);
      if (!scopeIsCurrent()) return null;
      final keep = ref.keepAlive();
      final timer = Timer(const Duration(minutes: 3), keep.close);
      ref.onDispose(timer.cancel);
      return cover;
    });

Future<String?> _kugouCover(
  KugouPlatform adapter,
  Playlist playlist,
  bool Function() current,
) async {
  final api = adapter.api;
  Map<String, dynamic> response;
  final ownPlaylist = playlist.editId?.isNotEmpty == true ||
      (playlist.editable && RegExp(r'^\d+$').hasMatch(playlist.id));
  if (ownPlaylist) {
    response = await api.getUserPlaylistSongs(playlist.editableId, page: 1, limit: 1);
  } else if (playlist.id.startsWith('collection_')) {
    response = await api.getSharedPlaylistSongs(playlist.id, page: 1, limit: 1);
  } else {
    response = await api.getPlaylistSongs(playlist.id, page: 1, limit: 1);
  }
  if (!current()) return null;
  _check(response);
  final playlistCover = _kugouPlaylistImage(response);
  if (playlistCover != null) return playlistCover;
  var row = _kugouFirst(response);
  if (row.isEmpty && !ownPlaylist) {
    final parts = playlist.id.split('_');
    final listId = playlist.id.startsWith('collection_')
        ? (parts.length >= 4 ? parts[3] : null)
        : playlist.id;
    if (listId != null && listId.isNotEmpty && listId != '0' && current()) {
      response = await api.getUserPlaylistSongs(listId, page: 1, limit: 1);
      if (!current()) return null;
      _check(response);
      final fallbackCover = _kugouPlaylistImage(response);
      if (fallbackCover != null) return fallbackCover;
      row = _kugouFirst(response);
    }
  }
  final cover = _kugouSongImage(row);
  if (cover != null) return cover;
  final hash = _text([
    row['hash'],
    row['FileHash'],
    row['filehash'],
    _map(row['audio_info'])['hash'],
  ]);
  if (hash == null || !RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(hash) || !current()) {
    return null;
  }
  final metadata = await api.getSongInfo(hash);
  if (!current()) return null;
  _check(metadata);
  final data = _map(metadata['data']);
  return _kugouSongImage(data) ?? _kugouSongImage(metadata);
}

String? _kugouPlaylistImage(Map response) {
  final data = _map(response['data']);
  for (final node in [_map(data['list_info']), _map(response['list_info']), data, response]) {
    final cover = _kugouImage([
      node['pic'],
      node['imgurl'],
      node['image'],
      node['cover'],
      node['flexible_cover'],
      node['sizable_cover'],
    ]);
    if (cover != null) return cover;
  }
  return null;
}

String? _kugouSongImage(Map row) => _kugouImage([
    _map(row['trans_param'])['union_cover'],
    row['album_img'],
    row['image'],
    row['cover'],
    row['album_sizable_cover'],
    row['sizable_cover'],
    row['imgUrl'],
    row['imgurl'],
    _map(row['info'])['image'],
    _map(row['albuminfo'])['cover'],
    _map(row['albuminfo'])['image'],
    _map(row['album_info'])['cover'],
  ]);

String? _kugouImage(Iterable<Object?> values) {
  for (final value in values) {
    final text = _text([value])?.replaceAll('{size}', '480');
    if (text == null) continue;
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty ||
        (uri.scheme.isNotEmpty && uri.scheme != 'http' && uri.scheme != 'https')) {
      continue;
    }
    return uri.scheme.isEmpty ? uri.replace(scheme: 'https').toString() : text;
  }
  return null;
}

Map _kugouFirst(Map response) {
  for (final node in [_map(response['data']), response]) {
    for (final key in const ['info', 'songs', 'list', 'data', 'lists']) {
      final row = _first(node[key]);
      if (row.isNotEmpty) return row;
    }
  }
  return const {};
}

Map _qqSong(Map row) {
  for (final key in const ['songInfo', 'song', 'musicData', 'data']) {
    if (row[key] is Map) return row[key] as Map;
  }
  return row;
}

Map _map(Object? value) => value is Map ? value : const {};
Map _first(Object? value) => value is List && value.isNotEmpty
    ? _map(value.first)
    : const {};
String? _text(Iterable<Object?> values) {
  for (final value in values) {
    if (value is! String) continue;
    final text = value.trim();
    if (text.isNotEmpty && text != 'null') return text;
  }
  return null;
}

void _check(Map response) {
  if (response.isEmpty || response['status'] == 0) {
    throw const FormatException('Playlist preview unavailable');
  }
  for (final key in const ['code', 'subcode', 'error_code', 'errcode', 'errno']) {
    if (!response.containsKey(key)) continue;
    final code = int.tryParse('${response[key]}');
    if (code != 0 && !(key == 'code' && code == 200)) {
      throw const FormatException('Playlist preview rejected');
    }
  }
}

class _CoverQueue {
  int _active = 0;
  final _waiting = Queue<Completer<void>>();

  Future<String?> run(
    Future<String?> Function() request,
    bool Function() current,
  ) async {
    while (_active >= 2) {
      final ready = Completer<void>();
      _waiting.add(ready);
      await ready.future;
    }
    if (!current()) {
      if (_waiting.isNotEmpty) _waiting.removeFirst().complete();
      return null;
    }
    _active++;
    try {
      final result = await request();
      return current() ? result : null;
    } catch (_) {
      return null;
    } finally {
      _active--;
      if (_waiting.isNotEmpty) _waiting.removeFirst().complete();
    }
  }
}

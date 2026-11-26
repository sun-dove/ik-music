import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/platform_http.dart';
import '../../l10n/ik_recommendation_catalog_strings.dart';
import '../../models/platform_type.dart';
import '../../models/playlist.dart';
import '../../models/recommendation_source.dart';
import '../../platform/kugou/kugou_api.dart';
import '../../platform/kugou/kugou_platform.dart';
import '../../platform/netease/netease_crypto.dart';
import '../../platform/qq/qq_api.dart';
import '../../platform/qq/qq_platform.dart';
import '../../platform/qq/qq_toplist_ids.dart';

final ikPublicRecommendationsProvider = Provider<IkPublicRecommendations>((
  ref,
) {
  final client = IkPublicRecommendations();
  ref.onDispose(client.dispose);
  return client;
});

class IkPlaylistCatalogBatch {
  const IkPlaylistCatalogBatch({
    required this.platform,
    required this.playlists,
    required this.source,
    required this.rawCount,
    this.nextOffset,
    this.endKnown = false,
  });

  final PlatformType platform;
  final List<Playlist> playlists;
  final String source;
  final int rawCount;
  final int? nextOffset;
  final bool endKnown;
}

/// 独立公开读取；不恢复账号、不复制注册平台凭据、不广播会话失效。
class IkPublicRecommendations {
  IkPublicRecommendations() {
    _qq = QqPlatform(api: QqApi(dio: _qqDio));
    _kugou = KugouPlatform(api: KugouApi(dio: _kugouDio));
  }

  static const pageSize = 24;
  static const _timeout = Duration(seconds: 12);
  final _qqDio = _publicDio('https://y.qq.com/');
  final _neteaseDio = _publicDio('https://music.163.com/');
  final _kugouDio = _publicDio('https://m.kugou.com/');
  late final QqPlatform _qq;
  late final KugouPlatform _kugou;

  static Dio _publicDio(String referer) => createPlatformDio(
    onSessionExpired: (_) {},
    maxRetries: 0,
    connectTimeout: _timeout,
    receiveTimeout: _timeout,
    sendTimeout: _timeout,
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
      'Referer': referer,
    },
  );

  Future<RecommendationResult> songs(PlatformType platform) async {
    if (platform == PlatformType.qq) {
      Object? lastError;
      for (final chart in const [
        (QqToplistIds.newSongs, IkRecommendationCatalogStrings.qqNew),
        (QqToplistIds.hot, IkRecommendationCatalogStrings.qqHot),
      ]) {
        try {
          final ranked = await _qq
              .getRankedSongs('${chart.$1}', num: 30)
              .timeout(_timeout);
          final tracks = ranked.map((item) => item.song).toList();
          if (tracks.isNotEmpty) {
            return RecommendationResult(
              songs: List.unmodifiable(tracks),
              source: RecommendationSource(
                platform: platform,
                kind: RecommendationKind.fallbackToplist,
                label: chart.$2,
                note: IkRecommendationCatalogStrings.publicHint,
              ),
            );
          }
        } catch (error) {
          lastError = error;
        }
      }
      if (lastError != null) throw lastError;
    } else if (platform == PlatformType.kugou) {
      final tracks = await _kugou.fetchHomepageRecommendations().timeout(
        _timeout,
      );
      if (tracks.isNotEmpty) {
        return RecommendationResult(
          songs: List.unmodifiable(tracks),
          source: RecommendationSource(
            platform: platform,
            kind: RecommendationKind.fallbackHomepage,
            label: IkRecommendationCatalogStrings.kugouHome,
            note: IkRecommendationCatalogStrings.publicHint,
          ),
        );
      }
    }
    return const RecommendationResult(
      error: IkRecommendationCatalogStrings.publicUnavailable,
    );
  }

  Future<IkPlaylistCatalogBatch> playlists(
    PlatformType platform, {
    int offset = 0,
  }) => switch (platform) {
    PlatformType.qq => _qqPlaylists(offset),
    PlatformType.netease => _neteasePlaylists(offset),
    PlatformType.kugou => _kugouPlaylists(),
    PlatformType.local => throw const FormatException('Unsupported catalog'),
  };

  Future<IkPlaylistCatalogBatch> _qqPlaylists(int offset) async {
    final response = await _qqDio
        .get<Object>(
          'https://c.y.qq.com/splcloud/fcgi-bin/fcg_get_diss_by_tag.fcg',
          queryParameters: {
            'format': 'json',
            'inCharset': 'utf8',
            'outCharset': 'utf-8',
            'sortId': 5,
            'categoryId': 10000000,
            'sin': offset,
            'ein': offset + pageSize - 1,
          },
        )
        .timeout(_timeout);
    final body = _map(response.data);
    if (_integer(body['code']) != 0) {
      throw const FormatException('QQ catalog rejected');
    }
    final data = _map(body['data']);
    final rows = _rows(data['list']);
    final total = _integer(data['sum']);
    final next = offset + rows.length;
    if (total != null && rows.isEmpty && next < total) {
      throw const FormatException('Incomplete QQ catalog page');
    }
    return _batch(
      PlatformType.qq,
      rows,
      nextOffset: total != null && next < total ? next : null,
      endKnown: total != null,
      parse: (row) => Playlist(
        id: _id(row['dissid'] ?? row['disstid']),
        name: _text(row['dissname'] ?? row['diss_name']),
        platform: PlatformType.qq,
        coverUrl: _optional(row['imgurl'] ?? row['diss_cover']),
        songCount:
            _integer(row['song_count'] ?? row['songcnt'] ?? row['song_cnt']) ??
            0,
        creatorName: row['creator'] is Map
            ? _optional((row['creator'] as Map)['name'])
            : null,
      ),
    );
  }

  Future<IkPlaylistCatalogBatch> _neteasePlaylists(int offset) async {
    final response = await _neteaseDio
        .post<Object>(
          'https://music.163.com/weapi/playlist/list',
          data: NeteaseCrypto.encryptPublicRequest({
            'cat': '全部', // i18n-exempt: 网易云公开目录分类协议值
            'order': 'hot',
            'limit': pageSize,
            'offset': offset,
            'total': true,
            'csrf_token': '',
          }),
          options: Options(contentType: Headers.formUrlEncodedContentType),
        )
        .timeout(_timeout);
    final body = _map(response.data);
    if (_integer(body['code']) != 200) {
      throw const FormatException('Netease catalog rejected');
    }
    final rows = _rows(body['playlists']);
    final total = _integer(body['total']);
    final more = body['more'] is bool ? body['more'] as bool : null;
    final next = offset + rows.length;
    final hasMore = more ?? (total == null ? false : next < total);
    if (hasMore && rows.isEmpty) {
      throw const FormatException('Incomplete Netease catalog page');
    }
    return _batch(
      PlatformType.netease,
      rows,
      nextOffset: hasMore ? next : null,
      endKnown: more != null || total != null,
      parse: (row) => Playlist(
        id: _id(row['id']),
        name: _text(row['name']),
        platform: PlatformType.netease,
        coverUrl: _optional(row['coverImgUrl']),
        songCount: _integer(row['trackCount']) ?? 0,
        creatorName: row['creator'] is Map
            ? _optional((row['creator'] as Map)['nickname'])
            : null,
      ),
    );
  }

  Future<IkPlaylistCatalogBatch> _kugouPlaylists() async {
    final body = await _kugou.api.getHomepage().timeout(_timeout);
    final rows = _rows(_map(_map(body['special'])['list'])['info']);
    return _batch(
      PlatformType.kugou,
      rows,
      endKnown: true,
      parse: (row) => Playlist(
        id: _id(
          row['specialid'] ??
              row['global_specialid'] ??
              row['global_collection_id'],
        ),
        name: _text(row['specialname'] ?? row['name']),
        platform: PlatformType.kugou,
        coverUrl: _optional(row['imgurl'])?.replaceAll('{size}', '400'),
        songCount: _integer(row['songcount'] ?? row['song_count']) ?? 0,
        creatorName: _optional(row['nickname'] ?? row['username']),
      ),
    );
  }

  IkPlaylistCatalogBatch _batch(
    PlatformType platform,
    List<dynamic> rows, {
    required Playlist Function(Map<String, dynamic>) parse,
    int? nextOffset,
    bool endKnown = false,
  }) {
    final unique = <String, Playlist>{};
    for (final raw in rows) {
      final item = parse(_map(raw));
      if (item.id.isEmpty || item.name.isEmpty) {
        throw const FormatException('Invalid playlist identity');
      }
      unique.putIfAbsent(item.id, () => item);
    }
    return IkPlaylistCatalogBatch(
      platform: platform,
      playlists: List.unmodifiable(unique.values),
      rawCount: rows.length,
      source: IkRecommendationCatalogStrings.source(platform),
      nextOffset: nextOffset,
      endKnown: endKnown,
    );
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is String) value = jsonDecode(value);
    if (value is Map) return Map<String, dynamic>.from(value);
    throw const FormatException('Expected catalog object');
  }

  static List<dynamic> _rows(Object? value) {
    if (value is List) return value;
    throw const FormatException('Expected catalog rows');
  }

  static int? _integer(Object? value) {
    final number = int.tryParse(value?.toString() ?? '');
    return number != null && number >= 0 ? number : null;
  }

  static String _text(Object? value) => value?.toString().trim() ?? '';
  static String? _optional(Object? value) {
    final text = _text(value);
    return text.isEmpty ? null : text;
  }

  static String _id(Object? value) {
    final text = _text(value);
    return text.isEmpty || text == '0' || text == 'null' ? '' : text;
  }

  void dispose() {
    _qqDio.close(force: true);
    _neteaseDio.close(force: true);
    _kugouDio.close(force: true);
  }
}

import 'package:flutter/foundation.dart';

import '../../models/platform_type.dart';
import '../../models/song.dart';
import '../data/video_catalog.dart';

typedef IkSearchRequest = Future<VideoPage> Function(
  PlatformType platform,
  String query,
  int page,
);

class IkSearchGroup {
  const IkSearchGroup({
    this.songs = const [],
    this.page = 0,
    this.total,
    this.hasMore = false,
    this.loading = false,
    this.error,
  });
  final List<Song> songs;
  final int page;
  final int? total;
  final bool hasMore, loading;
  final VideoFailure? error;
}

/// 每个来源独立分页、失败和重试；查询代次隔离迟到响应。
class IkSearchController extends ChangeNotifier {
  IkSearchController({
    required this.search,
    this.platforms = const [
      PlatformType.local,
      PlatformType.qq,
      PlatformType.netease,
      PlatformType.kugou,
    ],
  });
  final IkSearchRequest search;
  final List<PlatformType> platforms;
  final _groups = <PlatformType, IkSearchGroup>{};
  Map<PlatformType, IkSearchGroup> get groups => Map.unmodifiable(_groups);
  List<Song> get songs => [
    for (final platform in platforms) ...?_groups[platform]?.songs,
  ];
  String query = '';
  int _generation = 0;
  bool _disposed = false;

  Future<void> submit(String text) async {
    final generation = ++_generation;
    query = text.trim();
    _groups.clear();
    if (query.isEmpty) {
      notifyListeners();
      return;
    }
    for (final platform in platforms) {
      _groups[platform] = const IkSearchGroup(loading: true);
    }
    notifyListeners();
    await Future.wait([
      for (final platform in platforms) _load(platform, 1, generation),
    ]);
  }

  Future<void> retry(PlatformType platform) async {
    final group = _groups[platform];
    if (group == null || group.loading || group.error?.canRetry != true) return;
    await _load(platform, group.page + 1, _generation);
  }

  Future<void> loadMore(PlatformType platform) async {
    final group = _groups[platform];
    if (group == null || group.loading || !group.hasMore) return;
    await _load(platform, group.page + 1, _generation);
  }

  Future<void> _load(PlatformType platform, int page, int generation) async {
    final previous = _groups[platform] ?? const IkSearchGroup();
    _groups[platform] = IkSearchGroup(
      songs: previous.songs,
      page: previous.page,
      total: previous.total,
      hasMore: previous.hasMore,
      loading: true,
    );
    notifyListeners();
    try {
      final result = await search(platform, query, page);
      if (_disposed || generation != _generation) return;
      final merged = <String, Song>{
        for (final song in previous.songs)
          '${song.platform.name}:${song.id}': song,
        for (final song in result.songs)
          '${song.platform.name}:${song.id}': song,
      };
      _groups[platform] = IkSearchGroup(
        songs: List.unmodifiable(merged.values),
        page: result.page,
        total: result.total,
        hasMore: result.hasMore,
      );
    } catch (error) {
      if (_disposed || generation != _generation) return;
      _groups[platform] = IkSearchGroup(
        songs: previous.songs,
        page: previous.page,
        total: previous.total,
        hasMore: previous.hasMore,
        error: VideoFailure.from(error),
      );
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/ik_recommendation_catalog_strings.dart';
import '../../models/platform_type.dart';
import '../../models/playlist.dart';
import 'ik_public_recommendations.dart';

class IkPlaylistCatalogState {
  const IkPlaylistCatalogState({
    this.playlists = const [],
    this.loading = false,
    this.initialized = false,
    this.source,
    this.nextOffset,
    this.endKnown = false,
    this.error,
  });

  final List<Playlist> playlists;
  final bool loading, initialized, endKnown;
  final String? source, error;
  final int? nextOffset;
  bool get hasMore => nextOffset != null;
}

/// 按平台保留完整已加载目录；页面往返不重新请求首批。
final ikPlaylistCatalogProvider = StateNotifierProvider.family<
  IkPlaylistCatalogNotifier,
  IkPlaylistCatalogState,
  PlatformType
>((ref, platform) {
  return IkPlaylistCatalogNotifier(
    platform,
    ref.watch(ikPublicRecommendationsProvider),
  );
});

class IkPlaylistCatalogNotifier extends StateNotifier<IkPlaylistCatalogState> {
  IkPlaylistCatalogNotifier(this.platform, this.client)
      : super(const IkPlaylistCatalogState(loading: true)) {
    scheduleMicrotask(refresh);
  }

  final PlatformType platform;
  final IkPublicRecommendations client;
  int _generation = 0;
  bool _retryRefresh = true;

  Future<void> refresh() => _load(refreshing: true);

  Future<void> loadMore() async {
    if (state.loading || !state.hasMore) return;
    await _load(refreshing: false);
  }

  Future<void> retry() async {
    if (state.loading) return;
    await _load(refreshing: _retryRefresh);
  }

  Future<void> _load({required bool refreshing}) async {
    if (!mounted) return;
    final previous = state;
    final offset = refreshing ? 0 : previous.nextOffset!;
    final generation = ++_generation;
    _retryRefresh = refreshing;
    state = IkPlaylistCatalogState(
      playlists: previous.playlists,
      loading: true,
      initialized: previous.initialized,
      source: previous.source,
      nextOffset: previous.nextOffset,
      endKnown: previous.endKnown,
    );
    try {
      final batch = await client.playlists(platform, offset: offset);
      if (!mounted || generation != _generation) return;
      if (batch.platform != platform ||
          batch.playlists.any((playlist) => playlist.platform != platform)) {
        throw const FormatException('Catalog platform mismatch');
      }
      final merged = <String, Playlist>{
        if (!refreshing)
          for (final item in previous.playlists) item.id: item,
        for (final item in batch.playlists) item.id: item,
      };
      if (!refreshing && batch.rawCount > 0 &&
          merged.length == previous.playlists.length) {
        throw const FormatException('Catalog page made no progress');
      }
      state = IkPlaylistCatalogState(
        playlists: List.unmodifiable(merged.values),
        initialized: true,
        source: batch.source,
        nextOffset: batch.nextOffset,
        endKnown: batch.endKnown,
      );
    } catch (error) {
      if (!mounted || generation != _generation) return;
      state = IkPlaylistCatalogState(
        playlists: previous.playlists,
        initialized: previous.initialized,
        source: previous.source,
        nextOffset: previous.nextOffset,
        endKnown: previous.endKnown,
        error: error is FormatException
            ? IkRecommendationCatalogStrings.invalid
            : refreshing
                ? IkRecommendationCatalogStrings.failed
                : IkRecommendationCatalogStrings.nextFailed,
      );
    }
  }
}

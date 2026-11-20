import '../../models/song.dart';
import '../multi_source/expanded_source_player.dart';
import 'catalog_coordinator.dart';

/// 自动准备不打断当前歌；明确发起新播放时先发布已校验的一批。
class IkCatalogPlayerNotifier extends ExpandedSourcePlayerNotifier {
  IkCatalogPlayerNotifier({
    required this.catalogCoordinator,
    required super.settings,
    required super.router,
    required super.resolve,
    super.onProgress,
    super.legacyFallback,
    super.playbackMemoryStore,
    super.offlineFilePathResolver,
    super.isOfflineModeEnabled,
    super.userGain,
  });
  final IkSourceCatalogCoordinator catalogCoordinator;
  int _catalogRequest = 0;
  @override
  Future<void> playSong(Song song) async {
    final request = ++_catalogRequest;
    try {
      await catalogCoordinator.commitAtPlaybackBoundary();
    } catch (_) {
      /* 保存失败沿用已确认版本播放。 */
    }
    if (!mounted || request != _catalogRequest) return;
    await super.playSong(song);
  }
}

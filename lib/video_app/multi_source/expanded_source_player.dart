import '../../models/audio_quality.dart';
import '../../models/song.dart';
import 'multi_source_player.dart';
import 'source_candidates_v3.dart';
import 'source_coordinator.dart';

class ExpandedSourcePlayerNotifier extends MultiSourceVideoPlayerNotifier {
  ExpandedSourcePlayerNotifier({
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
  @override
  List<SourceCandidate> candidatesFor(Song song, AudioLevel quality) =>
      buildSourceCandidatesV3(song, quality, settings.value);
  @override
  List<String> exclusionsFor(Song song, AudioLevel quality) =>
      sourceExclusionsV3(song, quality, settings.value);
}

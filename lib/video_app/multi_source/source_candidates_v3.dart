import '../../l10n/source_strings.dart';
import '../../models/audio_quality.dart';
import '../../models/song.dart';
import '../lx_source/lx_runtime_v3.dart';
import '../lx_source/lx_source.dart';
import 'source_collection.dart';
import 'source_coordinator.dart';

List<SourceCandidate> buildSourceCandidatesV3(
  Song song,
  AudioLevel fixed,
  SourceCollection collection, {
  bool download = false,
}) {
  final levels = collection.highestQuality && !download
      ? [AudioLevel.hires, AudioLevel.lossless, AudioLevel.high, AudioLevel.low]
      : [fixed];
  final enabled = collection.autoSwitch
      ? collection.enabled
      : collection.enabled.take(1);
  final platform = lxPlatformV3(song.platform);
  final result = <SourceCandidate>[];
  for (final level in levels) {
    final official = SourceCandidate(
      id: 'official',
      name: song.platform.displayName,
      quality: level,
      official: true,
    );
    if (!collection.sourceFirst) result.add(official);
    for (final entry in enabled) {
      if (download && !entry.config.allowForDownloads) continue;
      String type;
      try {
        type = lxQuality(level);
      } on LxSourceException {
        continue;
      }
      if (entry.config.sources[platform]?.contains(type) != true) continue;
      result.add(
        SourceCandidate(
          id: entry.id,
          name: entry.config.name,
          quality: level,
          entry: entry,
        ),
      );
    }
    if (collection.sourceFirst) result.add(official);
  }
  return result;
}

List<String> sourceExclusionsV3(
  Song song,
  AudioLevel fixed,
  SourceCollection collection, {
  bool download = false,
}) {
  final result = <String>[];
  final levels = collection.highestQuality && !download
      ? [AudioLevel.hires, AudioLevel.lossless, AudioLevel.high, AudioLevel.low]
      : [fixed];
  for (final entry
      in collection.autoSwitch
          ? collection.enabled
          : collection.enabled.take(1)) {
    if (download && !entry.config.allowForDownloads) {
      result.add(SourceStrings.downloadDisabled(entry.config.name));
      continue;
    }
    final supported =
        entry.config.sources[lxPlatformV3(song.platform)] ?? const [];
    if (supported.isEmpty) {
      result.add(
        SourceStrings.platformUnsupported(
          entry.config.name,
          song.platform.displayName,
        ),
      );
      continue;
    }
    for (final level in levels) {
      String? type;
      try {
        type = lxQuality(level);
      } on LxSourceException {
        type = null;
      }
      if (type == null || !supported.contains(type)) {
        result.add(
          SourceStrings.qualityUnsupported(
            entry.config.name,
            level.displayName,
          ),
        );
      }
    }
  }
  return result;
}

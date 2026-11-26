import 'dart:convert';

import '../../models/audio_quality.dart';
import '../../models/platform_type.dart';
import '../../models/song.dart';
import 'source_collection.dart';
import 'source_coordinator.dart';

typedef _Success = ({
  PlatformType platform,
  String songId,
  String key,
  AudioLevel quality,
  DateTime heardAt,
  Duration elapsed,
});

class BalancedSourcePlanner {
  BalancedSourcePlanner({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final _successes = <_Success>[];
  String? _configuration;
  int _generation = 0;

  void clear() {
    _successes.clear();
    _generation++;
  }

  void configure(SourceCollection policy) {
    final configuration = jsonEncode([
      policy.autoSwitch,
      policy.sourceFirst,
      policy.preferredId,
      for (final entry in policy.entries)
        [
          entry.id,
          entry.config.enabled,
          entry.config.version,
          entry.config.sha256,
          entry.config.sources,
        ],
    ]);
    if (_configuration == configuration) return;
    _configuration = configuration;
    clear();
  }

  void Function() beginAttempt(Song song, SourceCandidate candidate) {
    final generation = _generation;
    final started = _now();
    var recorded = false;
    return () {
      if (recorded || generation != _generation) return;
      recorded = true;
      final now = _now();
      _successes.add((
        platform: song.platform,
        songId: song.id,
        key: candidate.key,
        quality: candidate.quality,
        heardAt: now,
        elapsed: now.difference(started),
      ));
      if (_successes.length > 128) _successes.removeAt(0);
    };
  }

  List<SourceCandidate> plan(
    Song song,
    SourceCollection policy,
    List<SourceCandidate> eligible,
  ) {
    configure(policy);
    if (eligible.isEmpty) return const [];
    final now = _now();
    final times = <String, List<Duration>>{};
    final keys = eligible.map((c) => c.key).toSet();
    _Success? hot;
    for (final record in _successes.reversed) {
      final ttl = Duration(minutes: record.quality == AudioLevel.low ? 5 : 30);
      if (record.platform != song.platform ||
          !keys.contains(record.key) ||
          now.difference(record.heardAt) >= ttl) {
        continue;
      }
      if (record.songId == song.id) hot ??= record;
      final samples = times.putIfAbsent(record.key, () => []);
      if (samples.length < 3) samples.add(record.elapsed);
    }
    final medians = {
      for (final entry in times.entries) entry.key: _median(entry.value),
    };
    int priority(SourceCandidate candidate) => candidate.official
        ? (policy.sourceFirst ? 2 : 0)
        : (candidate.id == policy.preferredId ? 0 : 1) +
              (policy.sourceFirst ? 0 : 1);
    final order = {
      for (final (index, candidate) in eligible.indexed) candidate.key: index,
    };
    final sorted = [...eligible]
      ..sort((left, right) {
        final tier = right.quality.index.compareTo(left.quality.index);
        if (tier != 0) return tier;
        final group = priority(left).compareTo(priority(right));
        if (group != 0) return group;
        final a = medians[left.key], b = medians[right.key];
        if (a != b) {
          return a == null
              ? 1
              : b == null
              ? -1
              : a.compareTo(b);
        }
        return order[left.key]!.compareTo(order[right.key]!);
      });
    final early = <SourceCandidate>[];
    if (hot != null) {
      final hit = sorted.firstWhere((c) => c.key == hot!.key);
      early.addAll(
        sorted.where(
          (c) => c.quality == hit.quality && priority(c) < priority(hit),
        ),
      );
      early.add(hit);
    } else {
      AudioLevel firstTier = AudioLevel.lossless;
      Duration? best;
      for (final candidate in sorted) {
        if (candidate.quality != AudioLevel.hires &&
            candidate.quality != AudioLevel.lossless) {
          continue;
        }
        final latency = medians[candidate.key];
        if (latency != null && (best == null || latency < best)) {
          best = latency;
          firstTier = candidate.quality;
        }
      }
      if (!sorted.any((c) => c.quality == firstTier)) {
        firstTier = sorted.first.quality;
      }
      for (final tier in {firstTier, AudioLevel.high, AudioLevel.low}) {
        final candidate = sorted.where((c) => c.quality == tier).firstOrNull;
        if (candidate != null) early.add(candidate);
      }
    }
    final tried = early.map((c) => c.key).toSet();
    return [...early, ...sorted.where((c) => !tried.contains(c.key))];
  }

  Duration _median(List<Duration> values) {
    values.sort();
    return values.length == 2
        ? Duration(
            microseconds:
                (values.first.inMicroseconds + values.last.inMicroseconds) ~/ 2,
          )
        : values[values.length ~/ 2];
  }
}

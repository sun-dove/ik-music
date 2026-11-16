import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/video_app/lx_source/lx_source.dart';
import 'package:mconnect/video_app/multi_source/source_collection.dart';
import 'package:mconnect/video_app/multi_source/source_coordinator.dart';
import 'package:mconnect/video_app/multi_source/source_candidates_v3.dart';

void main() {
  test('酷狗先遍历同档可用源再降档，下载仍遵守独立音质和显式许可', () {
    const song = Song(
      id: 'hash',
      platform: PlatformType.kugou,
      name: '歌',
      artists: [],
    );
    var collection = const SourceCollection(
      autoSwitch: true,
      sourceFirst: true,
      highestQuality: true,
    );
    for (final name in ['A', 'B', '仅QQ源']) {
      collection = collection.upsert(
        LxSourceConfig(
          name: name,
          version: '1',
          origin: Uri.parse('https://example.com/$name.js'),
          script: 'fixture',
          sha256: name,
          enabled: true,
          allowForDownloads: name == 'B',
          sources: {
            name == '仅QQ源' ? 'tx' : 'kg': name == 'B'
                ? ['128k', 'flac']
                : ['128k'],
          },
        ),
      );
    }
    String label(SourceCandidate candidate) =>
        '${candidate.official ? 'official' : candidate.name}:${candidate.quality.name}';
    expect(
      buildSourceCandidatesV3(song, AudioLevel.low, collection).map(label),
      [
        'official:hires',
        'B:lossless',
        'official:lossless',
        'official:high',
        'A:low',
        'B:low',
        'official:low',
      ],
    );
    expect(
      buildSourceCandidatesV3(
        song,
        AudioLevel.low,
        collection,
        download: true,
      ).map(label),
      ['B:low', 'official:low'],
    );
  });
}

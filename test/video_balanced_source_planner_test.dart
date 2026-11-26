import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/video_app/lx_source/lx_source.dart';
import 'package:mconnect/video_app/multi_source/balanced_source_planner.dart';
import 'package:mconnect/video_app/multi_source/source_candidates_v3.dart';
import 'package:mconnect/video_app/multi_source/source_collection.dart';
import 'package:mconnect/video_app/multi_source/source_coordinator.dart';

Song _song(String id, [PlatformType platform = PlatformType.qq]) =>
    Song(id: id, platform: platform, name: '同名歌曲', artists: const []);

class _Fixture {
  DateTime now = DateTime.utc(2026, 11, 26);
  late final planner = BalancedSourcePlanner(now: () => now);
  SourceCollection policy = const SourceCollection(
    autoSwitch: true,
    sourceFirst: true,
  );

  _Fixture() {
    for (final id in ['A', 'B', 'C']) {
      policy = policy.upsert(
        LxSourceConfig(
          name: id,
          version: '1',
          origin: Uri.parse('https://example.com/$id.js'),
          sha256: id,
          script: 'fixture',
          enabled: true,
          sources: const {
            'tx': ['128k', '320k', 'flac', 'flac24bit'],
            'kg': ['128k', '320k', 'flac', 'flac24bit'],
          },
        ),
      );
    }
  }

  List<SourceCandidate> eligible(Song song) => buildSourceCandidatesV3(
    song,
    AudioLevel.low,
    policy.copyWith(highestQuality: true),
  );
  List<SourceCandidate> plan(Song song) =>
      planner.plan(song, policy, eligible(song));
  void advance(Duration by) => now = now.add(by);
  void Function() start(Song song, String source, AudioLevel level) {
    final candidate = plan(song)
        .singleWhere((c) => c.name == source && c.quality == level);
    return planner.beginAttempt(song, candidate);
  }

  void heard(Song song, String source, AudioLevel level, int ms) {
    final heard = start(song, source, level);
    advance(Duration(milliseconds: ms));
    heard();
  }
}

void main() {
  test('相同慢源和十五秒预算：均衡首轮起播，原顺序继续尝试时不重复', () async {
    for (final available in [AudioLevel.high, AudioLevel.low]) {
      for (final balanced in [false, true]) {
        final fixture = _Fixture();
        final song = _song('timed');
        final keys = <String>[];
        final session = SourceSession(
          candidates: balanced ? fixture.plan(song) : fixture.eligible(song),
          now: () => fixture.now,
          budget: const Duration(seconds: 15),
          resolve: (candidate, _) async {
            keys.add(candidate.key);
            if (candidate.quality == available) {
              fixture.advance(const Duration(milliseconds: 500));
              return ResolvedSource(
                candidate,
                Uri.parse('https://example.com/ok'),
              );
            }
            fixture.advance(
              candidate.quality == AudioLevel.high
                  ? Duration.zero
                  : const Duration(seconds: 5),
            );
            throw const SourceFailure('timeout', '上游未及时返回');
          },
        );
        final start = fixture.now;
        final result = await session.next();
        if (balanced) {
          expect(result?.candidate.quality, available);
          expect(
            fixture.now.difference(start),
            const Duration(milliseconds: 5500),
          );
          expect(keys.length, available == AudioLevel.high ? 2 : 3);
        } else {
          expect(result, isNull);
          expect(session.budgetExpired && session.canContinue, isTrue);
          ResolvedSource? continued;
          while (continued == null && session.canContinue) {
            session.renewBudget();
            continued = await session.next();
          }
          expect(continued?.candidate.quality, available);
          expect(keys.toSet(), hasLength(keys.length));
        }
        session.cancel();
      }
    }
  });

  test('保底提前、未试高档仍排在后续，完整候选不丢不重；关闭切源不扩大范围', () {
    final f = _Fixture();
    final song = _song('1');
    final original = f.eligible(song);
    final planned = f.plan(song);
    expect(planned.take(3).map((c) => c.quality), [
      AudioLevel.lossless,
      AudioLevel.high,
      AudioLevel.low,
    ]);
    expect(planned.take(3).map((c) => c.name), ['A', 'A', 'A']);
    final early = planned.take(3).map((c) => c.key).toSet();
    expect(
      planned.skip(3).map((c) => c.key),
      original.map((c) => c.key).where((k) => !early.contains(k)),
    );
    expect(planned.map((c) => c.key).toSet().length, original.length);
    f.policy = f.policy.copyWith(
      autoSwitch: false,
      preferredId: f.policy.entries[1].id,
    );
    expect(f.plan(song).map((c) => c.name).toSet(), {'B', 'QQ音乐'});
    expect(f.plan(song).first.name, 'B');
  });

  test('同曲标准命中五分钟到期；同名不同曲和不同平台不借用本曲命中', () {
    final f = _Fixture();
    final song = _song('1');
    f.heard(song, 'B', AudioLevel.low, 600);
    expect(
      f.plan(song).first.key,
      f
          .eligible(song)
          .singleWhere((c) => c.name == 'B' && c.quality == AudioLevel.low)
          .key,
    );
    expect(f.plan(_song('2')).first.quality, AudioLevel.lossless);
    expect(
      f.plan(_song('1', PlatformType.kugou)).first.quality,
      AudioLevel.lossless,
    );
    f.advance(const Duration(minutes: 5));
    expect(f.plan(song).first.quality, AudioLevel.lossless);
    f.heard(song, 'B', AudioLevel.hires, 500);
    expect(f.plan(_song('2')).first.quality, AudioLevel.hires);
    f.advance(const Duration(minutes: 30));
    expect(f.plan(song).first.quality, AudioLevel.lossless);
  });

  test('同平台同档按单个来源最近三次起播中位数，平局保持原顺序；用户优先组优先', () {
    final f = _Fixture();
    for (final ms in [1, 900, 700, 100]) {
      f.heard(_song('a$ms'), 'A', AudioLevel.lossless, ms);
    }
    for (final ms in [800, 400, 500]) {
      f.heard(_song('b$ms'), 'B', AudioLevel.lossless, ms);
    }
    final target = _song('new');
    expect(f.plan(target).first.name, 'B');
    f.heard(_song('C'), 'C', AudioLevel.lossless, 500);
    expect(f.plan(target).first.name, 'B');
    expect(f.plan(_song('kg', PlatformType.kugou)).first.name, 'A');
    f.policy = f.policy.prefer(f.policy.entries.first.id);
    f.heard(target, 'B', AudioLevel.low, 200);
    expect(f.plan(target).take(2).map((c) => c.name), ['A', 'B']);
    expect(
      f.plan(target).take(2).every((c) => c.quality == AudioLevel.low),
      isTrue,
    );
    f.policy = f.policy.copyWith(sourceFirst: false);
    f.heard(target, 'B', AudioLevel.low, 200);
    expect(f.plan(target).first.official, isTrue);
  });

  test('改顺序、更新、撤用与切账号令在途记录失效；只改下载授权不误清', () {
    final f = _Fixture();
    final song = _song('1');
    final b = f.policy.entries[1];
    f.heard(song, 'B', AudioLevel.low, 500);
    f.policy = f.policy.replace(
      b.id,
      b.config.copyWith(allowForDownloads: true),
    );
    expect(f.plan(song).first.quality, AudioLevel.low);
    final pending = f.start(song, 'B', AudioLevel.low);
    f.policy = f.policy.move(b.id, -1);
    f.plan(song);
    pending();
    expect(f.plan(song).first.quality, AudioLevel.lossless);
    f.heard(song, 'B', AudioLevel.low, 500);
    final update = LxSourceConfig(
      name: 'B',
      version: '2',
      origin: b.config.origin,
      sha256: 'update',
      script: 'fixture',
      enabled: true,
      sources: b.config.sources,
    );
    f.policy = f.policy.upsert(update);
    expect(f.plan(song).first.quality, AudioLevel.lossless);
    f.heard(song, 'B', AudioLevel.low, 500);
    f.policy = f.policy.replace(b.id, update.copyWith(enabled: false));
    expect(f.plan(song).any((c) => c.name == 'B'), isFalse);
    final accountAttempt = f.start(song, 'A', AudioLevel.low);
    f.planner.clear();
    accountAttempt();
    expect(f.plan(song).first.quality, AudioLevel.lossless);
  });

  test('内存只留最近128次真实起播，已用的回执不能重复登记', () {
    final f = _Fixture();
    final oldest = _song('oldest');
    final mark = f.start(oldest, 'B', AudioLevel.low);
    mark();
    for (var i = 0; i < 127; i++) {
      f.heard(_song('$i'), 'A', AudioLevel.high, 2);
    }
    mark();
    expect(f.plan(oldest).first.quality, AudioLevel.low);
    f.heard(_song('last'), 'A', AudioLevel.high, 1);
    expect(f.plan(oldest).first.quality, AudioLevel.lossless);
  });
}

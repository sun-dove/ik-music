import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/discovery/presentation/providers/recommendations_provider.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/recommendation_source.dart';
import 'package:mconnect/models/song.dart';

import 'support/content_page_fakes.dart';

void main() {
  test('K05 一个推荐来源等待时，成功来源先显示且不丢失', () async {
    final fast = <Completer<RecommendationResult>>[];
    final slow = <Completer<RecommendationResult>>[];
    final notifier = RecommendationsNotifier(
      supportedTypes: const [PlatformType.qq, PlatformType.netease],
      platformResolver: (platform) =>
          _RecommendationsPlatform(platform == PlatformType.qq ? fast : slow),
    );
    addTearDown(notifier.dispose);
    final pending = notifier.loadLatestRecommendations();
    fast.single.complete(
      const RecommendationResult(
        songs: [
          Song(
            id: 'fast',
            platform: PlatformType.qq,
            name: '先返回的歌曲',
            artists: [],
          ),
        ],
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(notifier.state.songsForPlatform(PlatformType.qq).single.id, 'fast');
    expect(notifier.state.isLoading, isTrue);
    slow.single.complete(const RecommendationResult(error: '该来源暂不可用'));
    await pending;
    expect(notifier.state.songsForPlatform(PlatformType.qq).single.id, 'fast');
    expect(notifier.state.errorsByPlatform[PlatformType.netease], '该来源暂不可用');
    expect(notifier.state.isLoading, isFalse);
    final retry = notifier.retryLatestPlatform(PlatformType.netease);
    expect(fast.length, 1, reason: '失败来源重试不重发成功来源');
    expect(notifier.state.songsForPlatform(PlatformType.qq).single.id, 'fast');
    slow[1].complete(
      const RecommendationResult(
        songs: [
          Song(
            id: 'retry',
            platform: PlatformType.netease,
            name: '重试成功',
            artists: [],
          ),
        ],
      ),
    );
    await retry;
    expect(
      notifier.state.songsForPlatform(PlatformType.netease).single.id,
      'retry',
    );
    expect(
      notifier.state.errorsByPlatform.containsKey(PlatformType.netease),
      isFalse,
    );
  });

  test('K05 新账号请求清除旧内容，迟到旧响应不得覆盖新账号推荐', () async {
    final requests = <Completer<RecommendationResult>>[];
    final platform = _RecommendationsPlatform(requests);
    final notifier = RecommendationsNotifier(
      supportedTypes: const [PlatformType.qq],
      platformResolver: (_) => platform,
    );
    addTearDown(notifier.dispose);
    final initial = notifier.loadLatestRecommendations();
    requests[0].complete(
      const RecommendationResult(
        songs: [
          Song(
            id: 'before',
            platform: PlatformType.qq,
            name: '原账号内容',
            artists: [],
          ),
        ],
      ),
    );
    await initial;
    final oldAccount = notifier.loadLatestRecommendations();
    expect(notifier.state.songsByPlatform, isEmpty);
    final newAccount = notifier.loadLatestRecommendations();
    requests[2].complete(
      const RecommendationResult(
        songs: [
          Song(
            id: 'new',
            platform: PlatformType.qq,
            name: '新账号内容',
            artists: [],
          ),
        ],
      ),
    );
    await newAccount;
    requests[1].complete(
      const RecommendationResult(
        songs: [
          Song(
            id: 'old',
            platform: PlatformType.qq,
            name: '迟到旧账号内容',
            artists: [],
          ),
        ],
      ),
    );
    await oldAccount;
    expect(notifier.state.songsForPlatform(PlatformType.qq).single.id, 'new');
    expect(notifier.state.isLoading, isFalse);
  });
}

class _RecommendationsPlatform extends FakeContentPlatform {
  _RecommendationsPlatform(this.requests)
    : super(type: PlatformType.qq, loggedIn: true);
  final List<Completer<RecommendationResult>> requests;
  @override
  bool get supportsDailyRecommendations => true;
  @override
  Future<RecommendationResult> getDailyRecommendation() {
    final request = Completer<RecommendationResult>();
    requests.add(request);
    return request.future;
  }
}

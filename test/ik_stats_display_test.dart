import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/stats/presentation/pages/listening_stats_page.dart';
import 'package:mconnect/features/stats/presentation/providers/listening_stats_provider.dart';
import 'package:mconnect/models/platform_type.dart';

class _StatsRepository extends MemoryListeningStatsRepository {
  _StatsRepository(this.snapshot);
  final ListeningStatsState snapshot;
  @override
  Future<ListeningStatsState> load() async => snapshot;
}

ListeningStatsState _snapshot(int count) {
  final all = List.generate(
    count,
    (index) => ListeningStatsSongEntry(
      songId: '$index',
      platform: PlatformType.qq,
      songName: '曲目${index + 1}',
      artistNames: '歌手',
      playCount: 1,
      listenDuration: const Duration(minutes: 1),
      lastListenedAt: DateTime(2026, 11, 20),
    ),
  );
  return ListeningStatsState(
    totalPlayCount: count,
    totalSongCount: count,
    totalListenDuration: Duration(minutes: count),
    allSongs: all,
    topSongs: all.take(listeningStatsTopSongViewLimit).toList(),
  );
}

Widget _page(int count, {bool legacy = false}) => ProviderScope(
  overrides: [
    listeningStatsProvider.overrideWith(
      (ref) => ListeningStatsNotifier(
        _StatsRepository(_snapshot(count)),
        importLegacySnapshot: false,
      ),
    ),
    listeningStatsReportProvider.overrideWith(
      (ref) async => const ListeningStatsReport(
        artists: [],
        albums: [],
        platforms: [],
        days: [],
        hours: [],
      ),
    ),
  ],
  child: MaterialApp(
    home: legacy
        ? const ListeningStatsPage()
        : const ListeningStatsPage(showAvailableSongs: true),
  ),
);

Future<void> _showSong(WidgetTester tester, int index) async {
  final target = find.text('曲目$index');
  final scrollable = tester.state<ScrollableState>(
    find.byType(Scrollable).first,
  );
  for (var attempt = 0; target.evaluate().isEmpty && attempt < 40; attempt++) {
    final position = scrollable.position;
    position.jumpTo(
      (position.pixels + 200).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
    await tester.pump();
  }
  expect(target, findsOneWidget, reason: '已提供的第$index首必须可滚动找到');
  await Scrollable.ensureVisible(tester.element(target), alignment: .5);
  await tester.pump();
  expect(target.hitTestable(), findsOneWidget, reason: '第$index首滚动后必须可见');
}

void main() {
  for (final count in [51, 100, 120]) {
    testWidgets('K06 ik统计$count首的实际显示与数量提示一致', (tester) async {
      await tester.pumpWidget(_page(count));
      await tester.pumpAndSettle();
      final displayed = count > listeningStatsTopSongViewLimit
          ? listeningStatsTopSongViewLimit
          : count;
      if (count > displayed) {
        expect(
          find.text('仅展示前 $displayed 首（共 $count 首，其余明细仍完整保留）'),
          findsOneWidget,
        );
      } else {
        expect(find.textContaining('仅展示前'), findsNothing);
      }
      for (var index = 1; index <= displayed; index++) {
        await _showSong(tester, index);
      }
      expect(find.text('曲目${displayed + 1}'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('K06 旧统计页缺省仍只显示前50首', (tester) async {
    await tester.pumpWidget(_page(51, legacy: true));
    await tester.pumpAndSettle();
    await _showSong(tester, 50);
    expect(find.text('曲目51'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

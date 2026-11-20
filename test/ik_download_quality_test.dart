import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/share/song_actions.dart';
import 'package:mconnect/features/album/presentation/pages/album_page.dart';
import 'package:mconnect/features/download/presentation/providers/download_provider.dart';
import 'package:mconnect/features/download/presentation/providers/download_quality_provider.dart';
import 'package:mconnect/models/album.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

import 'support/content_page_fakes.dart';

class _Downloads extends DownloadNotifier {
  _Downloads() : super(initialState: const DownloadState());
  final levels = <AudioLevel>[];
  @override
  Future<void> startDownload(Song song, AudioLevel quality) async {
    levels.add(quality);
  }

  @override
  Future<CacheEnqueueReport> cacheSongs(
    List<Song> songs, {
    AudioLevel quality = AudioLevel.low,
  }) async {
    levels.add(quality);
    return CacheEnqueueReport(queued: songs.length);
  }
}

void main() {
  testWidgets('K06 独立版专辑缓存与通用更多下载遵守统一音质，默认仍标准', (tester) async {
    final track = song('one', PlatformType.qq);
    registerFake(
      FakeContentPlatform(
        type: PlatformType.qq,
        album: const Album(id: 'album', name: '测试专辑'),
        albumSongs: [track],
      ),
    );
    for (final custom in [false, true]) {
      final downloads = _Downloads();
      late WidgetRef pageRef;
      await tester.pumpWidget(
        ProviderScope(
          key: ValueKey(custom),
          overrides: [
            downloadProvider.overrideWith((_) => downloads),
            if (custom)
              downloadQualityProvider.overrideWithValue(
                (_) => AudioLevel.lossless,
              ),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                pageRef = ref;
                return const AlbumPage(
                  platform: PlatformType.qq,
                  albumId: 'album',
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('整张缓存'));
      await tester.pump();
      expect(downloads.levels, [custom ? AudioLevel.lossless : AudioLevel.low]);
      if (custom) {
        final level = await liveSongActionDeps(pageRef).download(track);
        expect(level, AudioLevel.lossless);
        expect(downloads.levels.last, AudioLevel.lossless);
      }
    }
    await tester.pumpWidget(const SizedBox());
  });
}

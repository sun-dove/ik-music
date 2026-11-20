import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/database/app_database.dart';
import 'package:mconnect/core/database/song_record_mapping.dart';
import 'package:mconnect/features/download/presentation/providers/download_provider.dart';
import 'package:mconnect/features/library/presentation/providers/history_provider.dart';
import 'package:mconnect/features/library/presentation/providers/library_metadata_provider.dart';
import 'package:mconnect/features/library/presentation/providers/likes_provider.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/features/smart_playlists/domain/smart_playlist_rule.dart';
import 'package:mconnect/features/smart_playlists/presentation/providers/smart_playlist_preview_provider.dart';
import 'package:mconnect/features/stats/presentation/providers/listening_stats_provider.dart';
import 'package:mconnect/models/album.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

import 'support/content_page_fakes.dart';

const _liked = Song(
  id: 'liked',
  platform: PlatformType.qq,
  name: '收藏歌曲',
  artists: [Artist(id: 'artist-a', name: '歌手甲')],
  album: Album(id: 'album-a', name: '专辑甲'),
  trackNumber: 7,
);
const _played = Song(
  id: 'played',
  platform: PlatformType.netease,
  name: '历史歌曲',
  artists: [Artist(id: 'artist-b', name: '歌手乙')],
  album: Album(id: 'album-b', name: '专辑乙'),
  albumId: 'album-b',
  artistId: 'artist-b',
  trackNumber: 8,
);

ProviderContainer _container() => ProviderContainer(
  overrides: [
    libraryMetadataProvider.overrideWithValue(true),
    playerProvider.overrideWith(
      (ref) => PlayerNotifier(audioController: IdleAudioController()),
    ),
    downloadProvider.overrideWith(
      (ref) => DownloadNotifier(initialState: const DownloadState()),
    ),
    listeningStatsProvider.overrideWith(
      (ref) => ListeningStatsNotifier(
        MemoryListeningStatsRepository(),
        importLegacySnapshot: false,
      ),
    ),
  ],
);

Future<void> _load(ProviderContainer container) async {
  await container.read(likesProvider.notifier).loadAllLikes();
  await container.read(historyProvider.notifier).loadAllHistory();
}

void _expectRule(
  ProviderContainer container,
  Song song,
  String artistId,
  String albumId,
) {
  final rule = SmartPlaylistRule.create(
    name: '按歌手和专辑筛选',
    artistIds: {artistId},
    albumIds: {albumId},
  );
  expect(container.read(smartPlaylistPreviewProvider(rule)), [song]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  setUpAll(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    initializeApplicationDatabase(db);
  });
  setUp(() async {
    await db.delete(db.userLikes).go();
    await db.historyDao.clearHistory();
    await db.delete(db.songs).go();
  });
  tearDownAll(() => db.close());

  test('K06 新收藏和播放历史的歌手专辑 ID 落盘，重建容器仍可按高级规则匹配', () async {
    final first = _container();
    await _load(first);
    await first.read(likesProvider.notifier).toggleLike(_liked);
    await first.read(historyProvider.notifier).recordListen(_played);
    first.dispose();
    final likedRecord = await db.songsDao.getSong(
      _liked.id,
      _liked.platform.name,
    );
    final historyRecord = await db.songsDao.getSong(
      _played.id,
      _played.platform.name,
    );
    expect(likedRecord?.albumId, 'album-a');
    expect(likedRecord?.artistId, 'artist-a');
    expect(likedRecord?.trackNumber, 7);
    expect(historyRecord?.albumId, 'album-b');
    expect(historyRecord?.artistId, 'artist-b');
    expect(historyRecord?.trackNumber, 8);
    final reopened = _container();
    addTearDown(reopened.dispose);
    await _load(reopened);
    _expectRule(reopened, _liked, 'artist-a', 'album-a');
    _expectRule(reopened, _played, 'artist-b', 'album-b');
  });

  test('K06 已有完整数据库行重读后仍可按歌手专辑筛选', () async {
    await db.songsDao.insertSongs([
      songsCompanionFromSong(_liked),
      songsCompanionFromSong(_played),
    ]);
    await db.likesDao.likeSong(_liked.id, _liked.platform.name);
    await db.historyDao.recordListen(_played.id, _played.platform.name);
    final container = _container();
    addTearDown(container.dispose);
    await _load(container);
    expect(container.read(likesProvider).songs.single.album?.id, 'album-a');
    expect(
      container.read(historyProvider).entries.single.song.artistId,
      'artist-b',
    );
    _expectRule(container, _liked, 'artist-a', 'album-a');
    _expectRule(container, _played, 'artist-b', 'album-b');
  });

  test('K06 旧默认映射仍保持原读写行为', () async {
    final likes = LikesNotifier(db.likesDao, db.songsDao);
    final history = HistoryNotifier(db.historyDao, db.songsDao);
    addTearDown(likes.dispose);
    addTearDown(history.dispose);
    await likes.loadLikes();
    await history.loadHistory();
    await likes.toggleLike(_liked);
    await history.recordListen(_played);
    expect(
      (await db.songsDao.getSong(_liked.id, _liked.platform.name))?.albumId,
      isNull,
    );
    expect(
      (await db.songsDao.getSong(_played.id, _played.platform.name))?.artistId,
      isNull,
    );
    await db.songsDao.insertSongs([
      songsCompanionFromSong(_liked),
      songsCompanionFromSong(_played),
    ]);
    await likes.loadLikes();
    await history.loadHistory();
    expect(likes.state.songs.single.albumId, isNull);
    expect(likes.state.songs.single.album?.id, '');
    expect(history.state.entries.single.song.artistId, isNull);
    expect(history.state.entries.single.song.artists.single.id, '');
  });
}

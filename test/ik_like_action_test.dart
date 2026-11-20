import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/database/app_database.dart';
import 'package:mconnect/features/library/presentation/providers/likes_provider.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/video_app/ik/ik_like_action.dart';

void main() {
  test('喜欢及取消喜欢均按持久化结果反馈，旧false不是失败标志', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final likes = _Likes(db);
    await likes.loadAllLikes();
    final container = ProviderContainer(
      overrides: [likesProvider.overrideWith((ref) => likes)],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    const song = Song(
      id: 'action',
      name: '收藏门',
      platform: PlatformType.qq,
      artists: [],
    );
    final action = container.read(ikLikeActionProvider.notifier);
    await action.toggle(song);
    expect(await likes.isLiked(song.id, song.platform), isTrue);
    expect(container.read(ikLikeActionProvider).issue, isNull);
    await action.toggle(song);
    expect(await likes.isLiked(song.id, song.platform), isFalse);
    expect(container.read(ikLikeActionProvider).issue, isNull);
    likes.fail = true;
    await action.toggle(song);
    expect(await likes.isLiked(song.id, song.platform), isFalse);
    expect(container.read(ikLikeActionProvider).issue, isNotNull);
    expect(container.read(ikLikeActionProvider).busy, isFalse);
    likes.fail = false;
    await action.toggle(song);
    expect(await likes.isLiked(song.id, song.platform), isTrue);
    expect(container.read(ikLikeActionProvider).issue, isNull);
  });
}

class _Likes extends LikesNotifier {
  _Likes(AppDatabase db) : super(db.likesDao, db.songsDao);
  bool fail = false;
  @override
  Future<bool> toggleLike(Song song) =>
      fail ? Future.value(false) : super.toggleLike(song);
}

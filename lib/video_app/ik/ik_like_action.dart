import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/library/presentation/providers/likes_provider.dart';
import '../../l10n/ik_workspace_strings.dart';
import '../../models/song.dart';

class IkLikeActionState {
  const IkLikeActionState({this.busy = false, this.issue});
  final bool busy;
  final String? issue;
}

final ikLikeActionProvider =
    StateNotifierProvider<IkLikeAction, IkLikeActionState>(
      (ref) => IkLikeAction(ref),
    );

/// 旧 toggleLike 的 false 同时表示取消收藏；新播放栏另核对实际落盘状态。
class IkLikeAction extends StateNotifier<IkLikeActionState> {
  IkLikeAction(this.ref) : super(const IkLikeActionState());
  final Ref ref;

  Future<void> toggle(Song song) async {
    if (state.busy) return;
    state = const IkLikeActionState(busy: true);
    try {
      final likes = ref.read(likesProvider.notifier);
      final expected = !await likes.isLiked(song.id, song.platform);
      await likes.toggleLike(song);
      final actual = await likes.isLiked(song.id, song.platform);
      if (mounted) {
        state = IkLikeActionState(
          issue: actual == expected ? null : IkWorkspaceStrings.likeFailed,
        );
      }
    } catch (_) {
      if (mounted) {
        state = const IkLikeActionState(issue: IkWorkspaceStrings.likeFailed);
      }
    }
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/auth/presentation/providers/auth_provider.dart';
import 'package:mconnect/features/library/presentation/providers/platform_playlists_provider.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/playlist.dart';
import 'package:mconnect/models/user.dart';
import 'package:mconnect/video_app/ik/ik_account_runtime.dart';

class _Auth extends AuthNotifier {
  void replace(String? id) => state = AuthState(
    loggedUsers: {
      PlatformType.qq: id == null
          ? null
          : User(id: id, nickname: id, platform: PlatformType.qq),
    },
  );
}

class _Playlists extends PlatformPlaylistsNotifier {
  _Playlists(this.account);
  final String? account;
  bool loaded = false;
  @override
  Future<void> load() async {
    loaded = true;
    state = PlatformPlaylistsState(
      playlistsByPlatform: {
        PlatformType.qq: [
          if (account != null)
            Playlist(id: account!, name: account!, platform: PlatformType.qq),
        ],
      },
    );
  }
}

void main() {
  test('K04 当前账号切换/退出使平台歌单换成新账号，旧缓存不再显示', () async {
    final auth = _Auth()..replace('old');
    final instances = <_Playlists>[];
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((ref) => auth),
        platformPlaylistsProvider.overrideWith((ref) {
          final notifier = _Playlists(
            ref.read(authProvider).userFor(PlatformType.qq)?.id,
          );
          instances.add(notifier);
          return notifier;
        }),
      ],
    );
    addTearDown(container.dispose);
    container.read(ikAccountRuntimeProvider);
    await container.read(platformPlaylistsProvider.notifier).load();
    expect(
      container
          .read(platformPlaylistsProvider)
          .playlistsFor(PlatformType.qq)
          .single
          .id,
      'old',
    );
    auth.replace('new');
    await pumpEventQueue();
    expect(
      container
          .read(platformPlaylistsProvider)
          .playlistsFor(PlatformType.qq)
          .single
          .id,
      'new',
    );
    auth.replace(null);
    await pumpEventQueue();
    expect(
      container.read(platformPlaylistsProvider).playlistsFor(PlatformType.qq),
      isEmpty,
    );
    expect(instances, hasLength(3));
    expect(instances.every((instance) => instance.loaded), isTrue);
  });
}

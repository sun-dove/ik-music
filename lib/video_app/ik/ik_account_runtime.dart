import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/library/presentation/providers/platform_playlists_provider.dart';
import '../../models/platform_type.dart';

/// 账号身份改变后重新创建平台歌单状态，旧请求随原 notifier 销毁失效。
final ikAccountRuntimeProvider = Provider<void>((ref) {
  var active = true;
  var generation = 0;
  ref.onDispose(() => active = false);
  ref.listen(authProvider, (previous, next) {
    if (!PlatformType.musicServices.any(
      (platform) =>
          previous?.userFor(platform)?.id != next.userFor(platform)?.id,
    )) {
      return;
    }
    final current = ++generation;
    // 认证可能由页面建树触发，推迟状态重建避免 build 期间修改 provider。
    unawaited(
      Future<void>.microtask(() async {
        if (!active || generation != current) return;
        ref.invalidate(platformPlaylistsProvider);
        await ref.read(platformPlaylistsProvider.notifier).load();
      }),
    );
  });
});

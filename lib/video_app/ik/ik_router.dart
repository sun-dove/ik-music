import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/album/presentation/pages/album_page.dart';
import '../../features/artist/presentation/pages/artist_page.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/discovery/presentation/pages/recommendations_page.dart';
import '../../features/download/presentation/screens/download_page.dart';
import '../../features/library/presentation/pages/history_page.dart';
import '../../features/library/presentation/pages/import_playlist_page.dart';
import '../../features/library/presentation/pages/likes_page.dart';
import '../../features/library/presentation/pages/platform_playlists_page.dart';
import '../../features/library/presentation/pages/playlist_detail_page.dart';
import '../../features/local_music/presentation/pages/local_music_page.dart';
import '../../features/new_songs/presentation/pages/new_songs_page.dart';
import '../../features/offline_cache/presentation/pages/offline_cache_page.dart';
import '../../features/player/presentation/pages/queue_page.dart';
import '../../features/smart_playlists/presentation/pages/smart_playlist_editor_page.dart';
import '../../features/smart_playlists/presentation/pages/smart_playlists_page.dart';
import '../../features/stats/presentation/pages/listening_stats_page.dart';
import '../../features/toplist/presentation/pages/toplists_page.dart';
import '../../l10n/ik_strings.dart';
import '../../models/platform_type.dart';
import 'ik_audio_page.dart';
import 'ik_backup_page.dart';
import 'ik_floating_lyrics.dart';
import 'ik_personal_daily_page.dart';

GoRouter createIkRouter({
  required WidgetBuilder home,
  required WidgetBuilder player,
  Widget Function(BuildContext, Widget)? detailShell,
  Widget Function(BuildContext, String)? settings,
  WidgetBuilder? downloads,
  bool alignToDesign = false,
}) {
  Widget detail(BuildContext context, Widget page) =>
      detailShell?.call(context, page) ?? page;
  GoRoute page(String path, WidgetBuilder builder) => GoRoute(
    path: path,
    builder: (context, _) => detail(context, builder(context)),
  );
  Widget platformPage(
    BuildContext context,
    GoRouterState state,
    Widget Function(PlatformType, String) builder,
  ) {
    final name = state.pathParameters['platform'];
    final platform = PlatformType.values
        .where((value) => value.name == name)
        .firstOrNull;
    final id = state.pathParameters['id'] ?? '';
    if (platform == null || id.trim().isEmpty) return const IkRouteError();
    return detail(context, builder(platform, id));
  }

  return GoRouter(
    initialLocation: '/',
    overridePlatformDefaultLocation: true,
    errorBuilder: (_, _) => const IkRouteError(),
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (context, _) => NoTransitionPage<void>(
          key: const ValueKey('ik-home'),
          child: home(context),
        ),
      ),
      GoRoute(path: '/player', builder: (context, _) => player(context)),
      page('/queue', (_) => const QueuePage()),
      page(
        '/recommendations',
        (_) => RecommendationsPage(alignToDesign: alignToDesign),
      ),
      if (alignToDesign)
        GoRoute(
          path: '/daily',
          builder: (context, state) {
            final name = state.uri.queryParameters['platform'];
            final platform = name == null
                ? PlatformType.netease
                : PlatformType.tryParse(name);
            if (platform == null || !platform.isMusicService) {
              return const IkRouteError();
            }
            return detail(
              context,
              IkPersonalDailyPage(initialPlatform: platform),
            );
          },
        ),
      page('/toplists', (_) => ToplistsPage(alignToDesign: alignToDesign)),
      page('/new-songs', (_) => NewSongsPage(alignToDesign: alignToDesign)),
      page('/history', (_) => const HistoryPage(allEntries: true)),
      page('/local-music', (_) => const LocalMusicPage()),
      page('/likes', (_) => const LikesPage(allEntries: true)),
      page(
        '/platform-playlists',
        (_) => const PlatformPlaylistsPage(
          jsonFormatLabel: IkStrings.playlistJson,
        ),
      ),
      page(
        '/import-playlist',
        (_) => const ImportPlaylistPage(
          formatHint: IkStrings.importPlaylistHint,
          localImportFailure: IkStrings.importPlaylistFailed,
        ),
      ),
      page('/downloads', downloads ?? (_) => const DownloadPage()),
      page('/offline-cache', (_) => const OfflineCachePage()),
      page(
        '/listening-stats',
        (_) => const ListeningStatsPage(showAvailableSongs: true),
      ),
      page(
        '/smart-playlists',
        (_) => const SmartPlaylistsPage(safeDelete: true),
      ),
      GoRoute(
        path: '/smart-playlists/editor',
        builder: (context, state) => detail(
          context,
          SmartPlaylistEditorPage(ruleId: state.uri.queryParameters['id']),
        ),
      ),
      page('/backup', (_) => const IkBackupPage()),
      page(
        '/settings/audio',
        (context) => settings?.call(context, 'audio') ?? const IkAudioPage(),
      ),
      page(
        '/settings/floating-lyrics',
        (context) =>
            settings?.call(context, 'lyrics') ?? const IkFloatingLyricsPage(),
      ),
      if (settings != null) ...[
        page('/settings', (context) => settings(context, 'audio')),
        for (final section in [
          'appearance',
          'lyrics',
          'sources',
          'downloads',
          'accounts',
          'backup',
        ])
          page('/settings/$section', (context) => settings(context, section)),
      ],
      GoRoute(
        path: '/login/:platform',
        builder: (context, state) {
          final platform = PlatformType.values
              .where(
                (value) =>
                    value.name == state.pathParameters['platform'] &&
                    value.isMusicService,
              )
              .firstOrNull;
          return platform == null
              ? const IkRouteError()
              : detail(context, LoginPage(platform: platform));
        },
      ),
      GoRoute(
        path: '/album/:platform/:id',
        builder: (context, state) => platformPage(
          context,
          state,
          (p, id) => AlbumPage(
            platform: p,
            albumId: id,
            albumName: state.uri.queryParameters['name'],
          ),
        ),
      ),
      GoRoute(
        path: '/artist/:platform/:id',
        builder: (context, state) => platformPage(
          context,
          state,
          (p, id) => ArtistPage(
            platform: p,
            artistId: id,
            artistName: state.uri.queryParameters['name'],
          ),
        ),
      ),
      GoRoute(
        path: '/toplist/:platform/:id',
        builder: (context, state) => platformPage(
          context,
          state,
          (p, id) => ToplistDetailPage(
            platform: p,
            toplistId: id,
            toplistName: state.uri.queryParameters['name'],
          ),
        ),
      ),
      GoRoute(
        path: '/playlist/:platform/:id',
        builder: (context, state) => platformPage(
          context,
          state,
          (p, id) => PlaylistDetailPage(
            platform: p,
            playlistId: id,
            playlistName:
                state.uri.queryParameters['name'] ?? IkStrings.playlists,
            coverUrl: state.uri.queryParameters['cover'],
          ),
        ),
      ),
    ],
  );
}

class IkRouteError extends StatelessWidget {
  const IkRouteError({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(IkStrings.pageMissing),
          TextButton(
            onPressed: () => context.go('/'),
            child: const Text(IkStrings.backHome),
          ),
        ],
      ),
    ),
  );
}

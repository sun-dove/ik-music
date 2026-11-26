import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'ik_router.dart';
import 'ik_personal_daily_page.dart';
import '../../core/platform/platform_utils.dart';
import '../../features/library/presentation/pages/import_playlist_page.dart';
import '../../features/library/presentation/pages/playlist_detail_page.dart';
import '../../features/smart_playlists/presentation/pages/smart_playlist_editor_page.dart';
import '../../l10n/ik_strings.dart';
import '../../models/platform_type.dart';

/// IK新正文导航。旧路由工厂和所有页面构造维持原默认行为。
GoRouter createIkWorkspaceRouter({
  required Widget Function(BuildContext, Widget, String) workspace,
  required WidgetBuilder player,
  required GlobalKey<NavigatorState> navigatorKey,
  Widget Function(BuildContext, String)? settings,
  WidgetBuilder? downloads,
}) => _createWorkspaceRouter(
  workspace: workspace,
  player: player,
  navigatorKey: navigatorKey,
  settings: settings,
  downloads: downloads,
);

/// 快速改版扩展新日推与桌面歌单装配；旧公开路由工厂与默认页面保持。
GoRouter createIkRefinedWorkspaceRouter({
  required Widget Function(BuildContext, Widget, String) workspace,
  required WidgetBuilder player,
  required GlobalKey<NavigatorState> navigatorKey,
  Widget Function(BuildContext, String)? settings,
  WidgetBuilder? downloads,
}) => _createWorkspaceRouter(
  workspace: workspace,
  player: player,
  navigatorKey: navigatorKey,
  settings: settings,
  downloads: downloads,
  refinedRecommendations: true,
);

GoRouter _createWorkspaceRouter({
  required Widget Function(BuildContext, Widget, String) workspace,
  required WidgetBuilder player,
  required GlobalKey<NavigatorState> navigatorKey,
  Widget Function(BuildContext, String)? settings,
  WidgetBuilder? downloads,
  bool refinedRecommendations = false,
}) {
  final original = createIkRouter(
    home: (_) => const SizedBox.shrink(),
    player: player,
    settings: settings,
    downloads: downloads,
    alignToDesign: true,
  );
  final routes = List<RouteBase>.of(original.configuration.routes);
  original.dispose();
  return GoRouter(
    initialLocation: '/',
    overridePlatformDefaultLocation: true,
    routes: [
      ShellRoute(
        navigatorKey: navigatorKey,
        builder: (context, state, child) =>
            workspace(context, child, state.uri.path),
        routes: [
          for (final route in routes)
            if (route is GoRoute && route.path == '/')
              GoRoute(
                path: '/',
                pageBuilder: (_, state) => NoTransitionPage<void>(
                  key: state.pageKey,
                  child: const SizedBox.shrink(),
                ),
              )
            else if (refinedRecommendations && route is GoRoute &&
                route.path == '/daily')
              GoRoute(
                path: route.path,
                builder: (_, state) {
                  final name = state.uri.queryParameters['platform'];
                  final platform = name == null
                      ? PlatformType.netease
                      : PlatformType.tryParse(name);
                  if (platform == null || !platform.isMusicService) {
                    return const IkRouteError();
                  }
                  return IkPersonalDailyPage(
                    initialPlatform: platform,
                    refinedRecommendations: true,
                  );
                },
              )
            else if (refinedRecommendations &&
                PlatformUtils.isWindows &&
                route is GoRoute &&
                route.path == '/playlist/:platform/:id')
              GoRoute(
                path: route.path,
                builder: (_, state) {
                  final name = state.pathParameters['platform'];
                  final platform = name == null
                      ? null
                      : PlatformType.tryParse(name);
                  final id = state.pathParameters['id'] ?? '';
                  if (platform == null || id.trim().isEmpty) {
                    return const IkRouteError();
                  }
                  return PlaylistDetailPage(
                    platform: platform,
                    playlistId: id,
                    playlistName:
                        state.uri.queryParameters['name'] ?? IkStrings.playlists,
                    coverUrl: state.uri.queryParameters['cover'],
                    desktopTable: true,
                  );
                },
              )
            else if (route is GoRoute && route.path == '/import-playlist')
              GoRoute(
                path: route.path,
                builder: (_, _) => const ImportPlaylistPage(
                  formatHint: IkStrings.importPlaylistHint,
                  localImportFailure: IkStrings.importPlaylistFailed,
                  protectWorkspaceDraft: true,
                ),
              )
            else if (route is GoRoute &&
                route.path == '/smart-playlists/editor')
              GoRoute(
                path: route.path,
                builder: (_, state) => SmartPlaylistEditorPage(
                  ruleId: state.uri.queryParameters['id'],
                  protectWorkspaceDraft: true,
                ),
              )
            else
              route,
          GoRoute(
            path: '/:unmatched(.*)',
            builder: (_, _) => const IkRouteError(),
          ),
        ],
      ),
    ],
  );
}

/// 仅在新正文内启用，主导航离开与页内返回共用已有草稿检查。
class IkWorkspaceNavigation extends InheritedWidget {
  const IkWorkspaceNavigation({
    super.key,
    required this.register,
    required this.unregister,
    required super.child,
  });

  final void Function(Object, Future<bool> Function()) register;
  final void Function(Object) unregister;

  static IkWorkspaceNavigation? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<IkWorkspaceNavigation>();

  @override
  bool updateShouldNotify(IkWorkspaceNavigation oldWidget) => false;
}

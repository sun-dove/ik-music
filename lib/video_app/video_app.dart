import '../l10n/source_strings.dart';

import '../l10n/video_strings.dart';

import 'dart:async';

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../l10n/ik_strings.dart';
import '../l10n/ik_alignment_strings.dart';
import '../core/widgets/song_actions_sheet.dart';
import '../features/discovery/presentation/providers/recommendations_provider.dart';
import '../features/library/presentation/providers/likes_provider.dart';
import 'ik/ik_search.dart';
import 'ik/ik_catalog_pages.dart';
import 'ik/ik_home_page.dart';
import 'ik/ik_shell.dart';
import 'ik/ik_router.dart';
import 'ik/ik_runtime.dart';
import 'ik/ik_theme.dart';
import 'ik/ik_workspace.dart';
import 'ik/ik_settings_workspace.dart';
import 'ik/ik_playback_bar.dart';
import 'ik/ik_recent_page.dart';
import 'ik/ik_library_workspace.dart';
import 'ik/ik_search_workspace.dart';
import 'ik/ik_download_submission.dart';
import 'ik/ik_download_folder.dart';
import 'ik/ik_downloads_workspace.dart';
import 'ik/ik_workspace_theme.dart';
import 'ik/ik_lyrics_action.dart';
import '../features/floating_lyrics/presentation/providers/floating_lyrics_provider.dart';
import 'built_in/catalog_panel.dart';

import '../features/auth/presentation/pages/login_page.dart';
import '../features/auth/presentation/providers/auth_provider.dart';
import '../features/download/data/download_directory_service.dart';
import '../features/download/domain/entities/download_task.dart';
import '../features/download/domain/entities/download_failure.dart';
import '../features/download/presentation/providers/download_provider.dart';
import '../features/local_music/presentation/providers/local_music_provider.dart';
import '../features/offline_cache/presentation/providers/offline_cache_provider.dart';
import '../features/player/presentation/providers/lyrics_provider.dart';
import '../features/player/presentation/providers/player_provider.dart';
import '../models/audio_quality.dart';
import '../models/platform_type.dart';
import '../models/song.dart';
import 'custom_source/custom_source_client.dart';
import 'custom_source/custom_source_models.dart';
import 'custom_source/custom_source_storage.dart';
import 'data/video_auth_notifier.dart';
import 'data/video_catalog.dart';
import 'data/video_kugou_catalog.dart';
import 'lx_source/lx_source.dart';
import 'lx_source/lx_runtime.dart';
import 'lx_source/lx_http.dart';
import 'lx_source/lx_importer_v3.dart';
import 'multi_source/source_checks.dart';
import 'multi_source/source_collection.dart';
import 'multi_source/multi_source_player.dart';
import 'ui/source_manager_page.dart';
import 'ui/source_collection_page.dart';
import 'ui/kugou_playlists_page.dart';
import 'playback/video_stream_state.dart';
import 'ui/catalog_pages.dart';
import 'ui/custom_source_page.dart';
import 'ui/lx_source_page.dart';
import 'ui/my_page.dart';
import 'ui/player_page.dart';
import 'ui/video_shell.dart';
import 'ui/video_theme.dart';
import 'video_preferences.dart';
import '../l10n/windows_music_strings.dart';
import 'windows/windows_appearance.dart';
import 'windows/windows_appearance_dialogs.dart';
import 'windows/windows_music_preferences.dart';
import 'windows/windows_my_page.dart';
import 'windows/windows_player_page.dart';
import 'windows/windows_download.dart';

IkPlaybackBar _workspacePlaybackBar({
  required bool alignToDesign,
  required VoidCallback? onOpen,
  required VoidCallback onAudio,
}) => alignToDesign
    ? IkPlaybackBar.aligned(onOpen: onOpen, onAudio: onAudio)
    : IkPlaybackBar(onOpen: onOpen, onAudio: onAudio);

class VideoMusicApp extends StatefulWidget {
  const VideoMusicApp({
    super.key,
    required this.preferences,
    this.customSourceCredentials,
    this.customSourceDio,
    this.onCustomSourceChanged,
    this.sourceSettings,
    this.sourceEngine,
    this.catalog,
    this.expandedPlatforms = false,
    this.windowsAppearance,
    this.unifiedPreferences,
    this.redesign = false,
    this.workspace = false,
    this.alignToDesign = false,
    this.mobileKeyboardLayout = false,
    this.dismissSourceMenuOnBack = false,
    this.pageInteractionRefinements = false,
  });
  final VideoPreferences preferences;
  final CustomSourceCredentialStore? customSourceCredentials;
  final Dio? customSourceDio;
  final VoidCallback? onCustomSourceChanged;
  final SourceSettings? sourceSettings;
  final LxSourceEngine? sourceEngine;
  final ExpandedVideoCatalog? catalog;
  final bool expandedPlatforms;
  final WindowsAppearance? windowsAppearance;
  final WindowsMusicPreferences? unifiedPreferences;
  final bool redesign;
  final bool workspace;
  final bool alignToDesign;
  final bool mobileKeyboardLayout;
  final bool dismissSourceMenuOnBack;
  final bool pageInteractionRefinements;
  @override
  State<VideoMusicApp> createState() => _VideoMusicAppState();
}

class _VideoMusicAppState extends State<VideoMusicApp> {
  final _homeKey = GlobalKey<_VideoHomeState>();
  late final _router = createIkRouter(
    alignToDesign: widget.workspace && widget.alignToDesign,
    home: (_) => _routeContent(_home()),
    player: (_) => _routeContent(
      _homeKey.currentState?._playerPage() ?? const IkRouteError(),
    ),
    downloads: widget.alignToDesign && widget.workspace
        ? (_) =>
              _homeKey.currentState?._alignedDownloadsPage() ??
              const IkRouteError()
        : null,
    settings: widget.workspace
        ? (_, section) => Scaffold(
            appBar: AppBar(leading: const BackButton()),
            body:
                _homeKey.currentState?._workspaceSettings(section) ??
                const IkRouteError(),
          )
        : null,
    detailShell: (context, page) => _routeContent(
      Scaffold(
        body: Column(
          children: [
            Expanded(child: page),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Consumer(
                builder: (context, ref, _) {
                  if (widget.workspace) {
                    return _workspacePlaybackBar(
                      alignToDesign: widget.alignToDesign,
                      onOpen: () => context.push('/player'),
                      onAudio: () => context.push('/settings/audio'),
                    );
                  }
                  final player = ref.watch(playerProvider);
                  return VideoMiniPlayer(
                    song: player.currentSong,
                    isPlaying: player.isPlaying,
                    isLoading: player.isTransitioning,
                    error: player.error,
                    onOpen: () => context.push('/player'),
                    onToggle: ref.read(playerProvider.notifier).togglePlay,
                    onQueue: () => context.push('/queue'),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _routeContent(Widget page) => widget.workspace && widget.alignToDesign
      ? Overlay.wrap(clipBehavior: Clip.none, child: page)
      : page;

  @override
  void dispose() {
    if (widget.redesign) _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.windowsAppearance == null
      ? _app()
      : ListenableBuilder(
          listenable: widget.windowsAppearance!,
          builder: (_, _) => _app(),
        );
  Widget _app() {
    if (widget.redesign) {
      return MaterialApp.router(
        title: VideoStrings.appName,
        debugShowCheckedModeBanner: false,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('zh')],
        theme: _workspaceTheme(
          widget.windowsAppearance?.theme(Brightness.light) ?? VideoTheme.light,
        ),
        darkTheme: _workspaceTheme(
          widget.windowsAppearance?.theme(Brightness.dark) ?? VideoTheme.dark,
        ),
        themeMode: switch (widget.preferences.theme) {
          'dark' => ThemeMode.dark,
          'system' => ThemeMode.system,
          _ => ThemeMode.light,
        },
        routerConfig: _router,
        builder: (context, child) => IkRuntime(
          onNavigate: (path) => _router.push(path),
          child: widget.windowsAppearance == null
              ? child!
              : WindowsBackground(
                  appearance: widget.windowsAppearance!,
                  child: child!,
                ),
        ),
      );
    }
    return MaterialApp(
      title: VideoStrings.appName,
      debugShowCheckedModeBanner: false,
      theme:
          widget.windowsAppearance?.theme(Brightness.light) ?? VideoTheme.light,
      darkTheme:
          widget.windowsAppearance?.theme(Brightness.dark) ?? VideoTheme.dark,
      builder: widget.windowsAppearance == null
          ? null
          : (context, child) => WindowsBackground(
              appearance: widget.windowsAppearance!,
              child: child!,
            ),
      themeMode: switch (widget.preferences.theme) {
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => ThemeMode.light,
      },
      home: _home(),
    );
  }

  ThemeData _workspaceTheme(ThemeData base) => widget.workspace
      ? widget.alignToDesign
            ? IkWorkspaceTheme.aligned(base)
            : IkWorkspaceTheme.from(base)
      : IkTheme.from(base);

  Widget _home() => _VideoHome(
    key: _homeKey,
    redesign: widget.redesign,
    workspace: widget.workspace,
    alignToDesign: widget.alignToDesign,
    mobileKeyboardLayout: widget.mobileKeyboardLayout,
    dismissSourceMenuOnBack: widget.dismissSourceMenuOnBack,
    pageInteractionRefinements: widget.pageInteractionRefinements,
    preferences: widget.preferences,
    customSourceCredentials:
        widget.customSourceCredentials ??
        const SecureCustomSourceCredentialStore(),
    customSourceDio: widget.customSourceDio ?? Dio(),
    onCustomSourceChanged: widget.onCustomSourceChanged,
    sourceSettings: widget.sourceSettings,
    sourceEngine: widget.sourceEngine,
    catalog: widget.catalog,
    expandedPlatforms: widget.expandedPlatforms,
    windowsAppearance: widget.windowsAppearance,
    unifiedPreferences: widget.unifiedPreferences,
    onThemeChanged: () => setState(() {}),
  );
}

class _VideoHome extends ConsumerStatefulWidget {
  const _VideoHome({
    super.key,
    required this.preferences,
    required this.customSourceCredentials,
    required this.customSourceDio,
    this.onCustomSourceChanged,
    required this.onThemeChanged,
    this.sourceSettings,
    this.sourceEngine,
    this.catalog,
    this.expandedPlatforms = false,
    this.windowsAppearance,
    this.unifiedPreferences,
    this.redesign = false,
    this.workspace = false,
    this.alignToDesign = false,
    this.mobileKeyboardLayout = false,
    this.dismissSourceMenuOnBack = false,
    this.pageInteractionRefinements = false,
  });
  final VideoPreferences preferences;
  final CustomSourceCredentialStore customSourceCredentials;
  final Dio customSourceDio;
  final VoidCallback? onCustomSourceChanged;
  final VoidCallback onThemeChanged;
  final SourceSettings? sourceSettings;
  final LxSourceEngine? sourceEngine;
  final ExpandedVideoCatalog? catalog;
  final bool expandedPlatforms;
  final WindowsAppearance? windowsAppearance;
  final WindowsMusicPreferences? unifiedPreferences;
  final bool redesign;
  final bool workspace;
  final bool alignToDesign;
  final bool mobileKeyboardLayout;
  final bool dismissSourceMenuOnBack;
  final bool pageInteractionRefinements;
  @override
  ConsumerState<_VideoHome> createState() => _VideoHomeState();
}

class _VideoHomeState extends ConsumerState<_VideoHome>
    with WidgetsBindingObserver {
  bool get _refinePageInteractions =>
      widget.workspace &&
      widget.alignToDesign &&
      widget.pageInteractionRefinements;

  WindowsMusicPreferences? get _unifiedPreferences =>
      widget.unifiedPreferences ?? widget.windowsAppearance?.preferences;
  AudioLevel _effectiveQuality(
    PlatformType platform, {
    bool download = false,
  }) =>
      _unifiedPreferences?.quality(platform, download: download) ??
      widget.preferences.quality(platform, download: download);
  late final VideoCatalog _catalog = widget.catalog ?? VideoCatalog();
  List<PlatformType> get _platforms => [
    PlatformType.qq,
    PlatformType.netease,
    if (widget.expandedPlatforms) PlatformType.kugou,
  ];
  final _query = LatestVideoQuery<VideoPage>();
  final _search = TextEditingController();
  final _libraries = <PlatformType, VideoLibrary>{};
  final _syncing = <PlatformType>{};
  final _libraryEpoch = <PlatformType, int>{};
  final _pendingLikes = <String>{};
  var _result = const VideoCatalogViewState();
  var _searchPlatform = PlatformType.qq;
  late var _index = widget.redesign
      ? 0
      : widget.expandedPlatforms
      ? 4
      : 3;
  late final _ikSearch = IkSearchController(
    search: (platform, query, page) async {
      if (platform == PlatformType.local) {
        await ref.read(localMusicProvider.notifier).initialize();
        final songs = ref
            .read(localMusicProvider)
            .songs
            .where(
              (song) =>
                  '${song.name} ${song.artistNames} ${song.album?.name ?? ''}'
                      .toLowerCase()
                      .contains(query.toLowerCase()),
            )
            .toList();
        return VideoPage(
          songs: songs,
          total: songs.length,
          page: 1,
          hasMore: false,
        );
      }
      return _catalog.search(platform, query, page: page);
    },
  );
  var _page = 0;
  var _submitted = false;
  var _localReady = false;
  var _committedQuery = '';
  var _hotTerms = <String>[];
  var _hotLoading = false;
  String? _hotError;
  var _settingsSection = 'audio';
  var _settingsSectionRequest = 0;
  Offset? _workspacePointer;
  final _totals = <PlatformType, int?>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.redesign) {
      widget.windowsAppearance?.addListener(_appearanceChanged);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_initialize());
      });
    } else {
      unawaited(_initialize());
    }
  }

  void _appearanceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant _VideoHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.redesign != widget.redesign ||
        oldWidget.windowsAppearance != widget.windowsAppearance) {
      if (oldWidget.redesign) {
        oldWidget.windowsAppearance?.removeListener(_appearanceChanged);
      }
      if (widget.redesign) {
        widget.windowsAppearance?.addListener(_appearanceChanged);
      }
    }
  }

  Future<void> _initialize() async {
    unawaited(
      widget.workspace && widget.alignToDesign
          ? _loadAlignedHotTerms()
          : _loadHotTerms(),
    );
    unawaited(_initializeLocal());
    await ref.read(authProvider.notifier).init();
    if (!mounted) return;
    for (final platform in _platforms) {
      if (ref.read(authProvider).isLoggedIn(platform)) {
        unawaited(_sync(platform));
      }
    }
    await ref.read(offlineCacheSettingsProvider.notifier).ready;
    if (!mounted) return;
    if (widget.preferences.box.get('video.cacheInitialized') != true) {
      await ref
          .read(offlineCacheSettingsProvider.notifier)
          .setSizeLimitMb(10240);
      await widget.preferences.box.put('video.cacheInitialized', true);
    }
    await ref.read(downloadProvider.notifier).ready;
    if (!mounted) return;
    unawaited(ref.read(downloadProvider.notifier).refreshCacheUsage());
  }

  Future<void> _loadHotTerms() async {
    try {
      final words = await _catalog.hotSearch();
      if (mounted) setState(() => _hotTerms = words);
    } catch (_) {
      /* 热搜失败仍可手动输入并搜索。 */
    }
  }

  Future<void> _loadAlignedHotTerms() async {
    if (_hotLoading) return;
    setState(() {
      _hotLoading = true;
      _hotError = null;
    });
    try {
      final words = await _catalog.hotSearch();
      if (mounted) setState(() => _hotTerms = words);
    } catch (error) {
      if (mounted) setState(() => _hotError = VideoFailure.from(error).message);
    } finally {
      if (mounted) setState(() => _hotLoading = false);
    }
  }

  Future<void> _initializeLocal() async {
    await ref.read(localMusicProvider.notifier).initialize();
    if (mounted) setState(() => _localReady = true);
  }

  @override
  void dispose() {
    if (widget.redesign) {
      widget.windowsAppearance?.removeListener(_appearanceChanged);
      _ikSearch.dispose();
    }
    _query.invalidate();
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(ref.read(playerProvider.notifier).flushPlaybackMemory());
      unawaited(ref.read(playerProvider.notifier).reassertBackgroundPlayback());
    }
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _runSearch(String text, {bool more = false}) async {
    final keyword = more ? _committedQuery : text.trim();
    if (!more) {
      _query.invalidate();
      _page = 0;
      _committedQuery = keyword;
      setState(() {
        _submitted = keyword.isNotEmpty;
        _totals.clear();
        _result = VideoCatalogViewState(loading: keyword.isNotEmpty);
      });
    } else {
      if (_result.loading || _result.loadingMore || !_result.hasMore) return;
      setState(
        () => _result = VideoCatalogViewState(
          songs: _result.songs,
          total: _result.total,
          hasMore: true,
          loadingMore: true,
        ),
      );
    }
    if (keyword.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final platform = _searchPlatform;
    final requestedPage = _page + 1;
    try {
      final response = await _query.run(() async {
        if (platform == PlatformType.local) {
          await ref.read(localMusicProvider.notifier).initialize();
          final words = keyword.toLowerCase();
          final songs = ref
              .read(localMusicProvider)
              .songs
              .where(
                (s) => '${s.name} ${s.artistNames} ${s.album?.name ?? ''}'
                    .toLowerCase()
                    .contains(words),
              )
              .toList();
          return VideoPage(
            songs: songs,
            total: songs.length,
            page: 1,
            hasMore: false,
          );
        }
        return _catalog.search(platform, keyword, page: requestedPage);
      });
      if (!mounted || response == null) return;
      final songs = <String, Song>{
        for (final song in more ? _result.songs : <Song>[])
          videoSongKey(song): song,
        for (final song in response.songs) videoSongKey(song): song,
      };
      setState(() {
        _page = response.page;
        _totals[platform] = response.total;
        _result = VideoCatalogViewState(
          songs: songs.values.toList(),
          total: response.total,
          hasMore: response.hasMore,
        );
      });
    } catch (error) {
      if (!mounted) return;
      final failure = VideoFailure.from(error);
      setState(
        () => _result = VideoCatalogViewState(
          songs: more ? _result.songs : const [],
          total: _result.total,
          hasMore: more,
          error: failure.message,
          canRetry: failure.canRetry,
        ),
      );
      if (failure.kind == VideoFailureKind.sessionExpired) {
        await ref.read(authProvider.notifier).handleSessionExpired(platform);
      }
    }
  }

  Future<void> _sync(PlatformType platform) async {
    final user = ref.read(authProvider).userFor(platform);
    if (user == null || _syncing.contains(platform)) return;
    final authEpoch = _authEpoch(platform);
    final epoch = (_libraryEpoch[platform] ?? 0) + 1;
    _libraryEpoch[platform] = epoch;
    bool isCurrent() =>
        mounted &&
        _libraryEpoch[platform] == epoch &&
        _authEpoch(platform) == authEpoch &&
        ref.read(authProvider).userFor(platform)?.id == user.id;
    setState(() => _syncing.add(platform));
    void update(VideoLibrary value) {
      if (!isCurrent()) return;
      setState(() => _libraries[platform] = value);
      ref
          .read(playerProvider.notifier)
          .updateLikedSongs(
            _libraries.values.expand((lib) => lib.songs).toList(),
          );
    }

    try {
      final library = await _catalog.syncLikes(
        platform,
        userId: user.id,
        onProgress: update,
      );
      update(library);
      if (isCurrent() &&
          library.error?.kind == VideoFailureKind.sessionExpired) {
        await ref.read(authProvider.notifier).handleSessionExpired(platform);
      }
    } finally {
      if (isCurrent()) setState(() => _syncing.remove(platform));
    }
  }

  Future<void> _account(PlatformType platform) async {
    final user = ref.read(authProvider).userFor(platform);
    if (user == null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => LoginPage(platform: platform)),
      );
      if (mounted && ref.read(authProvider).isLoggedIn(platform)) {
        await _sync(platform);
      }
      return;
    }
    if (widget.workspace && widget.alignToDesign) {
      final action = await showContextualDialog<String>(
        context,
        builder: (dialogContext) => SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(user.nickname),
                  subtitle: Text(videoPlatformLabel(platform)),
                  trailing: IconButton(
                    tooltip: IkStrings.close,
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.sync),
                  title: const Text(VideoStrings.resyncLikes),
                  onTap: () => Navigator.of(dialogContext).pop('sync'),
                ),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text(VideoStrings.logout),
                  onTap: () => Navigator.of(dialogContext).pop('logout'),
                ),
              ],
            ),
          ),
        ),
      );
      if (!mounted || action == null) return;
      if (action == 'sync') {
        await _sync(platform);
      } else {
        _libraryEpoch[platform] = (_libraryEpoch[platform] ?? 0) + 1;
        _syncing.remove(platform);
        await ref.read(authProvider.notifier).logout(platform);
        if (mounted) {
          setState(() => _libraries.remove(platform));
          _pushLikes();
        }
      }
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(user.nickname),
              subtitle: Text(videoPlatformLabel(platform)),
            ),
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text(VideoStrings.resyncLikes),
              onTap: () {
                Navigator.pop(sheet);
                unawaited(_sync(platform));
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text(VideoStrings.logout),
              onTap: () async {
                Navigator.pop(sheet);
                _libraryEpoch[platform] = (_libraryEpoch[platform] ?? 0) + 1;
                _syncing.remove(platform);
                await ref.read(authProvider.notifier).logout(platform);
                if (mounted) {
                  setState(() => _libraries.remove(platform));
                  _pushLikes();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleLike(Song song) async {
    if (song.platform == PlatformType.local) {
      _notice(VideoStrings.localLikeAtSource);
      return;
    }
    if (!ref.read(authProvider).isLoggedIn(song.platform)) {
      await _account(song.platform);
      return;
    }
    final key = videoSongKey(song);
    if (_syncing.contains(song.platform)) {
      _notice(VideoStrings.syncingPleaseWait);
      return;
    }
    final userId = ref.read(authProvider).userFor(song.platform)?.id;
    final authEpoch = _authEpoch(song.platform);
    final epoch = _libraryEpoch[song.platform];
    bool isCurrent() =>
        mounted &&
        ref.read(authProvider).userFor(song.platform)?.id == userId &&
        _authEpoch(song.platform) == authEpoch &&
        _libraryEpoch[song.platform] == epoch;
    if (!_pendingLikes.add(key)) return;
    final existing = _libraries[song.platform] ?? const VideoLibrary();
    final liked = existing.songs.any((s) => videoSongKey(s) == key);
    try {
      await _catalog.setLiked(song, !liked);
      if (!isCurrent()) return;
      final latest = _libraries[song.platform] ?? const VideoLibrary();
      final songs = [...latest.songs]
        ..removeWhere((s) => videoSongKey(s) == key);
      if (!liked) songs.insert(0, song);
      setState(
        () => _libraries[song.platform] = VideoLibrary(
          songs: songs,
          total: latest.total == null ? null : latest.total! + (liked ? -1 : 1),
          complete: latest.complete,
          error: latest.error,
        ),
      );
      ref
          .read(playerProvider.notifier)
          .updateLikedSongs(
            _libraries.values.expand((lib) => lib.songs).toList(),
          );
      _notice(liked ? VideoStrings.unliked : VideoStrings.liked);
    } catch (error) {
      if (isCurrent()) _notice(VideoFailure.from(error).message);
    } finally {
      _pendingLikes.remove(key);
    }
  }

  int? _authEpoch(PlatformType platform) {
    final notifier = ref.read(authProvider.notifier);
    return notifier is VideoAuthNotifier
        ? notifier.sessionEpoch(platform)
        : null;
  }

  void _pushLikes() => ref
      .read(playerProvider.notifier)
      .updateLikedSongs(_libraries.values.expand((lib) => lib.songs).toList());

  Future<void> _kugouPlaylists() async {
    const platform = PlatformType.kugou;
    final user = ref.read(authProvider).userFor(platform);
    if (user == null) {
      await _account(platform);
      return;
    }
    final epoch = _authEpoch(platform);
    final catalog = _catalog;
    if (catalog is! ExpandedVideoCatalog) return;
    bool current() =>
        mounted &&
        _authEpoch(platform) == epoch &&
        ref.read(authProvider).userFor(platform)?.id == user.id;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => VideoKugouPlaylistsPage(
          isSessionCurrent: current,
          loadPlaylists: () => catalog.kugou.playlists(userId: user.id),
          loadSongs: (playlist) =>
              catalog.kugou.playlistSongs(playlist, userId: user.id),
          onPlay: (song, songs) => unawaited(_play(song, songs)),
          onDownload: (songs) => unawaited(_download(songs)),
        ),
      ),
    );
  }

  void _retrySearch() => unawaited(
    _runSearch(_committedQuery, more: _page > 0 && _result.hasMore),
  );

  Future<void> _play(Song song, List<Song> songs) async {
    _openPlayer();
    await ref
        .read(playerProvider.notifier)
        .playPlaylist(
          songs,
          startIndex: songs.indexOf(song).clamp(0, songs.length - 1),
        );
  }

  void _openPlayer() {
    if (widget.redesign) {
      context.push('/player');
      return;
    }
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => _playerPage()));
  }

  Widget _playerPage() => Consumer(
    builder: (context, ref, _) {
      final player = ref.watch(playerProvider);
      final song = player.currentSong;
      if (song == null) {
        return Scaffold(
          appBar: AppBar(),
          body: const Center(child: Text(VideoStrings.chooseSong)),
        );
      }
      final lyrics = ref.watch(lyricsProvider);
      final info = ref.watch(videoStreamInfoProvider)[videoSongKey(song)];
      final notifier = ref.read(playerProvider.notifier);
      final source = ref.watch(sourcePlaybackViewProvider);
      final multiSource =
          source.message.isNotEmpty ||
          (notifier is MultiSourceVideoPlayerNotifier &&
              notifier.router.guarded);
      final currentSourceQuality = <String>[
        if (source.format?.isNotEmpty == true) source.format!.toUpperCase(),
        if (source.bitrate != null && source.bitrate! > 0)
          '${(source.bitrate! / 1000).round()} kbps',
      ];
      if (widget.windowsAppearance != null || widget.redesign) {
        final document = lyrics.asData?.value;
        final albumId = [
          song.albumId,
          song.album?.id,
        ].whereType<String>().where((id) => id.trim().isNotEmpty).firstOrNull;
        final artistId = [
          song.artistId,
          ...song.artists.map((artist) => artist.id),
        ].whereType<String>().where((id) => id.trim().isNotEmpty).firstOrNull;
        return WindowsPlayerPage(
          alignToDesign: widget.alignToDesign,
          lyricsAutoResumeDelay: _refinePageInteractions
              ? const Duration(seconds: 3)
              : null,
          onAlbum:
              widget.alignToDesign &&
                  song.platform != PlatformType.local &&
                  albumId != null
              ? () => context.push(
                  Uri(
                    pathSegments: ['', 'album', song.platform.name, albumId],
                    queryParameters: {'name': song.album?.name ?? ''},
                  ).toString(),
                )
              : null,
          onArtist:
              widget.alignToDesign &&
                  song.platform != PlatformType.local &&
                  artistId != null
              ? () => context.push(
                  Uri(
                    pathSegments: ['', 'artist', song.platform.name, artistId],
                  ).toString(),
                )
              : null,
          playbackBar: widget.workspace
              ? _workspacePlaybackBar(
                  alignToDesign: widget.alignToDesign,
                  onOpen: null,
                  onAudio: () => context.push('/settings/audio'),
                )
              : null,
          onDesktopLyrics:
              widget.workspace &&
                  ref.watch(ikLyricsCapabilityProvider).supported &&
                  !ref.watch(ikLyricsActionProvider)
              ? () => ref
                    .read(ikLyricsActionProvider.notifier)
                    .setEnabled(!ref.read(floatingLyricsProvider).enabled)
              : null,
          desktopLyricsEnabled:
              widget.workspace && ref.watch(floatingLyricsProvider).enabled,
          song: song,
          position: player.position,
          duration: player.duration,
          isPlaying: player.isPlaying,
          isLoading: player.isTransitioning,
          error: player.error,
          sourceStatus: source.message.isEmpty
              ? null
              : widget.alignToDesign
              ? _inlineSourceStatus(context, source, notifier)
              : _sourceStatus(context, source, notifier),
          qualityLabel: song.platform == PlatformType.local
              ? VideoStrings.localAudio
              : widget.redesign && multiSource
              ? currentSourceQuality.isEmpty
                    ? VideoStrings.qualityUnknown
                    : currentSourceQuality.join(' · ')
              : source.message.isNotEmpty
              ? SourceStrings.qualityAbove
              : player.error != null
              ? VideoStrings.requestedQuality(
                  WindowsMusicPreferences.qualityName(
                    _effectiveQuality(song.platform),
                  ),
                )
              : videoStreamLabel(info),
          isPreview:
              (widget.redesign ? !multiSource : source.message.isEmpty) &&
              info?.isPreview == true,
          sourceDetails: widget.redesign
              ? WindowsSourceDetails(
                  sourceName: multiSource
                      ? source.sourceName
                      : info?.customSourceName ??
                            videoPlatformLabel(song.platform),
                  format: multiSource ? source.format : info?.actualFormat,
                  bitrate: multiSource ? source.bitrate : info?.actualBitrate,
                  note: source.message.isNotEmpty
                      ? source.message
                      : !multiSource && info?.isPreview == true
                      ? VideoStrings.previewSuffix
                      : null,
                )
              : null,
          lyrics: document?.lines ?? const [],
          timedLyrics: document?.format.name != 'unknown',
          lyricsLoading: lyrics.isLoading,
          lyricsError: lyrics.hasError ? VideoStrings.lyricsRetry : null,
          onLyricsRetry: () => ref.invalidate(lyricsProvider),
          modeLabel: _modeLabel(player),
          onToggle: notifier.togglePlay,
          onPrevious: notifier.skipToPrevious,
          onNext: notifier.skipToNext,
          onSeek: notifier.seek,
          onQueue: _queue,
          onMode: _mode,
          onQuality: widget.workspace
              ? () => context.push('/settings/audio')
              : () => _quality(song.platform, false),
        );
      }
      return VideoPlayerPage(
        song: song,
        position: player.position,
        duration: player.duration,
        isPlaying: player.isPlaying,
        isLoading: player.isTransitioning,
        error: player.error,
        sourceStatus: source.message.isEmpty
            ? null
            : _sourceStatus(context, source, notifier),
        qualityLabel: song.platform == PlatformType.local
            ? VideoStrings.localAudio
            : source.message.isNotEmpty
            ? SourceStrings.qualityAbove
            : player.error != null
            ? VideoStrings.requestedQuality(
                widget.preferences
                    .quality(song.platform)
                    .displayNameFor(song.platform),
              )
            : videoStreamLabel(info),
        isPreview: source.message.isEmpty && info?.isPreview == true,
        lyrics: lyrics.asData?.value?.lines ?? const [],
        lyricsLoading: lyrics.isLoading,
        lyricsError: lyrics.hasError ? VideoStrings.lyricsRetry : null,
        modeLabel: _modeLabel(player),
        onToggle: notifier.togglePlay,
        onPrevious: notifier.skipToPrevious,
        onNext: notifier.skipToNext,
        onSeek: notifier.seek,
        onQueue: _queue,
        onMode: _mode,
        onQuality: () => _quality(song.platform, false),
      );
    },
  );

  Widget _sourceStatus(
    BuildContext context,
    SourcePlaybackView source,
    PlayerNotifier notifier,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          source.message,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            if (source.details.isNotEmpty)
              TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (dialog) => AlertDialog(
                    title: const Text(SourceStrings.attemptDetails),
                    content: SingleChildScrollView(child: Text(source.details)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialog),
                        child: const Text(SourceStrings.close),
                      ),
                    ],
                  ),
                ),
                child: const Text(SourceStrings.details),
              ),
            if (source.canContinue &&
                notifier is MultiSourceVideoPlayerNotifier)
              TextButton(
                onPressed: source.busy ? null : notifier.continueSources,
                child: const Text(SourceStrings.continueSources),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _inlineSourceStatus(
    BuildContext context,
    SourcePlaybackView source,
    PlayerNotifier notifier,
  ) => Column(
    key: const ValueKey('ik-inline-source-status'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(source.message, style: const TextStyle(fontSize: 12)),
      if (source.busy)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: LinearProgressIndicator(),
        ),
      if (source.details.isNotEmpty) ...[
        const SizedBox(height: 12),
        const Text(
          SourceStrings.attemptDetails,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        SelectableText(
          source.details,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
      if (source.canContinue && notifier is MultiSourceVideoPlayerNotifier)
        TextButton(
          onPressed: source.busy ? null : notifier.continueSources,
          child: const Text(SourceStrings.continueSources),
        ),
    ],
  );

  String _modeLabel(PlayerState player) => player.isShuffle
      ? VideoStrings.shuffle
      : switch (player.repeatMode) {
          RepeatMode.off => VideoStrings.sequential,
          RepeatMode.all => VideoStrings.repeatAll,
          RepeatMode.one => VideoStrings.repeatOne,
        };
  void _mode() {
    final player = ref.read(playerProvider);
    final notifier = ref.read(playerProvider.notifier);
    if (player.isShuffle) {
      notifier.toggleShuffle();
    } else if (player.repeatMode == RepeatMode.one) {
      notifier.cycleRepeatMode();
      notifier.toggleShuffle();
    } else {
      notifier.cycleRepeatMode();
    }
  }

  void _queue() {
    if (widget.workspace) {
      showIkQueue(context);
      return;
    }
    if (widget.redesign && MediaQuery.sizeOf(context).width >= 840) {
      context.push('/queue');
      return;
    }
    _legacyQueue();
  }

  void _legacyQueue() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => Consumer(
      builder: (context, ref, _) {
        final player = ref.watch(playerProvider);
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .65,
            child: Column(
              children: [
                ListTile(
                  title: Text(VideoStrings.queueCount(player.playlist.length)),
                  trailing: TextButton(
                    onPressed: player.playlist.isEmpty
                        ? null
                        : () => ref.read(playerProvider.notifier).clearQueue(),
                    child: const Text(VideoStrings.clear),
                  ),
                ),
                Expanded(
                  child: player.playlist.isEmpty
                      ? const Center(child: Text(VideoStrings.emptyQueue))
                      : ReorderableListView.builder(
                          itemCount: player.playlist.length,
                          onReorderItem: (from, to) => ref
                              .read(playerProvider.notifier)
                              .moveInQueue(from, to),
                          itemBuilder: (context, index) {
                            final song = player.playlist[index];
                            return ListTile(
                              key: ValueKey('$index:${videoSongKey(song)}'),
                              selected: index == player.currentIndex,
                              title: Text(
                                song.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(song.artistNames, maxLines: 1),
                              onTap: () => ref
                                  .read(playerProvider.notifier)
                                  .playAtIndex(index),
                              trailing: IconButton(
                                tooltip: VideoStrings.removeFromQueue,
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () => ref
                                    .read(playerProvider.notifier)
                                    .removeFromQueue(song.dedupeKey),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );

  Future<bool> _windowsQuality(bool download) async {
    if (widget.workspace && widget.alignToDesign) {
      return _alignedWindowsQuality(download);
    }
    final preferences = _unifiedPreferences!;
    final highest = preferences.sources?.value.highestQuality == true;
    final selected = await showModalBottomSheet<(AudioLevel?, bool)>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(
                download
                    ? WindowsMusicStrings.downloadQuality
                    : WindowsMusicStrings.playQuality,
              ),
              subtitle: const Text(WindowsMusicStrings.qualityHint),
            ),
            if (!download && preferences.sources != null)
              ListTile(
                title: const Text(WindowsMusicStrings.highest),
                subtitle: const Text(SourceStrings.highestHint),
                trailing: highest ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(sheet, (null, true)),
              ),
            for (final level in [
              AudioLevel.low,
              AudioLevel.high,
              AudioLevel.lossless,
              AudioLevel.hires,
              AudioLevel.master,
            ])
              ListTile(
                title: Text(WindowsMusicPreferences.qualityName(level)),
                trailing:
                    (download || !highest) &&
                        preferences.qualityLabel(download: download) ==
                            WindowsMusicPreferences.qualityName(level)
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(sheet, (level, false)),
              ),
          ],
        ),
      ),
    );
    if (selected == null) return false;
    try {
      await preferences.setQuality(
        selected.$1,
        download: download,
        highest: selected.$2,
      );
    } on DesktopConfigurationException catch (error) {
      _notice(error.toString());
      return false;
    }
    if (!mounted) return true;
    setState(() {});
    final song = ref.read(playerProvider).currentSong;
    if (!download && song != null && song.platform != PlatformType.local) {
      await ref
          .read(playerProvider.notifier)
          .switchQuality(_effectiveQuality(song.platform));
    }
    return true;
  }

  Future<bool> _alignedWindowsQuality(bool download) async {
    final preferences = _unifiedPreferences!;
    final highest = preferences.sources?.value.highestQuality == true;
    final selected = await showContextualDialog<(AudioLevel?, bool)>(
      context,
      builder: (dialogContext) => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  download
                      ? WindowsMusicStrings.downloadQuality
                      : WindowsMusicStrings.playQuality,
                ),
                subtitle: const Text(WindowsMusicStrings.qualityHint),
                trailing: IconButton(
                  tooltip: IkStrings.close,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
              if (!download && preferences.sources != null)
                ListTile(
                  title: const Text(WindowsMusicStrings.highest),
                  subtitle: const Text(SourceStrings.highestHint),
                  trailing: highest ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.of(dialogContext).pop((null, true)),
                ),
              for (final level in [
                AudioLevel.low,
                AudioLevel.high,
                AudioLevel.lossless,
                AudioLevel.hires,
                AudioLevel.master,
              ])
                ListTile(
                  title: Text(WindowsMusicPreferences.qualityName(level)),
                  trailing:
                      (download || !highest) &&
                          preferences.qualityLabel(download: download) ==
                              WindowsMusicPreferences.qualityName(level)
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.of(dialogContext).pop((level, false)),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected == null) return false;
    try {
      await preferences.setQuality(
        selected.$1,
        download: download,
        highest: selected.$2,
      );
    } on DesktopConfigurationException catch (error) {
      _notice(error.toString());
      return false;
    }
    if (!mounted) return true;
    setState(() {});
    final song = ref.read(playerProvider).currentSong;
    if (!download && song != null && song.platform != PlatformType.local) {
      await ref
          .read(playerProvider.notifier)
          .switchQuality(_effectiveQuality(song.platform));
    }
    return true;
  }

  Widget _settingsPage() {
    final auth = ref.watch(authProvider);
    final downloads = ref.watch(downloadProvider);
    final cache = ref.watch(offlineCacheSettingsProvider);
    return _myPage(
      VideoMyPage(
        platforms: _platforms,
        localSongCount: _localReady
            ? ref.watch(localMusicProvider).songs.length
            : null,
        accounts: {
          for (final platform in _platforms)
            if (auth.userFor(platform) case final user?)
              platform: VideoAccountSummary(
                nickname: user.nickname,
                avatarUrl: user.avatarUrl,
                loaded: _libraries[platform]?.loaded ?? 0,
                total: _libraries[platform]?.total,
                complete: _libraries[platform]?.complete ?? false,
              ),
        },
        cacheLabel:
            '${_mb(downloads.estimatedOfflineCacheBytes)} / ${cache.sizeLimitMb} MB',
        downloadLabel: VideoStrings.taskCount(downloads.tasks.length),
        themeLabel: switch (widget.preferences.theme) {
          'dark' => VideoStrings.darkTheme,
          'system' => VideoStrings.systemTheme,
          _ => VideoStrings.lightTheme,
        },
        qualityLabels: {
          for (final platform in _platforms) ...{
            '${platform.name}:play':
                widget.sourceSettings?.value.highestQuality == true
                ? SourceStrings.highest
                : widget.preferences.quality(platform).displayNameFor(platform),
            '${platform.name}:download': widget.preferences
                .quality(platform, download: true)
                .displayNameFor(platform),
          },
        },
        customSourceLabel: _customSourceLabel,
        onAccount: _account,
        onQuality: _quality,
        onCache: _cache,
        onDownloads: _downloads,
        onDirectory: widget.windowsAppearance == null
            ? _directory
            : _windowsDirectory,
        onTheme: _theme,
        onLocal: _local,
        onCustomSource: _customSource,
      ),
    );
  }

  Widget _myPage(VideoMyPage settings) {
    final appearance = widget.windowsAppearance;
    if (appearance == null && !widget.redesign) return settings;
    return WindowsMyPage(
      settings: settings,
      showBrandSubtitle: !widget.redesign,
      showDesktopAppearance: appearance != null || !widget.redesign,
      extraEntries: widget.redesign
          ? [
              for (final entry in [
                (IkStrings.stats, '/listening-stats', Icons.insights),
                (IkStrings.smart, '/smart-playlists', Icons.auto_awesome),
                (IkStrings.backup, '/backup', Icons.backup_outlined),
                (IkStrings.audio, '/settings/audio', Icons.equalizer),
                (
                  IkStrings.floating,
                  '/settings/floating-lyrics',
                  Icons.picture_in_picture_alt_outlined,
                ),
              ])
                ListTile(
                  leading: Icon(entry.$3),
                  title: Text(entry.$1),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(entry.$2),
                ),
            ]
          : const [],
      showWindowSettings: appearance != null,
      playQuality:
          _unifiedPreferences?.qualityLabel() ??
          _effectiveQuality(PlatformType.qq).displayNameFor(PlatformType.qq),
      downloadQuality:
          _unifiedPreferences?.qualityLabel(download: true) ??
          _effectiveQuality(
            PlatformType.qq,
            download: true,
          ).displayNameFor(PlatformType.qq),
      onQuality: (download) => _unifiedPreferences == null
          ? _quality(PlatformType.qq, download)
          : _windowsQuality(download),
      backgroundLabel: appearance?.backgroundFile == null
          ? WindowsMusicStrings.defaultBackground
          : WindowsMusicStrings.savedBackground,
      fontLabel:
          (widget.redesign
              ? appearance?.currentFontLabel
              : appearance?.fontLabel) ??
          WindowsMusicStrings.defaultFont,
      closeAction:
          appearance?.preferences.closeAction ?? WindowsCloseAction.minimize,
      nativeAvailable: appearance?.nativeAvailable ?? false,
      errors: [
        for (final error in [
          appearance?.preferences.loadError,
          appearance?.backgroundError,
          appearance?.fontError,
          appearance?.nativeError,
        ].whereType<DesktopFailure>().toSet())
          WindowsMusicStrings.failure(error),
      ],
      onBackground: appearance == null
          ? null
          : () => showWindowsBackgroundPicker(context, appearance),
      onFont: appearance == null
          ? null
          : () => showWindowsFontPicker(
              context,
              appearance,
              preserveTheme: widget.redesign,
            ),
      onClose: appearance == null
          ? null
          : () => showWindowsClosePicker(context, appearance),
      onRetryNative: appearance?.initialize,
      onExit: () async {
        try {
          await appearance?.window.exitApplication();
        } on DesktopConfigurationException catch (error) {
          _notice(error.toString());
        }
      },
    );
  }

  Widget _workspaceSettings([String? section]) => IkSettingsWorkspace(
    alignToDesign: widget.alignToDesign,
    preferences: widget.preferences,
    unified: _unifiedPreferences,
    appearance: widget.windowsAppearance,
    initialSection: section ?? _settingsSection,
    sectionRequest: section == null ? _settingsSectionRequest : 0,
    onThemeChanged: widget.onThemeChanged,
    onAccount: _account,
    onSync: _sync,
    onSources: _customSource,
    onDirectory: widget.windowsAppearance == null
        ? _directory
        : _windowsDirectory,
    onDownloads: _downloads,
    onCache: () => context.push('/offline-cache'),
  );

  Future<void> _quality(PlatformType platform, bool download) async {
    if (platform == PlatformType.local) return;
    if (_unifiedPreferences != null) {
      await _windowsQuality(download);
      return;
    }
    if (widget.workspace && widget.alignToDesign) {
      await _alignedPlatformQuality(platform, download);
      return;
    }
    var highest = false;
    final selected = await showModalBottomSheet<AudioLevel>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(
                VideoStrings.qualityPickerTitle(
                  videoPlatformLabel(platform),
                  download,
                ),
              ),
              subtitle: const Text(VideoStrings.qualityPermissions),
            ),
            if (!download && widget.sourceSettings != null)
              ListTile(
                title: const Text(SourceStrings.highest),
                subtitle: const Text(SourceStrings.highestHint),
                trailing: widget.sourceSettings!.value.highestQuality
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  highest = true;
                  Navigator.pop(context);
                },
              ),
            for (final level in [
              AudioLevel.low,
              AudioLevel.high,
              AudioLevel.lossless,
              AudioLevel.hires,
              AudioLevel.master,
            ])
              ListTile(
                title: Text(level.displayNameFor(platform)),
                trailing:
                    (download ||
                            widget.sourceSettings?.value.highestQuality !=
                                true) &&
                        widget.preferences.quality(
                              platform,
                              download: download,
                            ) ==
                            level
                    ? const Icon(Icons.check, color: VideoTheme.primary)
                    : null,
                onTap: () => Navigator.pop(context, level),
              ),
          ],
        ),
      ),
    );
    if (selected == null && !highest) return;
    final settings = widget.sourceSettings;
    if (!download && settings != null) {
      await settings.save(settings.value.copyWith(highestQuality: highest));
    }
    if (selected != null) {
      await widget.preferences.setQuality(
        platform,
        selected,
        download: download,
      );
    }
    if (!mounted) return;
    setState(() {});
    if (!download &&
        ref.read(playerProvider).currentSong?.platform == platform) {
      await ref
          .read(playerProvider.notifier)
          .switchQuality(selected ?? widget.preferences.quality(platform));
    }
  }

  Future<void> _alignedPlatformQuality(
    PlatformType platform,
    bool download,
  ) async {
    final selected = await showContextualDialog<(AudioLevel?, bool)>(
      context,
      builder: (dialogContext) => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  VideoStrings.qualityPickerTitle(
                    videoPlatformLabel(platform),
                    download,
                  ),
                ),
                subtitle: const Text(VideoStrings.qualityPermissions),
                trailing: IconButton(
                  tooltip: IkStrings.close,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
              if (!download && widget.sourceSettings != null)
                ListTile(
                  title: const Text(SourceStrings.highest),
                  subtitle: const Text(SourceStrings.highestHint),
                  trailing: widget.sourceSettings!.value.highestQuality
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.of(dialogContext).pop((null, true)),
                ),
              for (final level in [
                AudioLevel.low,
                AudioLevel.high,
                AudioLevel.lossless,
                AudioLevel.hires,
                AudioLevel.master,
              ])
                ListTile(
                  title: Text(level.displayNameFor(platform)),
                  trailing:
                      (download ||
                              widget.sourceSettings?.value.highestQuality !=
                                  true) &&
                          widget.preferences.quality(
                                platform,
                                download: download,
                              ) ==
                              level
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.of(dialogContext).pop((level, false)),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected == null) return;
    final settings = widget.sourceSettings;
    if (!download && settings != null) {
      await settings.save(settings.value.copyWith(highestQuality: selected.$2));
    }
    if (selected.$1 != null) {
      await widget.preferences.setQuality(
        platform,
        selected.$1!,
        download: download,
      );
    }
    if (!mounted) return;
    setState(() {});
    if (!download &&
        ref.read(playerProvider).currentSong?.platform == platform) {
      await ref
          .read(playerProvider.notifier)
          .switchQuality(selected.$1 ?? widget.preferences.quality(platform));
    }
  }

  Future<void> _download(List<Song> songs) async {
    if (songs.isEmpty) return;
    final notifier = ref.read(downloadProvider.notifier);
    if (widget.alignToDesign) {
      final report = await submitIkDownloads(
        songs: songs,
        qualityFor: (song) => _effectiveQuality(song.platform, download: true),
        readTasks: () => ref.read(downloadProvider).tasks,
        start: notifier.startDownload,
        ready: notifier.ready,
      );
      if (!mounted) return;
      _notice(
        IkAlignmentStrings.submission(
          added: report.added,
          existing: report.existing,
          retried: report.retried,
          failed: report.failed,
        ),
      );
      return;
    }
    for (final song in songs) {
      await notifier.startDownload(
        song,
        _effectiveQuality(song.platform, download: true),
      );
    }
    _notice(VideoStrings.downloadsSubmitted(songs.length));
  }

  void _songMore(Song song) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(title: Text(song.name), subtitle: Text(song.artistNames)),
          ListTile(
            leading: const Icon(Icons.favorite_outline),
            title: const Text(VideoStrings.toggleLike),
            onTap: () {
              Navigator.pop(sheet);
              unawaited(_toggleLike(song));
            },
          ),
          if (song.platform != PlatformType.local)
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text(VideoStrings.downloadSong),
              onTap: () {
                Navigator.pop(sheet);
                unawaited(_download([song]));
              },
            ),
        ],
      ),
    ),
  );

  Future<void> _ikSongMore(Song song, {BuildContext? menuContext}) async {
    final local = ref.read(likesProvider).songs.contains(song);
    final action = widget.workspace
        ? await _workspaceSongMenu(song, local, anchorContext: menuContext)
        : await showModalBottomSheet<String>(
            context: context,
            showDragHandle: true,
            builder: (sheet) => SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      title: Text(song.name),
                      subtitle: Text(song.artistNames),
                    ),
                    ListTile(
                      leading: const Icon(Icons.favorite_outline),
                      title: Text(
                        local ? IkStrings.removeLocal : IkStrings.saveLocal,
                      ),
                      onTap: () => Navigator.pop(sheet, 'local'),
                    ),
                    if (song.platform != PlatformType.local)
                      ListTile(
                        leading: const Icon(Icons.cloud_outlined),
                        title: const Text(VideoStrings.toggleLike),
                        onTap: () => Navigator.pop(sheet, 'like'),
                      ),
                    ListTile(
                      leading: const Icon(Icons.album_outlined),
                      title: const Text(IkStrings.album),
                      enabled:
                          (song.albumId ?? song.album?.id ?? '').isNotEmpty,
                      onTap: () => Navigator.pop(sheet, 'album'),
                    ),
                    for (final artist in song.artists.where(
                      (value) => value.id.isNotEmpty,
                    ))
                      ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: Text('${IkStrings.artist} · ${artist.name}'),
                        onTap: () =>
                            Navigator.pop(sheet, 'artist:${artist.id}'),
                      ),
                    if (song.platform != PlatformType.local)
                      ListTile(
                        leading: const Icon(Icons.download_outlined),
                        title: const Text(VideoStrings.downloadSong),
                        onTap: () => Navigator.pop(sheet, 'download'),
                      ),
                  ],
                ),
              ),
            ),
          );
    if (!mounted || action == null) return;
    if (action == 'local') {
      await ref.read(likesProvider.notifier).toggleLike(song);
    } else if (action == 'like') {
      await _toggleLike(song);
    } else if (action == 'download') {
      await _download([song]);
    } else if (action == 'album') {
      await context.push<void>(
        Uri(
          pathSegments: [
            '',
            'album',
            song.platform.name,
            song.albumId ?? song.album!.id,
          ],
          queryParameters: {'name': song.album?.name ?? ''},
        ).toString(),
      );
    } else if (action.startsWith('artist:')) {
      await context.push<void>(
        Uri(
          pathSegments: ['', 'artist', song.platform.name, action.substring(7)],
        ).toString(),
      );
    }
  }

  Future<String?> _workspaceSongMenu(
    Song song,
    bool local, {
    BuildContext? anchorContext,
  }) {
    final size = MediaQuery.sizeOf(context);
    final point = _workspacePointer ?? Offset(size.width / 2, size.height / 2);
    PopupMenuItem<String> item(
      String value,
      String label,
      IconData icon, {
      bool enabled = true,
    }) => PopupMenuItem(
      value: value,
      enabled: enabled,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: Center(child: Icon(icon, size: 18)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
    return showMenu<String>(
      context: context,
      useRootNavigator: anchorContext != null,
      position: anchorContext == null
          ? RelativeRect.fromLTRB(
              point.dx,
              point.dy,
              size.width - point.dx,
              size.height - point.dy,
            )
          : null,
      positionBuilder: anchorContext == null
          ? null
          : (_, _) {
              final overlay =
                  Navigator.of(
                        context,
                        rootNavigator: true,
                      ).overlay!.context.findRenderObject()!
                      as RenderBox;
              final box = anchorContext.mounted
                  ? anchorContext.findRenderObject()
                  : null;
              if (box is! RenderBox || !box.hasSize || !box.attached) {
                return RelativeRect.fromRect(
                  Rect.fromCenter(
                    center: overlay.size.center(Offset.zero),
                    width: 0,
                    height: 0,
                  ),
                  Offset.zero & overlay.size,
                );
              }
              final bottom = box.localToGlobal(
                box.size.bottomLeft(Offset.zero),
                ancestor: overlay,
              );
              return RelativeRect.fromRect(
                Rect.fromLTWH(bottom.dx, bottom.dy, box.size.width, 0),
                Offset.zero & overlay.size,
              );
            },
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 300),
      items: [
        PopupMenuItem<String>(
          enabled: false,
          child: Text(song.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const PopupMenuDivider(),
        item(
          'local',
          local ? IkStrings.removeLocal : IkStrings.saveLocal,
          Icons.favorite_border,
        ),
        if (song.platform != PlatformType.local)
          item('like', VideoStrings.toggleLike, Icons.cloud_outlined),
        item(
          'album',
          IkStrings.album,
          Icons.album_outlined,
          enabled: (song.albumId ?? song.album?.id ?? '').isNotEmpty,
        ),
        for (final artist in song.artists.where((value) => value.id.isNotEmpty))
          item(
            'artist:${artist.id}',
            '${IkStrings.artist} · ${artist.name}',
            Icons.person_outline,
          ),
        if (song.platform != PlatformType.local)
          item('download', VideoStrings.downloadSong, Icons.download_outlined),
      ],
    );
  }

  void _downloads() {
    if (widget.alignToDesign && widget.workspace) {
      context.push('/downloads');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Consumer(
          builder: (context, ref, _) {
            final state = ref.watch(downloadProvider);
            final notifier = ref.read(downloadProvider.notifier);
            return Scaffold(
              appBar: AppBar(
                title: const Text(VideoStrings.downloadManagement),
              ),
              body: state.tasks.isEmpty
                  ? const Center(child: Text(VideoStrings.noDownloads))
                  : ListView(
                      children: [
                        if (state.queueBlockedReason != null)
                          ListTile(title: Text(state.queueBlockedReason!)),
                        for (final task in state.tasks.reversed)
                          ListTile(
                            title: Text(task.song.name),
                            onTap: task.status == DownloadStatus.completed
                                ? () => _playDownload(task)
                                : null,
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  task.error ??
                                      switch (task.status) {
                                        DownloadStatus.waiting =>
                                          VideoStrings.waitingDownload,
                                        DownloadStatus.downloading =>
                                          VideoStrings.downloadProgress(
                                            (task.progress * 100)
                                                .toStringAsFixed(0),
                                          ),
                                        DownloadStatus.paused =>
                                          VideoStrings.paused,
                                        DownloadStatus.completed =>
                                          VideoStrings.downloadedPath(
                                            task.filePath,
                                          ),
                                        DownloadStatus.failed =>
                                          VideoStrings.downloadFailed,
                                      },
                                  style: TextStyle(
                                    fontSize: VideoTheme.readableSize(
                                      context,
                                      11,
                                    ),
                                  ),
                                ),
                                if (widget.windowsAppearance != null)
                                  Text(
                                    WindowsMusicPreferences.qualityName(
                                      task.quality,
                                    ),
                                    style: TextStyle(
                                      fontSize: VideoTheme.readableSize(
                                        context,
                                        11,
                                      ),
                                    ),
                                  ),
                                if (task.status == DownloadStatus.downloading)
                                  LinearProgressIndicator(value: task.progress),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (task.status == DownloadStatus.downloading)
                                  IconButton(
                                    tooltip: VideoStrings.pauseDownload,
                                    icon: const Icon(Icons.pause),
                                    onPressed: () =>
                                        notifier.pauseDownload(task.id),
                                  ),
                                if (task.status == DownloadStatus.failed ||
                                    task.status == DownloadStatus.paused)
                                  IconButton(
                                    tooltip:
                                        task.status == DownloadStatus.paused
                                        ? VideoStrings.resumeDownload
                                        : _downloadActionLabel(task),
                                    icon: const Icon(Icons.refresh),
                                    onPressed:
                                        task.status == DownloadStatus.paused
                                        ? () => notifier.resumeDownload(task.id)
                                        : _canActOnDownload(task)
                                        ? () => _resolveDownload(task)
                                        : null,
                                  ),
                                if (task.status != DownloadStatus.completed)
                                  IconButton(
                                    tooltip: VideoStrings.cancelDownload,
                                    icon: const Icon(Icons.close),
                                    onPressed: () =>
                                        notifier.cancelDownload(task.id),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _playDownload(DownloadTask task) async {
    final path = await ref
        .read(downloadProvider.notifier)
        .localFilePathFor(task.song, quality: task.quality);
    if (!mounted) return;
    if (path == null) {
      _notice(VideoStrings.downloadMissing);
      return;
    }
    final song = task.song;
    final local = Song(
      id: path,
      platform: PlatformType.local,
      name: song.name,
      artists: song.artists,
      album: song.album,
      duration: song.duration,
      coverUrl: song.coverUrl,
    );
    await _play(local, [local]);
  }

  Widget _alignedDownloadsPage() =>
      Scaffold(appBar: AppBar(), body: _alignedDownloadsContent());

  Widget _alignedDownloadsContent() => Consumer(
    builder: (context, ref, _) {
      final state = ref.watch(downloadProvider);
      final notifier = ref.read(downloadProvider.notifier);
      return IkDownloadsWorkspace(
        tasks: state.tasks,
        queueBlockedReason: state.queueBlockedReason,
        onDirectory: widget.windowsAppearance == null
            ? _directory
            : _windowsDirectory,
        onPause: (task) async {
          notifier.pauseDownload(task.id);
        },
        onResume: (task) => notifier.resumeDownload(task.id),
        onResolve: _resolveDownload,
        onCancel: (task) async {
          notifier.cancelDownload(task.id);
        },
        onPlay: _playDownload,
        onOpenFolder: (task) => openIkDownloadFolder(
          notifier.manager.directoryService,
          task.filePath,
        ),
        canResolve: _canActOnDownload,
        actionLabel: _downloadActionLabel,
      );
    },
  );

  bool _canActOnDownload(DownloadTask task) => ![
    DownloadFailureKind.notFound,
    DownloadFailureKind.unsupported,
    DownloadFailureKind.cancelled,
    DownloadFailureKind.unknown,
  ].contains(task.failureKind);
  String _downloadActionLabel(DownloadTask task) => switch (task.failureKind) {
    DownloadFailureKind.auth => VideoStrings.loginAgain,
    DownloadFailureKind.vip => VideoStrings.chooseDownloadQuality,
    DownloadFailureKind.storagePermission => VideoStrings.chooseStorageAgain,
    DownloadFailureKind.disk => VideoStrings.freeStorageRetry,
    DownloadFailureKind.notFound ||
    DownloadFailureKind.unsupported => VideoStrings.resourceCannotDownload,
    DownloadFailureKind.unknown ||
    DownloadFailureKind.cancelled => VideoStrings.taskCannotRetry,
    _ => VideoStrings.retryDownload,
  };
  Future<void> _resolveDownload(DownloadTask task) async {
    if (widget.windowsAppearance != null) {
      switch (task.failureKind) {
        case DownloadFailureKind.auth:
          await _account(task.song.platform);
        case DownloadFailureKind.vip:
          if (!await _windowsQuality(true)) return;
        case DownloadFailureKind.storagePermission:
          if (!await _windowsDirectory()) return;
        case DownloadFailureKind.disk:
          _notice(VideoStrings.freeDeviceSpace);
        default:
          break;
      }
      if (!mounted) return;
      await retryWindowsDownload(
        ref.read(downloadProvider.notifier),
        task,
        _effectiveQuality(task.song.platform, download: true),
        readState: () => ref.read(downloadProvider),
      );
      return;
    }
    switch (task.failureKind) {
      case DownloadFailureKind.auth:
        await _account(task.song.platform);
      case DownloadFailureKind.vip:
        await _quality(task.song.platform, true);
      case DownloadFailureKind.storagePermission:
        await _directory();
      case DownloadFailureKind.disk:
        _notice(VideoStrings.freeDeviceSpace);
        await ref.read(downloadProvider.notifier).resumeDownload(task.id);
      default:
        await ref.read(downloadProvider.notifier).resumeDownload(task.id);
    }
  }

  Future<void> _directory() async {
    final result = await DownloadDirectoryService().applySafTreeDirectory();
    if (!result.isCancelled) _notice(result.message);
  }

  Future<bool> _windowsDirectory() async {
    try {
      final result = await chooseWindowsDownloadDirectory(
        ref.read(downloadProvider.notifier),
      );
      if (!mounted || result == null) return false;
      _notice(result.message);
      return result.isOk;
    } catch (_) {
      _notice(WindowsMusicStrings.failure(DesktopFailure.readFailed));
      return false;
    }
  }

  void _cache() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => Consumer(
      builder: (context, ref, _) {
        final settings = ref.watch(offlineCacheSettingsProvider);
        final notifier = ref.read(offlineCacheSettingsProvider.notifier);
        final download = ref.watch(downloadProvider);
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text(VideoStrings.cacheManagement),
                  subtitle: Text(
                    '${_mb(download.estimatedOfflineCacheBytes)} / ${settings.sizeLimitMb} MB',
                  ),
                ),
                ListTile(
                  title: const Text(VideoStrings.cacheLimit),
                  trailing: DropdownButton<int>(
                    value: settings.sizeLimitMb,
                    items: {1024, 5120, 10240, 20480, settings.sizeLimitMb}
                        .map(
                          (size) => DropdownMenuItem(
                            value: size,
                            child: Text('$size MB'),
                          ),
                        )
                        .toList(),
                    onChanged: (size) {
                      if (size != null) {
                        unawaited(notifier.setSizeLimitMb(size));
                      }
                    },
                  ),
                ),
                SwitchListTile(
                  title: const Text(VideoStrings.wifiCacheOnly),
                  value: settings.wifiOnly,
                  onChanged: notifier.setWifiOnly,
                ),
                SwitchListTile(
                  title: const Text(VideoStrings.autoRetry),
                  value: settings.autoRetry,
                  onChanged: notifier.setAutoRetry,
                ),
                SwitchListTile(
                  title: const Text(VideoStrings.autoCleanup),
                  value: settings.autoCleanup,
                  onChanged: notifier.setAutoCleanup,
                ),
                SwitchListTile(
                  title: const Text(VideoStrings.offlineMode),
                  subtitle: const Text(VideoStrings.useCachedFiles),
                  value: settings.offlineMode,
                  onChanged: notifier.setOfflineMode,
                ),
                ListTile(
                  leading: const Icon(Icons.sync),
                  title: const Text(VideoStrings.cacheSyncedLikes),
                  onTap: () async {
                    final songs = _libraries.values
                        .expand((lib) => lib.songs)
                        .toList();
                    for (final platform in [
                      PlatformType.qq,
                      PlatformType.netease,
                      if (widget.windowsAppearance != null &&
                          widget.expandedPlatforms)
                        PlatformType.kugou,
                    ]) {
                      await ref
                          .read(downloadProvider.notifier)
                          .cacheSongs(
                            songs
                                .where((song) => song.platform == platform)
                                .toList(),
                            quality: _effectiveQuality(platform),
                          );
                    }
                    if (context.mounted) Navigator.pop(context);
                    _notice(
                      songs.isEmpty
                          ? VideoStrings.loginSyncFirst
                          : VideoStrings.cacheSubmitted,
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.cleaning_services_outlined),
                  title: const Text(VideoStrings.cleanupToLimit),
                  onTap: () async {
                    final count = await ref
                        .read(downloadProvider.notifier)
                        .cleanupOfflineCache();
                    _notice(VideoStrings.cleanedCache(count));
                  },
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
  Future<void> _theme() async {
    final value = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in {
              'light': VideoStrings.lightTheme,
              'dark': VideoStrings.darkTheme,
              'system': VideoStrings.systemTheme,
            }.entries)
              ListTile(
                title: Text(entry.value),
                trailing: widget.preferences.theme == entry.key
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(context, entry.key),
              ),
          ],
        ),
      ),
    );
    if (value != null) {
      await widget.preferences.setTheme(value);
      widget.onThemeChanged();
    }
  }

  String get _customSourceLabel {
    final collection = widget.sourceSettings?.value;
    if (collection != null && collection.entries.isNotEmpty) {
      return SourceStrings.sourceCount(
        collection.entries.length,
        collection.enabled.length,
      );
    }
    final lx = widget.preferences.lxSource;
    if (lx?.enabled == true) return VideoStrings.customSourceEnabled(lx!.name);
    final config = widget.preferences.customSource;
    if (config == null) {
      return lx == null
          ? VideoStrings.customSourceNotConfigured
          : VideoStrings.customSourceDisabled;
    }
    return config.enabled
        ? VideoStrings.customSourceEnabled(config.name)
        : VideoStrings.customSourceDisabled;
  }

  Future<VideoCustomSourceTestResult> _testCustomSource(
    VideoCustomSourceDraft draft,
  ) async {
    try {
      final config = _configFromDraft(draft, enabled: true);
      config.validate();
      final testCredentials = MemoryCustomSourceCredentialStore({
        if (draft.token.trim().isNotEmpty)
          config.credentialRef!: draft.token.trim(),
      });
      final requestPlatform = config.platforms.first;
      await HttpCustomSourceResolver(
        config: config,
        dio: widget.customSourceDio,
        credentialStore: testCredentials,
      ).resolve(
        CustomSourceRequest(
          requestId: 'connection-test',
          platform: requestPlatform,
          song: Song(
            id: 'connection-test',
            platform: requestPlatform,
            name: VideoStrings.customSourceConnectionTest,
            artists: const [],
          ),
          quality: AudioLevel.low,
          purpose: CustomSourcePurpose.play,
        ),
      );
      return const VideoCustomSourceTestResult.success();
    } on CustomSourceException catch (error) {
      return switch (error.code) {
        CustomSourceFailureCode.unauthorized =>
          const VideoCustomSourceTestResult.unauthorized(),
        CustomSourceFailureCode.timeout =>
          const VideoCustomSourceTestResult.timeout(),
        CustomSourceFailureCode.invalidResponse ||
        CustomSourceFailureCode.qualityUnavailable =>
          const VideoCustomSourceTestResult.incompatible(),
        _ => const VideoCustomSourceTestResult.unavailable(),
      };
    } on Object {
      return const VideoCustomSourceTestResult.incompatible();
    }
  }

  CustomSourceConfig _configFromDraft(
    VideoCustomSourceDraft draft, {
    bool? enabled,
  }) {
    final current = widget.preferences.customSource;
    final id = current?.id ?? 'primary';
    return CustomSourceConfig(
      id: id,
      name: draft.name,
      endpoint: Uri.parse(draft.endpoint),
      enabled: enabled ?? draft.enabled,
      platforms: draft.platforms,
      timeoutSeconds: draft.timeoutSeconds,
      allowForDownloads: draft.allowForDownloads,
      credentialRef: id,
    );
  }

  Future<void> _customSource() async {
    if (widget.sourceSettings != null && widget.sourceEngine != null) {
      await _sourceCollection();
      return;
    }
    final engine = LxSourceRuntime();
    final importerDio = createLxDio();
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => VideoLxSourcePage(
            initial: widget.preferences.lxSource,
            onImport: (link, token) => LxSourceImporter(
              dio: importerDio,
              engine: engine,
            ).importLink(link, cancelToken: token),
            onTest: (source) async {
              await engine.inspect(source.script);
            },
            onSave: (source) async {
              widget.onCustomSourceChanged?.call();
              if (source.enabled &&
                  widget.preferences.customSource?.enabled == true) {
                await widget.preferences.setCustomSource(
                  widget.preferences.customSource!.copyWith(enabled: false),
                );
              }
              await widget.preferences.setLxSource(source);
              if (mounted) {
                setState(() {});
                Navigator.pop(context);
              }
            },
            onDelete: widget.preferences.lxSource == null
                ? null
                : () async {
                    widget.onCustomSourceChanged?.call();
                    await widget.preferences.deleteLxSource();
                    if (mounted) {
                      setState(() {});
                      Navigator.pop(context);
                    }
                  },
            onHttp: () async {
              Navigator.pop(context);
              await _httpCustomSource();
            },
          ),
        ),
      );
    } finally {
      importerDio.close(force: true);
      engine.dio.close(force: true);
    }
  }

  Future<void> _sourceCollection() async {
    final settings = widget.sourceSettings!;
    final engine = widget.sourceEngine!;
    final dio = createLxDio();
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => widget.expandedPlatforms
              ? IkSourceEditingScope(
                  child: SourceManagerPage(
                    initial: settings.value,
                    warning: settings.loadError,
                    runtimeId: '${Theme.of(context).platform.name}-lx3',
                    initialChecks: SourceCheckStore(widget.preferences.box)
                        .load(),
                    onChecksChanged: SourceCheckStore(widget.preferences.box)
                        .save,
                    onImport: (link, token) => LxSourceImporterV3(
                      dio: dio,
                      engine: engine,
                    ).importLink(link, cancelToken: token),
                    onInspect: (config, token) async {
                      await engine.inspect(config.script, cancelToken: token);
                    },
                    onSave: (value) async {
                      await settings.save(value);
                      widget.onCustomSourceChanged?.call();
                      if (mounted) {
                        setState(() {});
                      }
                    },
                    onHttp: () {
                      Navigator.pop(context);
                      unawaited(_httpCustomSource());
                    },
                  ),
                )
              : SourceCollectionPage(
                  initial: settings.value,
                  warning: settings.loadError,
                  onImport: (link, token) => LxSourceImporter(
                    dio: dio,
                    engine: engine,
                  ).importLink(link, cancelToken: token),
                  onInspect: (config, token) async {
                    await engine.inspect(config.script, cancelToken: token);
                  },
                  onSave: (value) async {
                    await settings.save(value);
                    widget.onCustomSourceChanged?.call();
                    if (mounted) {
                      setState(() {});
                      Navigator.pop(context);
                    }
                  },
                  onHttp: () {
                    Navigator.pop(context);
                    unawaited(_httpCustomSource());
                  },
                ),
        ),
      );
    } finally {
      dio.close(force: true);
    }
  }

  Future<void> _httpCustomSource() async {
    final current = widget.preferences.customSource;
    final token = current == null
        ? ''
        : await widget.customSourceCredentials.readToken(
                current.credentialRef ?? current.id,
              ) ??
              '';
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => VideoCustomSourcePage(
          initialDraft: current == null
              ? const VideoCustomSourceDraft()
              : VideoCustomSourceDraft(
                  name: current.name,
                  endpoint: current.endpoint.toString(),
                  platforms: current.platforms,
                  timeoutSeconds: current.timeoutSeconds,
                  token: token,
                  allowForDownloads: current.allowForDownloads,
                  enabled: current.enabled,
                ),
          onTest: _testCustomSource,
          onSave: (draft) async {
            try {
              final config = _configFromDraft(draft);
              config.validate();
              final sources = widget.sourceSettings;
              if (config.enabled && sources != null) {
                await sources.save(
                  sources.value.copyWith(
                    autoSwitch: false,
                    highestQuality: false,
                    sourceFirst: false,
                    entries: [
                      for (final e in sources.value.entries)
                        SourceEntry(e.id, e.config.copyWith(enabled: false)),
                    ],
                  ),
                );
              }
              if (config.enabled &&
                  widget.preferences.lxSource?.enabled == true) {
                await widget.preferences.setLxSource(
                  widget.preferences.lxSource!.copyWith(enabled: false),
                );
              }
              await widget.preferences.setCustomSource(config);
              widget.onCustomSourceChanged?.call();
              if (draft.token.trim().isEmpty) {
                await widget.customSourceCredentials.deleteToken(config.id);
              } else {
                await widget.customSourceCredentials.writeToken(
                  config.id,
                  draft.token,
                );
              }
              if (mounted) {
                setState(() {});
                Navigator.pop(context);
              }
            } on CustomSourceConfigurationException catch (error) {
              _notice(error.message);
            }
          },
          onDelete: current == null
              ? null
              : () async {
                  await widget.customSourceCredentials.deleteToken(
                    current.credentialRef ?? current.id,
                  );
                  await widget.preferences.deleteCustomSource();
                  widget.onCustomSourceChanged?.call();
                  if (mounted) {
                    setState(() {});
                    Navigator.pop(context);
                  }
                },
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _local() async {
    await ref.read(localMusicProvider.notifier).pickAndScanDirectory();
    if (!mounted) return;
    final local = ref.read(localMusicProvider);
    _notice(local.error ?? VideoStrings.loadedLocalSongs(local.songs.length));
    setState(() {
      _index = widget.redesign ? 1 : 0;
      _searchPlatform = PlatformType.local;
    });
    if (_search.text.trim().isNotEmpty) unawaited(_runSearch(_search.text));
  }

  String _mb(int bytes) => '${(bytes / 1048576).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final player = ref.watch(playerProvider);
    ref.listen(authProvider, (previous, next) {
      if (widget.redesign) {
        for (final platform in _platforms) {
          if (previous?.userFor(platform)?.id == next.userFor(platform)?.id) {
            continue;
          }
          _libraryEpoch[platform] = (_libraryEpoch[platform] ?? 0) + 1;
          _syncing.remove(platform);
          _libraries.remove(platform);
          _pushLikes();
          if (next.isLoggedIn(platform)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) unawaited(_sync(platform));
            });
          }
        }
      }
      if (next.expiredPlatform != null &&
          previous?.expiryNoticeId != next.expiryNoticeId) {
        final platform = next.expiredPlatform!;
        _libraryEpoch[platform] = (_libraryEpoch[platform] ?? 0) + 1;
        setState(() => _libraries.remove(platform));
        _syncing.remove(platform);
        _pushLikes();
        _notice(VideoStrings.expiredPlatform(videoPlatformLabel(platform)));
      }
    });
    final liked = _libraries.values
        .expand((lib) => lib.songs)
        .map(videoSongKey)
        .toSet();
    VideoCatalogViewState libraryState(PlatformType platform) {
      final library = _libraries[platform] ?? const VideoLibrary();
      return VideoCatalogViewState(
        songs: library.songs,
        total: library.total,
        loading: _syncing.contains(platform),
        error: library.error?.message,
        canRetry: library.error?.canRetry ?? true,
      );
    }

    if (widget.redesign) {
      final localLikes = ref.watch(likesProvider);
      final pages = <Widget>[
        IkHomePage(
          workspace: widget.workspace,
          alignToDesign: widget.alignToDesign,
          onNavigate: (path) => context.push(path),
          onPlayer: _openPlayer,
          onPlay: _play,
          onMore: _ikSongMore,
          onMoreWithContext: widget.workspace && widget.alignToDesign
              ? (buttonContext, song) =>
                    _ikSongMore(song, menuContext: buttonContext)
              : null,
        ),
        if (widget.workspace)
          IkSearchWorkspace(
            alignToDesign: widget.alignToDesign,
            fullRecommendations: _refinePageInteractions,
            compactDiscovery: widget.alignToDesign,
            useSharedSearch: widget.alignToDesign,
            dismissSourceMenuOnBack: widget.dismissSourceMenuOnBack,
            search: _ikSearch,
            onPlay: _play,
            onLike: _toggleLike,
            onMore: _ikSongMore,
            onMoreWithContext: widget.alignToDesign
                ? (buttonContext, song) =>
                      _ikSongMore(song, menuContext: buttonContext)
                : null,
            hotTerms: widget.alignToDesign ? _hotTerms : const [],
            hotLoading: widget.alignToDesign && _hotLoading,
            hotError: widget.alignToDesign ? _hotError : null,
            onRetryHot: widget.alignToDesign
                ? () => unawaited(_loadAlignedHotTerms())
                : null,
            recommendations: widget.alignToDesign
                ? ref.watch(recommendationsProvider)
                : null,
            loggedIn: widget.alignToDesign
                ? {
                    for (final platform in _platforms)
                      if (auth.isLoggedIn(platform)) platform,
                  }
                : const {},
            onBrowseRecommendations: widget.alignToDesign
                ? () => context.push('/recommendations')
                : null,
            onRetryRecommendation: widget.alignToDesign
                ? (platform) => unawaited(
                    ref
                        .read(recommendationsProvider.notifier)
                        .retryLatestPlatform(platform),
                  )
                : null,
            onAccount: _account,
            likedKeys: liked,
            currentSong: player.currentSong,
          )
        else
          IkSearchPage(
            search: _ikSearch,
            onPlay: _play,
            onLike: _toggleLike,
            onMore: _ikSongMore,
            onAccount: _account,
            likedKeys: liked,
            currentSong: player.currentSong,
          ),
        if (widget.workspace)
          IkLibraryWorkspace(
            alignToDesign: widget.alignToDesign,
            stableCategoryTabs: _refinePageInteractions,
            simplifySources: widget.alignToDesign,
            libraries: _libraries,
            syncing: _syncing,
            loggedIn: {
              for (final platform in _platforms)
                if (auth.isLoggedIn(platform)) platform,
            },
            onSync: _sync,
            onPlay: _play,
            onMore: _ikSongMore,
            onMoreWithContext: widget.alignToDesign
                ? (buttonContext, song) =>
                      _ikSongMore(song, menuContext: buttonContext)
                : null,
            downloadsBuilder: widget.alignToDesign
                ? (_) => _alignedDownloadsContent()
                : null,
            onNavigate: (path) => context.push(path),
            onDownloads: _downloads,
            onAccounts: () => setState(() {
              _settingsSection = 'accounts';
              _index = 4;
            }),
            localLikes: localLikes.songs,
            localLoading: localLikes.isLoading,
            localError: localLikes.error,
            onRetryLocal: () =>
                unawaited(ref.read(likesProvider.notifier).loadAllLikes()),
            currentSong: player.currentSong,
          )
        else
          IkLibraryPage(
            libraries: _libraries,
            syncing: _syncing,
            loggedIn: {
              for (final platform in _platforms)
                if (auth.isLoggedIn(platform)) platform,
            },
            onAccount: _account,
            onSync: _sync,
            onPlay: _play,
            onLike: _toggleLike,
            onMore: _ikSongMore,
            onNavigate: (path) => context.push(path),
            onDownloads: _downloads,
            localLikes: localLikes.songs,
            localLoading: localLikes.isLoading,
            localError: localLikes.error,
            onRetryLocal: () =>
                unawaited(ref.read(likesProvider.notifier).loadAllLikes()),
            currentSong: player.currentSong,
          ),
        if (widget.workspace)
          IkRecentPage(
            alignToDesign: widget.alignToDesign,
            onNavigate: (path) => context.push(path),
            onMore: _ikSongMore,
            onMoreWithContext: widget.alignToDesign
                ? (buttonContext, song) =>
                      _ikSongMore(song, menuContext: buttonContext)
                : null,
          ),
        widget.workspace ? _workspaceSettings() : _settingsPage(),
      ];
      if (widget.workspace) {
        return Listener(
          onPointerDown: (event) => _workspacePointer = event.position,
          child: IkDesktopWorkspace(
            alignToDesign: widget.alignToDesign,
            mobileKeyboardLayout: widget.mobileKeyboardLayout,
            onSearch: widget.alignToDesign
                ? (query) {
                    unawaited(_ikSearch.submit(query));
                    setState(() => _index = 1);
                  }
                : null,
            index: _index,
            onSelect: (index) => setState(() => _index = index),
            onAccount: () => setState(() {
              _settingsSection = 'accounts';
              _index = 4;
            }),
            pages: pages,
            playbackBar: _workspacePlaybackBar(
              alignToDesign: widget.alignToDesign,
              onOpen: _openPlayer,
              onAudio: () => setState(() {
                _settingsSection = 'audio';
                if (widget.alignToDesign) _settingsSectionRequest++;
                _index = 4;
              }),
            ),
          ),
        );
      }
      return IkShell(
        index: _index,
        onSelect: (index) => setState(() => _index = index),
        pages: pages,
        queue: const IkQueuePanel(),
        miniPlayer: VideoMiniPlayer(
          song: player.currentSong,
          isPlaying: player.isPlaying,
          isLoading: player.isTransitioning,
          error: player.error,
          onOpen: _openPlayer,
          onToggle: ref.read(playerProvider.notifier).togglePlay,
          onQueue: _queue,
        ),
      );
    }
    return VideoShell(
      expandedPlatforms: widget.expandedPlatforms,
      platformIcons: widget.windowsAppearance != null,
      index: _index,
      onSelect: (index) => setState(() => _index = index),
      pages: [
        VideoSearchPage(
          platforms: [PlatformType.local, ..._platforms],
          controller: _search,
          onSearch: (text) => _runSearch(text),
          platform: _searchPlatform,
          onPlatformChanged: (platform) {
            setState(() => _searchPlatform = platform);
            unawaited(_runSearch(_committedQuery));
          },
          result: _result,
          submitted: _submitted,
          hotTerms: _hotTerms,
          totals: _totals,
          onRetry: _retrySearch,
          onRefresh: () => _runSearch(_committedQuery),
          onLoadMore: () => _runSearch(_committedQuery, more: true),
          onSongTap: (song) => _play(song, _result.songs),
          onSongLike: _toggleLike,
          onSongMore: _songMore,
          likedKeys: liked,
          currentSong: player.currentSong,
        ),
        for (final platform in _platforms)
          VideoLibraryPage(
            platform: platform,
            onPlaylists: platform == PlatformType.kugou
                ? _kugouPlaylists
                : null,
            result: libraryState(platform),
            loggedIn: auth.isLoggedIn(platform),
            onLogin: () => _account(platform),
            onRefresh: () => _sync(platform),
            onRetry: () => _sync(platform),
            onPlayAll: () {
              final songs = _libraries[platform]?.songs ?? [];
              if (songs.isNotEmpty) unawaited(_play(songs.first, songs));
            },
            onDownloadAll: () => _download(_libraries[platform]?.songs ?? []),
            onSongTap: (song) =>
                _play(song, _libraries[platform]?.songs ?? [song]),
            onSongLike: _toggleLike,
            onSongMore: _songMore,
            likedKeys: liked,
            currentSong: player.currentSong,
            syncComplete: _libraries[platform]?.complete ?? false,
          ),
        _settingsPage(),
      ],
      miniPlayer: VideoMiniPlayer(
        song: player.currentSong,
        isPlaying: player.isPlaying,
        isLoading: player.isTransitioning,
        error: player.error,
        onOpen: _openPlayer,
        onToggle: ref.read(playerProvider.notifier).togglePlay,
        onQueue: _queue,
      ),
    );
  }
}

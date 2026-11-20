import 'package:flutter/material.dart';

import '../../l10n/ik_strings.dart';
import '../../l10n/video_strings.dart';
import '../../models/platform_type.dart';
import '../../models/song.dart';
import '../data/video_catalog.dart';
import '../ui/catalog_pages.dart';
import '../ui/video_shell.dart';
import '../windows/windows_platform_icon.dart';
import 'ik_search.dart';

class IkSongTile extends StatelessWidget {
  const IkSongTile({
    super.key,
    required this.song,
    required this.onTap,
    this.onMore,
    this.onLike,
    this.liked = false,
    this.playing = false,
  });
  final Song song;
  final VoidCallback onTap;
  final VoidCallback? onMore, onLike;
  final bool liked, playing;
  @override
  Widget build(BuildContext context) => ListTile(
    selected: playing,
    leading: VideoCover(url: song.coverUrl, size: 44, radius: 8),
    title: Text(song.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      '${song.artistNames} · ${videoPlatformLabel(song.platform)}',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12),
    ),
    onTap: onTap,
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onLike != null)
          IconButton(
            tooltip: liked ? VideoStrings.unlike : VideoStrings.like,
            onPressed: onLike,
            icon: Icon(liked ? Icons.favorite : Icons.favorite_border),
          ),
        if (onMore != null)
          IconButton(
            tooltip: IkStrings.more,
            onPressed: onMore,
            icon: const Icon(Icons.more_horiz),
          ),
      ],
    ),
  );
}

class IkSearchPage extends StatefulWidget {
  const IkSearchPage({
    super.key,
    required this.search,
    required this.onPlay,
    required this.onLike,
    required this.onMore,
    this.likedKeys = const {},
    this.currentSong,
    this.onAccount,
  });
  final IkSearchController search;
  final void Function(Song, List<Song>) onPlay;
  final ValueChanged<Song> onLike, onMore;
  final Set<String> likedKeys;
  final Song? currentSong;
  final ValueChanged<PlatformType>? onAccount;
  @override
  State<IkSearchPage> createState() => _IkSearchPageState();
}

class _IkSearchPageState extends State<IkSearchPage> {
  final _text = TextEditingController();
  PlatformType? _filter;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.search,
    builder: (context, _) => CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(20),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  VideoStrings.search,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _text,
                  textInputAction: TextInputAction.search,
                  onSubmitted: widget.search.submit,
                  decoration: InputDecoration(
                    hintText: IkStrings.searchHint,
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: VideoStrings.search,
                      onPressed: () => widget.search.submit(_text.text),
                      icon: const Icon(Icons.arrow_forward),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final platform in <PlatformType?>[
                      null,
                      ...widget.search.platforms,
                    ])
                      ChoiceChip(
                        label: Text(
                          platform == null
                              ? IkStrings.all
                              : videoPlatformLabel(platform),
                        ),
                        selected: _filter == platform,
                        onSelected: (_) => setState(() => _filter = platform),
                      ),
                  ],
                ),
                if (widget.search.query.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 28),
                    child: Text(IkStrings.searchIntro),
                  ),
              ],
            ),
          ),
        ),
        for (final platform in widget.search.platforms)
          if (_filter == null || platform == _filter)
            if (widget.search.groups[platform] case final group?) ...[
              SliverToBoxAdapter(
                child: ListTile(
                  leading: WindowsPlatformIcon(platform: platform),
                  title: Text(videoPlatformLabel(platform)),
                  subtitle: Text(
                    IkStrings.results(group.songs.length, group.total),
                  ),
                ),
              ),
              SliverList.builder(
                itemCount: group.songs.length,
                itemBuilder: (context, index) {
                  final song = group.songs[index];
                  return IkSongTile(
                    song: song,
                    onTap: () => widget.onPlay(song, group.songs),
                    playing:
                        widget.currentSong != null &&
                        videoSongKey(widget.currentSong!) == videoSongKey(song),
                    liked: widget.likedKeys.contains(videoSongKey(song)),
                    onLike: () => widget.onLike(song),
                    onMore: () => widget.onMore(song),
                  );
                },
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  child: Column(
                    children: [
                      if (group.loading) const LinearProgressIndicator(),
                      if (group.error case final error?) ...[
                        Text(
                          error.message,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        if (error.canRetry)
                          TextButton(
                            onPressed: () => widget.search.retry(platform),
                            child: const Text(VideoStrings.retry),
                          ),
                        if (widget.onAccount != null &&
                            (error.kind == VideoFailureKind.notLoggedIn ||
                                error.kind == VideoFailureKind.sessionExpired))
                          TextButton(
                            onPressed: () => widget.onAccount!(platform),
                            child: Text(
                              VideoStrings.loginPlatform(
                                videoPlatformLabel(platform),
                              ),
                            ),
                          ),
                      ] else if (!group.loading && group.songs.isEmpty)
                        const Text(IkStrings.noResults),
                      if (!group.loading &&
                          group.hasMore &&
                          group.error == null)
                        TextButton(
                          onPressed: () => widget.search.loadMore(platform),
                          child: const Text(VideoStrings.loadMore),
                        ),
                    ],
                  ),
                ),
              ),
            ],
      ],
    ),
  );
}

class IkLibraryPage extends StatefulWidget {
  const IkLibraryPage({
    super.key,
    required this.libraries,
    required this.syncing,
    required this.loggedIn,
    required this.onAccount,
    required this.onSync,
    required this.onPlay,
    required this.onLike,
    required this.onMore,
    required this.onNavigate,
    required this.onDownloads,
    this.localLikes = const [],
    this.currentSong,
    this.localLoading = false,
    this.localError,
    this.onRetryLocal,
  });
  final Map<PlatformType, VideoLibrary> libraries;
  final Set<PlatformType> syncing, loggedIn;
  final ValueChanged<PlatformType> onAccount, onSync;
  final void Function(Song, List<Song>) onPlay;
  final ValueChanged<Song> onLike, onMore;
  final ValueChanged<String> onNavigate;
  final VoidCallback onDownloads;
  final List<Song> localLikes;
  final Song? currentSong;
  final bool localLoading;
  final String? localError;
  final VoidCallback? onRetryLocal;
  @override
  State<IkLibraryPage> createState() => _IkLibraryPageState();
}

class _IkLibraryPageState extends State<IkLibraryPage> {
  PlatformType? _filter;
  bool _local = false;
  @override
  Widget build(BuildContext context) {
    final songs = _local
        ? widget.localLikes
        : <Song>[
            for (final entry in widget.libraries.entries)
              if (widget.loggedIn.contains(entry.key) &&
                  (_filter == null || entry.key == _filter))
                ...entry.value.songs,
          ];
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  IkStrings.library,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      label: const Text(IkStrings.playlists),
                      avatar: const Icon(Icons.queue_music),
                      onPressed: () => widget.onNavigate('/platform-playlists'),
                    ),
                    ActionChip(
                      label: const Text(VideoStrings.localMusic),
                      avatar: const Icon(Icons.folder_outlined),
                      onPressed: () => widget.onNavigate('/local-music'),
                    ),
                    ActionChip(
                      label: const Text(VideoStrings.downloadManagement),
                      avatar: const Icon(Icons.download_outlined),
                      onPressed: widget.onDownloads,
                    ),
                    ActionChip(
                      label: const Text(IkStrings.history),
                      avatar: const Icon(Icons.history),
                      onPressed: () => widget.onNavigate('/history'),
                    ),
                    ActionChip(
                      label: const Text(IkStrings.smart),
                      avatar: const Icon(Icons.auto_awesome),
                      onPressed: () => widget.onNavigate('/smart-playlists'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text(IkStrings.platformLikes),
                      selected: !_local,
                      onSelected: (_) => setState(() => _local = false),
                    ),
                    ChoiceChip(
                      label: const Text(IkStrings.localLikes),
                      selected: _local,
                      onSelected: (_) => setState(() => _local = true),
                    ),
                  ],
                ),
                if (!_local) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final platform in <PlatformType?>[
                        null,
                        PlatformType.qq,
                        PlatformType.netease,
                        PlatformType.kugou,
                      ])
                        ChoiceChip(
                          label: Text(
                            platform == null
                                ? IkStrings.all
                                : videoPlatformLabel(platform),
                          ),
                          selected: _filter == platform,
                          onSelected: (_) => setState(() => _filter = platform),
                        ),
                    ],
                  ),
                  for (final platform in [
                    PlatformType.qq,
                    PlatformType.netease,
                    PlatformType.kugou,
                  ])
                    if (_filter == null || _filter == platform)
                      _accountStatus(context, platform),
                ],
                if (_local && widget.localLoading)
                  const LinearProgressIndicator(),
                if (_local && widget.localError != null) ...[
                  Text(
                    widget.localError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  if (widget.onRetryLocal != null)
                    TextButton(
                      onPressed: widget.localLoading
                          ? null
                          : widget.onRetryLocal,
                      child: const Text(VideoStrings.retry),
                    ),
                ],
                if (songs.isEmpty &&
                    (!_local ||
                        (!widget.localLoading && widget.localError == null)))
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(IkStrings.emptyLikes),
                  ),
              ],
            ),
          ),
        ),
        SliverList.builder(
          itemCount: songs.length,
          itemBuilder: (context, index) => IkSongTile(
            song: songs[index],
            onTap: () => widget.onPlay(songs[index], songs),
            playing:
                widget.currentSong != null &&
                videoSongKey(songs[index]) == videoSongKey(widget.currentSong!),
            onMore: () => widget.onMore(songs[index]),
            onLike: _local ? null : () => widget.onLike(songs[index]),
            liked: true,
          ),
        ),
      ],
    );
  }

  Widget _accountStatus(BuildContext context, PlatformType platform) {
    final action = widget.syncing.contains(platform)
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : TextButton(
            onPressed: () => widget.loggedIn.contains(platform)
                ? widget.onSync(platform)
                : widget.onAccount(platform),
            child: Text(
              widget.loggedIn.contains(platform)
                  ? VideoStrings.resyncLikes
                  : VideoStrings.loginPlatform(videoPlatformLabel(platform)),
            ),
          );
    final subtitle = Text(
      !widget.loggedIn.contains(platform)
          ? VideoStrings.loginToSyncLikes
          : widget.syncing.contains(platform)
          ? VideoStrings.syncingMusic
          : widget.libraries[platform]?.error?.message ??
                '${IkStrings.results(widget.libraries[platform]?.songs.length ?? 0, widget.libraries[platform]?.total)}${widget.libraries[platform]?.complete == false ? ' · ${VideoStrings.syncIncomplete}' : ''}',
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < 560 ||
            MediaQuery.textScalerOf(context).scale(14) > 18;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: WindowsPlatformIcon(platform: platform),
                title: Text(videoPlatformLabel(platform)),
                subtitle: subtitle,
                trailing: compact ? null : action,
              ),
              if (compact)
                Padding(
                  padding: const EdgeInsets.only(left: 48),
                  child: action,
                ),
            ],
          ),
        );
      },
    );
  }
}

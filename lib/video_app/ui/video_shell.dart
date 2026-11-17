import '../../l10n/expanded_strings.dart';

import '../../l10n/video_strings.dart';

import 'dart:ui';

import 'package:flutter/material.dart';

import '../../models/song.dart';
import 'video_theme.dart';
import '../../models/platform_type.dart';
import '../windows/windows_platform_icon.dart';

class VideoShell extends StatelessWidget {
  const VideoShell({
    super.key,
    required this.index,
    required this.onSelect,
    required this.pages,
    required this.miniPlayer,
    this.expandedPlatforms = false,
    this.platformIcons = false,
  });
  final int index;
  final ValueChanged<int> onSelect;
  final List<Widget> pages;
  final Widget miniPlayer;
  final bool expandedPlatforms;
  final bool platformIcons;
  Widget _destinationIcon(int index) =>
      platformIcons && index >= 1 && index <= (expandedPlatforms ? 3 : 2)
      ? WindowsPlatformIcon(
          platform: [
            PlatformType.qq,
            PlatformType.netease,
            PlatformType.kugou,
          ][index - 1],
        )
      : Icon(_icons[index]);
  List<String> get _labels => [
    VideoStrings.search,
    VideoStrings.qqMusic,
    VideoStrings.netease,
    if (expandedPlatforms) VideoStrings.kugou,
    VideoStrings.my,
  ];
  List<IconData> get _icons => [
    Icons.search_rounded,
    Icons.format_list_bulleted_rounded,
    Icons.view_list_rounded,
    if (expandedPlatforms) Icons.library_music_outlined,
    Icons.account_circle_outlined,
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: VideoTheme.canvas(context),
    body: SafeArea(
      bottom: false,
      child: expandedPlatforms && MediaQuery.sizeOf(context).width >= 840
          ? Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      NavigationRail(
                        extended: true,
                        selectedIndex: index,
                        onDestinationSelected: onSelect,
                        minExtendedWidth: 190,
                        labelType: NavigationRailLabelType.none,
                        leading: Padding(
                          padding: EdgeInsets.all(16),
                          child: platformIcons
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Image.asset(
                                      'assets/branding/yueyin/note-ribbons.png',
                                      width: 28,
                                      height: 28,
                                    ),
                                    const SizedBox(width: 10),
                                    const Text(
                                      ExpandedStrings.appName,
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                )
                              : const Text(
                                  ExpandedStrings.appName,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                        destinations: [
                          for (var i = 0; i < _labels.length; i++)
                            NavigationRailDestination(
                              icon: _destinationIcon(i),
                              label: Text(_labels[i]),
                            ),
                        ],
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: IndexedStack(index: index, children: pages),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                  child: miniPlayer,
                ),
              ],
            )
          : Column(
              children: [
                Expanded(
                  child: IndexedStack(index: index, children: pages),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: miniPlayer,
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    14,
                    6,
                    14,
                    8 + MediaQuery.paddingOf(context).bottom,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 7,
                        ),
                        color: VideoTheme.surface(context)
                            .withValues(alpha: .88),
                        child: Row(
                          children: [
                            for (var i = 0; i < _labels.length; i++)
                              Expanded(
                                child: _Tab(
                                  index: i,
                                  label: _labels[i],
                                  icon: _icons[i],
                                  artwork:
                                      platformIcons &&
                                          i >= 1 &&
                                          i <= (expandedPlatforms ? 3 : 2)
                                      ? _destinationIcon(i)
                                      : null,
                                  selected: index == i,
                                  onTap: () => onSelect(i),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    ),
  );
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.index,
    required this.selected,
    required this.onTap,
    required this.label,
    required this.icon,
    this.artwork,
  });
  final int index;
  final bool selected;
  final VoidCallback onTap;
  final String label;
  final IconData icon;
  final Widget? artwork;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(25),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? VideoTheme.primary.withValues(alpha: .08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(25),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            artwork ??
                Icon(
                  icon,
                  size: 25,
                  color: selected
                      ? VideoTheme.primary
                      : Theme.of(context).colorScheme.onSurface
                            .withValues(alpha: .78),
                ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 10,
                color: selected
                    ? VideoTheme.primary
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class VideoMiniPlayer extends StatelessWidget {
  const VideoMiniPlayer({
    super.key,
    this.song,
    required this.isPlaying,
    this.isLoading = false,
    this.error,
    required this.onOpen,
    required this.onToggle,
    required this.onQueue,
  });
  final Song? song;
  final bool isPlaying;
  final bool isLoading;
  final String? error;
  final VoidCallback onOpen;
  final VoidCallback onToggle;
  final VoidCallback onQueue;
  @override
  Widget build(BuildContext context) => Material(
    color: VideoTheme.surface(context),
    borderRadius: BorderRadius.circular(22),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: song == null ? null : onOpen,
      child: Padding(
        padding: const EdgeInsets.only(left: 9, top: 7, bottom: 7, right: 4),
        child: Row(
          children: [
            VideoCover(url: song?.coverUrl, size: 38, radius: 9),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song?.name ?? VideoStrings.chooseSong,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    isLoading
                        ? VideoStrings.preparingAudio
                        : error != null
                        ? VideoStrings.playFailedTap
                        : song == null
                        ? VideoStrings.bothPlatforms
                        : '${song!.artistNames} · ${song!.platform.name == 'qq'
                              ? VideoStrings.qqMusic
                              : song!.platform.name == 'netease'
                              ? VideoStrings.netease
                              : song!.platform.name == 'kugou'
                              ? VideoStrings.kugou
                              : VideoStrings.local}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: VideoTheme.secondaryText(context),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: isPlaying ? VideoStrings.pause : VideoStrings.play,
              onPressed: song == null || isLoading ? null : onToggle,
              icon: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 25,
              ),
            ),
            IconButton(
              tooltip: VideoStrings.playQueue,
              onPressed: onQueue,
              icon: const Icon(Icons.queue_music_rounded, size: 23),
            ),
          ],
        ),
      ),
    ),
  );
}

class VideoCover extends StatelessWidget {
  const VideoCover({super.key, this.url, required this.size, this.radius = 18});
  final String? url;
  final double size;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff7fa3ed), Color(0xff5c8c9b), Color(0xff467c71)],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: size * .45,
          color: Colors.white.withValues(alpha: .85),
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: url == null || url!.isEmpty
            ? fallback
            : Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

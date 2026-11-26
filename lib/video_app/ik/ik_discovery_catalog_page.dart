import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/ik_personal_daily_strings.dart';
import '../../l10n/ik_recommendation_catalog_strings.dart';
import '../../l10n/ik_strings.dart';
import '../../models/platform_type.dart';
import '../../models/playlist.dart';
import '../data/ik_playlist_catalog_provider.dart';
import '../ui/video_shell.dart';
import 'ik_controls.dart';

class IkDiscoveryCatalogPage extends ConsumerStatefulWidget {
  const IkDiscoveryCatalogPage({
    super.key,
    required this.onNavigate,
    this.header,
    this.compactPlatformSelector = false,
  });
  final ValueChanged<String> onNavigate;
  final Widget? header;
  final bool compactPlatformSelector;

  @override
  ConsumerState<IkDiscoveryCatalogPage> createState() =>
      _IkDiscoveryCatalogPageState();
}

class _IkDiscoveryCatalogPageState extends ConsumerState<IkDiscoveryCatalogPage> {
  PlatformType _selected = PlatformType.netease;
  final _scroll = <PlatformType, ScrollController>{};

  ScrollController _controller(PlatformType platform) =>
      _scroll.putIfAbsent(platform, ScrollController.new);

  @override
  void dispose() {
    for (final controller in _scroll.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _open(Playlist playlist) => widget.onNavigate(Uri(
    path: '/playlist/${playlist.platform.name}/${playlist.id}',
    queryParameters: {
      'name': playlist.name,
      if (playlist.coverUrl != null) 'cover': playlist.coverUrl!,
    },
  ).toString());

  @override
  Widget build(BuildContext context) {
    final platform = _selected;
    final state = ref.watch(ikPlaylistCatalogProvider(platform));
    final notifier = ref.read(ikPlaylistCatalogProvider(platform).notifier);
    final controller = _controller(platform);
    final colors = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: notifier.refresh,
      child: Scrollbar(
        controller: controller,
        thumbVisibility: true,
        child: CustomScrollView(
          key: PageStorageKey('ik-discovery-catalog-${platform.name}'),
          controller: controller,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.header case final header?)
                      header
                    else ...[
                      Text(
                        IkRecommendationCatalogStrings.heading,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        IkRecommendationCatalogStrings.intro,
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 18),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth > 600;
                          return Row(
                            children: [
                              Expanded(
                                child: _DiscoveryEntryCard(
                                  key: const Key('ik-personal-daily-entry'),
                                  icon: Icons.wb_sunny_outlined,
                                  title: IkPersonalDailyStrings.title,
                                  subtitle: IkPersonalDailyStrings.hint,
                                  wide: wide,
                                  onTap: () => widget.onNavigate('/daily'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _DiscoveryEntryCard(
                                  icon: Icons.new_releases_outlined,
                                  title: IkStrings.newSongs,
                                  subtitle: IkPersonalDailyStrings.heading,
                                  wide: wide,
                                  onTap: () => widget.onNavigate('/new-songs'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _DiscoveryEntryCard(
                                  icon: Icons.leaderboard_outlined,
                                  title: IkStrings.toplists,
                                  subtitle: IkRecommendationCatalogStrings.publicSource,
                                  wide: wide,
                                  onTap: () => widget.onNavigate('/toplists'),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                    const SizedBox(height: 24),
                    if (widget.compactPlatformSelector)
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final title = Text(
                            IkRecommendationCatalogStrings.playlists,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          );
                          final controls = Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              IkSelect<PlatformType>(
                                key: const Key('ik-catalog-platform-select'),
                                label: IkRecommendationCatalogStrings.platform,
                                value: platform,
                                items: {
                                  for (final source in PlatformType.musicServices)
                                    source: IkPersonalDailyStrings.platformLabel(source),
                                },
                                alignToDesign: true,
                                dismissOnSystemBack: true,
                                onChanged: (source) =>
                                    setState(() => _selected = source),
                              ),
                              IconButton(
                                tooltip: IkRecommendationCatalogStrings.refresh,
                                onPressed: state.loading
                                    ? null
                                    : () => unawaited(notifier.refresh()),
                                icon: const Icon(Icons.refresh_rounded, size: 20),
                              ),
                            ],
                          );
                          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                          if (constraints.maxWidth < 440 * scale) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [title, const SizedBox(height: 12), controls],
                            );
                          }
                          return Row(
                            children: [Expanded(child: title), controls],
                          );
                        },
                      )
                    else ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (final source in PlatformType.musicServices)
                            _CatalogPlatformTab(
                              key: ValueKey('ik-catalog-platform-${source.name}'),
                              selected: source == platform,
                              label: IkPersonalDailyStrings.platformLabel(source),
                              onTap: () => setState(() => _selected = source),
                            ),
                          IconButton(
                            tooltip: IkRecommendationCatalogStrings.refresh,
                            onPressed: state.loading ? null : () => unawaited(notifier.refresh()),
                            icon: const Icon(Icons.refresh_rounded, size: 20),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        IkRecommendationCatalogStrings.playlists,
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 14,
                      runSpacing: 5,
                      children: [
                        Text(
                          state.source ?? IkRecommendationCatalogStrings.source(platform),
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                        if (state.initialized)
                          Text(
                            IkRecommendationCatalogStrings.loaded(state.playlists.length),
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (state.playlists.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    const gap = 16.0;
                    final columns = math.max(
                      2,
                      ((constraints.crossAxisExtent + gap) / 206).ceil(),
                    );
                    final width =
                        (constraints.crossAxisExtent - gap * (columns - 1)) / columns;
                    final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
                    return SliverGrid.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: gap,
                        mainAxisSpacing: 20,
                        mainAxisExtent: width + 72 * scale,
                      ),
                      itemCount: state.playlists.length,
                      itemBuilder: (context, index) => _PlaylistCard(
                        playlist: state.playlists[index],
                        width: width,
                        onOpen: () => _open(state.playlists[index]),
                      ),
                    );
                  },
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              sliver: SliverToBoxAdapter(
                child: Column(
                  children: [
                    if (state.loading) ...[
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(height: 10),
                      const Text(IkRecommendationCatalogStrings.loading),
                    ] else if (state.error case final error?) ...[
                      Text(error, textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: () => unawaited(notifier.retry()),
                        child: const Text(IkRecommendationCatalogStrings.retry),
                      ),
                    ] else if (state.playlists.isEmpty)
                      const Text(IkRecommendationCatalogStrings.empty)
                    else if (state.hasMore)
                      OutlinedButton.icon(
                        onPressed: () => unawaited(notifier.loadMore()),
                        icon: const Icon(Icons.expand_more_rounded, size: 18),
                        label: const Text(IkRecommendationCatalogStrings.loadMore),
                      )
                    else
                      Text(
                        state.endKnown && platform != PlatformType.kugou
                            ? IkRecommendationCatalogStrings.noMore
                            : IkRecommendationCatalogStrings.availableOnly,
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscoveryEntryCard extends StatelessWidget {
  const _DiscoveryEntryCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.wide,
    required this.onTap,
  });

  final IconData icon;
  final String title, subtitle;
  final bool wide;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, height: 1.3, fontWeight: FontWeight.w600),
        ),
        if (wide) ...[
          const SizedBox(height: 5),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, height: 1.3, color: colors.onSurfaceVariant),
          ),
        ],
      ],
    );
    return Material(
      color: colors.surfaceContainerHighest.withValues(alpha: .34),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: .6)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          height: wide ? 84 : 76,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: wide ? 16 : 6),
            child: wide
                ? Row(
                    children: [
                      Icon(icon, size: 24, color: colors.primary),
                      const SizedBox(width: 12),
                      Expanded(child: text),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 24, color: colors.primary),
                      const SizedBox(height: 7),
                      text,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _CatalogPlatformTab extends StatelessWidget {
  const _CatalogPlatformTab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                width: 2,
                color: selected ? colors.primary : Colors.transparent,
              ),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? colors.primary : colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({required this.playlist, required this.width, required this.onOpen});
  final Playlist playlist;
  final double width;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: width,
      child: InkWell(
        key: ValueKey('ik-catalog-${playlist.platform.name}-${playlist.id}'),
        borderRadius: BorderRadius.circular(12),
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: VideoCover(url: playlist.coverUrl, size: width, radius: 0),
            ),
            const SizedBox(height: 10),
            Text(
              playlist.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, height: 1.4, fontWeight: FontWeight.w600),
            ),
            if (playlist.songCount > 0) ...[
              const SizedBox(height: 4),
              Text(
                IkRecommendationCatalogStrings.songs(playlist.songCount),
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

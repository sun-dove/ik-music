import 'package:flutter/material.dart';

import '../../l10n/ik_strings.dart';
import '../../l10n/video_strings.dart';
import 'ik_theme.dart';

class IkShell extends StatelessWidget {
  const IkShell({
    super.key,
    required this.index,
    required this.onSelect,
    required this.pages,
    required this.miniPlayer,
    this.queue,
  });
  final int index;
  final ValueChanged<int> onSelect;
  final List<Widget> pages;
  final Widget miniPlayer;
  final Widget? queue;
  static const labels = [
    IkStrings.home,
    VideoStrings.search,
    IkStrings.library,
    VideoStrings.my,
  ];
  static const icons = [
    Icons.home_outlined,
    Icons.search,
    Icons.library_music_outlined,
    Icons.person_outline,
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final showQueue = queue != null && MediaQuery.sizeOf(context).width >= 1180;
    return Scaffold(
      backgroundColor:
          Theme.of(context).extension<IkThemeColors>()?.hasBackground == true
          ? Colors.transparent
          : null,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  if (wide) ...[
                    NavigationRail(
                      selectedIndex: index,
                      onDestinationSelected: onSelect,
                      extended: true,
                      minExtendedWidth: 168,
                      leading: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset(IkTheme.icon, width: 36, height: 36),
                            const SizedBox(width: 12),
                            const Text(
                              'ik',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      destinations: [
                        for (var i = 0; i < labels.length; i++)
                          NavigationRailDestination(
                            icon: Icon(icons[i]),
                            label: Text(labels[i]),
                          ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                  ],
                  Expanded(
                    child: IndexedStack(index: index, children: pages),
                  ),
                  if (showQueue) ...[
                    const VerticalDivider(width: 1),
                    SizedBox(width: 280, child: queue),
                  ],
                ],
              ),
            ),
            Padding(padding: EdgeInsets.all(wide ? 12 : 8), child: miniPlayer),
            if (!wide)
              NavigationBar(
                height: 80,
                selectedIndex: index,
                onDestinationSelected: onSelect,
                destinations: [
                  for (var i = 0; i < labels.length; i++)
                    NavigationDestination(
                      icon: Icon(icons[i]),
                      label: labels[i],
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

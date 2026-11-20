import 'package:flutter/material.dart';

import '../../l10n/ik_strings.dart';
import '../../l10n/ik_workspace_strings.dart';
import '../../l10n/video_strings.dart';
import 'ik_theme.dart';
import 'ik_version.dart';

class IkDesktopWorkspace extends StatelessWidget {
  const IkDesktopWorkspace({
    super.key,
    required this.index,
    required this.onSelect,
    required this.pages,
    required this.playbackBar,
    required this.onAccount,
  });
  final int index;
  final ValueChanged<int> onSelect;
  final List<Widget> pages;
  final Widget playbackBar;
  final VoidCallback onAccount;
  static const labels = [
    IkWorkspaceStrings.discovery,
    VideoStrings.search,
    IkWorkspaceStrings.library,
    IkStrings.history,
    IkWorkspaceStrings.settings,
  ];
  static const icons = [
    Icons.home_outlined,
    Icons.search_rounded,
    Icons.library_music_outlined,
    Icons.history_rounded,
    Icons.settings_outlined,
  ];

  Widget _nav(BuildContext context, int value, {bool compact = false}) {
    final selected = index == value;
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final icon = SizedBox(
      width: 22,
      height: 22,
      child: Center(child: Icon(icons[value], size: 20, color: color)),
    );
    final text = Text(
      labels[value],
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 13,
        height: 1.35,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        color: color,
      ),
    );
    return Semantics(
      selected: selected,
      button: true,
      label: labels[value],
      child: Tooltip(
        message: labels[value],
        child: Material(
          color: selected
              ? Theme.of(context).colorScheme.surface
              : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          child: InkWell(
            key: ValueKey('ik-workspace-nav-$value'),
            borderRadius: BorderRadius.circular(9),
            onTap: () => onSelect(value),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 4 : 12,
                vertical: compact ? 9 : 13,
              ),
              child: compact
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [icon, const SizedBox(height: 5), text],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        icon,
                        const SizedBox(width: 12),
                        Expanded(child: text),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _brand({bool compact = false}) => Row(
    children: [
      Image.asset(
        IkTheme.icon,
        width: compact ? 30 : 36,
        height: compact ? 30 : 36,
      ),
      const SizedBox(width: 9),
      Flexible(
        child: Text(
          IkVersion.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: compact ? 18 : 20,
            height: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final sidebar = Theme.of(context).colorScheme.primary
        .withValues(alpha: .035);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            if (!wide)
              Container(
                color: sidebar,
                padding: const EdgeInsets.fromLTRB(16, 10, 12, 0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: _brand(compact: true)),
                        IconButton(
                          key: const ValueKey('ik-workspace-nav-4'),
                          tooltip: IkWorkspaceStrings.settings,
                          onPressed: () => onSelect(4),
                          icon: const Icon(Icons.settings_outlined, size: 20),
                        ),
                        IconButton(
                          key: const ValueKey('ik-workspace-account'),
                          tooltip: IkWorkspaceStrings.connect,
                          onPressed: onAccount,
                          icon: const Icon(
                            Icons.person_outline_rounded,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        for (var i = 0; i < 4; i++)
                          Expanded(child: _nav(context, i, compact: true)),
                      ],
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Row(
                children: [
                  if (wide)
                    Container(
                      width: MediaQuery.sizeOf(context).width >= 1100
                          ? 204
                          : 168,
                      color: sidebar,
                      padding: const EdgeInsets.fromLTRB(16, 28, 16, 18),
                      child: Column(
                        children: [
                          _brand(),
                          const SizedBox(height: 36),
                          for (var i = 0; i < 4; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 5),
                              child: _nav(context, i),
                            ),
                          const Spacer(),
                          _nav(context, 4),
                          const SizedBox(height: 18),
                          const Divider(height: 1),
                          InkWell(
                            key: const ValueKey('ik-workspace-account'),
                            onTap: onAccount,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 16,
                                horizontal: 4,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const SizedBox(
                                    width: 30,
                                    height: 30,
                                    child: Center(
                                      child: Icon(
                                        Icons.person_outline_rounded,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          IkWorkspaceStrings.connect,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            height: 1.4,
                                          ),
                                        ),
                                        SizedBox(height: 3),
                                        Text(
                                          IkWorkspaceStrings.sync,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: IndexedStack(index: index, children: pages),
                  ),
                ],
              ),
            ),
            playbackBar,
          ],
        ),
      ),
    );
  }
}

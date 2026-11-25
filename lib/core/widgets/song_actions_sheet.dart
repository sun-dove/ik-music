import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../models/song.dart';
import '../theme/app_theme.dart';

/// Actions a song can offer from its long-press (or overflow) menu.
enum SongAction {
  playNext,
  addToPlaylist,
  download,
  toggleLike,
  copyLink,
  share,
}

/// Shared song action sheet.
///
/// The API is frozen here in Wave 0 so the content pages and the interaction
/// workstream can both call it without waiting for each other. This file owns
/// *presenting* the choices; the interaction workstream owns what each choice
/// does (and its tests), so a caller gets a [SongAction] back and dispatches it.
///
/// Note `useRootNavigator: true`: the shell hosts go_router's nested navigator,
/// and a sheet pushed onto that nested navigator is painted under the bottom
/// navigation capsules (this was fixed once already for modal sheets — see the
/// v1.3.2 notes in `docs/mconnect-improvement-plan.md`).
Future<SongAction?> showSongActionsSheet(
  BuildContext context, {
  required Song song,
  bool isLiked = false,
  bool isDownloaded = false,
  bool isLocal = false,
}) {
  if (ContextualActionTheme.isEnabled(context)) {
    return _showContextualSongMenu(
      context,
      song: song,
      isLiked: isLiked,
      isDownloaded: isDownloaded,
      isLocal: isLocal,
    );
  }
  return showModalBottomSheet<SongAction>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      // Every song list in the app shows this menu, so its labels live in the
      // shared `common*` group (docs/i18n-migration-plan.md §1.2 rule 3) — later
      // batches only reference them instead of writing the same strings again.
      final l = sheetContext.l10n;
      return SafeArea(
        // Scrollable on purpose: `showModalBottomSheet` caps an unscrollable
        // sheet at 9/16 of the screen, and this menu's six rows plus the header
        // and drag handle exceed that on a 360x800 phone (measured: 417px of
        // content in a 402px limit), which pushed the last action out of reach.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  song.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                subtitle: Text(
                  song.artistNames,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Divider(height: 1),
              _ActionTile(
                icon: Icons.playlist_play,
                label: l.commonPlayNext,
                action: SongAction.playNext,
              ),
              if (!isLocal)
                _ActionTile(
                  icon: Icons.playlist_add,
                  label: l.commonAddToPlaylist,
                  action: SongAction.addToPlaylist,
                ),
              if (!isLocal)
                _ActionTile(
                  icon: isDownloaded
                      ? Icons.download_done
                      : Icons.download_outlined,
                  label: isDownloaded ? l.commonDownloaded : l.commonDownload,
                  action: SongAction.download,
                  enabled: !isDownloaded,
                ),
              if (!isLocal)
                _ActionTile(
                  icon: isLiked ? Icons.favorite : Icons.favorite_border,
                  label: isLiked ? l.commonUnlike : l.commonLike,
                  action: SongAction.toggleLike,
                ),
              _ActionTile(
                icon: Icons.link,
                label: l.commonCopyLink,
                action: SongAction.copyLink,
              ),
              if (!isLocal)
                _ActionTile(
                  icon: Icons.share_outlined,
                  // Reuses the existing `share` key (zh/en already translated).
                  label: l.share,
                  action: SongAction.share,
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}

/// 复杂选择共用居中容器；调用方继续提供原选项、关闭与返回值。
Future<T?> showContextualDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showDialog<T>(
    context: context,
    useRootNavigator: true,
    builder: (dialogContext) {
      final visibleHeight =
          MediaQuery.sizeOf(dialogContext).height -
          MediaQuery.viewInsetsOf(dialogContext).bottom;
      return Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: visibleHeight * .8),
          child: SizedBox(width: 520, child: builder(dialogContext)),
        ),
      );
    },
  );
}

Future<SongAction?> _showContextualSongMenu(
  BuildContext context, {
  required Song song,
  required bool isLiked,
  required bool isDownloaded,
  required bool isLocal,
}) {
  final theme = Theme.of(context);
  final l = context.l10n;
  final anchorContext = _songMenuAnchorContext(context);
  final overlay =
      Navigator.of(
            context,
            rootNavigator: true,
          ).overlay!.context.findRenderObject()!
          as RenderBox;

  PopupMenuItem<SongAction> item(
    SongAction action,
    IconData icon,
    String label, {
    bool enabled = true,
  }) => PopupMenuItem<SongAction>(
    value: action,
    enabled: enabled,
    child: Row(
      children: [
        SizedBox(
          width: 22,
          height: 22,
          child: Center(
            child: Icon(
              icon,
              size: 18,
              color: enabled ? null : theme.disabledColor,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      ],
    ),
  );

  return showMenu<SongAction>(
    context: context,
    useRootNavigator: true,
    constraints: const BoxConstraints(minWidth: 220, maxWidth: 300),
    positionBuilder: (_, _) {
      final renderObject = anchorContext.mounted
          ? anchorContext.findRenderObject()
          : null;
      final Rect anchor;
      if (renderObject is RenderBox &&
          renderObject.hasSize &&
          renderObject.attached) {
        final topLeft = renderObject.localToGlobal(
          Offset.zero,
          ancestor: overlay,
        );
        final bottomRight = renderObject.localToGlobal(
          renderObject.size.bottomRight(Offset.zero),
          ancestor: overlay,
        );
        anchor = Rect.fromLTRB(
          topLeft.dx,
          bottomRight.dy,
          bottomRight.dx,
          bottomRight.dy,
        );
      } else {
        anchor = Rect.fromCenter(
          center: overlay.size.center(Offset.zero),
          width: 0,
          height: 0,
        );
      }
      return RelativeRect.fromRect(anchor, Offset.zero & overlay.size);
    },
    items: [
      PopupMenuItem<SongAction>(
        enabled: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              song.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 3),
            Text(
              song.artistNames,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      const PopupMenuDivider(),
      item(SongAction.playNext, Icons.playlist_play, l.commonPlayNext),
      if (!isLocal)
        item(
          SongAction.addToPlaylist,
          Icons.playlist_add,
          l.commonAddToPlaylist,
        ),
      if (!isLocal)
        item(
          SongAction.download,
          isDownloaded ? Icons.download_done : Icons.download_outlined,
          isDownloaded ? l.commonDownloaded : l.commonDownload,
          enabled: !isDownloaded,
        ),
      if (!isLocal)
        item(
          SongAction.toggleLike,
          isLiked ? Icons.favorite : Icons.favorite_border,
          isLiked ? l.commonUnlike : l.commonLike,
        ),
      item(SongAction.copyLink, Icons.link, l.commonCopyLink),
      if (!isLocal) item(SongAction.share, Icons.share_outlined, l.share),
    ],
  );
}

BuildContext _songMenuAnchorContext(BuildContext context) {
  final focusContext = FocusManager.instance.primaryFocus?.context;
  final ownBox = context.findRenderObject();
  if (focusContext == null || !focusContext.mounted || ownBox is! RenderBox) {
    return context;
  }
  final focusBox = focusContext.findRenderObject();
  if (focusBox is! RenderBox ||
      !ownBox.hasSize ||
      !focusBox.hasSize ||
      focusContext.findAncestorWidgetOfExactType<IconButton>() == null) {
    return context;
  }
  var withinCaller = identical(context, focusContext);
  focusContext.visitAncestorElements((element) {
    if (identical(element, context)) {
      withinCaller = true;
      return false;
    }
    return true;
  });
  return withinCaller &&
          (ownBox.size.width > focusBox.size.width ||
              ownBox.size.height > focusBox.size.height)
      ? focusContext
      : context;
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.action,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final SongAction action;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      enabled: enabled,
      onTap: enabled
          ? () => Navigator.of(context, rootNavigator: true).pop(action)
          : null,
    );
  }
}

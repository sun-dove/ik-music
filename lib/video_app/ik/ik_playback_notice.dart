import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/ik_playback_notice_strings.dart';
import '../../l10n/ik_strings.dart';

/// 仅由新版播放栏在静态失败时挂载，不保存播放器状态。
class IkPlaybackNotice extends StatefulWidget {
  const IkPlaybackNotice({
    super.key,
    required this.title,
    required this.reason,
    required this.details,
    required this.actionLabel,
    this.onAction,
  });

  final String title, reason, details, actionLabel;
  final VoidCallback? onAction;

  @override
  State<IkPlaybackNotice> createState() => _IkPlaybackNoticeState();
}

class _IkPlaybackNoticeState extends State<IkPlaybackNotice> {
  final _focus = FocusNode();
  final _detailsScroll = ScrollController();

  @override
  void dispose() {
    _focus.dispose();
    _detailsScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final viewport = MediaQuery.sizeOf(context);
    final panelWidth = math.min(380.0, math.max(0.0, viewport.width - 40));
    final actionStyle = TextButton.styleFrom(
      minimumSize: const Size(0, 32),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(fontSize: 12),
    );
    return Wrap(
      key: const ValueKey('ik-playback-compact-status'),
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 2,
      runSpacing: 0,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text(
            widget.title,
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
        ),
        if (widget.onAction != null)
          TextButton(
            onPressed: widget.onAction,
            style: actionStyle,
            child: Text(widget.actionLabel),
          ),
        MenuAnchor(
          childFocusNode: _focus,
          crossAxisUnconstrained: false,
          style: MenuStyle(
            elevation: const WidgetStatePropertyAll(8),
            backgroundColor: WidgetStatePropertyAll(colors.surface),
            surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: colors.outlineVariant),
              ),
            ),
          ),
          menuChildren: [
            SizedBox(
              width: panelWidth,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: math.min(340.0, viewport.height * .55),
                ),
                child: Scrollbar(
                  controller: _detailsScroll,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _detailsScroll,
                    primary: false,
                    padding: const EdgeInsets.fromLTRB(16, 8, 12, 12),
                    child: Builder(
                      builder: (context) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  IkPlaybackNoticeStrings.detailsTitle,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              IconButton(
                                autofocus: true,
                                tooltip: IkStrings.close,
                                onPressed: () {
                                  MenuController.maybeOf(context)?.close();
                                  _focus.requestFocus();
                                },
                                icon: const Icon(Icons.close_rounded, size: 18),
                              ),
                            ],
                          ),
                          Text(
                            widget.reason,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          if (widget.details.trim().isNotEmpty &&
                              widget.details.trim() !=
                                  widget.reason.trim()) ...[
                            const SizedBox(height: 12),
                            const Text(
                              IkPlaybackNoticeStrings.attempts,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              widget.details,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.6,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                          if (widget.onAction != null) ...[
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: () {
                                MenuController.maybeOf(context)?.close();
                                widget.onAction?.call();
                              },
                              style: actionStyle,
                              child: Text(widget.actionLabel),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          builder: (context, controller, _) => TextButton(
            focusNode: _focus,
            onPressed: () =>
                controller.isOpen ? controller.close() : controller.open(),
            style: actionStyle,
            child: const Text(IkPlaybackNoticeStrings.details),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../l10n/ik_workspace_strings.dart';

class IkSelect<T> extends StatefulWidget {
  const IkSelect({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.enabled = true,
    this.alignToDesign = false,
  });
  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;
  final bool enabled;
  final bool alignToDesign;
  @override
  State<IkSelect<T>> createState() => _IkSelectState<T>();
}

class _IkSelectState<T> extends State<IkSelect<T>> {
  final _focus = FocusNode();
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MenuAnchor(
      childFocusNode: _focus,
      style: MenuStyle(
        elevation: const WidgetStatePropertyAll(8),
        backgroundColor: WidgetStatePropertyAll(theme.colorScheme.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: theme.dividerColor.withValues(alpha: .12)),
          ),
        ),
      ),
      menuChildren: [
        for (final item in widget.items.entries)
          MenuItemButton(
            onPressed: () {
              widget.onChanged(item.key);
              _focus.requestFocus();
            },
            trailingIcon: item.key == widget.value
                ? Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: theme.colorScheme.primary,
                  )
                : const SizedBox(width: 18),
            style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(Size(180, 42)),
              backgroundColor: item.key == widget.value
                  ? WidgetStatePropertyAll(
                      theme.colorScheme.primary.withValues(alpha: .09),
                    )
                  : null,
              foregroundColor: item.key == widget.value
                  ? WidgetStatePropertyAll(theme.colorScheme.primary)
                  : null,
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
              ),
            ),
            child: Text(
              item.value,
              style: widget.alignToDesign
                  ? theme.textTheme.labelLarge?.copyWith(
                      fontSize: 13,
                      inherit: true,
                    )
                  : const TextStyle(fontSize: 13),
            ),
          ),
      ],
      builder: (context, controller, _) => Semantics(
        label: widget.label,
        child: OutlinedButton(
          focusNode: _focus,
          onPressed: !widget.enabled
              ? null
              : () =>
                    controller.isOpen ? controller.close() : controller.open(),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(140, 40),
            maximumSize: const Size(280, double.infinity),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            foregroundColor: theme.colorScheme.onSurface,
            side: BorderSide(
              color: controller.isOpen
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: widget.alignToDesign
                ? theme.textTheme.labelLarge?.copyWith(
                    fontSize: 13,
                    inherit: true,
                  )
                : const TextStyle(fontSize: 13),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  widget.items[widget.value] ?? widget.value.toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 16),
              Icon(
                controller.isOpen
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class IkSettingRow extends StatelessWidget {
  const IkSettingRow({
    super.key,
    required this.title,
    required this.control,
    this.description,
    this.status,
    this.alignToDesign = false,
  });
  final String title;
  final String? description, status;
  final Widget control;
  final bool alignToDesign;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final compact =
          size.maxWidth < (alignToDesign ? 460 : 560) ||
          MediaQuery.textScalerOf(context).scale(14) > 19;
      final label = Column(
        mainAxisSize: alignToDesign ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          if (description != null)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                description!,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (status != null)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                status!,
                style: TextStyle(
                  fontSize: 12,
                  color: status == IkWorkspaceStrings.failed
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
        ],
      );
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 20,
          vertical: alignToDesign ? 15 : 17,
        ),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  label,
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerRight, child: control),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: label),
                  const SizedBox(width: 22),
                  if (alignToDesign)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: (size.maxWidth - 40) * .52,
                      ),
                      child: control,
                    )
                  else
                    control,
                ],
              ),
      );
    },
  );
}

class IkSettingCard extends StatelessWidget {
  const IkSettingCard({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 18),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: Theme.of(context).colorScheme.outlineVariant
            .withValues(alpha: .6),
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          children[i],
        ],
      ],
    ),
  );
}

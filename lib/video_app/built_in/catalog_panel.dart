import '../../l10n/ik_source_catalog_strings.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'catalog_coordinator.dart';

class IkSourceCatalogPanel extends ConsumerWidget {
  const IkSourceCatalogPanel({super.key, this.onManageSources});
  final VoidCallback? onManageSources;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coordinator = ref.watch(ikSourceCatalogProvider);
    if (coordinator == null) return const Text(IkSourceCatalogStrings.missing);
    return AnimatedBuilder(
      animation: coordinator,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(IkSourceCatalogStrings.description),
          const SizedBox(height: 12),
          Material(
            color: Colors.transparent,
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text(IkSourceCatalogStrings.autoPrepare),
              value: coordinator.autoPrepare,
              onChanged: coordinator.settings.writesBlocked
                  ? null
                  : (value) => unawaited(
                      _run(context, () => coordinator.setAutoPrepare(value)),
                    ),
            ),
          ),
          Text(
            IkSourceCatalogStrings.progress(
              coordinator.readyCount,
              coordinator.pendingCount,
              coordinator.items.length,
            ),
            key: const ValueKey('ik-catalog-progress'),
          ),
          if (coordinator.error ?? coordinator.settings.managedError
              case final String error)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: coordinator.busy
                    ? null
                    : () => unawaited(
                        _run(context, coordinator.prepareCatalogUpdate),
                      ),
                child: const Text(IkSourceCatalogStrings.check),
              ),
              OutlinedButton(
                onPressed:
                    coordinator.busy ||
                        !coordinator.items.any((e) => e.retryable)
                    ? null
                    : () => unawaited(_run(context, coordinator.retry)),
                child: const Text(IkSourceCatalogStrings.retry),
              ),
              if (coordinator.busy)
                TextButton(
                  onPressed: coordinator.cancel,
                  child: const Text(IkSourceCatalogStrings.cancel),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (coordinator.readyCount > 0 &&
              !coordinator.settings.value.autoSwitch) ...[
            const Text(IkSourceCatalogStrings.keptPolicy),
            TextButton(
              onPressed: () =>
                  unawaited(_run(context, coordinator.enableAutomaticFallback)),
              child: Text(
                coordinator.settings.preferences.customSource?.enabled == true
                    ? IkSourceCatalogStrings.enablePolicyHttp
                    : IkSourceCatalogStrings.enablePolicy,
              ),
            ),
          ],
          for (final item in coordinator.items)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ExpansionTile(
                key: ValueKey('ik-catalog-${item.entry.sourceKey}'),
                title: Text(item.entry.displayName),
                subtitle: Text(IkSourceCatalogStrings.stage(item.stage)),
                trailing: item.retryable && !coordinator.busy
                    ? IconButton(
                        tooltip: IkSourceCatalogStrings.retrySource(
                          item.entry.displayName,
                        ),
                        icon: const Icon(Icons.refresh),
                        onPressed: () => unawaited(
                          _run(
                            context,
                            () => coordinator.retry(item.entry.sourceKey),
                          ),
                        ),
                      )
                    : null,
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.message ?? IkSourceCatalogStrings.stage(item.stage),
                  ),
                  const SizedBox(height: 8),
                  Text(item.entry.licenseNote),
                  if ((item.stage == IkSourceStage.disabled ||
                          item.stage == IkSourceStage.removed) &&
                      item.entry.blockReason(coordinator.runtimeId) == null)
                    TextButton(
                      onPressed: coordinator.busy
                          ? null
                          : () => unawaited(
                              _run(
                                context,
                                () => coordinator.restore(item.entry.sourceKey),
                              ),
                            ),
                      child: const Text(IkSourceCatalogStrings.restoreAction),
                    ),
                  const SizedBox(height: 8),
                  SelectableText(
                    IkSourceCatalogStrings.fixedVersion(
                      item.entry.path,
                      item.entry.contentSha256,
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (coordinator
                          .settings
                          .managed
                          .records[item.entry.sourceKey]
                          ?.previous !=
                      null)
                    TextButton(
                      onPressed: coordinator.busy
                          ? null
                          : () => unawaited(
                              _run(
                                context,
                                () =>
                                    coordinator.rollback(item.entry.sourceKey),
                              ),
                            ),
                      child: const Text(IkSourceCatalogStrings.rollbackAction),
                    ),
                ],
              ),
            ),
          if (onManageSources != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: OutlinedButton.icon(
                onPressed: onManageSources,
                icon: const Icon(Icons.tune),
                label: const Text(IkSourceCatalogStrings.manage),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _run(BuildContext context, Future<void> Function() work) async {
    try {
      await work();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(IkSourceCatalogStrings.saveFailed)),
        );
      }
    }
  }
}

/// 包住整条管理路由；草稿保存或放弃并退出之前暂停自动发布。
class IkSourceEditingScope extends ConsumerStatefulWidget {
  const IkSourceEditingScope({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<IkSourceEditingScope> createState() =>
      _IkSourceEditingScopeState();
}

class _IkSourceEditingScopeState extends ConsumerState<IkSourceEditingScope> {
  IkSourceCatalogCoordinator? _coordinator;
  @override
  void initState() {
    super.initState();
    _coordinator = ref.read(ikSourceCatalogProvider);
    _coordinator?.suspendPublishing();
  }

  @override
  void dispose() {
    _coordinator?.resumePublishing();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

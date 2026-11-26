import 'package:flutter/material.dart';

import 'source_updater.dart';

class IkSourceWorkspaceScope extends StatefulWidget {
  const IkSourceWorkspaceScope({super.key, required this.updater, required this.child});
  final IkSourceUpdater updater;
  final Widget child;

  @override
  State<IkSourceWorkspaceScope> createState() => _IkSourceWorkspaceScopeState();
}

class _IkSourceWorkspaceScopeState extends State<IkSourceWorkspaceScope> {
  @override
  void initState() {
    super.initState();
    widget.updater.openWorkspace();
  }

  @override
  void dispose() {
    widget.updater.closeWorkspace();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class IkSourceUpdatePanel extends StatelessWidget {
  const IkSourceUpdatePanel({super.key, required this.updater});
  final IkSourceUpdater updater;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: updater,
    builder: (context, _) {
      final colors = Theme.of(context).colorScheme;
      final checked = updater.lastChecked?.toLocal();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('自动更新音源'),
            subtitle: Text(
              '每天检查一次，编辑音源或正在切歌时暂缓'
              '${checked == null ? '' : ' · 上次检查 ${checked.month}/${checked.day} ${checked.hour.toString().padLeft(2, '0')}:${checked.minute.toString().padLeft(2, '0')}'}',
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
            value: updater.autoUpdate,
            onChanged: updater.settings.writesBlocked ? null : (value) async {
              try {
                await updater.setAutoUpdate(value);
              } catch (_) {
                // 协调器保留失败信息，在面板内显示。
              }
            },
          ),
          if (updater.busy) const LinearProgressIndicator(minHeight: 2),
          if (updater.message case final String message)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 8),
              child: Text(message, style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
            ),
        ],
      );
    },
  );
}

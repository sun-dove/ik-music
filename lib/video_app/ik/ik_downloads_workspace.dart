import 'package:flutter/material.dart';

import '../../features/download/domain/entities/download_task.dart';
import '../../l10n/ik_downloads_alignment_strings.dart';
import '../../l10n/video_strings.dart';
import '../ui/catalog_pages.dart';
import '../ui/video_shell.dart';

class IkDownloadsWorkspace extends StatefulWidget {
  const IkDownloadsWorkspace({
    super.key,
    required this.tasks,
    this.queueBlockedReason,
    required this.onDirectory,
    required this.onPause,
    required this.onResume,
    required this.onResolve,
    required this.onCancel,
    required this.onPlay,
    required this.onOpenFolder,
    required this.canResolve,
    required this.actionLabel,
  });
  final List<DownloadTask> tasks;
  final String? queueBlockedReason;
  final VoidCallback onDirectory;
  final Future<void> Function(DownloadTask) onPause,
      onResume,
      onResolve,
      onCancel,
      onPlay,
      onOpenFolder;
  final bool Function(DownloadTask) canResolve;
  final String Function(DownloadTask) actionLabel;

  @override
  State<IkDownloadsWorkspace> createState() => _IkDownloadsWorkspaceState();
}

class _IkDownloadsWorkspaceState extends State<IkDownloadsWorkspace> {
  static const _groups = {
    'current': IkDownloadsAlignmentStrings.current,
    'completed': IkDownloadsAlignmentStrings.completed,
    'failed': IkDownloadsAlignmentStrings.failed,
  };
  String _group = 'current';
  String? _expanded;
  final _busy = <String>{};
  final _errors = <String, String>{};
  bool _batchBusy = false;

  String _groupFor(DownloadTask task) => switch (task.status) {
    DownloadStatus.completed => 'completed',
    DownloadStatus.failed => 'failed',
    _ => 'current',
  };

  Future<void> _run(
    DownloadTask task,
    Future<void> Function(DownloadTask) action,
  ) async {
    if (_busy.contains(task.id)) return;
    setState(() {
      _busy.add(task.id);
      _errors.remove(task.id);
    });
    try {
      await action(task);
    } catch (error) {
      if (mounted) {
        _errors[task.id] = IkDownloadsAlignmentStrings.operationFailed(error);
      }
    } finally {
      if (mounted) setState(() => _busy.remove(task.id));
    }
  }

  Future<void> _batch(
    DownloadStatus status,
    Future<void> Function(DownloadTask) action,
  ) async {
    if (_batchBusy) return;
    final ids = widget.tasks
        .where((task) => !task.isOfflineCache && task.status == status)
        .map((task) => task.id)
        .toList();
    setState(() => _batchBusy = true);
    try {
      for (final id in ids) {
        if (!mounted) return;
        final current = widget.tasks.where(
          (task) =>
              task.id == id && !task.isOfflineCache && task.status == status,
        );
        if (current.isNotEmpty) await _run(current.first, action);
      }
    } finally {
      if (mounted) setState(() => _batchBusy = false);
    }
  }

  String _status(DownloadTask task) => switch (task.status) {
    DownloadStatus.waiting => VideoStrings.waitingDownload,
    DownloadStatus.downloading => VideoStrings.downloadProgress(
      (task.progress * 100).toStringAsFixed(0),
    ),
    DownloadStatus.paused => VideoStrings.paused,
    DownloadStatus.completed => IkDownloadsAlignmentStrings.completed,
    DownloadStatus.failed => VideoStrings.downloadFailed,
  };

  @override
  Widget build(BuildContext context) {
    final manual = widget.tasks.where((task) => !task.isOfflineCache).toList();
    final visible = manual
        .where((task) => _groupFor(task) == _group)
        .toList()
        .reversed
        .toList();
    final counts = {for (final key in _groups.keys) key: 0};
    for (final task in manual) {
      counts.update(_groupFor(task), (count) => count + 1);
    }
    final canPause = manual.any(
      (task) =>
          task.status == DownloadStatus.downloading && !_busy.contains(task.id),
    );
    final canResume = manual.any(
      (task) =>
          task.status == DownloadStatus.paused && !_busy.contains(task.id),
    );
    return LayoutBuilder(
      builder: (context, size) {
        final inset = size.maxWidth < 580 ? 16.0 : 28.0;
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(inset, 24, inset, 18),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      VideoStrings.downloadManagement,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      IkDownloadsAlignmentStrings.hint,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final group in _groups.entries)
                          ChoiceChip(
                            key: ValueKey('ik-downloads-group-${group.key}'),
                            selected: _group == group.key,
                            label: Text(
                              IkDownloadsAlignmentStrings.group(
                                group.value,
                                counts[group.key]!,
                              ),
                            ),
                            onSelected: (_) => setState(() {
                              _group = group.key;
                              _expanded = null;
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          key: const ValueKey('ik-downloads-directory'),
                          onPressed: widget.onDirectory,
                          icon: const Icon(Icons.folder_outlined, size: 18),
                          label: const Text(VideoStrings.storageLocation),
                        ),
                        if (_group == 'current') ...[
                          OutlinedButton(
                            key: const ValueKey('ik-downloads-pause-all'),
                            onPressed: !_batchBusy && canPause
                                ? () => _batch(
                                    DownloadStatus.downloading,
                                    widget.onPause,
                                  )
                                : null,
                            child: const Text(
                              IkDownloadsAlignmentStrings.pauseAll,
                            ),
                          ),
                          OutlinedButton(
                            key: const ValueKey('ik-downloads-resume-all'),
                            onPressed: !_batchBusy && canResume
                                ? () => _batch(
                                    DownloadStatus.paused,
                                    widget.onResume,
                                  )
                                : null,
                            child: const Text(
                              IkDownloadsAlignmentStrings.resumeAll,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (widget.queueBlockedReason != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 18),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.errorContainer
                              .withValues(alpha: .5),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(widget.queueBlockedReason!),
                      ),
                  ],
                ),
              ),
            ),
            if (visible.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Center(
                    child: Text(switch (_group) {
                      'completed' => IkDownloadsAlignmentStrings.noCompleted,
                      'failed' => IkDownloadsAlignmentStrings.noFailed,
                      _ => VideoStrings.noDownloads,
                    }),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(inset, 0, inset, 28),
                sliver: SliverList.builder(
                  itemCount: visible.length,
                  itemBuilder: (context, index) => _taskRow(visible[index]),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _action(
    DownloadTask task,
    String name,
    String label,
    Future<void> Function(DownloadTask) action, {
    bool enabled = true,
  }) => OutlinedButton(
    key: ValueKey('ik-download-$name-${task.id}'),
    onPressed: enabled && !_busy.contains(task.id)
        ? () => _run(task, action)
        : null,
    child: Text(label),
  );

  Widget _taskRow(DownloadTask task) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final expanded = _expanded == task.id;
    final controls = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (task.status == DownloadStatus.downloading)
          _action(task, 'pause', VideoStrings.pauseDownload, widget.onPause),
        if (task.status == DownloadStatus.paused)
          _action(task, 'resume', VideoStrings.resumeDownload, widget.onResume),
        if (task.status == DownloadStatus.failed)
          _action(
            task,
            'resolve',
            widget.actionLabel(task),
            widget.onResolve,
            enabled: widget.canResolve(task),
          ),
        if (task.status == DownloadStatus.completed) ...[
          _action(
            task,
            'play',
            IkDownloadsAlignmentStrings.play,
            widget.onPlay,
          ),
          _action(
            task,
            'folder',
            IkDownloadsAlignmentStrings.openFolder,
            widget.onOpenFolder,
            enabled: task.filePath?.isNotEmpty == true,
          ),
        ] else
          _action(task, 'cancel', VideoStrings.cancelDownload, widget.onCancel),
        IconButton(
          key: ValueKey('ik-download-details-${task.id}'),
          tooltip: expanded
              ? IkDownloadsAlignmentStrings.hideDetails
              : IkDownloadsAlignmentStrings.details,
          onPressed: () =>
              setState(() => _expanded = expanded ? null : task.id),
          icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
        ),
      ],
    );
    final info = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        VideoCover(url: task.song.coverUrl, size: 44, radius: 7),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                task.song.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '${task.song.artistNames.isEmpty ? VideoStrings.unknownArtist : task.song.artistNames}'
                ' · ${task.qualityLabel}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
    return Container(
      key: ValueKey('ik-download-row-${task.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, size) {
              final wide =
                  size.maxWidth >= 680 &&
                  MediaQuery.textScalerOf(context).scale(14) <= 19;
              if (!wide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [info, const SizedBox(height: 12), controls],
                );
              }
              return Row(
                children: [
                  Expanded(child: info),
                  const SizedBox(width: 18),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: size.maxWidth * .48),
                    child: controls,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            task.error ?? _status(task),
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: task.status == DownloadStatus.failed
                  ? scheme.error
                  : scheme.onSurfaceVariant,
            ),
          ),
          if (task.status == DownloadStatus.downloading) ...[
            const SizedBox(height: 9),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: task.progress,
                minHeight: 4,
              ),
            ),
          ],
          if (_busy.contains(task.id))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                IkDownloadsAlignmentStrings.processing,
                style: TextStyle(fontSize: 12, color: scheme.primary),
              ),
            ),
          if (_errors[task.id] != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _errors[task.id]!,
                style: TextStyle(fontSize: 12, color: scheme.error),
              ),
            ),
          if (expanded) ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 14),
            Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                _detail(
                  IkDownloadsAlignmentStrings.source,
                  videoPlatformLabel(task.song.platform),
                ),
                _detail(IkDownloadsAlignmentStrings.quality, task.qualityLabel),
                _detail(
                  IkDownloadsAlignmentStrings.size,
                  IkDownloadsAlignmentStrings.transferred(
                    task.downloadedBytes,
                    task.totalBytes,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              IkDownloadsAlignmentStrings.path,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 5),
            SelectableText(
              task.filePath?.isNotEmpty == true
                  ? task.filePath!
                  : task.status == DownloadStatus.completed
                  ? VideoStrings.downloadMissing
                  : IkDownloadsAlignmentStrings.pathPending,
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _detail(String label, String value) =>
      Text('$label · $value', style: Theme.of(context).textTheme.bodySmall);
}

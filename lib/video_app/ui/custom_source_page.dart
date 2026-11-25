import 'dart:convert';

import 'package:flutter/material.dart';

import '../../l10n/expanded_strings.dart';
import '../../l10n/source_strings.dart';
import '../../l10n/video_strings.dart';
import '../../models/platform_type.dart';
import '../custom_source/custom_source_models.dart';
import '../ik/ik_workspace_navigation.dart';

enum VideoCustomSourceTestStatus {
  success,
  unauthorized,
  incompatible,
  timeout,
  unavailable,
}

class VideoCustomSourceTestResult {
  const VideoCustomSourceTestResult._(this.status);
  const VideoCustomSourceTestResult.success()
    : this._(VideoCustomSourceTestStatus.success);
  const VideoCustomSourceTestResult.unauthorized()
    : this._(VideoCustomSourceTestStatus.unauthorized);
  const VideoCustomSourceTestResult.incompatible()
    : this._(VideoCustomSourceTestStatus.incompatible);
  const VideoCustomSourceTestResult.timeout()
    : this._(VideoCustomSourceTestStatus.timeout);
  const VideoCustomSourceTestResult.unavailable()
    : this._(VideoCustomSourceTestStatus.unavailable);

  final VideoCustomSourceTestStatus status;

  String get message => switch (status) {
    VideoCustomSourceTestStatus.success => VideoStrings.customSourceConnected,
    VideoCustomSourceTestStatus.unauthorized =>
      VideoStrings.customSourceUnauthorized,
    VideoCustomSourceTestStatus.incompatible =>
      VideoStrings.customSourceIncompatible,
    VideoCustomSourceTestStatus.timeout => VideoStrings.customSourceTimedOut,
    VideoCustomSourceTestStatus.unavailable =>
      VideoStrings.customSourceUnavailable,
  };
}

class VideoCustomSourceDraft {
  const VideoCustomSourceDraft({
    this.name = '',
    this.endpoint = '',
    this.platforms = const {},
    this.timeoutSeconds = 10,
    this.token = '',
    this.allowForDownloads = false,
    this.enabled = false,
  });

  final String name;
  final String endpoint;
  final Set<PlatformType> platforms;
  final int timeoutSeconds;
  final String token;
  final bool allowForDownloads;
  final bool enabled;
}

class VideoCustomSourcePage extends StatefulWidget {
  const VideoCustomSourcePage({
    super.key,
    this.initialDraft = const VideoCustomSourceDraft(),
    required this.onTest,
    required this.onSave,
    this.onDelete,
    this.protectWorkspaceDraft = false,
    this.onCommit,
    this.onRemove,
  });

  static const nameFieldKey = ValueKey('custom-source-name');
  static const endpointFieldKey = ValueKey('custom-source-endpoint');
  static const tokenFieldKey = ValueKey('custom-source-token');
  static const timeoutFieldKey = ValueKey('custom-source-timeout');
  static const qqSwitchKey = ValueKey('custom-source-qq');
  static const neteaseSwitchKey = ValueKey('custom-source-netease');
  static const downloadSwitchKey = ValueKey('custom-source-download');
  static const enabledSwitchKey = ValueKey('custom-source-enabled');

  final VideoCustomSourceDraft initialDraft;
  final Future<VideoCustomSourceTestResult> Function(
    VideoCustomSourceDraft draft,
  )
  onTest;
  final Future<void> Function(VideoCustomSourceDraft draft) onSave;
  final Future<void> Function()? onDelete;
  final bool protectWorkspaceDraft;
  final Future<bool> Function(VideoCustomSourceDraft draft)? onCommit;
  final Future<bool> Function()? onRemove;

  @override
  State<VideoCustomSourcePage> createState() => _VideoCustomSourcePageState();
}

class _VideoCustomSourcePageState extends State<VideoCustomSourcePage> {
  late final TextEditingController _name;
  late final TextEditingController _endpoint;
  late final TextEditingController _token;
  late final TextEditingController _timeout;
  late Set<PlatformType> _platforms;
  late bool _downloads;
  late bool _enabled;
  late String _saved;
  bool _busy = false, _leaving = false;
  IkWorkspaceNavigation? _workspaceNavigation;
  Future<bool>? _pendingLeave;
  String? _result;
  bool get _locked => widget.protectWorkspaceDraft && _busy;
  bool get _dirty => _snapshot != _saved;
  String get _snapshot => jsonEncode([
    _name.text,
    _endpoint.text,
    _token.text,
    _timeout.text,
    _platforms.map((value) => value.index).toList()..sort(),
    _downloads,
    _enabled,
  ]);

  @override
  void initState() {
    super.initState();
    final draft = widget.initialDraft;
    _name = TextEditingController(text: draft.name);
    _endpoint = TextEditingController(text: draft.endpoint);
    _token = TextEditingController(text: draft.token);
    _timeout = TextEditingController(text: draft.timeoutSeconds.toString());
    _platforms = {...draft.platforms};
    _downloads = draft.allowForDownloads;
    _enabled = draft.enabled;
    _saved = _snapshot;
    for (final controller in [_name, _endpoint, _token, _timeout]) {
      controller.addListener(_edited);
    }
  }

  void _edited() {
    if (widget.protectWorkspaceDraft) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindWorkspaceNavigation();
  }

  @override
  void didUpdateWidget(covariant VideoCustomSourcePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.protectWorkspaceDraft != widget.protectWorkspaceDraft) {
      _bindWorkspaceNavigation();
    }
  }

  void _bindWorkspaceNavigation() {
    final navigation = widget.protectWorkspaceDraft
        ? IkWorkspaceNavigation.maybeOf(context)
        : null;
    if (identical(navigation, _workspaceNavigation)) return;
    _workspaceNavigation?.unregister(this);
    _workspaceNavigation = navigation;
    navigation?.register(this, _confirmLeave);
  }

  @override
  void dispose() {
    _workspaceNavigation?.unregister(this);
    _name.dispose();
    _endpoint.dispose();
    _token.dispose();
    _timeout.dispose();
    super.dispose();
  }

  VideoCustomSourceDraft get _draft => VideoCustomSourceDraft(
    name: _name.text.trim(),
    endpoint: _endpoint.text.trim(),
    token: _token.text,
    timeoutSeconds: int.tryParse(_timeout.text) ?? 10,
    platforms: {..._platforms},
    allowForDownloads: _downloads,
    enabled: _enabled,
  );

  void _setPlatform(PlatformType platform, bool enabled) => setState(() {
    enabled ? _platforms.add(platform) : _platforms.remove(platform);
  });

  Future<bool> _confirmLeave() {
    if (_busy) return Future.value(false);
    return _pendingLeave ??= _checkLeave().whenComplete(
      () => _pendingLeave = null,
    );
  }

  Future<bool> _checkLeave() async {
    if (!mounted) return false;
    if (!_dirty) return true;
    final choice = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text(ExpandedStrings.dirty),
        content: const Text(ExpandedStrings.saveToApply),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, 'cancel'),
            child: const Text(ExpandedStrings.keepEditing),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, 'discard'),
            child: const Text(ExpandedStrings.discard),
          ),
          FilledButton(
            onPressed: widget.onCommit == null
                ? null
                : () => Navigator.pop(dialog, 'save'),
            child: const Text(ExpandedStrings.saveAndReturn),
          ),
        ],
      ),
    );
    if (!mounted || choice == null || choice == 'cancel') return false;
    return choice != 'save' || await _commit(close: false);
  }

  Future<void> _return() async {
    if (_busy) return;
    final route = ModalRoute.of(context);
    if (await _confirmLeave()) _closeCurrent(route);
  }

  void _closeCurrent(ModalRoute<Object?>? route) {
    if (!mounted || route?.isCurrent != true) return;
    setState(() => _leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (route?.isCurrent == true) {
        Navigator.of(context).pop();
      } else {
        setState(() => _leaving = false);
      }
    });
  }

  Future<bool> _commit({bool close = true}) async {
    if (_busy || widget.onCommit == null) return false;
    final route = ModalRoute.of(context);
    final snapshot = _snapshot;
    final draft = _draft;
    setState(() {
      _busy = true;
      _result = null;
    });
    var saved = false;
    try {
      saved = await widget.onCommit!(draft);
      if (mounted) {
        setState(() {
          if (saved) _saved = snapshot;
          _result = saved ? ExpandedStrings.saved : ExpandedStrings.saveFailed;
        });
      }
    } on CustomSourceConfigurationException catch (error) {
      if (mounted) setState(() => _result = error.message);
    } catch (_) {
      if (mounted) setState(() => _result = ExpandedStrings.saveFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return false;
    if (saved && close) _closeCurrent(route);
    return saved;
  }

  Future<void> _remove() async {
    if (_busy || widget.onRemove == null) return;
    final route = ModalRoute.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(VideoStrings.customSourceDeleteNamed(_name.text)),
        content: const Text(VideoStrings.customSourceDeleteEffect),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text(VideoStrings.customSourceCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text(VideoStrings.customSourceConfirmDelete),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || _busy) return;
    setState(() {
      _busy = true;
      _result = null;
    });
    var removed = false;
    try {
      removed = await widget.onRemove!();
      if (mounted) {
        setState(() {
          if (removed) _saved = _snapshot;
          _result = removed ? null : SourceStrings.operationFailed;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _result = SourceStrings.operationFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (removed) _closeCurrent(route);
  }

  Future<void> _testConnection() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final result = await widget.onTest(_draft);
      if (mounted) setState(() => _result = result.message);
    } catch (_) {
      if (mounted) {
        setState(() => _result = VideoStrings.customSourceUnavailable);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _page();
    if (!widget.protectWorkspaceDraft) return page;
    return PopScope(
      canPop: !_busy && (_leaving || !_dirty),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _return();
      },
      child: page,
    );
  }

  Widget _page() => Scaffold(
    appBar: AppBar(
      title: const Text(VideoStrings.customSource),
      leading: widget.protectWorkspaceDraft
          ? BackButton(onPressed: _return)
          : null,
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: VideoCustomSourcePage.nameFieldKey,
              controller: _name,
              enabled: _locked ? false : null,
              decoration: const InputDecoration(
                labelText: VideoStrings.customSourceName,
              ),
            ),
            TextField(
              key: VideoCustomSourcePage.endpointFieldKey,
              controller: _endpoint,
              enabled: _locked ? false : null,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: VideoStrings.customSourceHttpsAddress,
              ),
            ),
            SwitchListTile(
              key: VideoCustomSourcePage.qqSwitchKey,
              title: const Text(VideoStrings.qqMusic),
              value: _platforms.contains(PlatformType.qq),
              onChanged: _locked
                  ? null
                  : (value) => _setPlatform(PlatformType.qq, value),
            ),
            SwitchListTile(
              key: VideoCustomSourcePage.neteaseSwitchKey,
              title: const Text(VideoStrings.netease),
              value: _platforms.contains(PlatformType.netease),
              onChanged: _locked
                  ? null
                  : (value) => _setPlatform(PlatformType.netease, value),
            ),
            TextField(
              key: VideoCustomSourcePage.timeoutFieldKey,
              controller: _timeout,
              enabled: _locked ? false : null,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: VideoStrings.customSourceTimeout,
              ),
            ),
            TextField(
              key: VideoCustomSourcePage.tokenFieldKey,
              controller: _token,
              enabled: _locked ? false : null,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: VideoStrings.customSourceToken,
              ),
            ),
            SwitchListTile(
              key: VideoCustomSourcePage.downloadSwitchKey,
              title: const Text(VideoStrings.customSourceAllowDownloads),
              value: _downloads,
              onChanged: _locked
                  ? null
                  : (value) => setState(() => _downloads = value),
            ),
            SwitchListTile(
              key: VideoCustomSourcePage.enabledSwitchKey,
              title: const Text(VideoStrings.customSourceEnable),
              value: _enabled,
              onChanged: _locked
                  ? null
                  : (value) => setState(() => _enabled = value),
            ),
            const Text(VideoStrings.customSourcePrivacy),
            const Text(VideoStrings.customSourceAccuracy),
            if (_result != null) ...[
              const SizedBox(height: 12),
              Text(_result!),
            ],
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: widget.protectWorkspaceDraft
                  ? (_busy ? null : _testConnection)
                  : () async {
                      final result = await widget.onTest(_draft);
                      if (mounted) setState(() => _result = result.message);
                    },
              child: const Text(VideoStrings.customSourceTest),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: widget.protectWorkspaceDraft
                  ? (_busy || widget.onCommit == null ? null : () => _commit())
                  : () => widget.onSave(_draft),
              child: const Text(VideoStrings.customSourceSave),
            ),
            if (widget.onDelete != null ||
                (widget.protectWorkspaceDraft && widget.onRemove != null)) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: widget.protectWorkspaceDraft
                    ? (_busy || widget.onRemove == null ? null : _remove)
                    : () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(
                              VideoStrings.customSourceDeleteNamed(_name.text),
                            ),
                            content: const Text(
                              VideoStrings.customSourceDeleteEffect,
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text(
                                  VideoStrings.customSourceCancel,
                                ),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text(
                                  VideoStrings.customSourceConfirmDelete,
                                ),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) await widget.onDelete!();
                      },
                child: const Text(VideoStrings.customSourceDelete),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

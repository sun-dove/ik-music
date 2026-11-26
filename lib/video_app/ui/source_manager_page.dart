import '../../l10n/expanded_strings.dart';

import 'dart:convert';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/source_strings.dart';
import '../../l10n/ik_source_workspace_strings.dart';
import '../ik/ik_workspace_navigation.dart';
import '../lx_source/lx_source.dart';
import '../multi_source/source_checks.dart';
import '../multi_source/source_collection.dart';

class SourceManagerPage extends StatefulWidget {
  const SourceManagerPage({
    super.key,
    required this.initial,
    required this.onImport,
    required this.onInspect,
    required this.onSave,
    required this.onHttp,
    this.warning,
    this.initialChecks = const {},
    this.onChecksChanged,
    this.runtimeId = 'lx3',
    this.modernPolicyMenu = false,
    this.embedded = false,
    this.refinedLayout = false,
    this.catalogPanel,
    this.onCheckUpdates,
    this.onUpdateAll,
    this.onUpdateEntry,
    this.updateStatus,
    this.keepBackgroundDraft = false,
    this.backgroundBusy = false,
    this.backgroundDirty = false,
    this.onDraftChanged,
    this.onBackgroundCheck,
    this.onBackgroundUpdateAll,
    this.onBackgroundUpdateEntry,
    this.onCancelBackground,
  });
  final SourceCollection initial;
  final Future<LxSourceConfig> Function(String, CancelToken) onImport;
  final Future<void> Function(LxSourceConfig, CancelToken) onInspect;
  final Future<void> Function(SourceCollection) onSave;
  final VoidCallback onHttp;
  final String? warning;
  final Map<String, SourceCheckRecord> initialChecks;
  final Future<void> Function(Map<String, SourceCheckRecord>)? onChecksChanged;
  final String runtimeId;
  final bool modernPolicyMenu;
  final bool embedded, refinedLayout;
  final Widget? catalogPanel;
  final Future<void> Function(SourceCollection, CancelToken)? onCheckUpdates;
  final Future<SourceCollection> Function(SourceCollection, CancelToken)?
      onUpdateAll;
  final Future<LxSourceConfig> Function(SourceEntry, CancelToken)? onUpdateEntry;
  final String? Function(SourceEntry)? updateStatus;
  final bool keepBackgroundDraft, backgroundBusy, backgroundDirty;
  final ValueChanged<SourceCollection>? onDraftChanged;
  final Future<void> Function(SourceCollection)? onBackgroundCheck, onBackgroundUpdateAll;
  final Future<void> Function(SourceEntry)? onBackgroundUpdateEntry;
  final VoidCallback? onCancelBackground;
  @override
  State<SourceManagerPage> createState() => _SourceManagerPageState();
}

enum _SourceAction { prefer, inspect, update, downloads, up, down, remove }

class _SourceManagerPageState extends State<SourceManagerPage> {
  late SourceCollection _value = widget.initial;
  late String _saved = jsonEncode(widget.initial.toJson());
  late SourceCollection _savedValue = widget.initial;
  late final _checks = Map<String, SourceCheckRecord>.of(widget.initialChecks);
  final _search = TextEditingController();
  final _link = TextEditingController();
  final _notChecked = <String>{};
  final _policyMenu = MenuController();
  final _policyFocus = FocusNode();
  final _policyOptions = [FocusNode(), FocusNode()];
  IkWorkspaceNavigation? _workspaceNavigation;
  Future<bool>? _pendingLeave;
  CancelToken? _token;
  String _platform = 'all';
  bool _enabledOnly = false, _busy = false, _leaving = false;
  String? _message, _runningId;
  bool get _dirty => jsonEncode(_value.toJson()) != _saved;
  bool get _operationBusy => _busy || widget.backgroundBusy;

  @override
  void setState(VoidCallback fn) {
    final before = _value;
    super.setState(fn);
    if (widget.keepBackgroundDraft && !identical(before, _value)) {
      widget.onDraftChanged?.call(_value);
    }
  }
  bool get _filtered =>
      _search.text.trim().isNotEmpty || _platform != 'all' || _enabledOnly;
  List<SourceEntry> get _visible => _value.entries
      .where(
        (entry) =>
            (!_enabledOnly || entry.config.enabled) &&
            (_platform == 'all' ||
                entry.config.sources.containsKey(_platform)) &&
            entry.config.name.toLowerCase().contains(
              _search.text.trim().toLowerCase(),
            ),
      )
      .toList();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindWorkspaceNavigation();
  }

  @override
  void didUpdateWidget(covariant SourceManagerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.keepBackgroundDraft && !identical(widget.initial, _value)) {
      _value = widget.initial;
    }
    if (oldWidget.modernPolicyMenu != widget.modernPolicyMenu ||
        oldWidget.embedded != widget.embedded) {
      _bindWorkspaceNavigation();
    }
  }

  void _bindWorkspaceNavigation() {
    final navigation = widget.modernPolicyMenu || widget.embedded
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
    _token?.cancel();
    _search.dispose();
    _link.dispose();
    _policyFocus.dispose();
    for (final focus in _policyOptions) {
      focus.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function(CancelToken) work) async {
    if (_operationBusy) return;
    final token = CancelToken();
    _token = token;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await work(token);
    } on LxSourceException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) setState(() => _message = SourceStrings.operationFailed);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _runningId = null;
        });
      }
    }
  }

  Future<bool> _save() async {
    if (_operationBusy) return false;
    var saved = false;
    await _run((_) async {
      try {
        await widget.onSave(_value);
      } catch (_) {
        if (mounted) setState(() => _message = ExpandedStrings.saveFailed);
        return;
      }
      if (!mounted) return;
      setState(() {
        _saved = jsonEncode(_value.toJson());
        _savedValue = _value;
        _message = ExpandedStrings.saved;
      });
      saved = true;
    });
    return saved;
  }

  Future<bool> _confirmLeave() =>
      _pendingLeave ??= _checkLeave().whenComplete(() => _pendingLeave = null);

  Future<bool> _checkLeave() async {
    if (_policyMenu.isOpen) _policyMenu.close();
    if (!mounted) return false;
    if (_busy) {
      if (widget.embedded || widget.refinedLayout) {
        setState(() => _message = IkSourceWorkspaceStrings.busyLeave);
      }
      return false;
    }
    if (widget.keepBackgroundDraft) return true;
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
            onPressed: () => Navigator.pop(dialog, 'save'),
            child: const Text(ExpandedStrings.saveAndReturn),
          ),
        ],
      ),
    );
    if (!mounted || choice == null || choice == 'cancel') return false;
    if (choice == 'discard' && widget.embedded) {
      setState(() {
        _value = _savedValue;
        _message = null;
      });
    }
    return choice != 'save' || await _save();
  }

  Future<void> _return() async {
    if (widget.embedded) {
      await _returnFromEmbedded();
      return;
    }
    final route = widget.modernPolicyMenu ? ModalRoute.of(context) : null;
    if (widget.modernPolicyMenu && _policyMenu.isOpen) {
      _policyMenu.close();
      return;
    }
    if (_busy) {
      _token?.cancel();
      return;
    }
    if (widget.modernPolicyMenu) {
      if (!await _confirmLeave()) return;
    } else if (_dirty) {
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
              onPressed: () => Navigator.pop(dialog, 'save'),
              child: const Text(ExpandedStrings.saveAndReturn),
            ),
          ],
        ),
      );
      if (choice == null || choice == 'cancel') return;
      if (choice == 'save' && !await _save()) return;
    }
    if (!mounted) return;
    if (widget.modernPolicyMenu && route?.isCurrent != true) return;
    setState(() => _leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!widget.modernPolicyMenu || route?.isCurrent == true) {
        Navigator.pop(context);
      } else {
        setState(() => _leaving = false);
      }
    });
  }

  Future<void> _returnFromEmbedded() async {
    if (_policyMenu.isOpen) {
      _policyMenu.close();
      return;
    }
    if (_busy) {
      _token?.cancel();
      return;
    }
    final route = ModalRoute.of(context);
    final navigator = Navigator.of(context);
    if (!await _confirmLeave() || !mounted) return;
    if (route?.isCurrent != true || !navigator.canPop()) return;
    setState(() => _leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (route?.isCurrent == true && navigator.canPop()) {
        final popped = await navigator.maybePop();
        if (!popped && mounted) setState(() => _leaving = false);
      } else {
        setState(() => _leaving = false);
      }
    });
  }

  Future<void> _record(
    SourceEntry entry,
    String outcome, {
    String? code,
    String? message,
  }) async {
    _checks[entry.id] = SourceCheckRecord(
      entryId: entry.id,
      scriptSha256: entry.config.sha256,
      runtimeId: widget.runtimeId,
      outcome: outcome,
      checkedAt: DateTime.now(),
      errorCode: code,
      message: message,
    );
    _notChecked.remove(entry.id);
    if (mounted) setState(() {});
    try {
      await widget.onChecksChanged?.call(Map.of(_checks));
    } catch (_) {
      if (mounted) setState(() => _message = ExpandedStrings.checkSaveFailed);
    }
  }

  Future<void> _import([String? origin]) => _run((token) async {
    final config = await widget.onImport(origin ?? _link.text.trim(), token);
    if (!mounted || token.isCancelled) return;
    setState(() {
      _value = _value.upsert(config);
      _message = SourceStrings.imported;
    });
    final entry = _value.entries.firstWhere(
      (entry) => entry.config.origin == config.origin,
    );
    await _record(entry, 'initialized');
  });

  Future<void> _checkUpdates() => _run((token) async {
    await widget.onCheckUpdates!(_value, token);
  });

  Future<void> _updateAll() => _run((token) async {
    final value = await widget.onUpdateAll!(_value, token);
    if (!mounted) return;
    setState(() {
      _value = value;
      _message = token.isCancelled
          ? IkSourceWorkspaceStrings.cancelledDraft
          : IkSourceWorkspaceStrings.draftUpdated;
    });
  });

  Future<void> _updateEntry(SourceEntry entry) => _run((token) async {
    final config = await widget.onUpdateEntry!(entry, token);
    if (!mounted || token.isCancelled) return;
    setState(() {
      _value = _value.replace(entry.id, config);
      _message = IkSourceWorkspaceStrings.draftUpdated;
    });
    await _record(SourceEntry(entry.id, config), 'initialized');
  });

  Future<void> _inspect(List<SourceEntry> entries) => _run((token) async {
    var completed = 0, failures = 0;
    setState(() {
      _notChecked.addAll(entries.map((entry) => entry.id));
    });
    for (final entry in entries) {
      if (!mounted || token.isCancelled) break;
      setState(() {
        _runningId = entry.id;
        _message = ExpandedStrings.checkProgress(completed, entries.length);
      });
      try {
        await widget.onInspect(entry.config, token);
        if (!mounted || token.isCancelled) break;
        await _record(entry, 'initialized');
      } on LxSourceException catch (error) {
        if (!mounted) return;
        if (token.isCancelled || error.code == 'cancelled') break;
        failures++;
        await _record(
          entry,
          'failed',
          code: error.code,
          message: error.message,
        );
      } catch (_) {
        if (!mounted || token.isCancelled) break;
        failures++;
        await _record(
          entry,
          'failed',
          code: 'unknown',
          message: ExpandedStrings.checkFailed,
        );
      }
      completed++;
    }
    if (mounted) {
      setState(
        () => _message = ExpandedStrings.checkSummary(
          token.isCancelled,
          completed,
          entries.length,
          failures,
        ),
      );
    }
  });

  String _status(SourceEntry entry) {
    if (_runningId == entry.id) return ExpandedStrings.checking;
    if (_notChecked.contains(entry.id)) return ExpandedStrings.notCheckedNow;
    final record = _checks[entry.id];
    if (record == null || !record.applies(entry, widget.runtimeId)) {
      return ExpandedStrings.notChecked;
    }
    final time = record.checkedAt.toLocal();
    final stamp =
        '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    return '${record.outcome == 'initialized' ? SourceStrings.inspectPassed : ExpandedStrings.initializedFailed(record.message ?? ExpandedStrings.retryShort)} · $stamp';
  }

  Future<void> _action(SourceEntry entry, _SourceAction action) async {
    switch (action) {
      case _SourceAction.inspect:
        await _inspect([entry]);
      case _SourceAction.update:
        if (widget.onBackgroundUpdateEntry != null) {
          unawaited(widget.onBackgroundUpdateEntry!(entry));
        } else if (widget.onUpdateEntry != null) {
          await _updateEntry(entry);
        } else {
          await _import(entry.config.origin.toString());
        }
      case _SourceAction.prefer:
        setState(() => _value = _value.prefer(entry.id));
      case _SourceAction.downloads:
        setState(
          () => _value = _value.replace(
            entry.id,
            entry.config.copyWith(
              allowForDownloads: !entry.config.allowForDownloads,
            ),
          ),
        );
      case _SourceAction.up:
        setState(() => _value = _value.move(entry.id, -1));
      case _SourceAction.down:
        setState(() => _value = _value.move(entry.id, 1));
      case _SourceAction.remove:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: Text(SourceStrings.deleteNamed(entry.config.name)),
            content: const Text(SourceStrings.saveToApply),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text(ExpandedStrings.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text(ExpandedStrings.delete),
              ),
            ],
          ),
        );
        if (confirmed == true && mounted) {
          setState(() => _value = _value.remove(entry.id));
        }
    }
  }

  static const _platformNames = {
    'all': ExpandedStrings.allPlatforms,
    'tx': ExpandedStrings.qq,
    'wy': ExpandedStrings.netease,
    'kg': ExpandedStrings.kugou,
  };

  Widget _modernPolicy() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            const Text(SourceStrings.playOrder),
            _policySelect(),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(
                      () => _value = _value.copyWith(
                        autoSwitch: true,
                        sourceFirst: true,
                        highestQuality: true,
                      ),
                    ),
              child: const Text(SourceStrings.recommended),
            ),
          ],
        ),
      ),
      SwitchListTile(
        key: const ValueKey('manager-auto-switch'),
        contentPadding: EdgeInsets.zero,
        title: const Text(SourceStrings.autoSwitch),
        subtitle: const Text(SourceStrings.autoSwitchHint),
        value: _value.autoSwitch,
        onChanged: _busy
            ? null
            : (value) =>
                  setState(() => _value = _value.copyWith(autoSwitch: value)),
      ),
      SwitchListTile(
        key: const ValueKey('manager-highest'),
        contentPadding: EdgeInsets.zero,
        title: const Text(SourceStrings.highest),
        subtitle: const Text(SourceStrings.highestSourceHint),
        value: _value.highestQuality,
        onChanged: _busy
            ? null
            : (value) => setState(
                () => _value = _value.copyWith(highestQuality: value),
              ),
      ),
      const SizedBox(height: 12),
    ],
  );

  Widget _policySelect() {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 232),
      child: LayoutBuilder(
        builder: (context, constraints) => MenuAnchor(
          controller: _policyMenu,
          childFocusNode: _policyFocus,
          crossAxisUnconstrained: false,
          onOpen: () => setState(() {}),
          onClose: () {
            if (mounted) setState(() {});
          },
          alignmentOffset: const Offset(0, 6),
          style: MenuStyle(
            fixedSize: WidgetStatePropertyAll(
              Size.fromWidth(constraints.maxWidth),
            ),
            elevation: const WidgetStatePropertyAll(8),
            backgroundColor: WidgetStatePropertyAll(theme.colorScheme.surface),
            surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
            padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
          ),
          menuChildren: [
            for (final sourceFirst in [false, true])
              Semantics(
                selected: _value.sourceFirst == sourceFirst,
                child: MenuItemButton(
                  key: ValueKey('manager-policy-option-$sourceFirst'),
                  focusNode: _policyOptions[sourceFirst ? 1 : 0],
                  onPressed: _busy
                      ? null
                      : () {
                          setState(
                            () => _value = _value.copyWith(
                              sourceFirst: sourceFirst,
                            ),
                          );
                          _policyFocus.requestFocus();
                        },
                  trailingIcon: _value.sourceFirst == sourceFirst
                      ? Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: theme.colorScheme.primary,
                        )
                      : const SizedBox(width: 18),
                  style: ButtonStyle(
                    minimumSize: const WidgetStatePropertyAll(Size(0, 62)),
                    padding: const WidgetStatePropertyAll(EdgeInsets.all(10)),
                    backgroundColor: _value.sourceFirst == sourceFirst
                        ? WidgetStatePropertyAll(
                            theme.colorScheme.primary.withValues(alpha: .09),
                          )
                        : null,
                    foregroundColor: _value.sourceFirst == sourceFirst
                        ? WidgetStatePropertyAll(theme.colorScheme.primary)
                        : null,
                    shape: WidgetStatePropertyAll(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sourceFirst
                            ? SourceStrings.customFirst
                            : ExpandedStrings.officialFirst,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        sourceFirst
                            ? SourceStrings.sourceFirstHint
                            : SourceStrings.officialFirstHint,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          builder: (context, controller, _) => Focus(
            canRequestFocus: false,
            onKeyEvent: (_, event) {
              if (!_busy &&
                  event is KeyDownEvent &&
                  (event.logicalKey == LogicalKeyboardKey.arrowDown ||
                      event.logicalKey == LogicalKeyboardKey.arrowUp)) {
                controller.open();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && controller.isOpen) {
                    _policyOptions[_value.sourceFirst ? 1 : 0].requestFocus();
                  }
                });
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Semantics(
              label: SourceStrings.playOrder,
              child: OutlinedButton(
                key: const ValueKey('manager-policy-trigger'),
                focusNode: _policyFocus,
                onPressed: _busy
                    ? null
                    : () => controller.isOpen
                          ? controller.close()
                          : controller.open(),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 42),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  backgroundColor: theme.colorScheme.surface,
                  foregroundColor: theme.colorScheme.onSurface,
                  side: BorderSide(
                    color: controller.isOpen
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: theme.textTheme.labelLarge?.copyWith(fontSize: 13),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _value.sourceFirst
                            ? SourceStrings.customFirst
                            : ExpandedStrings.officialFirst,
                      ),
                    ),
                    const SizedBox(width: 12),
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
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.refinedLayout || widget.embedded) return _refinedPage();
    final entries = _visible;
    return PopScope(
      canPop:
          !(widget.modernPolicyMenu && _policyMenu.isOpen) &&
          (_leaving || (!_dirty && !_busy)),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _return();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(ExpandedStrings.managerTitle),
          leading: BackButton(onPressed: _return),
          actions: [
            IconButton(
              tooltip: ExpandedStrings.httpSettings,
              onPressed: _busy || _dirty ? null : widget.onHttp,
              icon: const Icon(Icons.settings_ethernet),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: CustomScrollView(
                  key: const ValueKey('manager-scroll'),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  SourceStrings.sourceCount(
                                    _value.entries.length,
                                    _value.enabled.length,
                                  ),
                                ),
                                if (widget.warning != null)
                                  Text(widget.warning!),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _link,
                                        enabled: !_busy,
                                        keyboardType: TextInputType.url,
                                        decoration: const InputDecoration(
                                          labelText: ExpandedStrings.scriptLink,
                                          hintText: 'https://…/latest.js',
                                          isDense: true,
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton.filled(
                                      tooltip: ExpandedStrings.importLink,
                                      onPressed: _busy ? null : () => _import(),
                                      icon: const Icon(Icons.add_link),
                                    ),
                                  ],
                                ),
                                if (widget.modernPolicyMenu)
                                  _modernPolicy()
                                else
                                  ExpansionTile(
                                    tilePadding: EdgeInsets.zero,
                                    title: const Text(
                                      ExpandedStrings.playPolicy,
                                    ),
                                    subtitle: Text(
                                      '${_value.sourceFirst ? ExpandedStrings.sourceFirst : ExpandedStrings.officialFirst} · ${_value.highestQuality ? ExpandedStrings.highest : ExpandedStrings.fixed}',
                                    ),
                                    children: [
                                      TextButton(
                                        onPressed: _busy
                                            ? null
                                            : () => setState(
                                                () => _value = _value.copyWith(
                                                  autoSwitch: true,
                                                  sourceFirst: true,
                                                  highestQuality: true,
                                                ),
                                              ),
                                        child: const Text(
                                          SourceStrings.recommended,
                                        ),
                                      ),
                                      SwitchListTile(
                                        title: const Text(
                                          SourceStrings.autoSwitch,
                                        ),
                                        value: _value.autoSwitch,
                                        onChanged: _busy
                                            ? null
                                            : (value) => setState(
                                                () => _value = _value.copyWith(
                                                  autoSwitch: value,
                                                ),
                                              ),
                                      ),
                                      SwitchListTile(
                                        title: const Text(
                                          SourceStrings.sourceFirst,
                                        ),
                                        value: _value.sourceFirst,
                                        onChanged: _busy
                                            ? null
                                            : (value) => setState(
                                                () => _value = _value.copyWith(
                                                  sourceFirst: value,
                                                ),
                                              ),
                                      ),
                                      SwitchListTile(
                                        title: const Text(
                                          SourceStrings.highest,
                                        ),
                                        subtitle: const Text(
                                          SourceStrings.highestSourceHint,
                                        ),
                                        value: _value.highestQuality,
                                        onChanged: _busy
                                            ? null
                                            : (value) => setState(
                                                () => _value = _value.copyWith(
                                                  highestQuality: value,
                                                ),
                                              ),
                                      ),
                                    ],
                                  ),
                                TextField(
                                  key: const ValueKey('manager-search'),
                                  controller: _search,
                                  enabled: !_busy,
                                  onChanged: (_) => setState(() {}),
                                  decoration: InputDecoration(
                                    hintText: ExpandedStrings.searchName,
                                    isDense: true,
                                    prefixIcon: const Icon(Icons.search),
                                    suffixIcon: _search.text.isEmpty
                                        ? null
                                        : IconButton(
                                            tooltip:
                                                ExpandedStrings.clearSearch,
                                            onPressed: () =>
                                                setState(() => _search.clear()),
                                            icon: const Icon(Icons.clear),
                                          ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 2,
                                  children: [
                                    for (final entry in _platformNames.entries)
                                      ChoiceChip(
                                        key: ValueKey(
                                          'manager-platform-${entry.key}',
                                        ),
                                        label: Text(entry.value),
                                        selected: _platform == entry.key,
                                        onSelected: _busy
                                            ? null
                                            : (_) => setState(
                                                () => _platform = entry.key,
                                              ),
                                      ),
                                    FilterChip(
                                      label: const Text(
                                        ExpandedStrings.enabled,
                                      ),
                                      selected: _enabledOnly,
                                      onSelected: _busy
                                          ? null
                                          : (value) => setState(
                                              () => _enabledOnly = value,
                                            ),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _filtered
                                            ? ExpandedStrings.filterCount(
                                                entries.length,
                                              )
                                            : ExpandedStrings.orderHint,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ),
                                    TextButton(
                                      key: const ValueKey(
                                        'manager-inspect-all',
                                      ),
                                      onPressed: _busy || entries.isEmpty
                                          ? null
                                          : () => _inspect(entries),
                                      child: const Text(
                                        ExpandedStrings.inspectList,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (_busy) const LinearProgressIndicator(),
                          if (_message != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              child: Text(
                                _message!,
                                key: const ValueKey('manager-message'),
                              ),
                            ),
                          if (_busy)
                            TextButton(
                              onPressed: () => _token?.cancel(),
                              child: const Text(
                                ExpandedStrings.cancelOperation,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (entries.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Text(
                            _value.entries.isEmpty
                                ? SourceStrings.empty
                                : ExpandedStrings.noMatches,
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        sliver: SliverReorderableList(
                          itemCount: entries.length,
                          onReorderItem: (from, to) {
                            if (_busy || _filtered) return;
                            setState(
                              () => _value = _value.move(
                                entries[from].id,
                                to - from,
                              ),
                            );
                          },
                          itemBuilder: (context, index) =>
                              _row(entries[index], index),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _dirty
                            ? ExpandedStrings.dirty
                            : ExpandedStrings.settingsSaved,
                      ),
                    ),
                    FilledButton.icon(
                      key: const ValueKey('manager-save'),
                      onPressed: _busy ? null : _save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text(ExpandedStrings.saveSettings),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _refinedPage() {
    final entries = _visible;
    final body = LayoutBuilder(
      builder: (context, size) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: size.maxHeight * .48),
            child: SingleChildScrollView(child: _refinedToolbar()),
          ),
          const SizedBox(height: 12),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          if (_message != null)
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: size.maxHeight * .18),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Text(
                    _message!,
                    key: const ValueKey('manager-message'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ),
        Expanded(
          child: CustomScrollView(
            key: const ValueKey('manager-scroll'),
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.catalogPanel != null) ...[
                      widget.catalogPanel!,
                      const SizedBox(height: 16),
                    ],
                    if (widget.warning != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          widget.warning!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    _refinedCard(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            IkSourceWorkspaceStrings.playbackPolicy,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          _modernPolicy(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _refinedFilters(entries),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              if (entries.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _value.entries.isEmpty
                              ? IkSourceWorkspaceStrings.noSources
                              : ExpandedStrings.noMatches,
                        ),
                        if (_value.entries.isEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            IkSourceWorkspaceStrings.noSourcesHint,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              else
                SliverReorderableList(
                  itemCount: entries.length,
                  onReorderItem: (from, to) {
                    if (_busy || _filtered) return;
                    setState(
                      () => _value = _value.move(entries[from].id, to - from),
                    );
                  },
                  itemBuilder: (context, index) =>
                      _refinedRow(entries[index], index),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            ],
          ),
        ),
        ],
      ),
    );
    return PopScope(
      canPop: !_policyMenu.isOpen &&
          (_leaving || (!(_dirty && !widget.keepBackgroundDraft) && !_busy)),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _return();
      },
      child: widget.embedded
          ? body
          : Scaffold(
              appBar: AppBar(
                title: const Text(ExpandedStrings.managerTitle),
                leading: BackButton(onPressed: _return),
              ),
              body: SafeArea(
                child: Padding(padding: const EdgeInsets.all(20), child: body),
              ),
            ),
    );
  }

  Widget _refinedToolbar() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    IkSourceWorkspaceStrings.title,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    SourceStrings.sourceCount(
                      _value.entries.length,
                      _value.enabled.length,
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              key: const ValueKey('manager-save'),
              onPressed: _operationBusy ? null : _save,
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text(ExpandedStrings.saveSettings),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (widget.onCheckUpdates != null || widget.onBackgroundCheck != null)
              OutlinedButton.icon(
                key: const ValueKey('manager-check-updates'),
                onPressed: _operationBusy ? null : widget.onBackgroundCheck == null
                    ? _checkUpdates : () => unawaited(widget.onBackgroundCheck!(_value)),
                icon: const Icon(Icons.refresh_rounded, size: 17),
                label: const Text(IkSourceWorkspaceStrings.checkUpdates),
              ),
            if (widget.onUpdateAll != null || widget.onBackgroundUpdateAll != null)
              OutlinedButton.icon(
                key: const ValueKey('manager-update-all'),
                onPressed: _operationBusy ? null : widget.onBackgroundUpdateAll == null
                    ? _updateAll : () => unawaited(widget.onBackgroundUpdateAll!(_value)),
                icon: const Icon(Icons.system_update_alt_rounded, size: 17),
                label: const Text(IkSourceWorkspaceStrings.updateAll),
              ),
            TextButton.icon(
              onPressed: _busy ? null : widget.onHttp,
              icon: const Icon(Icons.settings_ethernet_rounded, size: 17),
              label: const Text(ExpandedStrings.httpSettings),
            ),
            if (_operationBusy)
              TextButton.icon(
                onPressed: () {
                  _token?.cancel();
                  widget.onCancelBackground?.call();
                },
                icon: const Icon(Icons.close_rounded, size: 17),
                label: const Text(ExpandedStrings.cancelOperation),
              ),
            Text(
              widget.keepBackgroundDraft
                  ? widget.backgroundDirty ? '草稿已保留，保存后生效' : ExpandedStrings.settingsSaved
                  : _dirty ? ExpandedStrings.dirty : ExpandedStrings.settingsSaved,
              style: theme.textTheme.bodySmall?.copyWith(
                color: _dirty
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('manager-import-link'),
                controller: _link,
                enabled: !_operationBusy,
                keyboardType: TextInputType.url,
                onSubmitted: _operationBusy ? null : (_) => _import(),
                decoration: InputDecoration(
                  hintText: IkSourceWorkspaceStrings.scriptLink,
                  prefixIcon: const Icon(Icons.link_rounded, size: 19),
                  isDense: true,
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerLow,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              key: const ValueKey('manager-import'),
              onPressed: _operationBusy ? null : () => _import(),
              child: const Text(IkSourceWorkspaceStrings.importLink),
            ),
          ],
        ),
      ],
    );
  }

  Widget _refinedCard(Widget child) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );

  Widget _refinedFilters(List<SourceEntry> entries) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('manager-search'),
          controller: _search,
          enabled: !_busy,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: ExpandedStrings.searchName,
            isDense: true,
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: ExpandedStrings.clearSearch,
                    onPressed: _busy
                        ? null
                        : () => setState(() => _search.clear()),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final entry in _platformNames.entries)
              TextButton(
                key: ValueKey('manager-platform-${entry.key}'),
                onPressed: _busy
                    ? null
                    : () => setState(() => _platform = entry.key),
                style: TextButton.styleFrom(
                  backgroundColor: _platform == entry.key
                      ? theme.colorScheme.primary.withValues(alpha: .09)
                      : Colors.transparent,
                  foregroundColor: _platform == entry.key
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(entry.value),
              ),
            FilterChip(
              label: const Text(ExpandedStrings.enabled),
              selected: _enabledOnly,
              elevation: 0,
              pressElevation: 0,
              onSelected: _busy
                  ? null
                  : (value) => setState(() => _enabledOnly = value),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                _filtered
                    ? ExpandedStrings.filterCount(entries.length)
                    : ExpandedStrings.orderHint,
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              key: const ValueKey('manager-inspect-all'),
              onPressed: _operationBusy || entries.isEmpty
                  ? null
                  : () => _inspect(entries),
              child: const Text(ExpandedStrings.inspectList),
            ),
          ],
        ),
      ],
    );
  }

  Widget _refinedRow(SourceEntry entry, int index) {
    final theme = Theme.of(context);
    final updateStatus = widget.updateStatus?.call(entry);
    final preferred = _value.preferred?.id == entry.id;
    return Padding(
      key: ValueKey(entry.id),
      padding: const EdgeInsets.only(bottom: 8),
      child: _refinedCard(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(entry.config.name, style: theme.textTheme.titleSmall),
                      if (preferred)
                        Text(
                          IkSourceWorkspaceStrings.preferred,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${entry.config.version} · ${entry.config.sources.keys.map((key) => _platformNames[key] ?? key).join(' / ')}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    updateStatus ?? _status(entry),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    entry.config.origin.scheme == 'file' ? '本机 LX 导入' : entry.config.origin.host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch.adaptive(
                  key: ValueKey('manager-enabled-${entry.id}'),
                  value: entry.config.enabled,
                  onChanged: _busy
                      ? null
                      : (value) => setState(
                          () => _value = _value.replace(
                            entry.id,
                            entry.config.copyWith(enabled: value),
                          ),
                        ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_busy && !_filtered)
                      ReorderableDragStartListener(
                        index: index,
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.drag_indicator_rounded, size: 19),
                        ),
                      ),
                    _refinedMenu(entry, index),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _refinedMenu(SourceEntry entry, int index) => MenuAnchor(
    style: MenuStyle(
      elevation: const WidgetStatePropertyAll(8),
      padding: const WidgetStatePropertyAll(EdgeInsets.all(5)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    menuChildren: [
      _sourceMenuAction(
        entry,
        _SourceAction.prefer,
        ExpandedStrings.prefer,
        Icons.star_outline_rounded,
        enabled: entry.config.enabled,
      ),
      _sourceMenuAction(
        entry,
        _SourceAction.inspect,
        ExpandedStrings.inspect,
        Icons.fact_check_outlined,
      ),
      if (widget.onUpdateEntry != null || widget.onBackgroundUpdateEntry != null)
        _sourceMenuAction(
          entry,
          _SourceAction.update,
          IkSourceWorkspaceStrings.update,
          Icons.system_update_alt_rounded,
        ),
      _sourceMenuAction(
        entry,
        _SourceAction.downloads,
        ExpandedStrings.allowDownloads,
        Icons.download_outlined,
        selected: entry.config.allowForDownloads,
      ),
      const Divider(height: 10),
      _sourceMenuAction(
        entry,
        _SourceAction.up,
        ExpandedStrings.moveUp,
        Icons.arrow_upward_rounded,
        enabled: !_filtered && index > 0,
      ),
      _sourceMenuAction(
        entry,
        _SourceAction.down,
        ExpandedStrings.moveDown,
        Icons.arrow_downward_rounded,
        enabled: !_filtered && index < _value.entries.length - 1,
      ),
      const Divider(height: 10),
      _sourceMenuAction(
        entry,
        _SourceAction.remove,
        ExpandedStrings.deleteSource,
        Icons.delete_outline_rounded,
      ),
    ],
    builder: (context, controller, _) => IconButton(
      tooltip: ExpandedStrings.more,
      onPressed: _busy
          ? null
          : () => controller.isOpen ? controller.close() : controller.open(),
      icon: const Icon(Icons.more_horiz_rounded, size: 20),
    ),
  );

  Widget _sourceMenuAction(
    SourceEntry entry,
    _SourceAction action,
    String label,
    IconData icon, {
    bool enabled = true,
    bool selected = false,
  }) => MenuItemButton(
    onPressed: _busy || !enabled ||
            (widget.backgroundBusy &&
                (action == _SourceAction.update || action == _SourceAction.inspect))
        ? null : () => _action(entry, action),
    leadingIcon: Icon(icon, size: 18),
    trailingIcon: selected ? const Icon(Icons.check_rounded, size: 17) : null,
    child: Text(label),
  );

  Widget _row(SourceEntry entry, int index) => Card(
    key: ValueKey(entry.id),
    margin: const EdgeInsets.symmetric(vertical: 4),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.config.name,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  ExpandedStrings.version(
                    entry.config.version,
                    _value.preferred?.id == entry.id,
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  entry.config.sources.keys
                      .map((key) => _platformNames[key] ?? key)
                      .join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  _status(entry),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  entry.config.origin.host,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Column(
            children: [
              Switch(
                key: ValueKey('manager-enabled-${entry.id}'),
                value: entry.config.enabled,
                onChanged: _busy
                    ? null
                    : (value) => setState(
                        () => _value = _value.replace(
                          entry.id,
                          entry.config.copyWith(enabled: value),
                        ),
                      ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_busy && !_filtered)
                    ReorderableDragStartListener(
                      index: index,
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.drag_handle, size: 20),
                      ),
                    ),
                  PopupMenuButton<_SourceAction>(
                    tooltip: ExpandedStrings.more,
                    enabled: !_busy,
                    onSelected: (action) => _action(entry, action),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: _SourceAction.prefer,
                        enabled: entry.config.enabled,
                        child: const Text(ExpandedStrings.prefer),
                      ),
                      const PopupMenuItem(
                        value: _SourceAction.inspect,
                        child: Text(ExpandedStrings.inspect),
                      ),
                      const PopupMenuItem(
                        value: _SourceAction.update,
                        child: Text(ExpandedStrings.update),
                      ),
                      CheckedPopupMenuItem(
                        value: _SourceAction.downloads,
                        checked: entry.config.allowForDownloads,
                        child: const Text(ExpandedStrings.allowDownloads),
                      ),
                      PopupMenuItem(
                        value: _SourceAction.up,
                        enabled: !_filtered && index > 0,
                        child: const Text(ExpandedStrings.moveUp),
                      ),
                      PopupMenuItem(
                        value: _SourceAction.down,
                        enabled:
                            !_filtered && index < _value.entries.length - 1,
                        child: const Text(ExpandedStrings.moveDown),
                      ),
                      const PopupMenuItem(
                        value: _SourceAction.remove,
                        child: Text(ExpandedStrings.deleteSource),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

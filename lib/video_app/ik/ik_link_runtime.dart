import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/share/deep_link_service.dart';
import '../../core/share/share_links.dart';
import '../../core/transfer/transfer_providers.dart';
import '../../features/player/presentation/providers/player_provider.dart';
import '../../l10n/ik_strings.dart';

/// 只控制订阅生命周期；解析仍用已有分享协议，保留旧链接兼容。
class IkLinkController {
  IkLinkController({required this.source, required this.onLink});
  final LinkSource source;
  final Future<void> Function(Uri) onLink;
  StreamSubscription<Uri>? _subscription;
  bool _started = false, _disposed = false;
  String? _initialReplay;

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    try {
      final initial = await source.initialLink();
      if (_disposed) return;
      if (initial != null) {
        _initialReplay = initial.toString();
        await _deliver(initial, initial: true);
      }
      if (_disposed) return;
      _subscription = source.links().listen(
        (uri) => unawaited(_deliver(uri)),
        onError: (Object _) {},
      );
    } catch (_) {
      // 未安装插件或宿主未注册协议时不影响应用启动。
    }
  }

  Future<void> _deliver(Uri uri, {bool initial = false}) async {
    if (_disposed) return;
    if (!initial && uri.toString() == _initialReplay) {
      _initialReplay = null;
      return;
    }
    try {
      await onLink(uri);
    } catch (_) {
      /* 单个错误链接不终止订阅。 */
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _subscription?.cancel();
    _subscription = null;
  }
}

class IkLinkRuntime extends ConsumerStatefulWidget {
  const IkLinkRuntime({
    super.key,
    required this.child,
    required this.onNavigate,
    this.source = const AppLinksSource(),
  });
  final Widget child;
  final ValueChanged<String> onNavigate;
  final LinkSource source;
  @override
  ConsumerState<IkLinkRuntime> createState() => _IkLinkRuntimeState();
}

class _IkLinkRuntimeState extends ConsumerState<IkLinkRuntime> {
  late final IkLinkController _controller;
  @override
  void initState() {
    super.initState();
    _controller = IkLinkController(source: widget.source, onLink: _handle);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_controller.start());
    });
  }

  Future<void> _handle(Uri uri) async {
    if (!mounted) return;
    final raw = uri.toString();
    final target = ShareLinks.classify(raw);
    if (target is SongLinkTarget) {
      widget.onNavigate(ShareLinks.playerLocation);
      try {
        await ref.read(playerProvider.notifier).playSong(target.song);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(content: Text(IkStrings.actionFailed)),
          );
        }
      }
      return;
    }
    final payload = target?.link ?? InboundLinkHandler.transferPayloadOf(raw);
    if (payload == null) return;
    ref.read(pendingPlaylistTransferProvider.notifier).state = payload;
    widget.onNavigate(ShareLinks.importPlaylistLocation);
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

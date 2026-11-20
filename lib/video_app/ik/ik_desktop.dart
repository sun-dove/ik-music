import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/player/presentation/providers/player_provider.dart';

final ikDesktopProvider = Provider<IkDesktopController?>((ref) => null);

class IkDesktopController extends ChangeNotifier {
  IkDesktopController({
    required this.onCommand,
    this.channel = const MethodChannel('sun-dove.yueyin/ik-desktop'),
  });
  final Future<void> Function(String) onCommand;
  final MethodChannel channel;
  bool available = false;
  bool connecting = false;
  bool tray = false, media = false, windowMemory = false;
  String? mediaError;
  Map<String, Object>? _lastUpdate;
  PlayerState? _latest;
  bool _disposed = false;
  bool get complete => available && tray && media && windowMemory;

  Future<void> connect() async {
    if (_disposed || connecting) return;
    connecting = true;
    notifyListeners();
    channel.setMethodCallHandler((call) async {
      if (call.method != 'command' || call.arguments is! String) {
        throw MissingPluginException();
      }
      await onCommand(call.arguments as String);
    });
    try {
      available = await channel.invokeMethod<bool>('initialize') == true;
      if (available) await _readCapabilities();
    } on PlatformException {
      available = false;
    } on MissingPluginException {
      available = false;
    }
    connecting = false;
    if (_disposed) return;
    _lastUpdate = null;
    notifyListeners();
    final latest = _latest;
    if (available && latest != null) await update(latest);
  }

  Future<void> _readCapabilities() async {
    final values = await channel.invokeMapMethod<String, dynamic>(
      'capabilities',
    );
    tray = values?['tray'] == true;
    media = values?['media'] == true;
    windowMemory = values?['windowMemory'] == true;
    mediaError = values?['mediaError'] as String?;
  }

  Future<void> update(PlayerState state) async {
    _latest = state;
    if (!available || _disposed) return;
    final next = <String, Object>{
      'title': state.currentSong?.name ?? '',
      'artist': state.currentSong?.artistNames ?? '',
      'playing': state.isPlaying,
      'enabled': state.currentSong != null,
    };
    if (mapEquals(_lastUpdate, next)) return;
    _lastUpdate = next;
    try {
      await channel.invokeMethod<void>('update', next);
      await _readCapabilities();
    } on PlatformException {
      available = false;
    } on MissingPluginException {
      available = false;
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    channel.setMethodCallHandler(null);
    super.dispose();
  }
}

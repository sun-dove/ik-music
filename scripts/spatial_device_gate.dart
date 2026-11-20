// 正式 U07 Android 设备门；只有显式 --target 本文件才执行。
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mconnect/features/player/data/android_spatial_audio.dart';
import 'package:mconnect/features/player/data/spatial_audio_capability.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: _Gate()));
}

class _Gate extends StatefulWidget {
  const _Gate();
  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  String message = 'U07 running';
  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    final player = AudioPlayer();
    final spatial = AndroidSpatialAudio();
    try {
      if (!await spatial.supportsSpatialAudio()) throw StateError('capability');
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/ik-u07-device.wav');
      const rate = 48000, frames = rate * 4;
      final bytes = ByteData(44 + frames * 4);
      void ascii(int start, String text) {
        for (var i = 0; i < text.length; i++) {
          bytes.setUint8(start + i, text.codeUnitAt(i));
        }
      }

      ascii(0, 'RIFF');
      bytes.setUint32(4, bytes.lengthInBytes - 8, Endian.little);
      ascii(8, 'WAVEfmt ');
      bytes.setUint32(16, 16, Endian.little);
      bytes.setUint16(20, 1, Endian.little);
      bytes.setUint16(22, 2, Endian.little);
      bytes.setUint32(24, rate, Endian.little);
      bytes.setUint32(28, rate * 4, Endian.little);
      bytes.setUint16(32, 4, Endian.little);
      bytes.setUint16(34, 16, Endian.little);
      ascii(36, 'data');
      bytes.setUint32(40, frames * 4, Endian.little);
      for (var i = 0; i < frames; i++) {
        bytes.setInt16(
          44 + i * 4,
          (sin(i * 2 * pi * 997 / rate) * 4096).round(),
          Endian.little,
        );
      }
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await player.setVolume(0); // 设备门不发声；处理节点位于输出音量前。
      await spatial.applySpatialAudio(
        const SpatialSettings(enabled: true),
        701,
      );
      await player.setFilePath(file.path);
      unawaited(player.play());
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      var report = await spatial.readSpatialAudio();
      if (report.requestId != 701 ||
          report.processedFrames <= 0 ||
          report.error != null) {
        throw StateError(
          'PCM first: ${report.requestId}/${report.processedFrames}/${report.error}',
        );
      }
      debugPrint(
        'IK_SPATIAL_GATE PASS native frames=${report.processedFrames} request=701',
      );
      final evidence = await const MethodChannel('ik.music/spatial')
          .invokeMapMethod<String, Object?>('read');
      if ((evidence?['inputRightEnergy'] as num?)?.toDouble() != 0 ||
          ((evidence?['outputRightEnergy'] as num?)?.toDouble() ?? 0) <=
              0.00001) {
        throw StateError('real PCM energy $evidence');
      }
      debugPrint(
        'IK_SPATIAL_GATE PASS measured right energy=${evidence?['outputRightEnergy']} from silent right input',
      );
      await spatial.applySpatialAudio(
        const SpatialSettings(
          enabled: true,
          strength: .25,
          azimuth: 90,
          elevation: 30,
        ),
        702,
      );
      await player.seek(const Duration(milliseconds: 500));
      await Future<void>.delayed(const Duration(milliseconds: 600));
      report = await spatial.readSpatialAudio();
      if (report.requestId != 702 ||
          report.processedFrames <= 0 ||
          report.error != null) {
        throw StateError('PCM change/seek');
      }
      debugPrint(
        'IK_SPATIAL_GATE PASS direction/strength/seek frames=${report.processedFrames}',
      );
      await player.stop();
      await player.setFilePath(file.path);
      unawaited(player.play());
      await Future<void>.delayed(const Duration(milliseconds: 600));
      report = await spatial.readSpatialAudio();
      if (report.requestId != 702 || report.processedFrames <= 0) {
        throw StateError('track reload');
      }
      await spatial.applySpatialAudio(const SpatialSettings(), 703);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      report = await spatial.readSpatialAudio();
      if (report.requestId != 703 || report.processedFrames <= 0) {
        throw StateError('disable');
      }
      debugPrint('IK_SPATIAL_GATE PASS reload/disable');
      message = 'U07 DEVICE PASS';
    } catch (error, stack) {
      message = 'U07 DEVICE FAIL $error';
      debugPrint('IK_SPATIAL_GATE FAIL $error\n$stack');
    } finally {
      await player.dispose();
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(message)));
}

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/video_app/ik/ik_spatial_runtime.dart';

void main() {
  test('U07 配置被接受但没有PCM帧只能等待，不能显示生效', () async {
    final backend = _Spatial();
    final runtime = IkSpatialCoordinator(
      capability: () => backend,
      initial: const SpatialSettings(),
      save: (_) async {},
      pollAutomatically: false,
    );
    await runtime.initialize();
    await runtime.setEnabled(true);
    expect(runtime.state.status, IkSpatialStatus.waiting);
    backend.frames = 128;
    await runtime.refresh();
    expect(runtime.state.status, IkSpatialStatus.active);
    expect(runtime.state.processedFrames, 128);
    runtime.dispose();
  });

  test('U07 缺少原生能力时不保存假开启', () async {
    var writes = 0;
    final runtime = IkSpatialCoordinator(
      capability: () => null,
      initial: const SpatialSettings(),
      save: (_) async {
        writes++;
      },
      pollAutomatically: false,
    );
    await runtime.initialize();
    await runtime.setEnabled(true);
    expect(runtime.state.status, IkSpatialStatus.unsupported);
    expect(runtime.state.effective.enabled, false);
    expect(writes, 0);
    runtime.dispose();
  });

  test('U07 播放器重建时重放最新配置，旧帧不误判生效', () async {
    var backend = _Spatial();
    final runtime = IkSpatialCoordinator(
      capability: () => backend,
      initial: const SpatialSettings(),
      save: (_) async {},
      pollAutomatically: false,
    );
    await runtime.initialize();
    await runtime.setEnabled(true);
    backend.frames = 256;
    await runtime.refresh();
    expect(runtime.state.status, IkSpatialStatus.active);
    backend = _Spatial();
    await runtime.refresh();
    expect(backend.settings.enabled, true);
    expect(runtime.state.status, IkSpatialStatus.waiting);
    runtime.dispose();
  });

  test('U07 处理失败恢复有效设置并保留明确失败原因', () async {
    final backend = _Spatial();
    final runtime = IkSpatialCoordinator(
      capability: () => backend,
      initial: const SpatialSettings(),
      save: (_) async {},
      pollAutomatically: false,
    );
    await runtime.initialize();
    backend.fail = true;
    await runtime.setEnabled(true);
    expect(runtime.state.status, IkSpatialStatus.failed);
    expect(runtime.state.effective.enabled, false);
    expect(runtime.state.message, contains('回滚'));
    runtime.dispose();
  });
}

class _Spatial implements SpatialAudioCapable {
  var settings = const SpatialSettings();
  int request = 0;
  int frames = 0;
  bool fail = false;
  @override
  Future<bool> supportsSpatialAudio() async => true;
  @override
  Future<void> applySpatialAudio(SpatialSettings next, int requestId) async {
    if (fail) throw StateError('原生图失败，回滚');
    settings = next;
    request = requestId;
  }

  @override
  Future<SpatialProcessingReport> readSpatialAudio() async =>
      SpatialProcessingReport(requestId: request, processedFrames: frames);
}

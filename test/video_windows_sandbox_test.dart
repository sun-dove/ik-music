import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/video_app/lx_source/windows_lx_sandbox.dart';
import 'package:mconnect/video_app/lx_source/lx_source.dart';
import 'package:mconnect/video_app/lx_source/lx_runtime_v3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final enabled =
      Platform.isWindows && Platform.environment['YUEYIN_SANDBOX_GATE'] == '1';
  final skip = enabled ? false : '需要Windows、WebView2与编译后的独立宿主；此处不代表原生门通过';
  test('取消正在创建的Windows沙箱，迟到创建不能遗留会话', () async {
    final sandbox = WindowsLxSandbox(
      hostPath: Platform.environment['YUEYIN_LX_HOST'],
    );
    addTearDown(() => sandbox.close('cancel-create'));
    final creating = sandbox.create('cancel-create');
    final assertion = expectLater(
      creating,
      throwsA(
        isA<LxSourceException>().having(
          (error) => error.code,
          '错误类别',
          'cancelled',
        ),
      ),
    );
    await sandbox.close('cancel-create');
    await assertion;
    await expectLater(
      sandbox.evaluate('cancel-create', '"late"'),
      throwsA(isA<LxSourceException>()),
    );
  }, skip: skip);
  test('Windows原生沙箱创建、JSON返回、异步回调与销毁', () async {
    final sandbox = WindowsLxSandbox(
      hostPath: Platform.environment['YUEYIN_LX_HOST'],
    );
    addTearDown(() => sandbox.close('native-gate'));
    await sandbox.create('native-gate');
    expect(
      await sandbox.evaluate(
        'native-gate',
        'JSON.stringify({answer:6*7, node:typeof process, host:typeof chrome})',
      ),
      '{"answer":42,"node":"undefined","host":"undefined"}',
    );
    await sandbox.evaluate(
      'native-gate',
      'globalThis.done="waiting";Promise.resolve().then(()=>{done="ready"});"started"',
    );
    expect(await sandbox.evaluate('native-gate', 'done'), 'ready');
    await sandbox.close('native-gate');
    await expectLater(
      sandbox.evaluate('native-gate', '1'),
      throwsA(isA<LxSourceException>()),
    );
  }, skip: skip);
  test('Windows真实引擎可加载完整LX兼容层和crypto/zlib资产', () async {
    final engine = LxSourceRuntimeV3(
      environment: 'desktop',
      sandbox: WindowsLxSandbox(
        hostPath: Platform.environment['YUEYIN_LX_HOST'],
      ),
    );
    expect(
      await engine.inspect('''
      /* @name native fixture */
      if(lx.env!=='desktop')throw new Error('environment');
      if(lx.utils.crypto.md5('abc')!=='900150983cd24fb0d6963f7d28e17f72')throw new Error('md5');
      lx.send(lx.EVENT_NAMES.inited,{sources:{kg:{type:'music',actions:['musicUrl'],qualitys:['128k','flac']}}});
      lx.on(lx.EVENT_NAMES.request,()=>Promise.resolve('https://media.example/song.flac'));
    '''),
      {
        'kg': ['128k', 'flac'],
      },
    );
  }, skip: skip);
  test('Windows禁止fetch、XHR、WebSocket、Worker、iframe与图片绕过宿主网络', () async {
    final sink = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    sink.listen((request) {
      requests++;
      request.response.close();
    });
    addTearDown(() => sink.close(force: true));
    final sandbox = WindowsLxSandbox(
      hostPath: Platform.environment['YUEYIN_LX_HOST'],
    );
    addTearDown(() => sandbox.close('network-gate'));
    await sandbox.create('network-gate');
    final url = 'http://127.0.0.1:${sink.port}/must-not-connect';
    await sandbox.evaluate('network-gate', '''
      globalThis.bypass={fetch:false,xhr:false};
      fetch('$url').then(()=>{bypass.fetch=true}).catch(()=>{});
      const xhr=new XMLHttpRequest();xhr.open('GET','$url');xhr.onload=()=>{bypass.xhr=true};try{xhr.send()}catch(_){}
      try{new WebSocket('${url.replaceFirst('http:', 'ws:')}')}catch(_){}
      try{new Worker(URL.createObjectURL(new Blob(['fetch("$url")'])))}catch(_){}
      const frame=document.createElement('iframe');frame.src='$url';document.body.append(frame);
      const image=new Image();image.src='$url';
      "queued";
    ''');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(requests, 0);
    expect(
      await sandbox.evaluate('network-gate', 'JSON.stringify(bypass)'),
      '{"fetch":false,"xhr":false}',
    );
  }, skip: skip);
  test('Windows死循环可终止，取消后新沙箱仍能工作', () async {
    final sandbox = WindowsLxSandbox(
      hostPath: Platform.environment['YUEYIN_LX_HOST'],
      evaluationTimeout: const Duration(seconds: 2),
    );
    await sandbox.create('loop');
    final watch = Stopwatch()..start();
    await expectLater(
      sandbox.evaluate('loop', 'while(true){}'),
      throwsA(
        isA<LxSourceException>().having(
          (error) => error.code,
          '错误类别',
          'timeout',
        ),
      ),
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 6)));
    await sandbox.create('next');
    expect(await sandbox.evaluate('next', 'String(1+1)'), '2');
    await sandbox.close('next');
  }, skip: skip);
}

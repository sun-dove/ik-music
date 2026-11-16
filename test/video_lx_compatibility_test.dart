import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/video_app/lx_source/lx_bootstrap_v2.dart';
import 'package:mconnect/video_app/lx_source/lx_bootstrap_v3.dart';

void main() {
  test('桌面协议允许省略status、先声明能力后注册回调，明确false仍拒绝', () async {
    final result = await _javascript(_bootstrap(), r'''
const assert=(value,label)=>{if(!value)throw Error(label);};
lx.send(lx.EVENT_NAMES.inited,{sources:{tx:{type:'music',actions:['musicUrl'],qualitys:['128k']}}});
lx.on(lx.EVENT_NAMES.request,()=>Promise.resolve('https://media.example/song.mp3'));
const state=JSON.parse(__lxHost.drain());
assert(state.ready===true && state.error===null,'合法桌面初始化被拒绝');
console.log('通过');
''');
    expect(result.exitCode, 0, reason: result.stderr.toString());
  });

  test('请求返回raw具备Buffer语义且回调的body保持JSON对象', () async {
    final result = await _javascript(_bootstrap(), r'''
let passed=false;
lx.request('https://fixture.example',{},(error,response,body)=>{
  if(error || !(response.raw instanceof Uint8Array) || response.raw.toString('utf8')!=='{"ok":true}' || body.ok!==true)throw Error('raw/body形状不兼容');
  passed=true;
});
const state=JSON.parse(__lxHost.drain());
__lxHost.response(state.queue[0].id,{statusCode:200,body:{ok:true},raw:'{"ok":true}'});
if(!passed || JSON.parse(__lxHost.drain()).error)throw Error('响应桥失败');
console.log('通过');
''');
    expect(result.exitCode, 0, reason: result.stderr.toString());
  });

  test('源明确拒绝初始化时不显示成功，脚本看不到宿主能力', () async {
    final result = await _javascript(_bootstrap(), r'''
lx.on(lx.EVENT_NAMES.request,()=>Promise.resolve('https://media.example/song.mp3'));
lx.send(lx.EVENT_NAMES.inited,{status:false,sources:{}});
const state=JSON.parse(__lxHost.drain());
if(state.ready || !state.error)throw Error('错误声明被当作成功');
if([typeof require,typeof process,typeof fetch,typeof document].join(',')!=='undefined,undefined,undefined,undefined')throw Error('宿主能力泄漏');
console.log('通过');
''');
    expect(result.exitCode, 0, reason: result.stderr.toString());
  });
}

String _bootstrap() {
  final vendors = [
    File('assets/lx-runtime/forge-1.3.1.min.js').readAsStringSync(),
    File('assets/lx-runtime/pako-2.1.0.min.js').readAsStringSync(),
  ].join('\n');
  return '${lxV2Prelude(vendors, List.filled(65536, 7))}\n${lxV3Bootstrap()}';
}

// 这里只执行仓库自写黄金样例，不将第三方脚本交给Node或node:vm。
Future<ProcessResult> _javascript(String bootstrap, String assertions) async {
  final process = await Process.start('node', [
    '-e',
    r'''
const vm=require('node:vm');let input='';
process.stdin.on('data',chunk=>input+=chunk);
process.stdin.on('end',()=>{
  const [bootstrap,assertions]=JSON.parse(input);
  try{vm.runInNewContext(bootstrap+'\n'+assertions,{console},{timeout:4000});}
  catch(error){console.error(error.message);process.exitCode=1;}
});
''',
  ]);
  process.stdin.write(jsonEncode([bootstrap, assertions]));
  await process.stdin.close();
  final output = process.stdout.transform(utf8.decoder).join();
  final error = process.stderr.transform(utf8.decoder).join();
  return ProcessResult(
    process.pid,
    await process.exitCode,
    await output,
    await error,
  );
}

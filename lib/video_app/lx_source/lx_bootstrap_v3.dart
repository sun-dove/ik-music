import 'lx_bootstrap_v2.dart';

/// 桌面与移动版共用的公开源协议；旧bootstrap保持原行为。
String lxV3Bootstrap({String environment = 'mobile'}) => lxV2Bootstrap
    .replaceFirst(
      "env:'mobile', version:'2.0.0'",
      "env:'${environment == 'desktop' ? 'desktop' : 'mobile'}', version:'2.0.0'",
    )
    .replaceFirst(
      "!value || value.status !== true || !value.sources || !handler",
      "!value || ('status' in value && value.status !== true) || !value.sources || typeof value.sources !== 'object' || Array.isArray(value.sources)",
    )
    .replaceFirst(
      'const callback=callbacks.get(id); callbacks.delete(id);',
      '''const callback=callbacks.get(id); callbacks.delete(id);
      if(typeof response.rawBase64 === 'string') {response.raw=__lxV2.buffer.from(response.rawBase64,'base64');delete response.rawBase64;}
      else if(typeof response.raw === 'string') response.raw=__lxV2.buffer.from(response.raw);''',
    );

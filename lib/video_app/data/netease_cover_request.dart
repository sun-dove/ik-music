import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

const _imageHosts = {
  'p1.music.126.net',
  'p2.music.126.net',
  'p3.music.126.net',
  'p4.music.126.net',
};
const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/131.0.0.0 Safari/537.36';
const _timeout = Duration(seconds: 15);

Uri? neteaseCoverUri(String? value) {
  if (value == null) return null;
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      !_imageHosts.contains(uri.host.toLowerCase()) ||
      (uri.scheme.isNotEmpty &&
          uri.scheme != 'http' &&
          uri.scheme != 'https') ||
      uri.userInfo.isNotEmpty ||
      (uri.hasPort && uri.port != 80 && uri.port != 443)) {
    return null;
  }
  return uri.replace(scheme: 'https', port: 443);
}

/// 网易CDN拒绝Dart默认UA；设置客户端单值，避免NetworkImage追加出两条UA。
Future<Uint8List> loadNeteaseCoverBytes(Uri uri) async {
  final target = neteaseCoverUri(uri.toString());
  if (target == null) throw const FormatException('Invalid Netease image URL');
  final client = HttpClient()
    ..connectionTimeout = _timeout
    ..userAgent = _userAgent;
  try {
    return await (() async {
      final request = await client.getUrl(target);
      request.headers.set(HttpHeaders.refererHeader, 'https://music.163.com/');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw HttpException('Image HTTP ${response.statusCode}', uri: target);
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        bytes.add(chunk);
      }
      if (bytes.isEmpty)
        throw HttpException('Empty image response', uri: target);
      return bytes.takeBytes();
    })().timeout(_timeout);
  } finally {
    client.close(force: true);
  }
}

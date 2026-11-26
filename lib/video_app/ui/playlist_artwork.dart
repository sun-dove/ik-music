import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/playlist.dart';
import '../../models/song.dart';
import '../data/netease_cover_request.dart';
import '../data/playlist_first_cover_provider.dart';

/// 平台封面优先；空地址或图片失败后才读取首曲回退。
class PlaylistArtwork extends StatelessWidget {
  const PlaylistArtwork({
    super.key,
    required this.playlist,
    required this.size,
    this.radius = 6,
    this.firstSong,
    this.allowFirstSongRequest = false,
  });

  final Playlist playlist;
  final double size;
  final double radius;
  final Song? firstSong;
  final bool allowFirstSongRequest;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(child: Icon(Icons.queue_music, size: size * .46)),
    );
    final fallback = _FirstSongArtwork(
      playlist: playlist,
      firstSong: firstSong,
      allowRequest: allowFirstSongRequest,
      size: size,
      placeholder: placeholder,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox.square(
        dimension: size,
        child: _artwork(context, playlist.coverUrl, size, fallback),
      ),
    );
  }
}

class _FirstSongArtwork extends ConsumerWidget {
  const _FirstSongArtwork({
    required this.playlist,
    required this.firstSong,
    required this.allowRequest,
    required this.size,
    required this.placeholder,
  });
  final Playlist playlist;
  final Song? firstSong;
  final bool allowRequest;
  final double size;
  final Widget placeholder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (firstSong != null) {
      final albumFallback = _artwork(
        context,
        firstSong!.album?.coverUrl,
        size,
        placeholder,
      );
      return _artwork(context, firstSong!.coverUrl, size, albumFallback);
    }
    if (!allowRequest) return placeholder;
    final state = ref.watch(playlistFirstCoverProvider(playlist));
    final cover = state.isLoading ? null : state.asData?.value;
    return _artwork(context, cover, size, placeholder);
  }
}

Widget _artwork(
  BuildContext context,
  String? value,
  double size,
  Widget fallback,
) {
  final uri = value == null ? null : Uri.tryParse(value.trim());
  if (uri == null ||
      (uri.scheme != 'file' &&
          (!uri.hasAuthority ||
              (uri.scheme.isNotEmpty &&
                  uri.scheme != 'http' &&
                  uri.scheme != 'https')))) {
    return fallback;
  }
  final ImageProvider provider;
  if (uri.scheme == 'file') {
    provider = FileImage(File.fromUri(uri));
  } else {
    provider = _PlaylistArtworkImage(
      uri.scheme.isEmpty ? uri.replace(scheme: 'https') : uri,
    );
  }
  final pixels = (size * MediaQuery.devicePixelRatioOf(context))
      .ceil()
      .clamp(1, 960)
      .toInt();
  return Image(
    image: ResizeImage.resizeIfNeeded(pixels, pixels, provider),
    fit: BoxFit.cover,
    errorBuilder: (_, _, _) => fallback,
  );
}

class _PlaylistArtworkImage extends ImageProvider<_PlaylistArtworkImage> {
  const _PlaylistArtworkImage(this.uri);
  final Uri uri;

  @override
  Future<_PlaylistArtworkImage> obtainKey(
    ImageConfiguration configuration,
  ) async => this;

  @override
  ImageStreamCompleter loadImage(
    _PlaylistArtworkImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _load(decode),
    scale: 1,
    debugLabel: uri.toString(),
  );

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    try {
      final netease = neteaseCoverUri('$uri');
      final bytes = netease == null
          ? await _networkBytes()
          : await loadNeteaseCoverBytes(netease);
      return await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    } catch (_) {
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(this));
      rethrow;
    }
  }

  Future<Uint8List> _networkBytes() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12)
      ..userAgent =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
          'AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/131.0.0.0 Safari/537.36';
    try {
      return await (() async {
        final response = await (await client.getUrl(uri)).close();
        if (response.statusCode != HttpStatus.ok) {
          await response.drain<void>();
          throw HttpException('Image HTTP ${response.statusCode}', uri: uri);
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response) {
          bytes.add(chunk);
        }
        return bytes.takeBytes();
      })().timeout(const Duration(seconds: 15));
    } finally {
      client.close(force: true);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is _PlaylistArtworkImage && other.uri == uri;

  @override
  int get hashCode => uri.hashCode;
}

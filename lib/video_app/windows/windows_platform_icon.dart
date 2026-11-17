import 'package:flutter/material.dart';

import '../../models/platform_type.dart';
import '../ui/catalog_pages.dart';

class WindowsPlatformIcon extends StatelessWidget {
  const WindowsPlatformIcon({
    super.key,
    required this.platform,
    this.size = 26,
  });
  final PlatformType platform;
  final double size;
  static String asset(PlatformType platform) => switch (platform) {
    PlatformType.qq => 'assets/platform-icons/qq-music.jpg',
    PlatformType.netease => 'assets/platform-icons/netease-music.jpg',
    PlatformType.kugou => 'assets/platform-icons/kugou-music.jpg',
    PlatformType.local => '',
  };
  @override
  Widget build(BuildContext context) => platform == PlatformType.local
      ? Icon(Icons.library_music_outlined, size: size)
      : ClipRRect(
          borderRadius: BorderRadius.circular(size * .24),
          child: Image.asset(
            asset(platform),
            width: size,
            height: size,
            fit: BoxFit.cover,
            semanticLabel: videoPlatformLabel(platform),
          ),
        );
}

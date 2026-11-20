import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 独立入口显式保留曲库中的专辑/歌手标识；旧入口维持原映射。
final libraryMetadataProvider = Provider<bool>((ref) => false);

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../models/audio_quality.dart';
import '../../../../models/platform_type.dart';

/// 独立入口可注入统一下载音质；缺省为空，原应用保留每个入口原来的策略。
final downloadQualityProvider = Provider<AudioLevel Function(PlatformType)?>(
  (ref) => null,
);

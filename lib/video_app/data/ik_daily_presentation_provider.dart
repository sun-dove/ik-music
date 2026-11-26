import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/ik_recommendation_catalog_strings.dart';
import '../../models/personal_daily_result.dart';
import '../../models/platform_type.dart';
import '../../models/recommendation_source.dart';
import 'ik_public_recommendations.dart';
import 'personal_daily_provider.dart';

typedef IkDailyFallbackKey = ({
  PlatformType platform,
  PersonalDailyResult personal,
});

/// 严格结果对象随账号、凭据revision与日界变化而更换；旧公开响应不能接回新作用域。
final ikDailyFallbackProvider = FutureProvider.autoDispose.family<
  RecommendationResult,
  IkDailyFallbackKey
>((ref, key) => ref.watch(ikPublicRecommendationsProvider).songs(key.platform));

class IkDailyPresentationState {
  const IkDailyPresentationState({
    required this.personal,
    this.fallback,
    this.fallbackLoading = false,
    this.fallbackError,
  });

  final PersonalDailyState personal;
  final RecommendationResult? fallback;
  final bool fallbackLoading;
  final String? fallbackError;
}

final ikDailyPresentationProvider = Provider.autoDispose.family<
  IkDailyPresentationState,
  PlatformType
>((ref, platform) {
  final personal = ref.watch(personalDailyProvider(platform));
  final result = personal.result;
  if (personal.isLoading || result == null ||
      result.platform != platform ||
      result.status == PersonalDailyStatus.success ||
      result.status == PersonalDailyStatus.sessionChanged ||
      (platform != PlatformType.qq && platform != PlatformType.kugou)) {
    return IkDailyPresentationState(personal: personal);
  }
  final fallback = ref.watch(ikDailyFallbackProvider((
    platform: platform,
    personal: result,
  )));
  return fallback.when(
    data: (value) {
      final source = value.source;
      final valid = source?.platform == platform &&
          (source?.kind == RecommendationKind.fallbackToplist ||
              source?.kind == RecommendationKind.fallbackHomepage) &&
          value.songs.every((song) => song.platform == platform);
      return IkDailyPresentationState(
        personal: personal,
        fallback: valid ? value : null,
        fallbackError: valid && value.songs.isNotEmpty
            ? null
            : value.error ?? IkRecommendationCatalogStrings.publicUnavailable,
      );
    },
    error: (_, _) => IkDailyPresentationState(
      personal: personal,
      fallbackError: IkRecommendationCatalogStrings.publicFailed,
    ),
    loading: () => IkDailyPresentationState(
      personal: personal,
      fallbackLoading: true,
    ),
  );
});

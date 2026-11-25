import '../models/personal_daily_result.dart';
import '../models/platform_type.dart';

abstract final class IkPersonalDailyStrings {
  static const title = '每日推荐';
  static const refresh = '刷新每日推荐';
  static const playAll = '播放全部';
  static const heading = '今天，听点新的';
  static const hint = '每个平台最多30首';

  static String platformLabel(PlatformType platform) => switch (platform) {
    PlatformType.netease => '网易云',
    PlatformType.qq => 'QQ音乐',
    PlatformType.kugou => '酷狗音乐',
    PlatformType.local => '本地音乐',
  };

  static String count(int count) => '共$count首';
  static String fullCount(int count, int displayed) =>
      '本次推荐$count首，展示前$displayed首';

  static String date(DateTime value) =>
      '${value.year}年${value.month}月${value.day}日';

  static String acquired(DateTime value) => '${date(value.toLocal())}获取';
  static String sourceDate(DateTime value) => '推荐日期：${date(value)}';

  static bool _timedOut(PersonalDailyResult result) =>
      result.errorCode == 'timeout' || result.errorCode == 'requestTimeout';

  static String stateTitle(PersonalDailyResult? result) =>
      switch (result?.status) {
        PersonalDailyStatus.signedOut => '登录后查看每日推荐',
        PersonalDailyStatus.identityIncomplete => '需要重新连接账号',
        PersonalDailyStatus.sessionExpired => '登录已失效',
        PersonalDailyStatus.verificationRequired => '需要完成平台验证',
        PersonalDailyStatus.networkFailure =>
          _timedOut(result!) ? '推荐加载超时' : '网络连接失败',
        PersonalDailyStatus.serviceUnavailable => '平台暂时无法提供推荐',
        PersonalDailyStatus.invalidResponse => '暂时无法读取推荐',
        PersonalDailyStatus.empty => '今日推荐还没有歌曲',
        PersonalDailyStatus.unsupported => '该平台暂不支持个人日推',
        PersonalDailyStatus.sessionChanged => '账号已更新',
        PersonalDailyStatus.success || null => '推荐尚未加载',
      };

  static String stateHint(PlatformType platform, PersonalDailyResult? result) {
    final label = platformLabel(platform);
    return switch (result?.status) {
      PersonalDailyStatus.signedOut => '连接$label账号，听听今天为你推荐的歌曲。',
      PersonalDailyStatus.identityIncomplete => '当前登录信息不足，请重新连接$label账号后再试。',
      PersonalDailyStatus.sessionExpired => '重新连接$label账号后，即可继续查看个人推荐。',
      PersonalDailyStatus.verificationRequired => '请先在$label完成安全验证，再回来重试。',
      PersonalDailyStatus.networkFailure =>
        _timedOut(result!) ? '加载时间过长，请稍后重试。' : '请检查网络连接后重试。',
      PersonalDailyStatus.serviceUnavailable => '可以稍后重试，或先听听其他平台的推荐。',
      PersonalDailyStatus.invalidResponse => '平台返回的推荐暂时无法读取，请刷新后重试。',
      PersonalDailyStatus.empty => '平台本次没有返回推荐歌曲，稍后再来看看。',
      PersonalDailyStatus.unsupported => '可以切换其他平台查看每日推荐。',
      PersonalDailyStatus.sessionChanged => '刷新后获取当前账号的每日推荐。',
      PersonalDailyStatus.success || null => '点击刷新，获取这个平台的个人推荐。',
    };
  }

  static String? actionLabel(PersonalDailyResult? result) =>
      switch (result?.status) {
        PersonalDailyStatus.signedOut => '连接账号',
        PersonalDailyStatus.identityIncomplete ||
        PersonalDailyStatus.sessionExpired => '重新连接',
        PersonalDailyStatus.verificationRequired => '前往平台验证',
        PersonalDailyStatus.sessionChanged || null => '刷新推荐',
        PersonalDailyStatus.empty => '重试',
        _ => result!.retryable ? '重试' : null,
      };

  static const verificationRetry = '验证后重试';
  static const verificationOpenFailed = '未能打开平台页面，请在平台完成验证后重试。';
}

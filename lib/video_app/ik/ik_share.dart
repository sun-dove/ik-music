import 'package:flutter/widgets.dart';

import '../../core/share/share_service.dart';
import '../../l10n/ik_strings.dart';

/// 分享协议与旧产品兼容，仅独立入口的来源署名使用当前品牌。
class IkShareService extends ShareService {
  const IkShareService(this.channel) : super(channel);
  final ShareChannel channel;

  @override
  Future<void> sharePlaylist({
    required String name,
    required int songCount,
    required String link,
    Rect? origin,
  }) => channel.shareText(
    IkStrings.sharedPlaylist(playlistDisplayName(name), songCount, link),
    subject: name,
    origin: origin,
  );
}

import 'package:flutter/material.dart';

import '../../l10n/video_strings.dart';
import '../../l10n/windows_music_strings.dart';
import '../../models/platform_type.dart';
import '../ui/catalog_pages.dart';
import '../ui/my_page.dart';
import '../ui/video_theme.dart';
import 'windows_music_preferences.dart';
import 'windows_platform_icon.dart';

/// 复用旧设置页的公开数据与回调；旧页面与构造保持。
class WindowsMyPage extends StatelessWidget {
  const WindowsMyPage({
    super.key,
    required this.settings,
    required this.playQuality,
    required this.downloadQuality,
    required this.onQuality,
    this.backgroundLabel = WindowsMusicStrings.defaultBackground,
    this.fontLabel = WindowsMusicStrings.defaultFont,
    this.closeAction = WindowsCloseAction.minimize,
    this.nativeAvailable = false,
    this.errors = const [],
    this.onBackground,
    this.onFont,
    this.onClose,
    this.onExit,
    this.onRetryNative,
  });
  final VideoMyPage settings;
  final String playQuality, downloadQuality, backgroundLabel, fontLabel;
  final ValueChanged<bool> onQuality;
  final WindowsCloseAction closeAction;
  final bool nativeAvailable;
  final List<String> errors;
  final VoidCallback? onBackground, onFont, onClose, onExit, onRetryNative;
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 960),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            children: [
              Image.asset(
                'assets/branding/dj-music/source/windows/yangyin-256.png',
                width: 44,
                height: 44,
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      VideoStrings.my,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      WindowsMusicStrings.brandPronunciation,
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final platform in settings.platforms)
                  SizedBox(
                    width: constraints.maxWidth >= 820
                        ? (constraints.maxWidth -
                                  12 * (settings.platforms.length - 1)) /
                              settings.platforms.length
                        : constraints.maxWidth,
                    child: _account(context, platform),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _group(context, [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: LayoutBuilder(
                builder: (context, constraints) => Wrap(
                  runSpacing: 12,
                  children: [
                    for (final platform in settings.platforms)
                      _stat(
                        constraints.maxWidth /
                            (constraints.maxWidth >= 420
                                ? settings.platforms.length + 1
                                : 2),
                        videoPlatformLabel(platform),
                        (settings.accounts[platform]?.total ??
                                    settings.accounts[platform]?.loaded)
                                ?.toString() ??
                            '—',
                      ),
                    _stat(
                      constraints.maxWidth /
                          (constraints.maxWidth >= 420
                              ? settings.platforms.length + 1
                              : 2),
                      VideoStrings.localSongs,
                      settings.localSongCount?.toString() ?? '—',
                    ),
                  ],
                ),
              ),
            ),
          ]),
          _heading(VideoStrings.playSettings),
          _group(context, [
            _tile(
              VideoStrings.customSource,
              settings.customSourceLabel,
              Icons.hub_outlined,
              settings.onCustomSource,
            ),
            _tile(
              WindowsMusicStrings.playQuality,
              playQuality,
              Icons.equalizer_rounded,
              () => onQuality(false),
            ),
            _tile(
              VideoStrings.cacheManagement,
              settings.cacheLabel,
              Icons.storage_outlined,
              settings.onCache,
            ),
          ]),
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Text(
              WindowsMusicStrings.qualityHint,
              style: TextStyle(fontSize: 12),
            ),
          ),
          _heading(VideoStrings.downloadSettings),
          _group(context, [
            _tile(
              WindowsMusicStrings.downloadQuality,
              downloadQuality,
              Icons.music_note_outlined,
              () => onQuality(true),
            ),
            _tile(
              VideoStrings.downloadManagement,
              settings.downloadLabel,
              Icons.download_outlined,
              settings.onDownloads,
            ),
            _tile(
              VideoStrings.storageLocation,
              VideoStrings.chooseFolder,
              Icons.folder_outlined,
              settings.onDirectory,
            ),
          ]),
          _heading(WindowsMusicStrings.appearance),
          _group(context, [
            _tile(
              VideoStrings.appearanceTheme,
              settings.themeLabel,
              Icons.palette_outlined,
              settings.onTheme,
            ),
            _tile(
              WindowsMusicStrings.background,
              backgroundLabel,
              Icons.image_outlined,
              onBackground,
            ),
            _tile(
              WindowsMusicStrings.font,
              fontLabel,
              Icons.font_download_outlined,
              onFont,
            ),
          ]),
          for (final error in errors)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          _heading(WindowsMusicStrings.windowSettings),
          _group(context, [
            _tile(
              WindowsMusicStrings.closeWindow,
              closeAction == WindowsCloseAction.minimize
                  ? '${WindowsMusicStrings.minimize}\n${WindowsMusicStrings.minimizeHint}'
                  : '${WindowsMusicStrings.exit}\n${WindowsMusicStrings.exitHint}',
              Icons.close_rounded,
              nativeAvailable ? onClose : null,
            ),
            if (!nativeAvailable)
              _tile(
                WindowsMusicStrings.failure(DesktopFailure.nativeUnavailable),
                VideoStrings.retry,
                Icons.refresh_rounded,
                onRetryNative,
              ),
            _tile(
              WindowsMusicStrings.exit,
              '',
              Icons.logout_rounded,
              nativeAvailable ? onExit : null,
            ),
          ]),
          _heading(VideoStrings.otherSettings),
          _group(context, [
            _tile(
              VideoStrings.localMusic,
              VideoStrings.importScan,
              Icons.library_music_outlined,
              settings.onLocal,
            ),
          ]),
          const SizedBox(height: 22),
          const Text(
            VideoStrings.appVersion,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    ),
  );

  Widget _account(BuildContext context, PlatformType platform) {
    final account = settings.accounts[platform];
    return Material(
      color: VideoTheme.surface(context),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        leading: account?.avatarUrl == null
            ? WindowsPlatformIcon(platform: platform, size: 44)
            : CircleAvatar(
                radius: 22,
                backgroundImage: NetworkImage(account!.avatarUrl!),
              ),
        title: Text(
          account?.nickname ??
              VideoStrings.loginPlatform(videoPlatformLabel(platform)),
        ),
        subtitle: Text(
          account == null
              ? VideoStrings.loginToSyncLikes
              : '${VideoStrings.accountLikes(account.loaded, account.total)}${account.complete ? '' : ' · ${VideoStrings.syncIncomplete}'}',
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => settings.onAccount(platform),
      ),
    );
  }

  Widget _stat(double width, String title, String count) => SizedBox(
    width: width,
    child: Column(
      children: [
        Text(
          count,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        Text(title, style: const TextStyle(fontSize: 11)),
      ],
    ),
  );

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
    child: Text(
      text,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
  );
  Widget _group(BuildContext context, List<Widget> children) => Material(
    color: VideoTheme.surface(context),
    borderRadius: BorderRadius.circular(18),
    clipBehavior: Clip.antiAlias,
    child: Column(children: children),
  );
  Widget _tile(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback? onTap,
  ) => ListTile(
    leading: Icon(icon, size: 22),
    title: Text(title),
    subtitle: subtitle.isEmpty
        ? null
        : Text(subtitle, style: const TextStyle(fontSize: 12, height: 1.6)),
    trailing: onTap == null
        ? null
        : const Icon(Icons.chevron_right_rounded, size: 18),
    onTap: onTap,
  );
}

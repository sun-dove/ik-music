import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../core/platform/platform_utils.dart';
import '../../features/download/data/download_directory_service.dart';
import '../../features/download/data/saf_download_writer.dart';
import '../../l10n/ik_alignment_strings.dart';
import '../../utils/file_opener.dart';

/// 独立下载页的目录入口，旧文件通道契约保持。
Future<void> openIkDownloadFolder(
  DownloadDirectoryService service,
  String? filePath,
) async {
  if (filePath == null || filePath.trim().isEmpty) {
    throw StateError(IkAlignmentStrings.noFilePath);
  }
  if (isSafDocumentUri(filePath)) {
    if (!await service.openSafDirectory()) {
      throw StateError(IkAlignmentStrings.folderUnavailable);
    }
    return;
  }
  if (PlatformUtils.isWindows) {
    final directory = Uri.directory(p.windows.dirname(filePath), windows: true);
    if (!await launchUrl(directory, mode: LaunchMode.externalApplication)) {
      throw StateError(IkAlignmentStrings.folderUnavailable);
    }
    return;
  }
  await FileOpener.openFolder(p.posix.dirname(filePath));
}

import '../../l10n/ik_source_catalog_strings.dart';

import 'dart:convert';

import 'package:flutter/services.dart';

class IkCatalogEntry {
  const IkCatalogEntry({
    required this.sourceKey,
    required this.displayName,
    required this.path,
    required this.byteLength,
    required this.contentSha256,
    required this.autoPolicy,
    required this.licenseEvidence,
    required this.licenseNote,
    this.reason = '',
    this.licenseUrl = '',
    this.windowsBlockReason,
    this.downloadRestricted = false,
  });
  final String sourceKey, displayName, path, contentSha256, autoPolicy;
  final String licenseEvidence, licenseNote, reason, licenseUrl;
  final String? windowsBlockReason;
  final int byteLength;
  final bool downloadRestricted;

  String? blockReason(String runtime) {
    if (autoPolicy != 'prepare') return reason;
    if (runtime.startsWith('windows')) return windowsBlockReason;
    return null;
  }

  factory IkCatalogEntry.fromJson(Map<String, dynamic> json) {
    final entry = IkCatalogEntry(
      sourceKey: json['sourceKey'] as String,
      displayName: json['displayName'] as String,
      path: json['path'] as String,
      byteLength: json['byteLength'] as int,
      contentSha256: json['contentSha256'] as String,
      autoPolicy: json['autoPolicy'] as String,
      licenseEvidence: json['licenseEvidence'] as String,
      licenseNote: json['licenseNote'] as String,
      reason: json['reason'] as String? ?? '',
      licenseUrl: json['licenseUrl'] as String? ?? '',
      windowsBlockReason: json['windowsBlockReason'] as String?,
      downloadRestricted: json['downloadRestricted'] == true,
    );
    if (!RegExp(r'^pdone:[a-z0-9]+$').hasMatch(entry.sourceKey) ||
        !RegExp(r'^[a-z0-9]+/[a-zA-Z0-9._-]+\.js$').hasMatch(entry.path) ||
        entry.path.split('/').first != entry.sourceKey.split(':').last ||
        entry.path.contains('latest') ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(entry.contentSha256) ||
        entry.byteLength <= 0 ||
        entry.byteLength > 1024 * 1024 ||
        !['prepare', 'metadataOnly'].contains(entry.autoPolicy) ||
        (entry.autoPolicy == 'metadataOnly' && entry.reason.isEmpty)) {
      throw const FormatException(IkSourceCatalogStrings.invalidEntry);
    }
    return entry;
  }
}

class IkSourceCatalog {
  const IkSourceCatalog({
    required this.catalogVersion,
    required this.commit,
    required this.entries,
  });
  final int catalogVersion;
  final String commit;
  final List<IkCatalogEntry> entries;
  Uri origin(IkCatalogEntry entry) => Uri.https(
    'raw.githubusercontent.com',
    '/pdone/lx-music-source/$commit/${entry.path}',
  );
  List<Uri> downloadUris(IkCatalogEntry entry) => [
    origin(entry),
    Uri.https(
      'fastly.jsdelivr.net',
      '/gh/pdone/lx-music-source@$commit/${entry.path}',
    ),
  ];

  /// 仅已知仓库路径与已知内容共同命中；同名自定义源不会合并。
  bool matchesOrigin(IkCatalogEntry entry, Uri uri) {
    if (uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return false;
    }
    final path = uri.path;
    final directory = entry.sourceKey.split(':').last;
    final version = entry.path.split('/').last;
    final suffix =
        '(?:${RegExp.escape(commit)}|main)/$directory/(?:${RegExp.escape(version)}|latest\\.js)';
    return switch (uri.host) {
      'raw.githubusercontent.com' => RegExp(
        '^/pdone/lx-music-source/$suffix\$',
      ).hasMatch(path),
      'github.com' => RegExp(
        '^/pdone/lx-music-source/blob/$suffix\$',
      ).hasMatch(path),
      'fastly.jsdelivr.net' => RegExp(
        '^/gh/pdone/lx-music-source@$suffix\$',
      ).hasMatch(path),
      _ => false,
    };
  }

  factory IkSourceCatalog.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1 ||
        json['repository'] != 'pdone/lx-music-source' ||
        !RegExp(r'^[0-9a-f]{40}$').hasMatch(json['commit'] as String? ?? '')) {
      throw const FormatException(IkSourceCatalogStrings.invalidCatalog);
    }
    final entries = (json['entries'] as List)
        .map(
          (e) => IkCatalogEntry.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
    if (entries.map((e) => e.sourceKey).toSet().length != entries.length ||
        entries.fold<int>(0, (n, e) => n + e.byteLength) > 8 * 1024 * 1024) {
      throw const FormatException(IkSourceCatalogStrings.invalidCatalogBudget);
    }
    return IkSourceCatalog(
      catalogVersion: json['catalogVersion'] as int,
      commit: json['commit'] as String,
      entries: entries,
    );
  }
  static Future<IkSourceCatalog> load() async => IkSourceCatalog.fromJson(
    jsonDecode(
      await rootBundle.loadString('assets/source-catalog/pdone-v1.json'),
    ) as Map<String, dynamic>,
  );
}

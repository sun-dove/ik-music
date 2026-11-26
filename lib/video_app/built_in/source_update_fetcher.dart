import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as hashes;
import 'package:dio/dio.dart';

import '../lx_source/lx_http.dart';
import '../lx_source/lx_source.dart';
import 'catalog.dart';
import '../../l10n/ik_source_update_strings.dart';

class IkFetchedSourceUpdate {
  const IkFetchedSourceUpdate({
    required this.script,
    required this.name,
    required this.version,
    required this.origin,
    required this.sha256,
    required this.contentSha256,
    required this.byteLength,
    this.upstreamCommit,
    this.upstreamBlobSha1,
    this.path,
  });

  final String script, name, version, sha256, contentSha256;
  final Uri origin;
  final int byteLength;
  final String? upstreamCommit, upstreamBlobSha1, path;
}

/// 只获取候选，不初始化或执行脚本；上游blob验真通过后才返回内容。
class IkSourceUpdateFetcher {
  IkSourceUpdateFetcher({Dio? dio}) : _dio = dio ?? createLxDio();

  static const _repository = 'pdone/lx-music-source';
  static const _maxBytes = 1024 * 1024;
  static const _deadline = Duration(seconds: 30);
  static final _gitSha = RegExp(r'^[0-9a-f]{40}$');
  static final _sourceKey = RegExp(r'^pdone:([a-z0-9]+)$');
  static final _linkTarget = RegExp(
    r'^(?:\./)?([a-zA-Z0-9_-][a-zA-Z0-9._-]*\.js)$',
  );
  final Dio _dio;
  final _active = <CancelToken>{};
  _RepositorySnapshot? _snapshot;
  Future<_RepositorySnapshot>? _loading;
  int _generation = 0;
  bool _disposed = false;

  /// 显式开始新一轮；失败不保留上一轮快照。
  Future<void> refresh(CancelToken token) =>
      _bounded(token, (requestToken) async {
        _generation++;
        _snapshot = null;
        _loading = null;
        await _getSnapshot(requestToken);
      });

  Future<IkFetchedSourceUpdate> fetch(
    IkCatalogEntry entry,
    CancelToken token,
  ) => _bounded(token, (requestToken) async {
    final directory = _sourceKey.firstMatch(entry.sourceKey)?.group(1);
    if (directory == null) {
      throw const LxSourceException(
        'metadata',
        IkSourceUpdateStrings.invalidDirectory,
      );
    }
    final snapshot = await _getSnapshot(requestToken);
    var path = '$directory/latest.js';
    var blob = snapshot.entries[path];
    if (blob == null) {
      throw const LxSourceException(
        'sourceMissing',
        IkSourceUpdateStrings.upstreamSourceMissing,
      );
    }
    if (blob.mode == '120000' && blob.type == 'blob') {
      final linkBytes = await _verifiedBlob(
        snapshot.commit,
        blob,
        requestToken,
      );
      String target;
      try {
        target = utf8.decode(linkBytes, allowMalformed: false);
      } on FormatException {
        throw const LxSourceException(
          'metadata',
          IkSourceUpdateStrings.invalidUpstreamPathEncoding,
        );
      }
      final linkMatch = _linkTarget.firstMatch(target);
      final filename = linkMatch?.group(1);
      if (filename == null ||
          linkMatch!.end != target.length ||
          linkBytes.length != target.length) {
        throw const LxSourceException(
          'metadata',
          IkSourceUpdateStrings.invalidUpstreamLink,
        );
      }
      path = '$directory/$filename';
      blob = snapshot.entries[path];
    }
    if (blob == null ||
        blob.type != 'blob' ||
        (blob.mode != '100644' && blob.mode != '100755')) {
      throw const LxSourceException(
        'metadata',
        IkSourceUpdateStrings.invalidUpstreamFile,
      );
    }
    final bytes = await _verifiedBlob(snapshot.commit, blob, requestToken);
    return _result(
      bytes,
      _origin(snapshot.commit, path),
      upstreamCommit: snapshot.commit,
      upstreamBlobSha1: blob.sha,
      path: path,
    );
  });

  /// 自定义源始终跟随原导入地址；不猜latest或执行update_url。
  Future<IkFetchedSourceUpdate> fetchCustom(Uri origin, CancelToken token) =>
      _bounded(token, (requestToken) async {
        var normalized = lxImportUri(origin.toString());
        if (origin.hasQuery && !normalized.hasQuery) {
          normalized = normalized.replace(query: origin.query);
        }
        LxSourceException failure = const LxSourceException(
          'download',
          IkSourceUpdateStrings.downloadFailed,
        );
        // 带query的自定义URL可能有独立语义，镜像不可丢弃它。
        final candidates = normalized.hasQuery
            ? [normalized]
            : lxDownloadUris(normalized);
        for (final uri in candidates) {
          _checkCancelled(requestToken);
          try {
            final bytes = await _download(uri, requestToken);
            return _result(bytes, normalized);
          } on LxSourceException catch (error) {
            if (_terminal(error, requestToken)) rethrow;
            failure = error;
          } on DioException {
            _checkCancelled(requestToken);
          }
        }
        throw failure;
      });

  Future<_RepositorySnapshot> _getSnapshot(CancelToken token) async {
    _checkCancelled(token);
    if (_snapshot != null) return _snapshot!;
    final generation = _generation;
    late final Future<_RepositorySnapshot> pending;
    pending = _loading ??= _readSnapshot(token)
        .then((snapshot) {
          if (!_disposed && !token.isCancelled && generation == _generation) {
            _snapshot = snapshot;
          }
          return snapshot;
        })
        .whenComplete(() {
          if (identical(_loading, pending)) _loading = null;
        });
    return Future.any([
      pending,
      token.whenCancel.then<_RepositorySnapshot>((_) => throw _cancelled),
    ]);
  }

  Future<_RepositorySnapshot> _readSnapshot(CancelToken token) async {
    final reference = await _json(
      Uri.https('api.github.com', '/repos/$_repository/git/ref/heads/main'),
      token,
    );
    final object = reference['object'];
    final commit = object is Map ? object['sha'] : null;
    if (reference['ref'] != 'refs/heads/main' ||
        object is! Map ||
        object['type'] != 'commit' ||
        commit is! String ||
        !_gitSha.hasMatch(commit)) {
      throw const LxSourceException(
        'metadata',
        IkSourceUpdateStrings.invalidCommit,
      );
    }
    final commitBody = await _json(
      Uri.https('api.github.com', '/repos/$_repository/git/commits/$commit'),
      token,
    );
    final tree = commitBody['tree'];
    final treeSha = tree is Map ? tree['sha'] : null;
    if (commitBody['sha'] != commit ||
        treeSha is! String ||
        !_gitSha.hasMatch(treeSha)) {
      throw const LxSourceException(
        'metadata',
        IkSourceUpdateStrings.invalidTreeId,
      );
    }
    final treeBody = await _json(
      Uri.https('api.github.com', '/repos/$_repository/git/trees/$treeSha', {
        'recursive': '1',
      }),
      token,
    );
    final rows = treeBody['tree'];
    if (treeBody['sha'] != treeSha ||
        treeBody['truncated'] != false ||
        rows is! List) {
      throw const LxSourceException(
        'metadata',
        IkSourceUpdateStrings.mismatchedTree,
      );
    }
    final entries = <String, _TreeEntry>{};
    for (final row in rows) {
      if (row is! Map) {
        throw const LxSourceException(
          'metadata',
          IkSourceUpdateStrings.invalidTree,
        );
      }
      final path = row['path'];
      final sha = row['sha'];
      final mode = row['mode'];
      final type = row['type'];
      final size = row['size'];
      if (path is! String ||
          path.isEmpty ||
          entries.containsKey(path) ||
          sha is! String ||
          !_gitSha.hasMatch(sha) ||
          mode is! String ||
          type is! String ||
          (type == 'blob' && (size is! int || size < 0))) {
        throw const LxSourceException(
          'metadata',
          IkSourceUpdateStrings.invalidBlobInfo,
        );
      }
      entries[path] = _TreeEntry(path, sha, mode, type, size is int ? size : 0);
    }
    return _RepositorySnapshot(commit, Map.unmodifiable(entries));
  }

  Future<Map<String, dynamic>> _json(Uri uri, CancelToken token) async {
    final bytes = await _download(uri, token, metadata: true);
    try {
      final value = jsonDecode(utf8.decode(bytes, allowMalformed: false));
      if (value is Map<String, dynamic>) return value;
    } on FormatException {
      throw const LxSourceException(
        'metadata',
        IkSourceUpdateStrings.unreadableMetadata,
      );
    }
    throw const LxSourceException(
      'metadata',
      IkSourceUpdateStrings.invalidMetadata,
    );
  }

  Future<List<int>> _verifiedBlob(
    String commit,
    _TreeEntry blob,
    CancelToken token,
  ) async {
    if (blob.size <= 0 || blob.size > _maxBytes) {
      throw const LxSourceException(
        'size',
        IkSourceUpdateStrings.invalidFileSize,
      );
    }
    LxSourceException failure = const LxSourceException(
      'download',
      IkSourceUpdateStrings.downloadFailed,
    );
    for (final uri in lxDownloadUris(_origin(commit, blob.path))) {
      _checkCancelled(token);
      try {
        final bytes = await _download(uri, token);
        final sha = hashes.sha1.convert([
          ...utf8.encode('blob ${bytes.length}\u0000'),
          ...bytes,
        ]).toString();
        if (bytes.length != blob.size || sha != blob.sha) {
          failure = const LxSourceException(
            'integrity',
            IkSourceUpdateStrings.integrityMismatch,
          );
          continue;
        }
        return bytes;
      } on LxSourceException catch (error) {
        if (_terminal(error, token)) rethrow;
        failure = error;
      } on DioException {
        _checkCancelled(token);
      }
    }
    throw failure;
  }

  Future<List<int>> _download(
    Uri uri,
    CancelToken token, {
    bool metadata = false,
  }) async {
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      throw const LxSourceException(
        'link',
        IkSourceUpdateStrings.invalidUpdateUrl,
      );
    }
    _checkCancelled(token);
    final response = await _dio.getUri<ResponseBody>(
      uri,
      cancelToken: token,
      options: Options(
        responseType: ResponseType.stream,
        followRedirects: false,
        maxRedirects: 0,
        validateStatus: (_) => true,
        receiveTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 10),
        headers: {
          'User-Agent': 'IK-Music-source-update',
          if (metadata) 'Accept': 'application/vnd.github+json',
          if (metadata) 'X-GitHub-Api-Version': '2022-11-28',
        },
      ),
    );
    if (response.statusCode != 200 || response.data == null) {
      await response.data?.stream.listen(null).cancel();
      final limited =
          response.statusCode == 429 ||
          (metadata &&
              response.statusCode == 403 &&
              (response.headers.value('x-ratelimit-remaining') == '0' ||
                  response.headers.value('retry-after') != null));
      if (limited) {
        final seconds = int.tryParse(
          response.headers.value('x-ratelimit-reset') ?? '',
        );
        final retryAt = seconds != null && seconds > 0 && seconds < 10000000000
            ? DateTime.fromMillisecondsSinceEpoch(
                seconds * 1000,
                isUtc: true,
              ).toLocal().toIso8601String()
            : null;
        throw LxSourceException(
          'rateLimited',
          IkSourceUpdateStrings.rateLimited(metadata, retryAt),
        );
      }
      throw LxSourceException(
        'download',
        IkSourceUpdateStrings.httpFailure(response.statusCode),
      );
    }
    final declared = int.tryParse(
      response.headers.value('content-length') ?? '',
    );
    if (declared != null && declared > _maxBytes) {
      await response.data!.stream.listen(null).cancel();
      throw const LxSourceException(
        'size',
        IkSourceUpdateStrings.oversizedResponse,
      );
    }
    final bytes = <int>[];
    await for (final chunk in response.data!.stream) {
      _checkCancelled(token);
      if (bytes.length + chunk.length > _maxBytes) {
        throw const LxSourceException(
          'size',
          IkSourceUpdateStrings.oversizedResponse,
        );
      }
      bytes.addAll(chunk);
    }
    _checkCancelled(token);
    return bytes;
  }

  IkFetchedSourceUpdate _result(
    List<int> bytes,
    Uri origin, {
    String? upstreamCommit,
    String? upstreamBlobSha1,
    String? path,
  }) {
    String script;
    try {
      // UTF-8解码器自身剥离一个开头BOM，保留随后真实脚本字节的语义。
      script = utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      throw const LxSourceException(
        'invalidEncoding',
        IkSourceUpdateStrings.invalidEncoding,
      );
    }
    String? field(String key) =>
        RegExp('^\\s*(?:\\*|//)?\\s*@$key\\s+([^\\r\\n]+)', multiLine: true)
            .firstMatch(script)
            ?.group(1)
            ?.replaceFirst(RegExp(r'\s*\*/\s*$'), '')
            .trim();
    final name = field('name');
    if (script.trimLeft().startsWith('<') ||
        name == null ||
        name.isEmpty ||
        name.length > 160) {
      throw const LxSourceException(
        'script',
        IkSourceUpdateStrings.invalidScript,
      );
    }
    return IkFetchedSourceUpdate(
      script: script,
      name: name,
      version: field('version') ?? '',
      origin: origin,
      sha256: hashes.sha256.convert(utf8.encode(script)).toString(),
      contentSha256: hashes.sha256.convert(bytes).toString(),
      byteLength: bytes.length,
      upstreamCommit: upstreamCommit,
      upstreamBlobSha1: upstreamBlobSha1,
      path: path,
    );
  }

  Future<T> _bounded<T>(
    CancelToken parent,
    Future<T> Function(CancelToken) action,
  ) async {
    if (_disposed || parent.isCancelled) throw _cancelled;
    final token = CancelToken();
    _active.add(token);
    var timedOut = false;
    unawaited(parent.whenCancel.then((_) => token.cancel()));
    final timer = Timer(_deadline, () {
      timedOut = true;
      token.cancel();
    });
    try {
      final result = await Future.any<T>([
        Future<T>.sync(() => action(token)),
        token.whenCancel.then<T>((_) => throw _cancelled),
      ]);
      _checkCancelled(token);
      return result;
    } on LxSourceException {
      if (timedOut) {
        throw const LxSourceException(
          'timeout',
          IkSourceUpdateStrings.downloadTimeout,
        );
      }
      rethrow;
    } on DioException {
      if (timedOut) {
        throw const LxSourceException(
          'timeout',
          IkSourceUpdateStrings.downloadTimeout,
        );
      }
      if (token.isCancelled) throw _cancelled;
      throw const LxSourceException(
        'download',
        IkSourceUpdateStrings.networkUnavailable,
      );
    } finally {
      timer.cancel();
      token.cancel();
      _active.remove(token);
    }
  }

  static Uri _origin(String commit, String path) =>
      Uri.https('raw.githubusercontent.com', '/$_repository/$commit/$path');
  static const _cancelled = LxSourceException(
    'cancelled',
    IkSourceUpdateStrings.downloadCancelled,
  );
  static void _checkCancelled(CancelToken token) {
    if (token.isCancelled) throw _cancelled;
  }

  static bool _terminal(LxSourceException error, CancelToken token) =>
      token.isCancelled ||
      const ['cancelled', 'rateLimited', 'size'].contains(error.code);

  void dispose() {
    _disposed = true;
    _generation++;
    for (final token in _active) {
      token.cancel();
    }
    _snapshot = null;
    _loading = null;
    _dio.close(force: true);
  }
}

class _RepositorySnapshot {
  const _RepositorySnapshot(this.commit, this.entries);
  final String commit;
  final Map<String, _TreeEntry> entries;
}

class _TreeEntry {
  const _TreeEntry(this.path, this.sha, this.mode, this.type, this.size);
  final String path, sha, mode, type;
  final int size;
}

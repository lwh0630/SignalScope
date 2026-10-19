import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/app_info.dart';
import '../../../core/utils/app_version.dart';

/// One downloadable file of a GitHub release.
class ReleaseAsset {
  const ReleaseAsset({required this.name, required this.url, this.size});

  final String name;
  final Uri url;
  final int? size;
}

/// A published GitHub release.
class ReleaseInfo {
  const ReleaseInfo({
    required this.tag,
    required this.version,
    required this.notes,
    required this.assets,
  });

  /// e.g. `v1.2.0`.
  final String tag;
  final AppVersion version;

  /// Release notes (Markdown shown as plain text); may be empty.
  final String notes;
  final List<ReleaseAsset> assets;
}

/// A failed update step. [code] maps to the `update.err.<code>` string.
class UpdateException implements Exception {
  const UpdateException(this.code);

  /// `network`, `rate_limit`, `bad_response`, `bad_url`, `no_asset`,
  /// `no_checksum`, `download`, `cancelled`.
  final String code;

  @override
  String toString() => 'UpdateException($code)';
}

/// Decides which URLs the updater may contact.
typedef UrlPolicy = bool Function(Uri uri);

/// Production policy: HTTPS to GitHub only (API, release pages and the CDN that
/// serves release assets). Applied to the first URL and to every redirect.
bool githubOnlyPolicy(Uri uri) {
  if (uri.scheme != 'https') return false;
  final h = uri.host.toLowerCase();
  return h == 'github.com' ||
      h.endsWith('.github.com') ||
      h.endsWith('.githubusercontent.com');
}

/// Lets the UI stop a running download.
class UpdateCancel {
  bool _cancelled = false;
  bool get cancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// Talks to GitHub Releases with `dart:io` (no plugin, no analytics).
///
/// The only request made is an anonymous `GET` of the latest release; the only
/// thing sent besides standard HTTP headers is a `User-Agent` with the app version
/// (GitHub requires one). Draft and pre-release versions are never offered.
class UpdateRepository {
  UpdateRepository({
    Uri? latestReleaseUrl,
    UrlPolicy? urlPolicy,
    HttpClient Function()? clientFactory,
    this.requestTimeout = const Duration(seconds: 15),
    this.idleTimeout = const Duration(seconds: 30),
  }) : latestReleaseUrl =
           latestReleaseUrl ??
           Uri.parse(
             'https://api.github.com/repos/$kUpdateRepo/releases/latest',
           ),
       _policy = urlPolicy ?? githubOnlyPolicy,
       _clientFactory = clientFactory ?? HttpClient.new;

  static const String checksumAssetName = 'SHA256SUMS.txt';
  static const int _maxRedirects = 5;
  static const int _maxJsonBytes = 1024 * 1024;
  static const int _maxChecksumBytes = 64 * 1024;

  final Uri latestReleaseUrl;
  final Duration requestTimeout;
  final Duration idleTimeout;
  final UrlPolicy _policy;
  final HttpClient Function() _clientFactory;

  // ---- pure helpers (unit tested) ----

  /// Parses the GitHub "release" JSON. `null` for drafts, pre-releases and
  /// anything that does not carry a valid `vX.Y.Z` tag.
  static ReleaseInfo? parseRelease(Object? json) {
    if (json is! Map) return null;
    if (json['draft'] == true || json['prerelease'] == true) return null;
    final tag = json['tag_name'];
    if (tag is! String) return null;
    final version = AppVersion.tryParse(tag);
    if (version == null || version.isPreRelease) return null;
    final assets = <ReleaseAsset>[];
    final raw = json['assets'];
    if (raw is List) {
      for (final a in raw) {
        if (a is! Map) continue;
        final name = a['name'];
        final url = a['browser_download_url'];
        if (name is! String || url is! String) continue;
        final uri = Uri.tryParse(url);
        if (uri == null) continue;
        final size = a['size'];
        assets.add(
          ReleaseAsset(name: name, url: uri, size: size is int ? size : null),
        );
      }
    }
    final body = json['body'];
    return ReleaseInfo(
      tag: tag,
      version: version,
      notes: body is String ? body.trim() : '',
      assets: assets,
    );
  }

  /// The APK for the most preferred ABI of the device (`signalscope-<tag>-<abi>.apk`).
  static ReleaseAsset? pickApk(ReleaseInfo release, List<String> abis) {
    for (final abi in abis) {
      for (final a in release.assets) {
        if (a.name.startsWith('signalscope-') && a.name.endsWith('-$abi.apk')) {
          return a;
        }
      }
    }
    return null;
  }

  /// Parses `sha256sum` output (`<64 hex>  <file>` or `<64 hex> *<file>`).
  static Map<String, String> parseChecksums(String text) {
    final out = <String, String>{};
    final line = RegExp(r'^([0-9a-fA-F]{64})\s+\*?(.+?)\s*$');
    for (final l in const LineSplitter().convert(text)) {
      final m = line.firstMatch(l);
      if (m != null) out[m.group(2)!] = m.group(1)!.toLowerCase();
    }
    return out;
  }

  // ---- network ----

  /// The latest published release, or `null` when the repository has none.
  Future<ReleaseInfo?> fetchLatest({required String userAgent}) async {
    final bytes = await _getBytes(
      latestReleaseUrl,
      userAgent: userAgent,
      maxBytes: _maxJsonBytes,
      accept: 'application/vnd.github+json',
      notFoundIsNull: true,
    );
    if (bytes == null) return null;
    try {
      final json = jsonDecode(utf8.decode(bytes));
      if (json is! Map) throw const UpdateException('bad_response');
      return parseRelease(json);
    } on FormatException {
      throw const UpdateException('bad_response');
    }
  }

  /// Published SHA-256 (lower-case hex) of [assetName]. Throws `no_checksum`
  /// when the release has no checksum file or no entry for the APK.
  Future<String> fetchSha256(
    ReleaseInfo release,
    String assetName, {
    required String userAgent,
  }) async {
    final file = release.assets
        .where((a) => a.name == checksumAssetName)
        .firstOrNull;
    if (file == null) throw const UpdateException('no_checksum');
    final bytes = await _getBytes(
      file.url,
      userAgent: userAgent,
      maxBytes: _maxChecksumBytes,
    );
    final hash = parseChecksums(
      utf8.decode(bytes!, allowMalformed: true),
    )[assetName];
    if (hash == null) throw const UpdateException('no_checksum');
    return hash;
  }

  /// Downloads [asset] into [target]. A partial file is deleted on failure.
  Future<void> download(
    ReleaseAsset asset,
    File target, {
    required String userAgent,
    void Function(int received, int? total)? onProgress,
    UpdateCancel? cancel,
  }) async {
    final client = _clientFactory()..connectionTimeout = requestTimeout;
    IOSink? sink;
    try {
      final res = await _open(client, asset.url, {
        'User-Agent': userAgent,
        'Accept': 'application/octet-stream',
      });
      if (res.statusCode != 200) {
        await res.drain<void>();
        throw UpdateException(
          res.statusCode == 403 || res.statusCode == 429
              ? 'rate_limit'
              : 'download',
        );
      }
      final length = res.contentLength >= 0 ? res.contentLength : asset.size;
      sink = target.openWrite();
      var received = 0;
      await for (final chunk in res.timeout(idleTimeout)) {
        if (cancel?.cancelled == true) throw const UpdateException('cancelled');
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, length);
      }
      if (cancel?.cancelled == true) throw const UpdateException('cancelled');
      await sink.flush();
      await sink.close();
      sink = null;
      if (length != null && received != length) {
        throw const UpdateException('download');
      }
    } on UpdateException {
      await _discard(sink, target);
      rethrow;
    } on Object {
      await _discard(sink, target);
      throw const UpdateException('network');
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _discard(IOSink? sink, File target) async {
    try {
      await sink?.close();
    } on Object {
      // Already failing; the partial file is removed below.
    }
    try {
      if (await target.exists()) await target.delete();
    } on Object {
      // Best effort.
    }
  }

  Future<List<int>?> _getBytes(
    Uri uri, {
    required String userAgent,
    required int maxBytes,
    String accept = '*/*',
    bool notFoundIsNull = false,
  }) async {
    final client = _clientFactory()..connectionTimeout = requestTimeout;
    try {
      final res = await _open(client, uri, {
        'User-Agent': userAgent,
        'Accept': accept,
      });
      if (res.statusCode == 404 && notFoundIsNull) {
        await res.drain<void>();
        return null;
      }
      if (res.statusCode == 403 || res.statusCode == 429) {
        await res.drain<void>();
        throw const UpdateException('rate_limit');
      }
      if (res.statusCode != 200) {
        await res.drain<void>();
        throw const UpdateException('bad_response');
      }
      final out = <int>[];
      await for (final chunk in res.timeout(requestTimeout)) {
        out.addAll(chunk);
        if (out.length > maxBytes) throw const UpdateException('bad_response');
      }
      return out;
    } on UpdateException {
      rethrow;
    } on Object {
      throw const UpdateException('network');
    } finally {
      client.close(force: true);
    }
  }

  /// GET that follows redirects by hand so that every hop obeys the URL policy.
  Future<HttpClientResponse> _open(
    HttpClient client,
    Uri uri,
    Map<String, String> headers,
  ) async {
    var current = uri;
    for (var hop = 0; hop <= _maxRedirects; hop++) {
      if (!_policy(current)) throw const UpdateException('bad_url');
      final req = await client.getUrl(current).timeout(requestTimeout);
      req.followRedirects = false;
      headers.forEach(req.headers.set);
      final res = await req.close().timeout(requestTimeout);
      if (const {301, 302, 303, 307, 308}.contains(res.statusCode)) {
        final location = res.headers.value(HttpHeaders.locationHeader);
        await res.drain<void>();
        if (location == null) throw const UpdateException('bad_response');
        current = current.resolve(location);
        continue;
      }
      return res;
    }
    throw const UpdateException('bad_response');
  }
}

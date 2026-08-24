import 'dart:convert';
import 'dart:io';

import 'package:tidy/core/logging/logging.dart';
import 'package:tidy/core/updates/app_version.dart';
import 'package:tidy/core/updates/update_release.dart';

/// Reads the latest release from the GitHub Releases API.
///
/// `dart:io`'s `HttpClient` rather than a package. This is one GET returning
/// one JSON object, and `app_settings.dart` already makes the argument: a
/// dependency earns its place by doing something the SDK cannot. It also keeps
/// the promise in Settings honest — there is exactly one URL in this file, and
/// it is visible.
///
/// Every failure resolves to null. A background check that throws would take
/// out the timer that scheduled it, and there is nothing a user can do about
/// GitHub being unreachable except be told the check did not happen.
class GitHubReleaseClient {
  GitHubReleaseClient({
    HttpClient? client,
    String? repo,
    bool? includePrerelease,
  }) : _client = client ?? (HttpClient()..connectionTimeout = _timeout),
       _repo = repo ?? defaultRepo,
       _includePrerelease = includePrerelease ?? defaultIncludePrerelease;

  final HttpClient _client;
  final String _repo;
  final bool _includePrerelease;

  static const Duration _timeout = Duration(seconds: 15);

  /// Overridable so a release can be rehearsed against a scratch repo before
  /// it is published to the real one. Same shape as `TIDY_LOG_LEVEL`.
  static const String defaultRepo = String.fromEnvironment(
    'TIDY_UPDATE_REPO',
    defaultValue: 'yunweneric/tidy',
  );

  /// Testing only: `/releases/latest` ignores prereleases, which is right for
  /// users and useless for rehearsing the flow against one.
  static const bool defaultIncludePrerelease = bool.fromEnvironment(
    'TIDY_UPDATE_PRERELEASE',
  );

  /// The newest release, or null if there is none, or the request failed.
  ///
  /// [currentVersion] only shapes the `User-Agent`; the caller decides whether
  /// what comes back is newer. GitHub rejects requests without a `User-Agent`
  /// outright, so it is not optional.
  Future<UpdateRelease?> latest({String currentVersion = '0.0.0'}) async {
    final path =
        _includePrerelease
            ? '/repos/$_repo/releases?per_page=1'
            : '/repos/$_repo/releases/latest';
    final url = Uri.https('api.github.com', path);

    try {
      final request = await _client.getUrl(url).timeout(_timeout);
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.userAgentHeader, 'Tidy/$currentVersion (macOS)')
        ..set('X-GitHub-Api-Version', '2022-11-28');

      final response = await request.close().timeout(_timeout);
      final body = await response.transform(utf8.decoder).join();

      // 404 is the ordinary state of a repository with no releases yet, and
      // 403 is the unauthenticated rate limit (60/hour/IP). Neither is a bug,
      // and neither should reach the user as an error.
      if (response.statusCode != HttpStatus.ok) {
        AppLog.updates.debug(
          'release lookup returned no release',
          fields: {'status': response.statusCode, 'repo': _repo},
        );
        return null;
      }

      final decoded = jsonDecode(body);
      final json =
          _includePrerelease
              ? (decoded is List && decoded.isNotEmpty ? decoded.first : null)
              : decoded;
      if (json is! Map<String, dynamic>) return null;

      return await _parse(json, currentVersion);
    } catch (e) {
      AppLog.updates.failed('check for updates', e, fields: {'repo': _repo});
      return null;
    }
  }

  Future<UpdateRelease?> _parse(
    Map<String, dynamic> json,
    String currentVersion,
  ) async {
    if (json['draft'] == true) return null;

    final tag = json['tag_name'] as String? ?? '';
    final version = AppVersion.parse(tag);
    if (version == null) {
      AppLog.updates.debug('ignoring an unparseable tag', fields: {'tag': tag});
      return null;
    }

    final assets = (json['assets'] as List?) ?? const [];
    final zip = _asset(assets, _isUpdaterZip) ?? _asset(assets, _isAnyZip);
    if (zip == null) {
      // A release with no zip is a manual-download-only release. Reporting it
      // as available would offer a Download button with nothing behind it.
      AppLog.updates.warn(
        'release has no macOS zip to install',
        fields: {'tag': tag},
      );
      return null;
    }

    final url = Uri.tryParse(zip['browser_download_url'] as String? ?? '');
    if (url == null) return null;

    final dmg = _asset(assets, (name) => name.endsWith('.dmg'));

    // GitHub only records `digest` for assets uploaded recently enough, and
    // reports nothing at all for older releases, so it cannot be relied on.
    // `scripts/release.sh` publishes a SHA256SUMS.txt alongside the artifacts
    // for exactly this reason: falling back to it means every release has a
    // digest whether or not GitHub happened to record one.
    final digest =
        _digest(zip['digest'] as String?) ??
        await _checksum(
          assets,
          forAsset: zip['name'] as String? ?? '',
          currentVersion: currentVersion,
        );

    return UpdateRelease(
      version: version,
      tag: tag,
      name:
          (json['name'] as String?)?.trim().isNotEmpty == true
              ? (json['name'] as String).trim()
              : tag,
      notes: (json['body'] as String? ?? '').trim(),
      zipUrl: url,
      zipBytes: (zip['size'] as num?)?.toInt() ?? 0,
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? ''),
      sha256: digest,
      dmgUrl: Uri.tryParse(dmg?['browser_download_url'] as String? ?? ''),
      isPrerelease: json['prerelease'] == true,
    );
  }

  /// Reads the digest for [forAsset] out of the release's `SHA256SUMS.txt`.
  ///
  /// Null when there is no such asset, or it does not mention the file. The
  /// caller treats a missing digest as "no integrity check available" — which
  /// a Developer ID signature covers for, and which an unsigned build refuses
  /// to install without.
  Future<String?> _checksum(
    List<dynamic> assets, {
    required String forAsset,
    required String currentVersion,
  }) async {
    if (forAsset.isEmpty) return null;
    final sums = _asset(assets, (name) => name == 'sha256sums.txt');
    final url = Uri.tryParse(sums?['browser_download_url'] as String? ?? '');
    if (url == null) return null;

    try {
      final request = await _client.getUrl(url).timeout(_timeout);
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Tidy/$currentVersion (macOS)',
      );
      final response = await request.close().timeout(_timeout);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return null;
      }

      final body = await response.transform(utf8.decoder).join();
      for (final line in const LineSplitter().convert(body)) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length < 2 || parts.last != forAsset) continue;
        final hex = parts.first.toLowerCase();
        if (hex.length == 64) return hex;
      }
    } catch (e) {
      AppLog.updates.failed('read the release checksums', e);
    }
    return null;
  }

  static Map<String, dynamic>? _asset(
    List<dynamic> assets,
    bool Function(String name) matches,
  ) {
    for (final raw in assets) {
      if (raw is! Map) continue;
      final name = raw['name'] as String? ?? '';
      if (matches(name.toLowerCase())) return raw.cast<String, dynamic>();
    }
    return null;
  }

  /// What `scripts/release.sh` names the updater's artifact.
  static bool _isUpdaterZip(String name) =>
      name.startsWith('tidy-') && name.endsWith('-macos.zip');

  static bool _isAnyZip(String name) => name.endsWith('.zip');

  /// GitHub reports digests as `sha256:abc123…`; the native side wants the hex.
  static String? _digest(String? raw) {
    if (raw == null) return null;
    const prefix = 'sha256:';
    if (!raw.startsWith(prefix)) return null;
    final hex = raw.substring(prefix.length).trim().toLowerCase();
    return hex.length == 64 ? hex : null;
  }

  void close() => _client.close(force: true);
}

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:tidy/landing/data/github_release.dart';
import 'package:tidy/landing/data/tidy_repo.dart';

/// Reads the latest release and the star count straight from GitHub's public
/// API.
///
/// Both endpoints are unauthenticated and CORS-enabled, which is what makes
/// this possible from a static page with no backend — and also why the
/// download button resolves *releases* rather than Actions artifacts, since
/// artifact downloads need a token a public page cannot carry.
class GithubService {
  GithubService({http.Client? client, this.apiBase = TidyRepo.api})
    : _client = client ?? http.Client();

  final http.Client _client;

  /// Overridable so the resolved-release UI can be exercised against another
  /// repository without waiting for this one to publish.
  final String apiBase;

  static const Duration _timeout = Duration(seconds: 8);

  static const Map<String, String> _headers = {
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  ReleaseState? _cachedRelease;
  int? _cachedStars;

  Future<ReleaseState> latestRelease({bool refresh = false}) async {
    final cached = _cachedRelease;
    if (cached != null && !refresh) return cached;

    final state = await _fetchLatestRelease();
    // Never cache a transient failure: a visitor who reconnects and presses
    // "Try again" should get a real request, not the error they already saw.
    if (state is! ReleaseUnavailable) _cachedRelease = state;
    return state;
  }

  Future<ReleaseState> _fetchLatestRelease() async {
    try {
      final response = await _client
          .get(Uri.parse('$apiBase/releases/latest'), headers: _headers)
          .timeout(_timeout);

      if (response.statusCode == 404) return const ReleasePending();
      if (response.statusCode == 403 || response.statusCode == 429) {
        return const ReleaseUnavailable(
          'GitHub is rate limiting this browser.',
        );
      }
      if (response.statusCode != 200) {
        return ReleaseUnavailable(
          'GitHub answered with ${response.statusCode}.',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return const ReleaseUnavailable('GitHub returned an unexpected reply.');
      }

      final release = GithubRelease.fromJson(decoded);
      // A tag whose build jobs failed still creates a release, just an empty
      // one. Offering a version with nothing to download is worse than saying
      // the build is not ready.
      return release.hasDownloads
          ? ReleaseReady(release)
          : const ReleasePending();
    } on TimeoutException {
      return const ReleaseUnavailable('GitHub took too long to answer.');
    } on http.ClientException {
      return const ReleaseUnavailable('Could not reach GitHub.');
    } on FormatException {
      return const ReleaseUnavailable('GitHub returned an unexpected reply.');
    }
  }

  /// Best effort. A missing star count hides the chip; it never shows an error.
  Future<int?> stars() async {
    final cached = _cachedStars;
    if (cached != null) return cached;

    try {
      final response = await _client
          .get(Uri.parse(apiBase), headers: _headers)
          .timeout(_timeout);
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;

      final count = decoded['stargazers_count'];
      if (count is! int) return null;
      return _cachedStars = count;
    } on Exception {
      return null;
    }
  }

  void dispose() => _client.close();
}

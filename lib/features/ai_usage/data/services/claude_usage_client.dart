import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tidy/core/design/brand.dart';
import 'package:tidy/core/logging/logging.dart';
import 'package:tidy/features/ai_usage/data/models/claude_plan_usage.dart';

/// Asks Anthropic what is left of the plan, using the credentials Claude Code
/// already stores on this Mac.
///
/// This is the one part of AI Usage that leaves the machine, which is why it is
/// off until switched on and why there is exactly one URL in this file. It
/// sends the account's own OAuth token to the service that issued it and asks
/// one question — the same request `claude` makes to draw `/usage` — and gets
/// back percentages. No prompt text, no file paths, nothing about the Mac.
///
/// Nothing here mints, refreshes or stores a token: the refresh exchange needs
/// client secrets that belong to Claude Code, so when the stored token is near
/// expiry this shells out to `claude` and lets it do its own renewal, then
/// re-reads what it wrote. A copy of that exchange here would be a second
/// implementation of somebody else's auth, wrong the first time they change it.
class ClaudeUsageClient {
  ClaudeUsageClient({HttpClient? client})
    : _client = client ?? (HttpClient()..connectionTimeout = _timeout);

  final HttpClient _client;

  static const Duration _timeout = Duration(seconds: 10);

  /// Renew the token this long before it actually expires, so a fetch does not
  /// race the clock and come back 401.
  static const Duration _refreshSkew = Duration(minutes: 4);

  /// The endpoint. `anthropic-beta` is not optional — without it the request is
  /// answered as an ordinary API call and never sees the OAuth usage record.
  static final Uri _endpoint = Uri.https(
    'api.anthropic.com',
    '/api/oauth/usage',
  );
  static const String _betaHeader = 'oauth-2025-04-20';

  ClaudePlanUsage? _cached;
  Future<ClaudePlanReading>? _inFlight;
  bool _restored = false;

  /// Set after a 429, and after an account turns out to meter nothing. Until it
  /// passes, [fetch] serves what it has and asks nothing — retrying into a rate
  /// limit is how a soft limit becomes a hard one, and re-asking an account
  /// with no limits gets the same answer every time.
  DateTime? _pausedUntil;

  /// Why the pause is in force, so the caller can say which it is.
  ClaudePlanStatus _pausedBecause = ClaudePlanStatus.unreachable;

  List<String>? _serviceNames;

  /// The last reading, without asking for a new one.
  ClaudePlanUsage? get cached => _cached;

  /// Whether this Mac has Claude Code credentials at all.
  ///
  /// Separate from [fetch] so the page can tell "not signed in to Claude Code"
  /// apart from "asked and could not reach it" — one is a thing the user can
  /// fix, the other is weather.
  Future<bool> hasCredentials() async => await _readCredentials() != null;

  /// The current reading, from cache when it is fresh enough.
  ///
  /// Never throws. This is called from a one-minute timer, and a throw here
  /// would take out the publisher that scheduled it. A failure comes back as a
  /// [ClaudePlanStatus] instead, because a percentage that could not be fetched
  /// is not a zero and the panel has to say which kind of nothing it is.
  Future<ClaudePlanReading> fetch({bool force = false}) async {
    // A reading from a previous run, so a cold launch draws bars in the first
    // frame instead of blank rows until the first request lands.
    if (!_restored) {
      _restored = true;
      _cached ??= await _restore();
    }

    final now = DateTime.now();

    final held = _cached;
    if (!force &&
        held != null &&
        now.difference(held.fetchedAt) < kClaudePlanCacheFor) {
      return ClaudePlanReading(ClaudePlanStatus.ready, usage: held);
    }

    final until = _pausedUntil;
    if (until != null && now.isBefore(until)) {
      return ClaudePlanReading(_pausedBecause, usage: held, retryAt: until);
    }

    // One fetch at a time. Two callers arriving together must not become two
    // keychain reads and two requests.
    return _inFlight ??= _fetch()..whenComplete(() => _inFlight = null);
  }

  Future<ClaudePlanReading> _fetch() async {
    var credentials = await _readCredentials();
    if (credentials == null) {
      // Deliberately not paused: signing in to Claude Code is a thing the user
      // may do at any moment, and the next tick should notice.
      return const ClaudePlanReading(ClaudePlanStatus.notSignedIn);
    }

    if (credentials.expiresWithin(_refreshSkew)) {
      if (await _renewViaClaudeCli()) {
        credentials = await _readCredentials() ?? credentials;
      }
    }

    var outcome = await _get(credentials.accessToken);

    // One retry, and only for the failure a renewal can actually fix. The
    // stored token can be stale for reasons the expiry stamp does not show —
    // revoked, or rotated on another machine — so a 401 is worth one renewal
    // even when the clock said the token was fine.
    if (outcome is _FetchUnauthorized) {
      if (await _renewViaClaudeCli()) {
        final renewed = await _readCredentials();
        if (renewed != null) outcome = await _get(renewed.accessToken);
      }
    }

    switch (outcome) {
      case _FetchOk(:final usage):
        _pausedUntil = null;
        _cached = usage;
        unawaited(_persist(usage));
        return ClaudePlanReading(ClaudePlanStatus.ready, usage: usage);

      case _FetchUnauthorized():
        // A renewal was tried and the token is still refused: this is the same
        // dead end as having none, and the sentence to show is the same.
        return ClaudePlanReading(ClaudePlanStatus.notSignedIn, usage: _cached);

      case _FetchNoLimits():
        _pause(kClaudePlanNoLimitsBackoff, ClaudePlanStatus.noLimits);
        return ClaudePlanReading(
          ClaudePlanStatus.noLimits,
          retryAt: _pausedUntil,
        );

      case _FetchRateLimited(:final retryAfter):
        _pause(retryAfter, ClaudePlanStatus.rateLimited);
        return ClaudePlanReading(
          ClaudePlanStatus.rateLimited,
          usage: _cached,
          retryAt: _pausedUntil,
        );

      case _FetchFailed():
        return ClaudePlanReading(ClaudePlanStatus.unreachable, usage: _cached);
    }
  }

  void _pause(Duration by, ClaudePlanStatus because) {
    _pausedUntil = DateTime.now().add(by);
    _pausedBecause = because;
  }

  Future<_FetchOutcome> _get(String token) async {
    try {
      final request = await _client.getUrl(_endpoint).timeout(_timeout);
      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
        ..set('anthropic-beta', _betaHeader)
        ..set(HttpHeaders.contentTypeHeader, 'application/json')
        ..set(HttpHeaders.userAgentHeader, 'Tidy (macOS)');

      final response = await request.close().timeout(_timeout);
      final body = await response.transform(utf8.decoder).join();

      switch (response.statusCode) {
        case HttpStatus.ok:
          final decoded = jsonDecode(body);
          if (decoded is! Map) return const _FetchFailed();
          final usage = ClaudePlanUsage.parseApi(decoded);
          // An account with no metered limits answers 200 with every window
          // null — an API-key or Console plan. Its own outcome rather than a
          // failure: nothing went wrong, there is simply nothing to draw, and
          // asking again in two minutes will get the same answer.
          return usage.isEmpty ? const _FetchNoLimits() : _FetchOk(usage);

        case HttpStatus.unauthorized:
        case HttpStatus.forbidden:
          return const _FetchUnauthorized();

        case HttpStatus.tooManyRequests:
          final seconds =
              int.tryParse(response.headers.value('retry-after') ?? '') ?? 60;
          AppLog.aiUsage.debug(
            'Claude usage endpoint rate limited',
            fields: {'retry_after_s': seconds},
          );
          return _FetchRateLimited(Duration(seconds: seconds));

        default:
          AppLog.aiUsage.debug(
            'Claude usage endpoint returned no reading',
            fields: {'status': response.statusCode},
          );
          return const _FetchFailed();
      }
    } catch (e) {
      // Offline, DNS, timeout, malformed JSON. All the same to the caller:
      // there is no reading, and the last one stands until it goes stale.
      AppLog.aiUsage.failed('read the Claude plan limits', e);
      return const _FetchFailed();
    }
  }

  // ─── The last reading, across runs ────────────────────────────────────────
  //
  // One small file beside the usage cache, for the same reason that one exists:
  // the first paint after launch should not be blank while a request is in
  // flight. The reading ages out on its own through `isStaleAt`, so a stale
  // file cannot show a percentage from last week — the worst it can do is show
  // one from ten minutes ago, which is what the in-memory cache would have
  // shown anyway.

  File? _file;

  Future<File?> _resolveFile() async {
    if (_file != null) return _file;
    final home = Platform.environment['HOME'];
    if (home == null) return null;

    final dir = Directory(
      p.join(
        home,
        'Library',
        'Application Support',
        Brand.supportDirectoryName,
      ),
    );
    try {
      if (!dir.existsSync()) await dir.create(recursive: true);
    } on FileSystemException catch (e) {
      AppLog.aiUsage.failed('create the support directory', e);
      return null;
    }
    return _file = File(p.join(dir.path, 'claude_plan.json'));
  }

  Future<ClaudePlanUsage?> _restore() async {
    try {
      final file = await _resolveFile();
      if (file == null || !file.existsSync()) return null;
      final decoded = jsonDecode(await file.readAsString());
      final usage = ClaudePlanUsage.fromJson(decoded);
      // Restoring something already too old to draw would only put a reading
      // in hand that every caller then has to discard.
      if (usage == null || usage.isStaleAt(DateTime.now())) return null;
      return usage;
    } catch (e) {
      // A cache that cannot be read is a blank first frame, not a broken page.
      AppLog.aiUsage.failed('read the stored Claude plan reading', e);
      return null;
    }
  }

  Future<void> _persist(ClaudePlanUsage usage) async {
    try {
      final file = await _resolveFile();
      await file?.writeAsString(jsonEncode(usage.toJson()));
    } catch (e) {
      AppLog.aiUsage.failed('store the Claude plan reading', e);
    }
  }

  // ─── Credentials ─────────────────────────────────────────────────────────

  /// Claude Code's stored credentials, from the Keychain or its fallback file.
  Future<_ClaudeCredentials?> _readCredentials() async {
    if (Platform.isMacOS) {
      final fromKeychain = await _readFromKeychain();
      if (fromKeychain != null) return fromKeychain;
    }
    return _readFromFile();
  }

  /// Reads the Keychain item through `/usr/bin/security`, deliberately.
  ///
  /// Claude Code writes the item with that same binary, so `security` is on the
  /// item's access list and reading it back through `security` is allowed
  /// without a prompt. Going through the Security framework in-process would
  /// make Tidy the accessing application — a different app, not on the list —
  /// and the user would get a "Tidy wants to use your confidential information"
  /// panel for a number in a sidebar.
  Future<_ClaudeCredentials?> _readFromKeychain() async {
    // One service can hold several items under different accounts, and only one
    // of them carries `claudeAiOauth` — the others hold MCP tokens. Which one
    // an account-less lookup returns is not consistent between Macs, so every
    // candidate is tried and only an item that yields a token is taken.
    final accounts = <String?>['unknown', Platform.environment['USER'], null];

    for (final service in await _keychainServices()) {
      for (final account in accounts) {
        final found = await _keychainItem(service, account);
        if (found != null) return found;
      }
    }
    return null;
  }

  /// The service names to try, legacy name first.
  ///
  /// Claude Code moved from a single `Claude Code-credentials` item to one
  /// suffixed per installation, so the name cannot be hard-coded any more. The
  /// metadata dump is a dump of *names*: `security dump-keychain` without `-d`
  /// reads no secrets and raises no prompt. Cached because it is the slowest
  /// step here and the answer does not change while the app is running.
  Future<List<String>> _keychainServices() async {
    const legacy = 'Claude Code-credentials';
    final held = _serviceNames;
    if (held != null) return held;

    final names = <String>[legacy];
    try {
      final dump = await Process.run('/usr/bin/security', ['dump-keychain']);
      final pattern = RegExp('"($legacy[^"]*)"');
      for (final match in pattern.allMatches('${dump.stdout}')) {
        final name = match.group(1);
        if (name != null && !names.contains(name)) names.add(name);
      }
    } catch (e) {
      AppLog.aiUsage.failed('list the Claude Code keychain items', e);
    }
    return _serviceNames = names;
  }

  Future<_ClaudeCredentials?> _keychainItem(
    String service,
    String? account,
  ) async {
    try {
      final result = await Process.run('/usr/bin/security', [
        'find-generic-password',
        '-s',
        service,
        if (account != null) ...['-a', account],
        '-w',
      ]);
      if (result.exitCode != 0) return null;
      return _ClaudeCredentials.parse('${result.stdout}');
    } catch (e) {
      return null;
    }
  }

  /// Where Claude Code keeps credentials when there is no Keychain to use, and
  /// where it still keeps them for some installs on macOS.
  Future<_ClaudeCredentials?> _readFromFile() async {
    final configured = Platform.environment['CLAUDE_CONFIG_DIR'];
    final home = Platform.environment['HOME'];
    final dir = configured ?? (home == null ? null : '$home/.claude');
    if (dir == null) return null;

    final file = File('$dir/.credentials.json');
    try {
      if (!await file.exists()) return null;
      return _ClaudeCredentials.parse(await file.readAsString());
    } catch (e) {
      AppLog.aiUsage.failed('read the Claude Code credentials file', e);
      return null;
    }
  }

  /// Hands the refresh back to the tool that owns it.
  ///
  /// `claude auth status` performs the renewal as a side effect and writes the
  /// new token where it found the old one. `BROWSER=true` is the guard that
  /// matters: without it a token past saving makes the CLI open a sign-in page,
  /// and a usage bar must never launch a browser on its own.
  Future<bool> _renewViaClaudeCli() async {
    for (final cli in _cliCandidates()) {
      try {
        final result = await Process.run(
          cli,
          ['auth', 'status', '--json'],
          environment: const {'BROWSER': 'true'},
        ).timeout(const Duration(seconds: 12));
        if (result.exitCode == 0) return true;
      } catch (e) {
        // Not there, not executable, or it hung. Try the next path.
        continue;
      }
    }
    return false;
  }

  static List<String> _cliCandidates() {
    final home = Platform.environment['HOME'];
    final candidates = <String>[
      if (Platform.environment['CLAUDE_CLI_PATH'] case final path?) path,
      // A GUI app inherits no login-shell PATH, so the usual install sites are
      // named rather than searched for.
      if (home != null) ...[
        '$home/.local/bin/claude',
        '$home/.claude/local/claude',
      ],
      '/opt/homebrew/bin/claude',
      '/usr/local/bin/claude',
    ];
    for (final dir in (Platform.environment['PATH'] ?? '').split(':')) {
      if (dir.isEmpty) continue;
      final path = '$dir/claude';
      if (!candidates.contains(path)) candidates.add(path);
    }
    return candidates;
  }
}

/// What came back, kept as a type so "no reading" and "the token was rejected"
/// cannot be confused — only the second is worth a renewal and a retry.
sealed class _FetchOutcome {
  const _FetchOutcome();
}

class _FetchOk extends _FetchOutcome {
  const _FetchOk(this.usage);

  final ClaudePlanUsage usage;
}

class _FetchFailed extends _FetchOutcome {
  const _FetchFailed();
}

class _FetchUnauthorized extends _FetchOutcome {
  const _FetchUnauthorized();
}

/// Answered, and this account meters nothing.
class _FetchNoLimits extends _FetchOutcome {
  const _FetchNoLimits();
}

class _FetchRateLimited extends _FetchOutcome {
  const _FetchRateLimited(this.retryAfter);

  final Duration retryAfter;
}

class _ClaudeCredentials {
  const _ClaudeCredentials({required this.accessToken, this.expiresAt});

  final String accessToken;
  final DateTime? expiresAt;

  /// Unknown expiry counts as "not expiring": the request itself is the test,
  /// and renewing on every fetch would spawn a CLI once a minute.
  bool expiresWithin(Duration skew) {
    final at = expiresAt;
    if (at == null) return false;
    return at.isBefore(DateTime.now().add(skew));
  }

  static _ClaudeCredentials? parse(String raw) {
    // `security -w` prints the secret with a stray control byte in front of it
    // on some systems, which is enough to fail the decode.
    final start = raw.indexOf('{');
    if (start < 0) return null;

    try {
      final decoded = jsonDecode(raw.substring(start));
      if (decoded is! Map) return null;
      final oauth = decoded['claudeAiOauth'];
      // The item that holds only `mcpOAuth` is a different token for a
      // different service, and sending it to the usage endpoint would be a 401
      // that looks like an expired login.
      if (oauth is! Map) return null;

      final token = oauth['accessToken'] ?? oauth['access_token'];
      if (token is! String || token.isEmpty) return null;

      return _ClaudeCredentials(
        accessToken: token,
        expiresAt: _expiry(oauth['expiresAt'] ?? oauth['expires_at']),
      );
    } catch (e) {
      return null;
    }
  }

  /// Seconds and milliseconds both appear in the wild. Anything below the year
  /// 2001 read as milliseconds is really a seconds stamp, which would otherwise
  /// land in 1970 and make every token look expired.
  static DateTime? _expiry(Object? value) {
    if (value is! num) return null;
    final raw = value.toInt();
    if (raw <= 0) return null;
    final millis = raw < 100000000000 ? raw * 1000 : raw;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }
}

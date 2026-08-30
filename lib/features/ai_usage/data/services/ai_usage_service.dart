import 'dart:async';
import 'dart:io';

import 'package:tidy/core/logging/logging.dart';
import 'package:tidy/core/settings/app_settings.dart';
import 'package:tidy/features/ai_usage/data/models/ai_provider.dart';
import 'package:tidy/features/ai_usage/data/models/ai_usage_report.dart';
import 'package:tidy/features/ai_usage/data/models/ai_usage_summary.dart';
import 'package:tidy/features/ai_usage/data/models/claude_plan_usage.dart';
import 'package:tidy/features/ai_usage/data/services/ai_usage_bridge.dart';
import 'package:tidy/features/ai_usage/data/services/claude_usage_client.dart';
import 'package:tidy/features/ai_usage/data/parsing/usage_merge.dart';
import 'package:tidy/features/ai_usage/data/parsing/usage_scan.dart';
import 'package:tidy/features/ai_usage/data/services/ai_usage_cache.dart';

/// Reads the AI CLIs' session logs and hands back what they add up to.
///
/// Holds the last report so switching away from the page and back does not
/// re-sweep 1.5 GB, and owns the on-disk cache so a cold launch does not
/// either.
class AiUsageService {
  AiUsageService({
    required AppSettings settings,
    AiUsageCache? cache,
    ClaudeUsageClient? claude,
  }) : _settings = settings,
       _cache = cache ?? AiUsageCache(),
       _claude = claude ?? ClaudeUsageClient();

  /// How often the menu bar's summary is refreshed.
  static const Duration _publishInterval = Duration(minutes: 1);

  final AppSettings _settings;
  final AiUsageCache _cache;
  final ClaudeUsageClient _claude;

  AiUsageReport? _report;
  Future<AiUsageReport>? _inFlight;
  Timer? _publisher;

  /// The last sweep's result, or null if there has not been one.
  AiUsageReport? get cached => _report;

  /// Sweeps the logs, or returns the held report.
  ///
  /// Concurrent callers share one sweep: the page and a background refresh
  /// asking at the same moment should not spawn two isolates over the same
  /// gigabyte.
  Future<AiUsageReport> load({
    bool refresh = false,
    void Function(UsageScanProgress progress)? onProgress,
  }) {
    if (!refresh && _report != null) return Future.value(_report);
    return _inFlight ??= _sweep(onProgress: onProgress)
      ..whenComplete(() => _inFlight = null);
  }

  /// Throws the cache away and reads every log from scratch.
  ///
  /// The way out if the numbers ever look wrong — the cache is derived, so
  /// there is nothing here that a re-read cannot rebuild.
  Future<AiUsageReport> rebuild({
    void Function(UsageScanProgress progress)? onProgress,
  }) async {
    await _cache.clear();
    _report = null;
    return load(refresh: true, onProgress: onProgress);
  }

  Future<AiUsageReport> _sweep({
    void Function(UsageScanProgress progress)? onProgress,
  }) async {
    final roots = _roots();
    if (roots.isEmpty) {
      // Every provider switched off in Settings. An empty report, not an error.
      return _report = const AiUsageReport();
    }

    final started = DateTime.now();
    final cached = await _cache.read();

    try {
      final scan = await runUsageScan(
        roots: roots,
        cached: cached,
        onProgress: onProgress,
      );
      await _cache.write(scan.files);

      if (scan.unreadableFiles > 0) {
        // The sweep runs in an isolate with no logger of its own, so its
        // swallowed exceptions are logged here instead — `docs/feature.md` §4b
        // is about the failure being findable, not about where the catch sits.
        AppLog.aiUsage.warn(
          'could not read every session log',
          fields: {
            'count': scan.unreadableFiles,
            'paths': scan.unreadablePaths.join(', '),
          },
        );
      }

      final report = buildReport(scan).withClaudePlan(await _claudePlan());
      AppLog.aiUsage.info(
        'read the AI session logs',
        fields: {
          'files': scan.filesScanned,
          'parsed': scan.filesParsed,
          'unreadable': scan.unreadableFiles,
          'days': report.days.length,
          'ms': DateTime.now().difference(started).inMilliseconds,
        },
      );
      return _report = report;
    } catch (e) {
      AppLog.aiUsage.failed('sweep the AI session logs', e);
      // Whatever was held is better than nothing, and an empty report at least
      // renders the empty state rather than a broken page.
      return _report ??= const AiUsageReport();
    }
  }

  /// Keeps the menu bar's summary fresh.
  ///
  /// Main engine only, and started from the composition root rather than from
  /// here — the popover has no `AiUsageService` at all, and two engines
  /// sweeping the same gigabyte on a timer is exactly what one owner prevents.
  ///
  /// A minute, not a second. A cost figure only moves when a reply lands, and
  /// each pass is a warm sweep: every unchanged log comes straight from the
  /// cache, so the work is a `stat` per file and nothing else. Sampling this at
  /// the network readout's cadence would spend an isolate a second to redraw a
  /// number that had not changed.
  void startPublishing({Duration every = _publishInterval}) {
    if (_publisher != null) return;
    // Once immediately, so the bar is right within a second of launch rather
    // than a minute into it.
    unawaited(_publish());
    _publisher = Timer.periodic(every, (_) => unawaited(_publish()));
  }

  void stopPublishing() {
    _publisher?.cancel();
    _publisher = null;
  }

  Future<void> _publish() async {
    try {
      final report = await load(refresh: true);
      await AiUsageBridge.publish(report.summarise());
    } catch (e) {
      // The bar keeps whatever it last had, which is a stale number rather than
      // a wrong one — the native side ages it out on its own.
      AppLog.aiUsage.failed('refresh the menu bar summary', e);
    }
  }

  /// Claude's published limits, or null when the setting is off or the fetch
  /// did not answer.
  ///
  /// Awaited rather than raced with the sweep because the sweep is the slow
  /// half by two orders of magnitude — a warm pass is a `stat` per file, and
  /// this is one request with its own timeout and its own cache. Never allowed
  /// to throw: a plan reading that could not be fetched must cost the bar, not
  /// the whole report it would have decorated.
  Future<ClaudePlanReading> _claudePlan({bool force = false}) async {
    if (!_settings.aiUsageClaudeLimits) return const ClaudePlanReading.off();
    if (!_settings.aiUsageIncludeClaude) return const ClaudePlanReading.off();
    try {
      return await _claude.fetch(force: force);
    } catch (e) {
      AppLog.aiUsage.failed('read the Claude plan limits', e);
      return const ClaudePlanReading(ClaudePlanStatus.unreachable);
    }
  }

  /// Whether Claude Code is signed in on this Mac, so the limits fetch has
  /// something to use.
  ///
  /// What Settings asks before offering the switch: a toggle that can only ever
  /// fail is worse than one that explains why, and "sign in to Claude Code
  /// first" is a thing the user can act on.
  Future<bool> hasClaudeSignIn() => _claude.hasCredentials();

  /// Re-reads the plan limits and returns the held report carrying them.
  ///
  /// The cheap path, and the one switching the setting on should take: no
  /// sweep, no isolate, no cache write — one request against an endpoint that
  /// answers in milliseconds. Null when there is no report to attach the
  /// reading to yet, in which case the next sweep will pick it up anyway.
  Future<AiUsageReport?> refreshClaudePlan({bool force = false}) async {
    final held = _report;
    if (held == null) return null;

    final plan = await _claudePlan(force: force);
    return _report = held.withClaudePlan(plan);
  }

  /// The config roots to read, as absolute paths.
  ///
  /// A root the user named in Settings but which is not on disk is still
  /// returned: the sweep is what notices it is missing, and the page says so by
  /// name. Dropping it here would turn "Codex is not installed" into silence.
  Map<AiProvider, String> _roots() {
    final home = Platform.environment['HOME'];
    if (home == null) return const {};

    final enabled = {
      if (_settings.aiUsageIncludeClaude) AiProvider.claudeCode,
      if (_settings.aiUsageIncludeCodex) AiProvider.codex,
    };

    final overrides = _settings.aiUsageRoots;
    return {
      for (final provider in enabled)
        provider: _expand(
          overrides[provider.name] ?? provider.defaultRoot,
          home,
        ),
    };
  }

  static String _expand(String path, String home) {
    if (path.startsWith('/')) return path;
    if (path == '~') return home;
    if (path.startsWith('~/')) return '$home/${path.substring(2)}';
    return '$home/$path';
  }
}

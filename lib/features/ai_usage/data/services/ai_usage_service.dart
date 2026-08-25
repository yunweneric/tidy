import 'dart:io';

import 'package:tidy/core/logging/logging.dart';
import 'package:tidy/core/settings/app_settings.dart';
import 'package:tidy/features/ai_usage/data/models/ai_provider.dart';
import 'package:tidy/features/ai_usage/data/models/ai_usage_report.dart';
import 'package:tidy/features/ai_usage/data/parsing/usage_merge.dart';
import 'package:tidy/features/ai_usage/data/parsing/usage_scan.dart';
import 'package:tidy/features/ai_usage/data/services/ai_usage_cache.dart';

/// Reads the AI CLIs' session logs and hands back what they add up to.
///
/// Holds the last report so switching away from the page and back does not
/// re-sweep 1.5 GB, and owns the on-disk cache so a cold launch does not
/// either.
class AiUsageService {
  AiUsageService({required AppSettings settings, AiUsageCache? cache})
    : _settings = settings,
      _cache = cache ?? AiUsageCache();

  final AppSettings _settings;
  final AiUsageCache _cache;

  AiUsageReport? _report;
  Future<AiUsageReport>? _inFlight;

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

      final report = buildReport(scan);
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

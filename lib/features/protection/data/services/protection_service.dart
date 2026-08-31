import 'dart:async';

import 'package:tidy/core/models/launch_item.dart';
import 'package:tidy/core/platform/action_outcome.dart';
import 'package:tidy/core/platform/app_data_access_service.dart';
import 'package:tidy/core/services/launch_items_service.dart';
import 'package:tidy/core/logging/logging.dart';
import 'package:tidy/core/settings/app_settings.dart';
import 'package:tidy/core/utils/home_dir.dart';
import 'package:tidy/features/apps/data/services/apps_service.dart';
import 'package:tidy/features/protection/data/models/protection_finding.dart';
import 'package:tidy/features/protection/data/models/signing_info.dart';
import 'package:tidy/features/protection/data/services/app_audit.dart';
import 'package:tidy/features/protection/data/services/browser_extension_audit.dart';
import 'package:tidy/features/protection/data/services/privacy_traces_audit.dart';
import 'package:tidy/features/protection/data/services/path_safety.dart';
import 'package:tidy/features/protection/data/services/protection_bridge.dart';
import 'package:tidy/features/protection/data/services/startup_audit.dart';

/// What one area's audit found, and whether it finished.
class ProtectionAreaResult {
  const ProtectionAreaResult({
    this.findings = const [],
    this.loading = true,
    this.unreadable = 0,
  });

  final List<ProtectionFinding> findings;
  final bool loading;

  /// Places we could not look at all — counted so the page can say so beside
  /// the count of places we could.
  final int unreadable;
}

/// Owns the four audits and what they last found.
///
/// A singleton for the cache, which is the point of it: signing seventy apps
/// takes a second and a half, and navigating to Settings and back must not pay
/// it again. Refresh is the only thing that clears it, along with any action
/// that changes what is on disk.
class ProtectionService {
  ProtectionService({
    required LaunchItemsService launchItems,
    required AppManagerService apps,
    required AppSettings settings,
    required AppDataAccessService appData,
  }) : _launchItems = launchItems,
       _settings = settings,
       _appData = appData,
       _startup = StartupAudit(launchItems),
       _appAudit = AppAudit(apps);

  final LaunchItemsService _launchItems;
  final AppSettings _settings;
  final AppDataAccessService _appData;
  final StartupAudit _startup;
  final AppAudit _appAudit;
  final BrowserExtensionAudit _extensions = BrowserExtensionAudit();
  final PrivacyTracesAudit _traces = PrivacyTracesAudit();

  final Map<ProtectionArea, ProtectionAreaResult> _results = {};
  List<LaunchItem> _lastItems = const [];
  List<DownloadEvent> _recentDownloads = const [];

  Map<ProtectionArea, ProtectionAreaResult> get results => Map.of(_results);
  List<DownloadEvent> get recentDownloads => _recentDownloads;

  bool get hasRun => _results.isNotEmpty;

  /// The ignore list, which exists because of Homebrew.
  ///
  /// Three of the unsigned launch agents on a developer's Mac are a local
  /// database build, and a checker that mentions them on every visit is one
  /// people stop reading. Ignoring is per-finding and reversible.
  Set<String> get ignored => _settings.protectionIgnored.toSet();

  bool isIgnored(ProtectionFinding finding) => ignored.contains(finding.id);

  void setIgnored(ProtectionFinding finding, {required bool ignored}) {
    final current = _settings.protectionIgnored.toSet();
    if (ignored) {
      current.add(finding.id);
    } else {
      current.remove(finding.id);
    }
    _settings.protectionIgnored = current.toList()..sort();
  }

  /// Runs all four, emitting each as it lands.
  ///
  /// Not `Future.wait`: startup items are back in forty milliseconds and the app
  /// sweep takes a second and a half, and holding the fast three hostage to the
  /// slow one would leave the page empty for the whole of it.
  Stream<Map<ProtectionArea, ProtectionAreaResult>> run({
    bool refresh = false,
  }) async* {
    if (!refresh && _results.isNotEmpty) {
      yield results;
      return;
    }

    _results
      ..clear()
      ..addEntries([
        for (final area in ProtectionArea.values)
          MapEntry(area, const ProtectionAreaResult()),
      ]);
    yield results;

    final done = StreamController<ProtectionArea>();

    unawaited(() async {
      final findings = await _startup.run();
      _lastItems = await _launchItems.load();
      _results[ProtectionArea.startup] = ProtectionAreaResult(
        findings: findings,
        loading: false,
      );
      done.add(ProtectionArea.startup);
    }());

    unawaited(() async {
      // Only once macOS has already said yes. Asking is a button on the
      // section, not something opening the page does.
      final found = await _extensions.run(
        allowed: _appData.hasBeenAsked && (_appData.granted ?? false),
      );
      _results[ProtectionArea.extensions] = ProtectionAreaResult(
        findings: found.findings,
        loading: false,
        unreadable: found.unreadable,
      );
      done.add(ProtectionArea.extensions);
    }());

    unawaited(() async {
      final found = await _traces.run(
        allowed: _appData.hasBeenAsked && (_appData.granted ?? false),
      );
      _recentDownloads = found.recent;
      _results[ProtectionArea.traces] = ProtectionAreaResult(
        findings: found.findings,
        loading: false,
      );
      done.add(ProtectionArea.traces);
    }());

    unawaited(() async {
      await for (final findings in _appAudit.run()) {
        _results[ProtectionArea.apps] = ProtectionAreaResult(
          findings: findings,
          loading: true,
        );
        done.add(ProtectionArea.apps);
      }
      _results[ProtectionArea.apps] = ProtectionAreaResult(
        findings: _results[ProtectionArea.apps]?.findings ?? const [],
        loading: false,
      );
      done.add(ProtectionArea.apps);
      await done.close();
    }());

    await for (final _ in done.stream) {
      yield results;
    }
  }

  /// Forgets everything, so the next run measures again.
  void invalidate() => _results.clear();

  // ─── Actions ──────────────────────────────────────────────────────────────

  LaunchItem? _itemFor(ProtectionFinding finding) {
    for (final item in _lastItems) {
      if (item.path == finding.id) return item;
    }
    return null;
  }

  Future<ActionOutcome> setStartupEnabled(
    ProtectionFinding finding, {
    required bool enabled,
  }) async {
    final item = _itemFor(finding);
    if (item == null) {
      return const ActionOutcome(
        ok: false,
        message: 'That item is no longer here.',
      );
    }
    final outcome = await _launchItems.setEnabled(item, enabled: enabled);
    if (outcome.ok) invalidate();
    return outcome;
  }

  /// Removes a startup item through the path that already exists for it.
  ///
  /// Not reimplemented here: `LaunchItemsService.remove` already boots the job
  /// out before its file goes, routes user-space removals through
  /// `SystemBridge.trashItems` so Recycle Bin's Put Back keeps working, and
  /// sends the machine-wide ones through macOS's own authorization prompt. That
  /// routine deletes root-owned files and should exist exactly once.
  Future<ActionOutcome> removeStartupItem(ProtectionFinding finding) async {
    final item = _itemFor(finding);
    if (item == null) {
      return const ActionOutcome(
        ok: false,
        message: 'That item is no longer here.',
      );
    }

    // Checked here as well as natively. `SystemBridge.trashItems` has the last
    // word and refuses the dangerous roots regardless, but a bug in this module
    // should be caught before it gets that far rather than by leaning on the
    // guard underneath it — see `path_safety.dart`, which is the one part of
    // this module with tests.
    final home = kHomeDir;
    if (home == null ||
        !isActionableLaunchAgent(item.path, home: home) ||
        crossesSymlink(item.path)) {
      AppLog.protection.warn(
        'refused to remove a path outside the launchd folders',
        fields: {'path': item.path},
      );
      return const ActionOutcome(
        ok: false,
        message:
            'That file is not where Tidy expects a startup item to live, so it '
            'will not touch it.',
      );
    }

    final outcome = await _launchItems.remove(item);
    if (outcome.ok) invalidate();
    return outcome;
  }

  Future<({bool ok, String? reason})> validate(ProtectionFinding finding) =>
      ProtectionBridge.validate(finding.path ?? '');

  Future<({bool ok, String? reason})> assess(ProtectionFinding finding) =>
      ProtectionBridge.assess(finding.path ?? '');
}

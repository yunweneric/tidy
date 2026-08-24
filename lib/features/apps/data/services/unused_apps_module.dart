import 'package:flutter/widgets.dart';
import 'package:mac_uninstaller/core/design/app_icons.dart';
import 'package:mac_uninstaller/core/scanning/domain/scan_module.dart';
import 'package:mac_uninstaller/core/scanning/domain/scan_node.dart';
import 'package:mac_uninstaller/core/utils/disk_utils.dart';
import 'package:mac_uninstaller/features/apps/data/models/mac_app_model.dart';
import 'package:mac_uninstaller/features/apps/data/services/apps_service.dart';
import 'package:mac_uninstaller/features/apps/data/services/leftover_scanner.dart';
import 'package:mac_uninstaller/features/apps/data/services/scan_cache.dart';

/// Apps that have not been opened in a long time, with everything they would
/// take with them.
///
/// Deliberately reports each app as a *reviewable* finding rather than a safe
/// one. "You have not opened this in six months" is an observation, not a
/// verdict — plenty of software is kept for the once-a-year afternoon it is
/// needed, and pre-ticking someone's applications would be the single most
/// destructive default this app could ship.
class UnusedAppsModule implements ScanModule {
  UnusedAppsModule({
    AppManagerService? apps,
    LeftoverScanner? leftovers,
    ScanCache? cache,
    this.unusedAfter = const Duration(days: 180),
  }) : _apps = apps ?? AppManagerService(),
       _leftovers = leftovers ?? LeftoverScanner(),
       _cache = cache ?? ScanCache();

  final AppManagerService _apps;
  final LeftoverScanner _leftovers;
  final ScanCache _cache;

  /// Six months, matching the threshold the Applications module uses.
  final Duration unusedAfter;

  @override
  ModuleId get id => ModuleId.unusedApps;

  @override
  IconData get icon => AppIcons.applications;

  @override
  bool get needsFullDiskAccess => true;

  @override
  bool get mayNeedAdmin => true;

  @override
  Stream<ScanProgress> scan(ScanRequest request) async* {
    yield const ScanProgress(roots: [], fraction: 0);

    final installed = await _installedApps();
    final candidates = installed.where(_isUnused).toList();

    if (candidates.isEmpty) {
      yield const ScanProgress.done([]);
      return;
    }

    // Only the candidates get measured, not the whole Applications folder —
    // sizing means walking every file in a bundle, so narrowing first is the
    // difference between a second and a minute.
    final sizes = await pathSizes(candidates.map((app) => app.path).toList());

    final found = <ScanNode>[];
    for (var i = 0; i < candidates.length; i++) {
      final app = candidates[i];

      yield ScanProgress(
        roots: [if (found.isNotEmpty) _group(found)],
        fraction: i / candidates.length,
        currentPath: app.name,
      );

      found.add(await _node(app, sizes[app.path] ?? 0));
    }

    yield ScanProgress.done([_group(found)]);
  }

  /// Prefers the cached inventory so Smart Care does not pay for a second full
  /// application sweep when Cleanup has already loaded one.
  Future<List<MacApp>> _installedApps() async {
    final cached = await _cache.read();
    if (cached != null && cached.apps.isNotEmpty) return cached.apps;
    return _apps.scanApps();
  }

  bool _isUnused(MacApp app) {
    if (app.isSystem) return false;
    final days = app.daysSinceLastUsed;
    // A null date means Spotlight has no record — usually never launched, but
    // it can also mean an unindexed volume, so it is a finding, not a fact.
    return days == null || days >= unusedAfter.inDays;
  }

  /// One app plus its leftovers, as a single removable unit.
  Future<ScanNode> _node(MacApp app, int bundleBytes) async {
    final leftovers = await _leftovers.scan(app);
    final leftoverBytes = leftovers.fold<int>(
      0,
      (sum, item) => sum + item.sizeBytes,
    );

    return ScanNode(
      id: 'unusedApps:${app.path}',
      title: app.name,
      subtitle:
          app.lastUsedLabel == 'Never'
              ? 'Never opened'
              : 'Last opened ${app.lastUsedLabel.toLowerCase()}',
      detail:
          leftovers.isEmpty
              ? 'The app bundle. No leftovers found elsewhere on the system.'
              : 'The app plus ${leftovers.length} support '
                  '${leftovers.length == 1 ? 'file' : 'files'} it left around the '
                  'system.',
      // The bundle and every leftover go together: an uninstall that leaves the
      // app in place is not an uninstall.
      paths: [app.path, ...leftovers.map((item) => item.path)],
      sizeBytes: bundleBytes + leftoverBytes,
      safety: SafetyLevel.review,
      requiresAdmin: leftovers.any((item) => item.requiresAdmin),
      icon: app.iconBytes,
    );
  }

  ScanNode _group(List<ScanNode> apps) => ScanNode(
    id: 'unusedApps',
    title: ModuleId.unusedApps.label,
    detail:
        'Apps you have not opened in ${unusedAfter.inDays ~/ 30} months. '
        'Nothing here is ticked for you — have a look before removing any of it.',
    safety: SafetyLevel.review,
    children: apps,
  );
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tidy/core/design/app_icons.dart';
import 'package:tidy/core/scanning/domain/scan_module.dart';
import 'package:tidy/core/scanning/domain/scan_node.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/features/apps/data/services/apps_service.dart';
import 'package:tidy/features/apps/data/services/junk_scanner.dart';
import 'package:tidy/features/apps/data/services/scan_cache.dart';

/// Reclaimable space: caches, logs, saved window state and orphaned leftovers.
///
/// Wraps the existing [JunkScanner] in the generic [ScanModule] contract, and
/// streams one category at a time rather than waiting for all four — the
/// orphan sweep walks five roots and is several times slower than the rest, so
/// a single combined await would leave the screen empty for the whole scan.
class CleanupScanModule implements ScanModule {
  CleanupScanModule({
    JunkScanner? scanner,
    AppManagerService? apps,
    ScanCache? cache,
  }) : _scanner = scanner ?? JunkScanner(),
       _apps = apps ?? AppManagerService(),
       _cache = cache ?? ScanCache();

  final JunkScanner _scanner;
  final AppManagerService _apps;
  final ScanCache _cache;

  @override
  ModuleId get id => ModuleId.systemJunk;

  @override
  IconData get icon => AppIcons.cleanup;

  @override
  bool get needsFullDiskAccess => true;

  @override
  bool get mayNeedAdmin => false;

  static String? get _home => Platform.environment['HOME'];

  @override
  Stream<ScanProgress> scan(ScanRequest request) async* {
    yield const ScanProgress(roots: [], fraction: 0);

    final bundleIds = await _installedBundleIds();
    final found = <ScanNode>[];
    const kinds = JunkKind.values;

    for (var i = 0; i < kinds.length; i++) {
      final kind = kinds[i];

      yield ScanProgress(
        roots: List.of(found),
        fraction: i / kinds.length,
        currentPath: kind.label,
      );

      final group = await _scanner.scanKind(
        kind,
        installedBundleIds: bundleIds,
      );
      final node = _toNode(group);
      if (node != null) found.add(node);
    }

    yield ScanProgress.done(
      found,
      // Every root we scan lives under the user's own Library, so a denied read
      // there means Full Disk Access rather than a genuinely empty folder.
      skippedForPermission: !request.hasFullDiskAccess && found.isEmpty,
    );
  }

  /// Prefers the on-disk cache so the first Cleanup scan doesn't wait on a full
  /// application sweep; falls back to scanning when the cache is cold.
  Future<Set<String>> _installedBundleIds() async {
    final cached = await _cache.read();
    final apps =
        cached != null && cached.apps.isNotEmpty
            ? cached.apps
            : await _apps.scanApps();
    return {
      for (final app in apps)
        if (app.bundleId.isNotEmpty) app.bundleId,
    };
  }

  ScanNode? _toNode(JunkGroup group) {
    if (group.items.isEmpty) return null;

    final safety = switch (group.kind) {
      // Caches, logs and saved state are all regenerated on demand.
      JunkKind.caches ||
      JunkKind.logs ||
      JunkKind.savedState => SafetyLevel.safe,
      // Orphans are an inference about apps that are already gone. Sometimes
      // that inference is wrong, so they are never pre-selected.
      JunkKind.orphaned => SafetyLevel.review,
    };

    return ScanNode(
      id: 'cleanup:${group.kind.name}',
      title: group.kind.label,
      detail: group.kind.description,
      safety: safety,
      children: [
        for (final item in group.items)
          ScanNode(
            id: item.path,
            title: item.label,
            subtitle: collapseHome(_parentOf(item.path), _home),
            paths: [item.path],
            sizeBytes: item.sizeBytes,
            safety: safety,
          ),
      ],
    );
  }

  static String _parentOf(String path) {
    final cut = path.lastIndexOf('/');
    return cut <= 0 ? path : path.substring(0, cut);
  }
}

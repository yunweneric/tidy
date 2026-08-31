import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tidy/core/design/app_icons.dart';
import 'package:tidy/core/logging/app_log.dart';
import 'package:tidy/core/platform/system_bridge.dart';
import 'package:tidy/core/scanning/domain/scan_module.dart';
import 'package:tidy/core/scanning/domain/scan_node.dart';
import 'package:tidy/core/utils/byte_format.dart';

/// Large files the user has not opened in a long time.
///
/// This is an inference about what the user *probably* does not need any more —
/// a project they have not touched in a year, a render they are done with — so
/// every finding is [SafetyLevel.review], never pre-selected. Sizes come from
/// [SystemBridge.childSizes], the same native `fts(3)` walker that backs the
/// disk map, which reports allocated bytes and a modification date in one batch.
class LargeAndOldScanModule implements ScanModule {
  @override
  ModuleId get id => ModuleId.largeAndOld;

  @override
  IconData get icon => AppIcons.largeFiles;

  @override
  bool get needsFullDiskAccess => true;

  @override
  bool get mayNeedAdmin => false;

  /// Anything at or above this allocated size is worth putting in front of the
  /// user. Below it the list fills with files that are cheap to keep.
  static const int kMinBytes = 500 * 1024 * 1024; // 500 MB

  /// Unused long enough to be a candidate for reclaim.
  static const Duration kMinAge = Duration(days: 180);

  /// The roots to sweep, all immediate children of home. `~/Library` is
  /// deliberately absent: its contents are app-managed, not user clutter.
  static List<String> rootsOf(String home) => [
    for (final name in const {
      'Downloads',
      'Documents',
      'Desktop',
      'Pictures',
      'Movies',
      'Music',
      'Public',
    })
      '$home/$name',
  ];

  @override
  Stream<ScanProgress> scan(ScanRequest request) async* {
    yield const ScanProgress(roots: [], fraction: 0);

    final home = Platform.environment['HOME'];
    if (home == null) {
      yield const ScanProgress.done([]);
      return;
    }

    final found = <ScanNode>[];
    final roots = rootsOf(home);

    for (var i = 0; i < roots.length; i++) {
      final root = roots[i];

      yield ScanProgress(
        roots: List.of(found),
        fraction: i / roots.length,
        currentPath: collapseHome(root, home),
      );

      final children = await _candidatesOf(root);
      if (children == null) continue;
      if (children.isNotEmpty) {
        found.add(_groupNode(root, children, home));
      }
    }

    yield ScanProgress.done(
      found,
      // Every root lives under the user's own home but is TCC-protected
      // separately from Full Disk Access, and a denied read here comes back as
      // an empty list rather than an error — so, like Cleanup, a sweep that ran
      // without FDA and found nothing is reported as a permission problem, not
      // as a confident zero.
      skippedForPermission: !request.hasFullDiskAccess && found.isEmpty,
    );
  }

  /// Immediate child files of [root] that are large and old enough to show.
  ///
  /// Files only, deliberately. A directory's mtime only moves when its own
  /// entries change, so an active project can look years stale and a whole
  /// folder is a far bigger decision than one file; packages (`.app`,
  /// `.photoslibrary`, …) are directories too, so keeping to files also keeps
  /// the permanently off-limits packages out without a name list that will
  /// always miss one (`docs/feature.md` §5).
  ///
  /// Returns null when the folder could not be read at all — which for a root
  /// under the user's own home means Full Disk Access rather than a genuinely
  /// empty folder, and the caller must not pass it off as "nothing".
  Future<List<DirectoryEntry>?> _candidatesOf(String root) async {
    if (!Directory(root).existsSync()) return const [];

    final List<DirectoryEntry> children;
    try {
      children = await SystemBridge.childSizes(root);
    } catch (e) {
      AppLog.clutter.failed('list a clutter root', e, fields: {'root': root});
      return null;
    }

    final cutoff = DateTime.now().subtract(kMinAge);
    return [
      for (final child in children)
        if (!child.isDirectory &&
            child.sizeBytes >= kMinBytes &&
            _isOldEnough(child.modified, cutoff))
          child,
    ];
  }

  ScanNode _groupNode(String root, List<DirectoryEntry> children, String home) {
    final kids = [
      for (final child in children)
        ScanNode(
          id: child.path,
          title: child.name,
          subtitle: collapseHome(child.path, home),
          paths: [child.path],
          sizeBytes: child.sizeBytes,
          safety: SafetyLevel.review,
        ),
    ]..sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));

    return ScanNode(
      id: 'largeAndOld:${collapseHome(root, home)}',
      title: _titleFor(root, home),
      detail:
          'Large items you have not touched in months. Worth a look before '
          'removing — an inference about what you no longer need is never certain.',
      safety: SafetyLevel.review,
      children: kids,
    );
  }

  static String _titleFor(String root, String home) {
    final collapsed = collapseHome(root, home);
    return collapsed == '~' ? root : collapsed.split('/').last;
  }

  /// A missing modification date is treated as not-old-enough — assuming an
  /// unknown mtime makes it a candidate would put files on the list for the one
  /// thing we failed to read rather than for being unused.
  static bool _isOldEnough(DateTime? modified, DateTime cutoff) =>
      modified != null && !modified.isAfter(cutoff);
}

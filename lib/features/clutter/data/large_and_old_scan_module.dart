import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tidy/core/design/app_icons.dart';
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

    var denied = false;
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
      if (children == null) {
        denied = true;
        continue;
      }
      if (children.isNotEmpty) {
        found.add(_groupNode(root, children, home));
      }
    }

    yield ScanProgress.done(
      found,
      skippedForPermission: denied && found.isEmpty,
    );
  }

  /// Immediate children of [root] that are large and old enough to show.
  ///
  /// Returns null when the folder could not be read at all — which for a root
  /// under the user's own home means Full Disk Access rather than a genuinely
  /// empty folder, and must be reported rather than passed off as "nothing".
  Future<List<DirectoryEntry>?> _candidatesOf(String root) async {
    if (!Directory(root).existsSync()) return const [];

    final List<DirectoryEntry> children;
    try {
      children = await SystemBridge.childSizes(root);
    } catch (_) {
      return null;
    }

    final cutoff = DateTime.now().subtract(kMinAge);
    return [
      for (final child in children)
        if (child.sizeBytes >= kMinBytes &&
            _isOldEnough(child.modified, cutoff) &&
            !_isProtectedPackage(child))
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

  /// Everything `.photoslibrary`/`.musiclibrary`/`.tvlibrary` and `.app` is a
  /// package, not a deletable file. Even removing the package whole is a
  /// judgement this phase does not make, and the interior is permanently off
  /// limits (`docs/feature.md` §5) — treating the package as opaque here keeps
  /// it out of the removal UI entirely.
  static const Set<String> _protectedPackageSuffixes = {
    '.photoslibrary',
    '.musiclibrary',
    '.tvlibrary',
    '.app',
  };

  static bool _isProtectedPackage(DirectoryEntry child) {
    final lower = child.name.toLowerCase();
    return _protectedPackageSuffixes.any(lower.endsWith);
  }
}

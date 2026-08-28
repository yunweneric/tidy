import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tidy/core/design/app_icons.dart';
import 'package:tidy/core/platform/system_bridge.dart';
import 'package:tidy/core/scanning/domain/scan_module.dart';
import 'package:tidy/core/scanning/domain/scan_node.dart';
import 'package:tidy/core/utils/byte_format.dart';

/// One-time files still sitting in Downloads — installers and old downloads.
///
/// An installer you already ran, or a download you have long since acted on, is
/// exactly the kind of thing that piles up silently in the one folder macOS
/// never cleans. Every finding is [SafetyLevel.review]: "you probably do not
/// need this" is an inference, and never gets pre-selected.
class DownloadsClutterScanModule implements ScanModule {
  @override
  ModuleId get id => ModuleId.downloadsClutter;

  @override
  IconData get icon => AppIcons.downloads;

  @override
  bool get needsFullDiskAccess => true;

  @override
  bool get mayNeedAdmin => false;

  /// An installer is clutter the moment it has sat around this long, whatever
  /// its size — the point of it was the one install.
  static const Duration kInstallerMinAge = Duration(days: 90);

  /// A plain download has to be both big and old before it is worth offering.
  static const int kMinBytes = 50 * 1024 * 1024; // 50 MB
  static const Duration kMinAge = Duration(days: 180);

  static const Set<String> _installerExtensions = {'.dmg', '.pkg', '.mpkg'};

  @override
  Stream<ScanProgress> scan(ScanRequest request) async* {
    yield const ScanProgress(roots: [], fraction: 0);

    final home = Platform.environment['HOME'];
    if (home == null) {
      yield const ScanProgress.done([]);
      return;
    }
    final downloads = '$home/Downloads';

    yield ScanProgress(
      roots: const [],
      fraction: 0,
      currentPath: collapseHome(downloads, home),
    );

    final entries = await _candidatesOf(downloads);
    if (entries == null) {
      yield ScanProgress.done(const [], skippedForPermission: true);
      return;
    }

    final root = _buildRoot(downloads, entries);
    yield ScanProgress.done(
      root == null ? const [] : [root],
      skippedForPermission: false,
    );
  }

  Future<List<DirectoryEntry>?> _candidatesOf(String root) async {
    if (!Directory(root).existsSync()) return const [];

    final List<DirectoryEntry> children;
    try {
      children = await SystemBridge.childSizes(root);
    } catch (_) {
      return null;
    }

    final now = DateTime.now();
    final installerCutoff = now.subtract(kInstallerMinAge);
    final downloadCutoff = now.subtract(kMinAge);

    return [
      for (final child in children)
        // Directories are a different, deeper question than a loose file — this
        // phase only clears files that can be handed to removal wholesale.
        if (!child.isDirectory &&
            _isCandidate(child, installerCutoff, downloadCutoff))
          child,
    ];
  }

  static bool _isCandidate(
    DirectoryEntry child,
    DateTime installerCutoff,
    DateTime downloadCutoff,
  ) {
    final lower = child.name.toLowerCase();
    if (_installerExtensions.any(lower.endsWith)) {
      return _isOldEnough(child.modified, installerCutoff);
    }
    return child.sizeBytes >= kMinBytes &&
        _isOldEnough(child.modified, downloadCutoff);
  }

  /// A missing modification date is treated as not-old-enough rather than as a
  /// candidate — see `LargeAndOldScanModule._isOldEnough`.
  static bool _isOldEnough(DateTime? modified, DateTime cutoff) =>
      modified != null && !modified.isAfter(cutoff);

  ScanNode? _buildRoot(String root, List<DirectoryEntry> entries) {
    if (entries.isEmpty) return null;

    final home = Platform.environment['HOME'];
    final kids = [
      for (final child in entries)
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
      id: 'downloads:${collapseHome(root, home)}',
      title: 'Downloads',
      detail:
          'Installers you have likely already run, and old downloads you have '
          'long since acted on. Nothing here is pre-selected — it is your call.',
      safety: SafetyLevel.review,
      children: kids,
    );
  }
}

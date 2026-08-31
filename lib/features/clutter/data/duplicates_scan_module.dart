import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tidy/core/design/app_icons.dart';
import 'package:tidy/core/platform/system_bridge.dart';
import 'package:tidy/core/scanning/domain/scan_module.dart';
import 'package:tidy/core/scanning/domain/scan_node.dart';
import 'package:tidy/core/utils/byte_format.dart';

/// Byte-identical copies of the same file.
///
/// Two decisions shape everything here.
///
/// **One copy is never on the list.** Every group keeps its oldest member, and
/// that path is not among the children — so no combination of clicks, including
/// Select All, can remove the last copy of a file. The keeper is named in the
/// group's detail line instead, because "keeping the one in Documents" is a
/// claim the user can check, and silently dropping a row is not.
///
/// **Shared blocks are reported as zero.** On APFS a Finder duplicate is a
/// clone: two files, one set of extents. Deleting one frees almost nothing, so
/// it is marked [ScanNode.sharesStorage] and excluded from the reclaimable
/// total. Counting clones at full size is how a cleaner comes to promise 40 GB
/// and deliver 2.
class DuplicatesScanModule implements ScanModule {
  @override
  ModuleId get id => ModuleId.duplicates;

  @override
  IconData get icon => AppIcons.duplicates;

  @override
  bool get needsFullDiskAccess => true;

  @override
  bool get mayNeedAdmin => false;

  /// Below this a duplicate is not worth a decision. Identical small files are
  /// everywhere — icons, licences, config — and listing them buries the handful
  /// of copies that are actually costing gigabytes.
  static const int kMinBytes = 1024 * 1024; // 1 MB

  /// Nobody reviews more than a few hundred groups, and the ones past the cut
  /// are the smallest. Bounded here rather than in the UI so the channel never
  /// carries a payload the page cannot use.
  static const int kMaxGroups = 400;

  /// Where duplicates plausibly accumulate. `~/Library` is absent for the same
  /// reason it is absent from Large & Old: its contents are app-managed, and
  /// identical files in there are usually a cache doing its job.
  static List<String> rootsOf(String home) => [
    for (final name in const {
      'Downloads',
      'Documents',
      'Desktop',
      'Pictures',
      'Movies',
      'Music',
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

    // Roots are walked in one native call rather than one per root: a file in
    // Downloads and its copy in Documents are only a duplicate pair if both
    // sides are in the same bucket, and per-root calls would never see them
    // together. The cost is that there is no honest intermediate fraction to
    // report — the answer exists only once the whole walk is hashed — so this
    // sits at the start of the bar rather than inventing progress.
    final roots = rootsOf(home).where(_exists).toList();
    yield ScanProgress(
      roots: const [],
      fraction: 0,
      currentPath: collapseHome('$home/…', home),
    );

    final groups = await SystemBridge.duplicateGroups(
      roots,
      minBytes: kMinBytes,
      maxGroups: kMaxGroups,
    );

    final found = groups.isEmpty ? const <ScanNode>[] : [_root(groups, home)];
    yield ScanProgress.done(
      found,
      // Every root is TCC-protected separately from Full Disk Access and a
      // denied read comes back as an empty walk rather than an error — so, as
      // in Cleanup, nothing found without FDA is a permission problem and not a
      // confident zero.
      skippedForPermission: !request.hasFullDiskAccess && found.isEmpty,
    );
  }

  static bool _exists(String path) => Directory(path).existsSync();

  ScanNode _root(List<DuplicateGroup> groups, String home) {
    return ScanNode(
      id: 'duplicates',
      title: 'Duplicates',
      detail:
          'Files that are byte-for-byte identical. The oldest copy of each is '
          'kept and never listed, so what you see here is only the spares.',
      safety: SafetyLevel.review,
      children: [for (final group in groups) _group(group, home)],
    );
  }

  ScanNode _group(DuplicateGroup group, String home) {
    final shared = group.copies.every((copy) => copy.sharesStorage);

    return ScanNode(
      id: 'duplicates:${group.keeping}',
      title: group.name,
      subtitle:
          '${_copies(group.copies.length)} · '
          '${formatBytes(group.logicalSizeBytes)} each',
      detail:
          shared
              // Worth saying explicitly. The user sees several gigabytes of
              // apparent duplication and a reclaim figure of nothing; without
              // this line that reads as a bug rather than as APFS working.
              ? 'Keeping ${collapseHome(group.keeping, home)}. These copies '
                  'share their storage with it, so removing them frees almost '
                  'nothing — they cost a listing, not disk space.'
              : 'Keeping ${collapseHome(group.keeping, home)}, the oldest copy. '
                  'Everything below is a spare.',
      safety: SafetyLevel.review,
      children: [for (final copy in group.copies) _copy(copy, home)],
    );
  }

  ScanNode _copy(DuplicateCopy copy, String home) {
    return ScanNode(
      id: copy.path,
      title: copy.name,
      subtitle: collapseHome(copy.path, home),
      paths: [copy.path],
      sizeBytes: copy.sizeBytes,
      sharesStorage: copy.sharesStorage,
      safety: SafetyLevel.review,
    );
  }

  static String _copies(int spares) {
    final total = spares + 1;
    return '$total copies';
  }
}

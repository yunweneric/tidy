import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:tidy/core/design/app_icons.dart';
import 'package:tidy/core/logging/logging.dart';
import 'package:tidy/core/platform/system_bridge.dart';
import 'package:tidy/core/scanning/domain/scan_module.dart';
import 'package:tidy/core/scanning/domain/scan_node.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/utils/disk_utils.dart';
import 'package:tidy/core/utils/home_dir.dart';
import 'package:tidy/features/cleanup/data/scanners/developer_roots.dart';

/// Build output and package caches from developer tools.
///
/// The largest single category on a machine that builds software, and the one
/// where a cleaner can be plainly better than a guess: these are not inferred
/// leftovers, they are folders whose owning tool documents them as a cache.
/// Where the catalogue looks, and how each finding earns its [SafetyLevel], is
/// [devRootsFor] — including the list of paths that are deliberately never
/// touched.
///
/// Removal is the shared one: findings go back to `ScanBloc`, which trashes
/// through `SystemBridge.trashItems` and writes the ledger. This module reads.
class DeveloperJunkModule implements ScanModule {
  DeveloperJunkModule();

  @override
  ModuleId get id => ModuleId.developerJunk;

  @override
  IconData get icon => AppIcons.developerJunk;

  /// Every root is inside the user's own home and none of them is TCC-gated,
  /// so this module has nothing to ask for. Cleanup as a whole still does.
  @override
  bool get needsFullDiskAccess => false;

  @override
  bool get mayNeedAdmin => false;

  /// Cheapest group first, so something is on screen while the slow walks run.
  /// Derived Data and device support are two deep `fts` sweeps and go last;
  /// the tiles are re-ordered by size on screen anyway, so this costs nothing.
  static const List<DevGroup> _order = [
    DevGroup.editors,
    DevGroup.packages,
    DevGroup.xcode,
  ];

  /// A Derived Data folder touched this recently is likely the project open in
  /// Xcode right now, so it is offered but never pre-ticked.
  static const Duration _inUse = Duration(hours: 1);

  @override
  Stream<ScanProgress> scan(ScanRequest request) async* {
    yield const ScanProgress(roots: [], fraction: 0);

    final home = kHomeDir;
    if (home == null) {
      AppLog.cleanup.warn('no HOME, skipping the developer caches');
      yield const ScanProgress.done([]);
      return;
    }

    // A tool that is not installed has no cache, and that is not a zero worth
    // showing — it is a row about software the user does not use.
    //
    // A symlinked root is skipped outright. Relocating Derived Data or `~/go`
    // to an external disk with a symlink is common, and it breaks us in a way
    // that would go unnoticed: the sizer never crosses a mount point, so the
    // row would read as a few bytes, and trashing a symlink takes the link
    // rather than the thing it points at — we would report freeing space we
    // did not free.
    final present = <DevRoot>[];
    for (final root in devRootsFor(home)) {
      if (!Directory(root.path).existsSync()) continue;
      if (FileSystemEntity.isLinkSync(root.path)) {
        AppLog.cleanup.warn(
          'skipped a symlinked developer cache root',
          fields: {'root': collapseHome(root.path, home)},
        );
        continue;
      }
      present.add(root);
    }

    // The one honest way to tell "denied" from "empty": the native walker skips
    // unreadable directories silently, so a folder we cannot read comes back
    // looking exactly like a folder with nothing in it. `canReadPaths` answers
    // the question directly, in one round trip, and only for paths we already
    // know exist — it reports a missing path as readable.
    final readable = await SystemBridge.canReadPaths([
      for (final root in present) root.path,
    ]);
    final denied = [
      for (final root in present)
        if (readable[root.path] == false) root.path,
    ];
    if (denied.isNotEmpty) {
      AppLog.cleanup.warn(
        'some developer cache roots could not be read',
        fields: {'count': denied.length, 'roots': denied.join(', ')},
      );
    }

    final usable = [
      for (final root in present)
        if (readable[root.path] != false) root,
    ];

    // One step per group, plus one for each root listed child by child — those
    // are the slow ones, and the status line should name them while it waits.
    final steps = _order.length + usable.where((r) => r.expand).length;
    var step = 0;

    final found = <ScanNode>[];

    for (final group in _order) {
      final roots = [
        for (final root in usable)
          if (root.group == group) root,
      ];
      if (roots.isEmpty) continue;

      yield ScanProgress(
        roots: List.of(found),
        fraction: step / steps,
        currentPath: group.label,
      );
      step++;

      final children = <ScanNode>[];

      // Every whole-folder root in this group in one native call, rather than
      // one round trip each.
      final whole = [
        for (final root in roots)
          if (!root.expand) root,
      ];
      if (whole.isNotEmpty) {
        final sizes = await pathSizes([for (final root in whole) root.path]);
        for (final root in whole) {
          final bytes = sizes[root.path] ?? 0;
          if (bytes <= 0) continue;
          children.add(
            ScanNode(
              id: root.path,
              title: root.label,
              subtitle: collapseHome(_parentOf(root.path), home),
              detail: root.detail,
              paths: [root.path],
              sizeBytes: bytes,
              safety: root.safety,
              sharesStorage: root.sharesStorage,
            ),
          );
        }
      }

      for (final root in roots.where((root) => root.expand)) {
        yield ScanProgress(
          roots: List.of(found),
          fraction: step / steps,
          currentPath: collapseHome(root.path, home),
        );
        step++;
        children.addAll(await _childrenOf(root, home));
      }

      if (children.isEmpty) continue;
      children.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
      found.add(
        ScanNode(
          id: 'devJunk:${group.name}',
          title: group.label,
          detail: group.detail,
          safety: _worstOf(children),
          children: children,
        ),
      );
    }

    AppLog.cleanup.debug(
      'developer junk scan finished',
      fields: {
        'groups': found.length,
        'items': found.fold<int>(0, (sum, node) => sum + node.leafCount),
        'denied': denied.length,
      },
    );

    // Reported whatever else was found: a partial result that says so beats a
    // total that quietly leaves a folder out.
    yield ScanProgress.done(found, skippedForPermission: denied.isNotEmpty);
  }

  /// One finding per child, for roots where the folder itself is too big a
  /// thing to tick blind — Derived Data is one row per project this way.
  ///
  /// [SystemBridge.childSizes] is a single call that both lists and sizes, so
  /// this costs one round trip per root however many children it has.
  Future<List<ScanNode>> _childrenOf(DevRoot root, String home) async {
    final entries = await SystemBridge.childSizes(root.path);
    final busy = DateTime.now().subtract(_inUse);

    return [
      for (final entry in entries)
        if (entry.sizeBytes > 0) _leafFor(entry, root, home, busy),
    ];
  }

  ScanNode _leafFor(
    DirectoryEntry entry,
    DevRoot root,
    String home,
    DateTime busy,
  ) {
    // Written to a moment ago, so something is using it while we look.
    final inUse =
        root.safety == SafetyLevel.safe &&
        entry.modified != null &&
        entry.modified!.isAfter(busy);

    return ScanNode(
      id: entry.path,
      title: entry.name,
      subtitle: collapseHome(root.path, home),
      detail:
          inUse
              ? '${root.detail} Written to in the last hour, so this may be '
                  'the project you have open right now.'
              : root.detail,
      paths: [entry.path],
      sizeBytes: entry.sizeBytes,
      safety: inUse ? SafetyLevel.review : root.safety,
      sharesStorage: root.sharesStorage,
    );
  }

  /// A group cannot look safer than the strictest thing inside it.
  static SafetyLevel _worstOf(List<ScanNode> children) {
    var worst = SafetyLevel.safe;
    for (final child in children) {
      if (child.safety.index > worst.index) worst = child.safety;
    }
    return worst;
  }

  static String _parentOf(String path) {
    final cut = path.lastIndexOf('/');
    return cut <= 0 ? path : path.substring(0, cut);
  }
}

import 'package:flutter/foundation.dart';
import 'package:tidy/core/scanning/domain/scan_node.dart';

/// Which findings the user has agreed to remove.
///
/// Selection is stored as a set of leaf ids rather than a flag on the node, so
/// it survives a rescan replacing the whole tree — the same reason
/// `ListAppsScreen` keys its selection by install path today.
@immutable
class ScanSelection {
  const ScanSelection(this._selected);

  const ScanSelection.empty() : _selected = const {};

  final Set<String> _selected;

  /// Everything a module considers safe, pre-ticked. Items needing admin or
  /// sharing storage are left out — we cannot deliver on either.
  factory ScanSelection.defaultFor(Iterable<ScanNode> roots) {
    return ScanSelection({
      for (final root in roots)
        for (final leaf in root.leaves)
          if (leaf.safety.preselected &&
              leaf.isRemovable &&
              !leaf.sharesStorage)
            leaf.id,
    });
  }

  Set<String> get ids => Set.unmodifiable(_selected);

  bool get isEmpty => _selected.isEmpty;

  bool isSelected(ScanNode node) =>
      node.isLeaf ? _selected.contains(node.id) : stateOf(node) == true;

  /// Tri-state for a group: true = all, false = none, null = some.
  bool? stateOf(ScanNode node) {
    if (node.isLeaf) return _selected.contains(node.id);
    final leaves = node.leaves.where((l) => l.isRemovable).toList();
    if (leaves.isEmpty) return false;
    final picked = leaves.where((l) => _selected.contains(l.id)).length;
    if (picked == 0) return false;
    if (picked == leaves.length) return true;
    return null;
  }

  /// Selects or clears every removable leaf under [node].
  ScanSelection toggle(ScanNode node, {bool? select}) {
    final next = Set<String>.from(_selected);
    final leaves = node.leaves.where((l) => l.isRemovable).toList();
    final shouldSelect = select ?? stateOf(node) != true;
    for (final leaf in leaves) {
      if (shouldSelect) {
        next.add(leaf.id);
      } else {
        next.remove(leaf.id);
      }
    }
    return ScanSelection(next);
  }

  /// Drops ids that no longer exist in [roots], so a rescan doesn't leave the
  /// counter reporting bytes that are already gone.
  ScanSelection reconcile(Iterable<ScanNode> roots) {
    final live = {
      for (final root in roots)
        for (final leaf in root.leaves) leaf.id,
    };
    return ScanSelection(_selected.intersection(live));
  }

  List<ScanNode> selectedLeaves(Iterable<ScanNode> roots) => [
    for (final root in roots)
      for (final leaf in root.leaves)
        if (_selected.contains(leaf.id)) leaf,
  ];

  int selectedBytes(Iterable<ScanNode> roots) =>
      selectedLeaves(roots).fold<int>(0, (sum, leaf) => sum + leaf.sizeBytes);

  /// Deduplicated, because a leaf can legitimately list a path that a sibling
  /// also lists (an app bundle and one of its helpers, say).
  List<String> selectedPaths(Iterable<ScanNode> roots) {
    final paths = <String>{};
    for (final leaf in selectedLeaves(roots)) {
      paths.addAll(leaf.paths);
    }
    return paths.toList();
  }
}

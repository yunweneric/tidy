import 'package:equatable/equatable.dart';
import 'package:tidy/core/platform/system_bridge.dart';
import 'package:tidy/core/scanning/domain/scan_node.dart';
import 'package:tidy/core/scanning/domain/scan_selection.dart';

/// Where a module is in the scan → review → clean loop.
enum ScanPhase {
  /// Never run, or reset. Shows the hero and a single Scan button.
  idle,

  /// Running. Partial results stream in underneath.
  scanning,

  /// Finished with findings. Shows the tile grid.
  results,

  /// Finished with nothing to do.
  clean,

  /// Removal in flight.
  cleaning,

  /// Removal finished. Shows what was freed.
  finished,

  failed,
}

/// What a completed removal actually did.
class CleanOutcome extends Equatable {
  const CleanOutcome({
    required this.requestedBytes,
    required this.removedCount,
    required this.failures,
    required this.movedToTrash,
  });

  /// What the user was shown before confirming. Pro-rated when only some paths
  /// went, so the report never claims more than it delivered.
  final int requestedBytes;

  final int removedCount;
  final List<RemovalFailure> failures;

  /// Trashing frees nothing until the Trash is emptied, and the summary has to
  /// say so rather than reporting phantom free space.
  final bool movedToTrash;

  bool get hasFailures => failures.isNotEmpty;

  @override
  List<Object?> get props => [
    requestedBytes,
    removedCount,
    failures.length,
    movedToTrash,
  ];
}

class ScanState extends Equatable {
  const ScanState({
    this.phase = ScanPhase.idle,
    this.roots = const [],
    this.selection = const ScanSelection.empty(),
    this.fraction,
    this.currentPath,
    this.recentPaths = const [],
    this.visitedCount = 0,
    this.permissionLimited = false,
    this.outcome,
    this.error,
    this.focusedNodeId,
  });

  final ScanPhase phase;

  /// Top-level categories. Each becomes a result tile.
  final List<ScanNode> roots;

  final ScanSelection selection;

  /// 0–1, or null when the scanner cannot know the total yet.
  final double? fraction;

  /// The path being examined right now, for the rolling status line.
  final String? currentPath;

  /// The last handful of places the scanner looked, newest first.
  ///
  /// A single current path tells you the app is alive but not that it is
  /// getting anywhere — the line changes too fast to read. A short history
  /// does: you can see it walking through Caches, then Logs, then Containers.
  final List<String> recentPaths;

  /// How many distinct places have been looked at this run.
  ///
  /// The honest progress number for a filesystem walk. Most scans cannot know
  /// their total until they have already finished walking everything, so a
  /// percentage would be a guess; a count that keeps climbing is true, and
  /// still answers "is this stuck?".
  final int visitedCount;

  /// How many entries [recentPaths] keeps.
  static const int recentPathLimit = 6;

  /// At least one root was unreadable — almost always Full Disk Access.
  final bool permissionLimited;

  final CleanOutcome? outcome;
  final String? error;

  /// The tile the user drilled into. Null means the tile grid is showing.
  final String? focusedNodeId;

  bool get isBusy => phase == ScanPhase.scanning || phase == ScanPhase.cleaning;

  int get totalBytes =>
      roots.fold<int>(0, (sum, node) => sum + node.totalBytes);

  int get selectedBytes => selection.selectedBytes(roots);

  int get selectedCount => selection.ids.length;

  /// The node currently under review, if any.
  ScanNode? get focusedNode {
    if (focusedNodeId == null) return null;
    for (final root in roots) {
      if (root.id == focusedNodeId) return root;
    }
    return null;
  }

  ScanState copyWith({
    ScanPhase? phase,
    List<ScanNode>? roots,
    ScanSelection? selection,
    double? fraction,
    String? currentPath,
    List<String>? recentPaths,
    int? visitedCount,
    bool? permissionLimited,
    CleanOutcome? outcome,
    String? error,
    String? focusedNodeId,
    bool clearOutcome = false,
    bool clearFocus = false,
    bool clearError = false,
  }) {
    return ScanState(
      phase: phase ?? this.phase,
      roots: roots ?? this.roots,
      selection: selection ?? this.selection,
      fraction: fraction ?? this.fraction,
      currentPath: currentPath ?? this.currentPath,
      recentPaths: recentPaths ?? this.recentPaths,
      visitedCount: visitedCount ?? this.visitedCount,
      permissionLimited: permissionLimited ?? this.permissionLimited,
      outcome: clearOutcome ? null : (outcome ?? this.outcome),
      error: clearError ? null : (error ?? this.error),
      focusedNodeId: clearFocus ? null : (focusedNodeId ?? this.focusedNodeId),
    );
  }

  @override
  List<Object?> get props => [
    phase,
    roots,
    selection.ids,
    fraction,
    currentPath,
    recentPaths,
    visitedCount,
    permissionLimited,
    outcome,
    error,
    focusedNodeId,
  ];
}

import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tidy/core/platform/system_bridge.dart';
import 'package:tidy/core/scanning/domain/scan_module.dart';
import 'package:tidy/core/scanning/domain/scan_node.dart';
import 'package:tidy/core/scanning/domain/scan_selection.dart';
import 'package:tidy/core/scanning/logic/scan_event.dart';
import 'package:tidy/core/scanning/logic/scan_state.dart';
import 'package:tidy/core/store/models/store_models.dart';
import 'package:tidy/core/store/tidy_store.dart';

/// Drives one [ScanModule] through scan → review → clean.
///
/// Deliberately module-agnostic: every scanner gets the same state machine, and
/// adding a module means writing a data source, not another bloc.
class ScanBloc extends Bloc<ScanEvent, ScanState> {
  ScanBloc(this.module, {this.hasFullDiskAccess = true, TidyStore? store})
    : _store = store,
      super(const ScanState()) {
    on<StartScan>(_onStart);
    on<CancelScan>(_onCancel);
    on<ResetScan>(_onReset);
    on<ToggleNode>(_onToggleNode);
    on<ToggleAll>(_onToggleAll);
    on<FocusCategory>(_onFocus);
    on<CleanSelected>(_onClean);
  }

  final ScanModule module;

  /// Passed through to the module so it can decide whether to attempt
  /// TCC-protected roots, rather than silently reporting zero.
  final bool hasFullDiskAccess;

  /// Where scans and removals are written down. Null in the rare case nothing
  /// supplied one — the scan still runs, it is just not remembered.
  final TidyStore? _store;

  /// The live scan, held so [CancelScan] can actually stop it.
  ///
  /// This used to be declared and never assigned, which made every
  /// `_subscription?.cancel()` below a no-op: Stop emitted a state, the stream
  /// carried on, and the next progress frame overwrote it. The scan only ever
  /// ended by finishing.
  StreamSubscription<ScanProgress>? _subscription;

  /// Completes when the stream ends, fails, or is cancelled — so the event
  /// handler stays alive for as long as the scan does and `emit` stays legal.
  Completer<void>? _scanDone;

  /// Set by [CancelScan] so the teardown can tell "the user stopped this" from
  /// "it finished". A cancelled scan is not recorded: a half-swept run written
  /// down as a result would put a fictional trough in the history.
  bool _cancelled = false;

  /// Which scan run is current.
  ///
  /// `on<StartScan>` uses bloc's default concurrent transformer, so a second
  /// Scan press starts a handler while the first is still unwinding. Without a
  /// generation the older handler's teardown would null out the newer run's
  /// subscription and record the newer scan's start time against the older
  /// one's results.
  int _runId = 0;

  /// Timed from the event rather than the first progress emission: the wait
  /// before the first tile appears is part of how long a scan felt.
  Stopwatch? _scanClock;

  @override
  Future<void> close() async {
    _cancelled = true;
    await _stopScan();
    return super.close();
  }

  Future<void> _onStart(StartScan event, Emitter<ScanState> emit) async {
    await _stopScan();
    _cancelled = false;
    final runId = ++_runId;

    emit(
      const ScanState(phase: ScanPhase.scanning).copyWith(clearOutcome: true),
    );

    final startedAt = DateTime.now();
    _scanClock = Stopwatch()..start();

    final request = ScanRequest(
      root: event.root,
      hasFullDiskAccess: hasFullDiskAccess,
    );

    // An explicit subscription rather than `emit.forEach`, which owns its own
    // and hands back no handle — there is no way to stop a `forEach` from
    // another event handler, which is precisely what Stop has to do.
    final done = _scanDone = Completer<void>();

    _subscription = module
        .scan(request)
        .listen(
          (progress) {
            if (_cancelled || runId != _runId || emit.isDone) return;
            emit(_fromProgress(progress));
          },
          onError: (Object error, StackTrace _) {
            if (!_cancelled && runId == _runId && !emit.isDone) {
              emit(
                state.copyWith(
                  phase: ScanPhase.failed,
                  error: 'That scan could not finish.\n$error',
                ),
              );
            }
            if (!done.isCompleted) done.complete();
          },
          onDone: () {
            if (!done.isCompleted) done.complete();
          },
          cancelOnError: true,
        );

    await done.future;

    // Cancelled scans are neither recorded nor rewritten: `_onCancel` has
    // already emitted the state the user asked for, and anything here would
    // land on top of it.
    if (_cancelled || runId != _runId) return;

    _subscription = null;
    _scanDone = null;
    _recordScan(startedAt);
  }

  /// Stops the running scan, if there is one, and waits for it to let go.
  ///
  /// Awaiting the subscription's `cancel()` matters: an `async*` module stops
  /// at its next yield, and returning before that would let a frame from the
  /// old scan land on the new one's state.
  Future<void> _stopScan() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();

    final done = _scanDone;
    _scanDone = null;
    if (done != null && !done.isCompleted) done.complete();
  }

  /// Writes down what the scan found — including nothing.
  ///
  /// A scan that finds zero is the most interesting row in the table over time:
  /// it is the one that says the last clean held. Recording only the scans that
  /// found something would turn the history into a chart of bad news.
  void _recordScan(DateTime startedAt) {
    final store = _store;
    final clock = _scanClock;
    _scanClock = null;
    if (store == null || clock == null) return;
    if (state.phase == ScanPhase.failed) return;

    store.recordScan(
      ScanRecord(
        module: module.id.name,
        startedAt: startedAt,
        duration: clock.elapsed,
        bytesFound: state.totalBytes,
        itemsFound: state.roots.fold(0, (sum, root) => sum + root.leafCount),
        permissionLimited: state.permissionLimited,
      ),
    );
  }

  ScanState _fromProgress(ScanProgress progress) {
    final roots = [
      for (final node in progress.roots)
        if (node.totalBytes > 0 || node.leafCount > 0) node.sortedBySize(),
    ]..sort((a, b) => b.totalBytes.compareTo(a.totalBytes));

    // Keep whatever the user has already ticked, drop ids the rescan removed,
    // and default-select anything newly discovered.
    final selection =
        state.phase == ScanPhase.scanning && state.selection.isEmpty
            ? ScanSelection.defaultFor(roots)
            : ScanSelection.defaultFor(roots).reconcile(roots);

    if (!progress.done) {
      // Only count a place once. Modules emit a progress frame per result as
      // well as per directory, so counting every frame would inflate the number
      // into something that is technically moving and factually meaningless.
      final path = progress.currentPath;
      final isNew =
          path != null &&
          path.isNotEmpty &&
          (state.recentPaths.isEmpty || state.recentPaths.first != path);

      return state.copyWith(
        phase: ScanPhase.scanning,
        roots: roots,
        selection: selection,
        fraction: progress.fraction,
        currentPath: progress.currentPath,
        recentPaths:
            isNew
                ? [
                  path,
                  ...state.recentPaths.take(ScanState.recentPathLimit - 1),
                ]
                : state.recentPaths,
        visitedCount: isNew ? state.visitedCount + 1 : state.visitedCount,
        permissionLimited: progress.skippedForPermission,
      );
    }

    return state.copyWith(
      phase: roots.isEmpty ? ScanPhase.clean : ScanPhase.results,
      roots: roots,
      selection: selection,
      fraction: 1,
      currentPath: null,
      permissionLimited: progress.skippedForPermission,
    );
  }

  /// Stop, and keep whatever the scan had already found.
  ///
  /// Set before the await so an in-flight progress frame cannot slip past and
  /// repaint the scanning state after the user has left it.
  Future<void> _onCancel(CancelScan event, Emitter<ScanState> emit) async {
    _cancelled = true;
    _scanClock = null;
    await _stopScan();
    emit(
      state.copyWith(
        phase: state.roots.isEmpty ? ScanPhase.idle : ScanPhase.results,
        currentPath: null,
        interrupted: state.roots.isNotEmpty,
      ),
    );
  }

  Future<void> _onReset(ResetScan event, Emitter<ScanState> emit) async {
    _cancelled = true;
    _scanClock = null;
    await _stopScan();
    emit(const ScanState());
  }

  void _onToggleNode(ToggleNode event, Emitter<ScanState> emit) {
    emit(
      state.copyWith(
        selection: state.selection.toggle(event.node, select: event.select),
      ),
    );
  }

  void _onToggleAll(ToggleAll event, Emitter<ScanState> emit) {
    var selection = state.selection;
    for (final root in state.roots) {
      selection = selection.toggle(root, select: event.select);
    }
    emit(state.copyWith(selection: selection));
  }

  void _onFocus(FocusCategory event, Emitter<ScanState> emit) {
    emit(
      event.nodeId == null
          ? state.copyWith(clearFocus: true)
          : state.copyWith(focusedNodeId: event.nodeId),
    );
  }

  Future<void> _onClean(CleanSelected event, Emitter<ScanState> emit) async {
    final paths = state.selection.selectedPaths(state.roots);
    if (paths.isEmpty) return;

    final expected = state.selectedBytes;
    // Captured before the removal, because afterwards the tree has been rebuilt
    // without the leaves that went and there is nothing left to describe them.
    final removable = _selectedLeavesByCategory();

    emit(state.copyWith(phase: ScanPhase.cleaning, clearOutcome: true));

    final operationId = _store?.beginOperation(
      OperationDraft(
        kind: OperationKind.cleanup,
        label: module.id.label,
        module: module.id.name,
      ),
    );

    final result =
        event.toTrash
            ? await SystemBridge.trashItems(paths)
            : await SystemBridge.deleteItems(paths);

    final removed = result.removed.toSet();
    final survivors = _withoutRemoved(state.roots, removed);

    _recordRemoval(
      operationId: operationId,
      leaves: removable,
      removed: removed,
      toTrash: event.toTrash,
      failureCount: result.failures.length,
    );

    emit(
      state.copyWith(
        phase: ScanPhase.finished,
        roots: survivors,
        selection: state.selection.reconcile(survivors),
        clearFocus: true,
        outcome: CleanOutcome(
          requestedBytes: _proRated(
            requested: paths.length,
            removed: removed.length,
            expectedBytes: expected,
          ),
          removedCount: removed.length,
          failures: result.failures,
          movedToTrash: event.toTrash,
        ),
      ),
    );
  }

  /// Every selected leaf paired with the top-level category it sits under.
  ///
  /// The category is the root's title rather than anything the leaf carries:
  /// that is exactly the grouping the results screen shows, so the composition
  /// chart and the tiles the user ticked agree about what "Caches" means.
  List<({ScanNode leaf, String category})> _selectedLeavesByCategory() {
    final result = <({ScanNode leaf, String category})>[];
    for (final root in state.roots) {
      for (final leaf in state.selection.selectedLeaves([root])) {
        result.add((leaf: leaf, category: root.title));
      }
    }
    return result;
  }

  /// Writes down what actually went.
  ///
  /// Only leaves whose every path is in [removed] are recorded. A leaf that
  /// half-failed is left out entirely rather than counted at full size — the
  /// whole point of this table is that it can be trusted as a record of what
  /// left the disk.
  void _recordRemoval({
    required int? operationId,
    required List<({ScanNode leaf, String category})> leaves,
    required Set<String> removed,
    required bool toTrash,
    required int failureCount,
  }) {
    final store = _store;
    if (store == null || operationId == null) return;

    final at = DateTime.now();
    final items = <RemovedItemDraft>[];
    var bytes = 0;

    for (final entry in leaves) {
      final leaf = entry.leaf;
      if (leaf.paths.isEmpty || !leaf.paths.every(removed.contains)) continue;
      bytes += leaf.sizeBytes;
      items.add(
        RemovedItemDraft(
          path: leaf.paths.first,
          name: leaf.title,
          sizeBytes: leaf.sizeBytes,
          trashed: toTrash,
          category: entry.category,
          safety: leaf.safety.name,
          at: at,
        ),
      );
    }

    store
      ..recordRemovedItems(operationId, items)
      ..finishOperation(
        operationId,
        OperationOutcome(
          // Trashed and freed are kept apart on purpose: moving something to
          // the Trash reclaims nothing until the Trash is emptied, and a single
          // "space reclaimed" figure that adds them together promises the user
          // space they do not have.
          bytesTrashed: toTrash ? bytes : 0,
          bytesDeleted: toTrash ? 0 : bytes,
          itemCount: items.length,
          failureCount: failureCount,
          permissionLimited: state.permissionLimited,
        ),
      );
  }

  /// Rebuilds the tree without the leaves that actually went, so a partial
  /// failure leaves the survivors on screen instead of blanking everything.
  static List<ScanNode> _withoutRemoved(
    List<ScanNode> nodes,
    Set<String> removed,
  ) {
    final result = <ScanNode>[];
    for (final node in nodes) {
      if (node.isLeaf) {
        if (!node.paths.every(removed.contains)) result.add(node);
        continue;
      }
      final children = _withoutRemoved(node.children, removed);
      if (children.isNotEmpty) result.add(node.copyWith(children: children));
    }
    return result;
  }

  /// Never claim more than was delivered.
  static int _proRated({
    required int requested,
    required int removed,
    required int expectedBytes,
  }) {
    if (requested == 0) return 0;
    if (removed >= requested) return expectedBytes;
    return (expectedBytes * removed / requested).round();
  }
}

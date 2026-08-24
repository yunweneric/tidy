import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mac_uninstaller/core/platform/system_bridge.dart';
import 'package:mac_uninstaller/core/scanning/domain/scan_module.dart';
import 'package:mac_uninstaller/core/scanning/domain/scan_node.dart';
import 'package:mac_uninstaller/core/scanning/domain/scan_selection.dart';
import 'package:mac_uninstaller/core/scanning/logic/scan_event.dart';
import 'package:mac_uninstaller/core/scanning/logic/scan_state.dart';

/// Drives one [ScanModule] through scan → review → clean.
///
/// Deliberately module-agnostic: every scanner gets the same state machine, and
/// adding a module means writing a data source, not another bloc.
class ScanBloc extends Bloc<ScanEvent, ScanState> {
  ScanBloc(this.module, {this.hasFullDiskAccess = true})
    : super(const ScanState()) {
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

  StreamSubscription<ScanProgress>? _subscription;

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }

  Future<void> _onStart(StartScan event, Emitter<ScanState> emit) async {
    await _subscription?.cancel();

    emit(
      const ScanState(phase: ScanPhase.scanning).copyWith(clearOutcome: true),
    );

    final request = ScanRequest(
      root: event.root,
      hasFullDiskAccess: hasFullDiskAccess,
    );

    try {
      await emit.forEach<ScanProgress>(
        module.scan(request),
        onData: (progress) => _fromProgress(progress),
        onError:
            (error, _) => state.copyWith(
              phase: ScanPhase.failed,
              error: 'That scan could not finish.\n$error',
            ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          phase: ScanPhase.failed,
          error: 'That scan could not finish.\n$e',
        ),
      );
    }
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

  Future<void> _onCancel(CancelScan event, Emitter<ScanState> emit) async {
    await _subscription?.cancel();
    _subscription = null;
    emit(
      state.copyWith(
        phase: state.roots.isEmpty ? ScanPhase.idle : ScanPhase.results,
        currentPath: null,
      ),
    );
  }

  Future<void> _onReset(ResetScan event, Emitter<ScanState> emit) async {
    await _subscription?.cancel();
    _subscription = null;
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
    emit(state.copyWith(phase: ScanPhase.cleaning, clearOutcome: true));

    final result =
        event.toTrash
            ? await SystemBridge.trashItems(paths)
            : await SystemBridge.deleteItems(paths);

    final removed = result.removed.toSet();
    final survivors = _withoutRemoved(state.roots, removed);

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

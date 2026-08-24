import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tidy/core/feedback/feedback_tone.dart';
import 'package:tidy/core/models/trash_item.dart';
import 'package:tidy/core/store/metric_sampler.dart';
import 'package:tidy/core/store/models/store_models.dart';
import 'package:tidy/core/store/tidy_store.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/features/recycle_bin/data/services/recycle_bin_bridge.dart';
import 'package:tidy/features/recycle_bin/data/services/recycle_bin_service.dart';
import 'package:tidy/features/recycle_bin/logic/recycle_bin_event.dart';
import 'package:tidy/features/recycle_bin/logic/recycle_bin_state.dart';

/// Drives the Recycle Bin: what is in there, what is selected, and the two
/// things that can be done about it.
class RecycleBinBloc extends Bloc<RecycleBinEvent, RecycleBinState> {
  RecycleBinBloc(this._service, {TidyStore? store, MetricSampler? sampler})
    : _store = store,
      _sampler = sampler,
      super(const RecycleBinState()) {
    on<LoadBin>(_onLoad);
    on<RestoreItems>(_onRestore);
    on<DeleteItemsForever>(_onDelete);

    on<BinSearchChanged>(
      (event, emit) => emit(state.copyWith(query: event.query)),
    );
    on<BinLocationChanged>(
      (event, emit) => emit(
        event.locationId == null
            ? state.copyWith(clearLocation: true)
            : state.copyWith(locationId: event.locationId),
      ),
    );
    on<BinSortChanged>((event, emit) => emit(state.copyWith(sort: event.sort)));
    on<BinOldFilterToggled>(
      (event, emit) =>
          emit(state.copyWith(onlyOld: event.value ?? !state.onlyOld)),
    );
    on<BinSelectionToggled>(_onToggleSelection);
    on<BinSelectAllToggled>(_onSelectAll);
    on<BinSelectionCleared>(
      (event, emit) => emit(state.copyWith(selected: const {})),
    );
    on<BinNoticeDismissed>(
      (event, emit) => emit(state.copyWith(clearNotice: true)),
    );
  }

  final RecycleBinService _service;

  /// Where permanent deletes are written down, and where a put-back goes to
  /// un-count itself.
  final TidyStore? _store;
  final MetricSampler? _sampler;

  Future<void> _onLoad(LoadBin event, Emitter<RecycleBinState> emit) async {
    if (!event.silent) {
      emit(state.copyWith(status: RecycleBinStatus.loading, clearError: true));
    }

    try {
      final snapshot = await _service.load();
      final paths = {for (final item in snapshot.items) item.path};

      // A volume that has been unplugged takes its tab with it; leaving the
      // filter pointed at it would show an empty table with no way back.
      final locationGone =
          state.locationId != null &&
          !snapshot.locations.any((l) => l.id == state.locationId);

      // Free: the sweep has already measured every item, so the trend line
      // costs one insert rather than a walk of its own.
      _sampler?.recordTrashSize(snapshot.totalBytes);

      emit(
        state.copyWith(
          status: RecycleBinStatus.ready,
          locations: snapshot.locations,
          items: snapshot.items,
          // Anything that has left the bin since the last read cannot stay
          // selected, or the next action would be addressed to a path that is
          // no longer there.
          selected: state.selected.intersection(paths),
          clearLocation: locationGone,
          clearError: true,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: RecycleBinStatus.failed,
          error: 'Tidy could not read what is in your Trash.\n$e',
        ),
      );
    }
  }

  void _onToggleSelection(
    BinSelectionToggled event,
    Emitter<RecycleBinState> emit,
  ) {
    final selected = {...state.selected};
    if (!selected.remove(event.path)) selected.add(event.path);
    emit(state.copyWith(selected: selected));
  }

  /// Selects everything on screen, or clears it if it is already all selected.
  void _onSelectAll(BinSelectAllToggled event, Emitter<RecycleBinState> emit) {
    final visible = {for (final item in state.visibleItems) item.path};
    final allSelected =
        visible.isNotEmpty && visible.every(state.selected.contains);

    emit(
      state.copyWith(
        selected:
            allSelected
                ? state.selected.difference(visible)
                : {...state.selected, ...visible},
      ),
    );
  }

  Future<void> _onRestore(
    RestoreItems event,
    Emitter<RecycleBinState> emit,
  ) async {
    if (event.items.isEmpty) return;

    final known = event.items.where((item) => item.canPutBack).toList();
    final unknown = event.items.where((item) => !item.canPutBack).toList();

    // Only the items Tidy trashed itself carry an origin. For the rest — the
    // ones Finder put there — macOS keeps its record in a binary `.DS_Store`
    // no other app can read, so the honest move is to ask rather than to guess
    // at a folder and be confidently wrong.
    String? folder;
    if (unknown.isNotEmpty) {
      folder = await _service.chooseFolder(itemCount: unknown.length);
      // Cancelling leaves everything where it is, including the items that did
      // have an origin. Half-doing a bulk action nobody confirmed is worse than
      // doing none of it.
      if (folder == null) return;
    }

    emit(state.copyWith(busy: true, clearNotice: true));

    final results = <RestoreResult>[
      if (known.isNotEmpty) await _service.putBack(known),
      if (unknown.isNotEmpty) await _service.restoreTo(unknown, folder!),
    ];

    final restored = [for (final result in results) ...result.restored];
    final failures = [for (final result in results) ...result.failures];

    // Something pulled back out of the Trash was never reclaimed, so the
    // history has to stop counting it. Marking beats deleting the row: the
    // fact that it was removed and then restored is itself worth keeping.
    _store?.markRestored(restored.map((item) => item.from));

    add(const LoadBin(silent: true));
    emit(
      state.copyWith(
        busy: false,
        selected: state.selected.difference({
          for (final item in restored) item.from,
        }),
        notice: _restoreNotice(restored.length, failures),
      ),
    );
  }

  /// Records a permanent delete.
  ///
  /// The one removal in the app that genuinely frees space, so it is the one
  /// that writes to `bytes_deleted` rather than `bytes_trashed`. Everything
  /// else in Tidy moves things to the Trash, which reclaims nothing until this
  /// happens.
  void _recordDelete({
    required int? operationId,
    required List<TrashItem> items,
    required int freed,
    required int failureCount,
  }) {
    final store = _store;
    if (store == null || operationId == null) return;

    final at = DateTime.now();
    store
      ..recordRemovedItems(operationId, [
        for (final item in items)
          RemovedItemDraft(
            path: item.path,
            name: item.name,
            sizeBytes: item.sizeBytes,
            trashed: false,
            category: item.kind.label,
            at: at,
          ),
      ])
      ..finishOperation(
        operationId,
        OperationOutcome(
          bytesDeleted: freed,
          itemCount: items.length,
          failureCount: failureCount,
        ),
      );
    unawaited(_sampler?.sampleDiskNow() ?? Future<void>.value());
  }

  RecycleBinNotice _restoreNotice(
    int restored,
    List<RestoreFailure> failures,
  ) {
    if (failures.isEmpty) {
      return RecycleBinNotice(
        title: restored == 1 ? '1 item restored' : '$restored items restored',
        message:
            'Back out of the Trash. Anything that would have overwritten a file '
            'of the same name was given a number instead.',
        tone: FeedbackTone.success,
      );
    }

    return RecycleBinNotice(
      title: restored == 0 ? 'Nothing was restored' : '$restored of ${restored + failures.length} restored',
      message:
          'macOS refused the rest. They are still in the Trash, exactly where '
          'they were.',
      tone: restored == 0 ? FeedbackTone.danger : FeedbackTone.warning,
      details: [
        for (final failure in failures)
          (path: failure.path, error: failure.error),
      ],
    );
  }

  Future<void> _onDelete(
    DeleteItemsForever event,
    Emitter<RecycleBinState> emit,
  ) async {
    if (event.items.isEmpty) return;
    emit(state.copyWith(busy: true, clearNotice: true));

    final operationId = _store?.beginOperation(
      OperationDraft(
        kind: OperationKind.emptyTrash,
        label:
            event.items.length == 1
                ? event.items.first.name
                : '${event.items.length} items',
      ),
    );

    final result = await _service.deleteForever(event.items);
    final removed = result.removed.toSet();
    final gone = event.items.where((item) => removed.contains(item.path));
    final freed = gone.fold<int>(0, (sum, item) => sum + item.sizeBytes);

    _recordDelete(
      operationId: operationId,
      items: gone.toList(),
      freed: freed,
      failureCount: result.failures.length,
    );

    add(const LoadBin(silent: true));
    emit(
      state.copyWith(
        busy: false,
        selected: state.selected.difference(removed),
        notice:
            result.isCompleteSuccess
                ? RecycleBinNotice(
                  // Emptying the bin is the one removal in the app that
                  // genuinely frees space, so this is the one place the copy is
                  // allowed to say "freed".
                  title: '${formatBytes(freed)} freed',
                  message:
                      removed.length == 1
                          ? 'The item is gone for good.'
                          : '${removed.length} items are gone for good.',
                  tone: FeedbackTone.success,
                )
                : RecycleBinNotice(
                  title:
                      removed.isEmpty
                          ? 'Nothing was deleted'
                          : '${removed.length} of ${event.items.length} deleted',
                  message:
                      'macOS refused the rest. They are still in the Trash.',
                  tone:
                      removed.isEmpty
                          ? FeedbackTone.danger
                          : FeedbackTone.warning,
                  details: [
                    for (final failure in result.failures)
                      (path: failure.path, error: failure.error),
                  ],
                ),
      ),
    );
  }
}

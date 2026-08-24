import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mac_uninstaller/core/feedback/feedback.dart';
import 'package:mac_uninstaller/features/clipboard/data/services/clipboard_service.dart';
import 'package:mac_uninstaller/features/clipboard/logic/clipboard_event.dart';
import 'package:mac_uninstaller/features/clipboard/logic/clipboard_state.dart';

export 'package:mac_uninstaller/features/clipboard/logic/clipboard_event.dart';
export 'package:mac_uninstaller/features/clipboard/logic/clipboard_state.dart';

class ClipboardBloc extends Bloc<ClipboardEvent, ClipboardState> {
  ClipboardBloc(this._service) : super(const ClipboardState()) {
    on<LoadClipboard>(_onLoad);
    on<ClipboardChanged>(_onChanged);
    on<SearchClipboard>((event, emit) => emit(state.copyWith(query: event.query)));
    on<FilterClipboard>(
      (event, emit) => emit(
        state.copyWith(kind: event.kind, clearKind: event.kind == null),
      ),
    );
    on<CopyEntry>(_onCopy);
    on<TogglePinEntry>(_onTogglePin);
    on<DeleteEntries>(_onDelete);
    on<ClearClipboard>(_onClear);
    on<RevealEntrySource>(_onReveal);
    on<RevealSensitiveEntry>(
      (event, emit) =>
          emit(state.copyWith(revealed: {...state.revealed, event.id})),
    );
    on<DismissClipboardNotice>(
      (event, emit) => emit(state.copyWith(clearNotice: true)),
    );
  }

  final ClipboardService _service;

  /// The native store pushes when it changes, so there is no timer here and
  /// nothing to gate on page visibility — a subscription that is idle costs
  /// nothing, unlike the two-second poll the Performance monitor needs.
  StreamSubscription<void>? _subscription;

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }

  Future<void> _onLoad(LoadClipboard event, Emitter<ClipboardState> emit) async {
    emit(state.copyWith(status: ClipboardHistoryStatus.loading, clearError: true));

    _subscription ??= _service.onChanged.listen((_) {
      if (!isClosed) add(const ClipboardChanged());
    });

    await _refresh(emit);
  }

  Future<void> _onChanged(
    ClipboardChanged event,
    Emitter<ClipboardState> emit,
  ) => _refresh(emit);

  Future<void> _refresh(Emitter<ClipboardState> emit) async {
    try {
      final entries = await _service.history();
      if (isClosed) return;
      emit(
        state.copyWith(
          status: ClipboardHistoryStatus.ready,
          entries: entries,
          // A row that has gone takes its reveal with it, so an id reused by a
          // later identical copy does not arrive already unblurred.
          revealed: state.revealed
              .where((id) => entries.any((entry) => entry.id == id))
              .toSet(),
        ),
      );
    } catch (e) {
      if (isClosed) return;
      emit(
        state.copyWith(
          status: ClipboardHistoryStatus.failed,
          error: 'Could not read the clipboard history.',
        ),
      );
    }
  }

  Future<void> _onCopy(CopyEntry event, Emitter<ClipboardState> emit) async {
    _busy(emit, event.entry.id, true);
    final outcome = await _service.copyToClipboard(event.entry);
    if (isClosed) return;
    _busy(emit, event.entry.id, false);

    emit(
      state.copyWith(
        notice: outcome.ok
            ? const ClipboardNotice('Copied to the clipboard.')
            : ClipboardNotice(
                outcome.message ?? 'Could not copy that.',
                tone: FeedbackTone.warning,
              ),
      ),
    );
  }

  Future<void> _onTogglePin(
    TogglePinEntry event,
    Emitter<ClipboardState> emit,
  ) async {
    final pinned = !event.entry.pinned;
    _busy(emit, event.entry.id, true);
    await _service.setPinned(event.entry, pinned: pinned);
    if (isClosed) return;
    _busy(emit, event.entry.id, false);
    // No toast: the row visibly moves into or out of the pinned section, which
    // says it better than a message would.
  }

  Future<void> _onDelete(
    DeleteEntries event,
    Emitter<ClipboardState> emit,
  ) async {
    if (event.ids.isEmpty) return;
    await _service.delete(event.ids);
    if (isClosed) return;
    emit(
      state.copyWith(
        notice: ClipboardNotice(
          event.ids.length == 1
              ? 'Removed from the history.'
              : '${event.ids.length} items removed from the history.',
        ),
      ),
    );
  }

  Future<void> _onClear(
    ClearClipboard event,
    Emitter<ClipboardState> emit,
  ) async {
    await _service.clear(keepPinned: event.keepPinned);
    if (isClosed) return;
    emit(
      state.copyWith(
        notice: ClipboardNotice(
          event.keepPinned
              ? 'History cleared. Pinned items were kept.'
              : 'History cleared.',
        ),
      ),
    );
  }

  Future<void> _onReveal(
    RevealEntrySource event,
    Emitter<ClipboardState> emit,
  ) async {
    final outcome = await _service.revealSource(event.entry);
    if (isClosed || outcome.ok) return;
    emit(
      state.copyWith(
        notice: ClipboardNotice(
          outcome.message ?? 'Could not show that in Finder.',
          tone: FeedbackTone.warning,
        ),
      ),
    );
  }

  void _busy(Emitter<ClipboardState> emit, String id, bool busy) {
    final ids = Set<String>.from(state.busyIds);
    if (busy) {
      ids.add(id);
    } else {
      ids.remove(id);
    }
    emit(state.copyWith(busyIds: ids));
  }
}

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tidy/core/store/tidy_store.dart';
import 'package:tidy/features/activity/logic/activity_event.dart';
import 'package:tidy/features/activity/logic/activity_state.dart';

export 'package:tidy/features/activity/logic/activity_event.dart';
export 'package:tidy/features/activity/logic/activity_state.dart';

/// Drives the Activity page.
///
/// Reads [TidyStore] directly rather than through a service. There is nothing
/// to coordinate and nothing to cache: the store is a local Hive database whose
/// queries are already Dart, and a service in between would be a class that
/// forwards five calls.
class ActivityBloc extends Bloc<ActivityEvent, ActivityState> {
  ActivityBloc(this._store) : super(const ActivityState()) {
    on<LoadActivity>(_onLoad);
    on<ActivityRangeChanged>(_onRange);
    on<ActivityViewChanged>(_onView);
    on<ActivityOperationToggled>(_onToggle);
    on<ActivityCategoryChanged>(_onCategory);
    on<ActivitySearchChanged>(_onSearch);
  }

  /// How many operations the feed lists.
  ///
  /// Generous, because an operation is one row and someone looking at a
  /// quarter of history is looking for something specific.
  static const int _operationLimit = 300;

  /// How many files the audit list holds. The store's own default is 200; this
  /// page is the one place that wants the long version, and it is what
  /// [ActivityState.retentionReached] is measured against.
  static const int _itemLimit = 1000;

  final TidyStore _store;

  Future<void> _onLoad(LoadActivity event, Emitter<ActivityState> emit) async {
    if (!event.silent) emit(state.copyWith(status: ActivityStatus.loading));
    emit(_read(state));
  }

  void _onRange(ActivityRangeChanged event, Emitter<ActivityState> emit) {
    if (event.range == state.range) return;
    // Collapsed on a range change: the operation that was open may not be in
    // the new range at all, and a row of files under nothing reads as a bug.
    emit(_read(state.copyWith(range: event.range, clearExpanded: true)));
  }

  void _onView(ActivityViewChanged event, Emitter<ActivityState> emit) {
    if (event.view == state.view) return;
    emit(state.copyWith(view: event.view));
  }

  void _onCategory(ActivityCategoryChanged event, Emitter<ActivityState> emit) {
    final category = event.category;
    // Tapping the category you are already filtered to clears it, which is how
    // every other filter pill in the app behaves.
    if (category == null || category == state.category) {
      emit(state.copyWith(clearCategory: true));
      return;
    }
    emit(state.copyWith(category: category));
  }

  void _onSearch(ActivitySearchChanged event, Emitter<ActivityState> emit) {
    emit(state.copyWith(query: event.query));
  }

  /// Opens one operation's files, or closes the one that is open.
  void _onToggle(ActivityOperationToggled event, Emitter<ActivityState> emit) {
    if (state.expandedOperationId == event.operationId) {
      emit(state.copyWith(clearExpanded: true, operationItems: const []));
      return;
    }

    // One open at a time. Several expanded lists in a feed turn a page you can
    // scan into one you have to scroll, and the question being asked is about
    // one run.
    emit(
      state.copyWith(
        expandedOperationId: event.operationId,
        operationItems: _store.removedItems(
          operationId: event.operationId,
          limit: _itemLimit,
        ),
      ),
    );
  }

  /// Every query the page draws, against one cutoff.
  ///
  /// One pass rather than five events: they all come from the same store at the
  /// same instant, and staggering them would let the totals describe a range
  /// the rows below them do not.
  ActivityState _read(ActivityState from) {
    final cutoff = from.range.from();
    // The totals and the category breakdown both want a bound, and "All" has
    // none. The store cannot hold anything older than the app itself, so the
    // epoch stands in for everything without inventing a boundary.
    final bounded = cutoff ?? DateTime.fromMillisecondsSinceEpoch(0);
    final items = _store.removedItems(from: cutoff, limit: _itemLimit);

    // `recentOperations` has no cutoff of its own, so the range is applied
    // here. Without this the feed showed the last 300 runs whatever the range
    // said, while the totals above it moved — the page disagreeing with itself
    // in the most visible way it could.
    final operations = [
      for (final operation in _store.recentOperations(limit: _operationLimit))
        if (cutoff == null || !operation.startedAt.isBefore(cutoff)) operation,
    ];

    return from.copyWith(
      status: ActivityStatus.ready,
      operations: operations,
      items: items,
      categories: _store.removedByCategory(from: bounded),
      totals: _store.reclaimed(from: bounded),
      retentionReached: items.length >= _itemLimit,
      operationItems: from.expandedOperationId == null ? const [] : null,
    );
  }
}

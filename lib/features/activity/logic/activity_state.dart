import 'package:equatable/equatable.dart';
import 'package:tidy/core/store/models/store_models.dart';
import 'package:tidy/features/activity/domain/activity_range.dart';

enum ActivityStatus { initial, loading, ready }

class ActivityState extends Equatable {
  const ActivityState({
    this.status = ActivityStatus.initial,
    this.range = ActivityRange.month,
    this.view = ActivityView.operations,
    this.operations = const [],
    this.items = const [],
    this.categories = const [],
    this.totals = ReclaimTotals.empty,
    this.expandedOperationId,
    this.operationItems = const [],
    this.category,
    this.query = '',
    this.retentionReached = false,
  });

  final ActivityStatus status;
  final ActivityRange range;
  final ActivityView view;

  /// What Tidy did, newest first.
  final List<OperationSummary> operations;

  /// What it removed, newest first — the audit list, before filtering.
  final List<RemovedItemRecord> items;

  final List<CategoryTotal> categories;
  final ReclaimTotals totals;

  /// The operation whose files are showing, if any.
  final int? expandedOperationId;

  /// That operation's files. Fetched on expand rather than with the feed.
  final List<RemovedItemRecord> operationItems;

  final String? category;
  final String query;

  /// The audit list came back at its limit, so there are older files this page
  /// is not showing. Said out loud rather than left as a list that quietly
  /// stops — a history that appears to end in the middle is worse than one
  /// that admits where it was cut.
  final bool retentionReached;

  bool get isLoading => status == ActivityStatus.loading;
  bool get hasLoaded => status == ActivityStatus.ready;

  /// Loaded, and Tidy genuinely has not done anything in this range.
  bool get isEmpty => hasLoaded && operations.isEmpty && items.isEmpty;

  /// The audit list with the category and the search applied.
  ///
  /// Filtered here rather than in the query: the store reads Hive boxes in
  /// Dart, so a second pass over a list already in memory is cheaper than a
  /// second walk of every row on disk — and the search has to be responsive
  /// per keystroke.
  List<RemovedItemRecord> get visibleItems {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty && category == null) return items;

    return [
      for (final item in items)
        if ((category == null || item.category == category) &&
            (needle.isEmpty ||
                item.name.toLowerCase().contains(needle) ||
                item.path.toLowerCase().contains(needle)))
          item,
    ];
  }

  /// Bytes that are genuinely back, and bytes that are only in the Trash, kept
  /// apart everywhere — see [ReclaimTotals]. Only one of them is space you have.
  int get freedBytes => totals.deletedBytes;
  int get trashedBytes => totals.trashedBytes;

  ActivityState copyWith({
    ActivityStatus? status,
    ActivityRange? range,
    ActivityView? view,
    List<OperationSummary>? operations,
    List<RemovedItemRecord>? items,
    List<CategoryTotal>? categories,
    ReclaimTotals? totals,
    int? expandedOperationId,
    List<RemovedItemRecord>? operationItems,
    String? category,
    String? query,
    bool? retentionReached,
    bool clearExpanded = false,
    bool clearCategory = false,
  }) => ActivityState(
    status: status ?? this.status,
    range: range ?? this.range,
    view: view ?? this.view,
    operations: operations ?? this.operations,
    items: items ?? this.items,
    categories: categories ?? this.categories,
    totals: totals ?? this.totals,
    expandedOperationId:
        clearExpanded
            ? null
            : (expandedOperationId ?? this.expandedOperationId),
    operationItems: operationItems ?? this.operationItems,
    category: clearCategory ? null : (category ?? this.category),
    query: query ?? this.query,
    retentionReached: retentionReached ?? this.retentionReached,
  );

  @override
  List<Object?> get props => [
    status,
    range,
    view,
    operations,
    items,
    categories,
    totals,
    expandedOperationId,
    operationItems,
    category,
    query,
    retentionReached,
  ];
}

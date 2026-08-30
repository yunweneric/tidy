import 'package:equatable/equatable.dart';
import 'package:tidy/features/activity/domain/activity_range.dart';

sealed class ActivityEvent extends Equatable {
  const ActivityEvent();

  @override
  List<Object?> get props => const [];
}

/// First load, and the Refresh action.
class LoadActivity extends ActivityEvent {
  const LoadActivity({this.silent = false});

  /// Re-read without blanking what is on screen. The rows do not change while
  /// they are being re-read — this is a local store, not a network — so a
  /// spinner over the top of them is motion for its own sake.
  final bool silent;

  @override
  List<Object?> get props => [silent];
}

class ActivityRangeChanged extends ActivityEvent {
  const ActivityRangeChanged(this.range);

  final ActivityRange range;

  @override
  List<Object?> get props => [range];
}

class ActivityViewChanged extends ActivityEvent {
  const ActivityViewChanged(this.view);

  final ActivityView view;

  @override
  List<Object?> get props => [view];
}

/// Open or close one operation's list of files.
///
/// The files are fetched when it opens rather than with the feed: an operation
/// can carry thousands of rows and most are never looked at.
class ActivityOperationToggled extends ActivityEvent {
  const ActivityOperationToggled(this.operationId);

  final int operationId;

  @override
  List<Object?> get props => [operationId];
}

/// Narrow the audit list to one category, or clear it with null.
class ActivityCategoryChanged extends ActivityEvent {
  const ActivityCategoryChanged(this.category);

  final String? category;

  @override
  List<Object?> get props => [category];
}

/// Filter the audit list by name or path.
class ActivitySearchChanged extends ActivityEvent {
  const ActivitySearchChanged(this.query);

  final String query;

  @override
  List<Object?> get props => [query];
}

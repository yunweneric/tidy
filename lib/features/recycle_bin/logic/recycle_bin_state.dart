import 'package:equatable/equatable.dart';
import 'package:tidy/core/feedback/feedback_tone.dart';
import 'package:tidy/features/recycle_bin/data/models/trash_item.dart';
import 'package:tidy/features/recycle_bin/data/models/trash_location.dart';

enum RecycleBinStatus { initial, loading, ready, failed }

/// What the table is ordered by.
enum TrashSort { deleted, name, size }

/// One line about something that just happened, plus the per-item detail when
/// part of it did not work.
///
/// The page decides how to show it: a clean result is a toast, a partial
/// failure is an alert with the paths in it. That split lives there rather than
/// here so the bloc never picks a widget.
class RecycleBinNotice extends Equatable {
  const RecycleBinNotice({
    required this.message,
    required this.tone,
    this.title,
    this.details = const [],
  });

  final String message;
  final FeedbackTone tone;
  final String? title;

  /// Path and reason, for the things that failed.
  final List<({String path, String error})> details;

  @override
  List<Object?> get props => [message, tone, title, details.length];
}

class RecycleBinState extends Equatable {
  const RecycleBinState({
    this.status = RecycleBinStatus.initial,
    this.locations = const [],
    this.items = const [],
    this.selected = const {},
    this.query = '',
    this.locationId,
    this.sort = TrashSort.size,
    this.onlyOld = false,
    this.busy = false,
    this.notice,
    this.error,
  });

  /// How long something has to sit in the bin before the summary tile calls it
  /// out. A month is the shortest span where "you are still keeping this" is a
  /// fair thing to say — macOS's own automatic emptying uses 30 days.
  static const int staleDays = 30;

  final RecycleBinStatus status;
  final List<TrashLocation> locations;

  /// Everything in every bin. The filters below narrow this rather than the
  /// state holding several lists that can drift apart.
  final List<TrashItem> items;

  final Set<String> selected;
  final String query;

  /// Null means every bin at once.
  final String? locationId;

  final TrashSort sort;
  final bool onlyOld;

  /// An action is in flight. The table stays on screen; the buttons do not
  /// stay clickable.
  final bool busy;

  final RecycleBinNotice? notice;
  final String? error;

  // ─── Derived ──────────────────────────────────────────────────────────────

  /// The rows as they should appear: filtered, searched, sorted.
  List<TrashItem> get visibleItems {
    final needle = query.trim().toLowerCase();

    final filtered =
        items.where((item) {
          if (locationId != null && item.locationId != locationId) return false;
          if (onlyOld && (item.daysInBin ?? 0) < staleDays) return false;
          if (needle.isEmpty) return true;
          return item.name.toLowerCase().contains(needle) ||
              (item.origin?.originalPath.toLowerCase().contains(needle) ??
                  false);
        }).toList();

    filtered.sort(switch (sort) {
      TrashSort.size => (a, b) => b.sizeBytes.compareTo(a.sizeBytes),
      TrashSort.name =>
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      // Unknown dates sort last rather than pretending to be the epoch.
      TrashSort.deleted =>
        (a, b) => (b.deletedAt ?? DateTime(1970)).compareTo(
          a.deletedAt ?? DateTime(1970),
        ),
    });

    return filtered;
  }

  List<TrashItem> get selectedItems =>
      items.where((item) => selected.contains(item.path)).toList();

  int get totalBytes => items.fold(0, (sum, item) => sum + item.sizeBytes);

  int get visibleBytes =>
      visibleItems.fold(0, (sum, item) => sum + item.sizeBytes);

  int get selectedBytes =>
      selectedItems.fold(0, (sum, item) => sum + item.sizeBytes);

  /// Items nobody has looked at in a month. The one figure here with an
  /// unambiguous recommendation behind it.
  List<TrashItem> get staleItems =>
      items.where((item) => (item.daysInBin ?? 0) >= staleDays).toList();

  int countIn(String? locationId) =>
      locationId == null
          ? items.length
          : items.where((item) => item.locationId == locationId).length;

  /// True when a bin exists but macOS would not let us read it.
  bool get hasUnreadableLocation =>
      locations.any((location) => !location.readable);

  /// More than one bin means the location tabs are worth showing. One bin and
  /// they are a control with nothing to control.
  bool get hasMultipleLocations => locations.length > 1;

  bool get isEmpty => items.isEmpty;

  RecycleBinState copyWith({
    RecycleBinStatus? status,
    List<TrashLocation>? locations,
    List<TrashItem>? items,
    Set<String>? selected,
    String? query,
    String? locationId,
    TrashSort? sort,
    bool? onlyOld,
    bool? busy,
    RecycleBinNotice? notice,
    String? error,
    bool clearLocation = false,
    bool clearNotice = false,
    bool clearError = false,
  }) {
    return RecycleBinState(
      status: status ?? this.status,
      locations: locations ?? this.locations,
      items: items ?? this.items,
      selected: selected ?? this.selected,
      query: query ?? this.query,
      locationId: clearLocation ? null : (locationId ?? this.locationId),
      sort: sort ?? this.sort,
      onlyOld: onlyOld ?? this.onlyOld,
      busy: busy ?? this.busy,
      notice: clearNotice ? null : (notice ?? this.notice),
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  List<Object?> get props => [
    status,
    locations,
    items,
    selected,
    query,
    locationId,
    sort,
    onlyOld,
    busy,
    notice,
    error,
  ];
}

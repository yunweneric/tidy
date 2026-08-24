import 'package:equatable/equatable.dart';
import 'package:tidy/core/feedback/feedback.dart';
import 'package:tidy/features/clipboard/data/models/clipboard_entry.dart';

enum ClipboardHistoryStatus { initial, loading, ready, failed }

/// A one-shot outcome to toast, then forget.
class ClipboardNotice extends Equatable {
  const ClipboardNotice(this.message, {this.tone = FeedbackTone.success});

  final String message;
  final FeedbackTone tone;

  @override
  List<Object?> get props => [message, tone];
}

class ClipboardState extends Equatable {
  const ClipboardState({
    this.status = ClipboardHistoryStatus.initial,
    this.entries = const [],
    this.query = '',
    this.kind,
    this.busyIds = const {},
    this.revealed = const {},
    this.notice,
    this.error,
  });

  final ClipboardHistoryStatus status;

  /// Everything the native store holds, newest first.
  final List<ClipboardEntry> entries;

  final String query;

  /// Null means every kind.
  final ClipboardKind? kind;

  final Set<String> busyIds;

  /// Sensitive rows the user has chosen to see. Deliberately not persisted —
  /// revealing one is about this moment, not a standing decision.
  final Set<String> revealed;

  final ClipboardNotice? notice;
  final String? error;

  bool isBusy(String id) => busyIds.contains(id);

  bool isRevealed(ClipboardEntry entry) =>
      !entry.sensitive || revealed.contains(entry.id);

  /// The rows the current search and filter leave standing, newest first.
  List<ClipboardEntry> get visible {
    final needle = query.trim().toLowerCase();
    return entries.where((entry) {
      if (kind != null && entry.kind != kind) return false;
      if (needle.isEmpty) return true;
      // Sensitive rows are searchable by where they came from but not by their
      // contents — matching on a blurred secret would print it in the result.
      if (entry.sensitive) {
        return (entry.sourceAppName ?? '').toLowerCase().contains(needle);
      }
      return entry.preview.toLowerCase().contains(needle) ||
          (entry.sourceAppName ?? '').toLowerCase().contains(needle);
    }).toList();
  }

  List<ClipboardEntry> get pinned =>
      visible.where((entry) => entry.pinned).toList();

  List<ClipboardEntry> get unpinned =>
      visible.where((entry) => !entry.pinned).toList();

  /// How many of each kind are in the history, ignoring the kind filter — the
  /// tab counts must not change when a tab is selected.
  int countFor(ClipboardKind? kind) {
    final needle = query.trim().toLowerCase();
    return entries.where((entry) {
      if (kind != null && entry.kind != kind) return false;
      if (needle.isEmpty) return true;
      if (entry.sensitive) {
        return (entry.sourceAppName ?? '').toLowerCase().contains(needle);
      }
      return entry.preview.toLowerCase().contains(needle) ||
          (entry.sourceAppName ?? '').toLowerCase().contains(needle);
    }).length;
  }

  bool get isEmpty => entries.isEmpty;
  bool get hasFilter => query.trim().isNotEmpty || kind != null;

  ClipboardState copyWith({
    ClipboardHistoryStatus? status,
    List<ClipboardEntry>? entries,
    String? query,
    ClipboardKind? kind,
    bool clearKind = false,
    Set<String>? busyIds,
    Set<String>? revealed,
    ClipboardNotice? notice,
    bool clearNotice = false,
    String? error,
    bool clearError = false,
  }) {
    return ClipboardState(
      status: status ?? this.status,
      entries: entries ?? this.entries,
      query: query ?? this.query,
      kind: clearKind ? null : (kind ?? this.kind),
      busyIds: busyIds ?? this.busyIds,
      revealed: revealed ?? this.revealed,
      notice: clearNotice ? null : (notice ?? this.notice),
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  List<Object?> get props => [
    status,
    entries,
    query,
    kind,
    busyIds,
    revealed,
    notice,
    error,
  ];
}

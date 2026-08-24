import 'package:equatable/equatable.dart';
import 'package:tidy/core/models/clipboard_entry.dart';

sealed class ClipboardEvent extends Equatable {
  const ClipboardEvent();

  @override
  List<Object?> get props => const [];
}

/// Reads the history and subscribes to native changes.
class LoadClipboard extends ClipboardEvent {
  const LoadClipboard();
}

/// The native store told us something changed.
class ClipboardChanged extends ClipboardEvent {
  const ClipboardChanged();
}

class SearchClipboard extends ClipboardEvent {
  const SearchClipboard(this.query);

  final String query;

  @override
  List<Object?> get props => [query];
}

class FilterClipboard extends ClipboardEvent {
  const FilterClipboard(this.kind);

  /// Null means every kind.
  final ClipboardKind? kind;

  @override
  List<Object?> get props => [kind];
}

class CopyEntry extends ClipboardEvent {
  const CopyEntry(this.entry);

  final ClipboardEntry entry;

  @override
  List<Object?> get props => [entry.id];
}

class TogglePinEntry extends ClipboardEvent {
  const TogglePinEntry(this.entry);

  final ClipboardEntry entry;

  @override
  List<Object?> get props => [entry.id, entry.pinned];
}

class DeleteEntries extends ClipboardEvent {
  const DeleteEntries(this.ids);

  final List<String> ids;

  @override
  List<Object?> get props => [ids];
}

class ClearClipboard extends ClipboardEvent {
  const ClearClipboard({required this.keepPinned});

  final bool keepPinned;

  @override
  List<Object?> get props => [keepPinned];
}

class RevealEntrySource extends ClipboardEvent {
  const RevealEntrySource(this.entry);

  final ClipboardEntry entry;

  @override
  List<Object?> get props => [entry.id];
}

/// Un-blurs one sensitive row, for as long as the page is open.
class RevealSensitiveEntry extends ClipboardEvent {
  const RevealSensitiveEntry(this.id);

  final String id;

  @override
  List<Object?> get props => [id];
}

class DismissClipboardNotice extends ClipboardEvent {
  const DismissClipboardNotice();
}

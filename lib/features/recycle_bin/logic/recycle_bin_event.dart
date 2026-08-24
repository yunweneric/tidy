import 'package:equatable/equatable.dart';
import 'package:tidy/features/recycle_bin/data/models/trash_item.dart';
import 'package:tidy/features/recycle_bin/logic/recycle_bin_state.dart';

sealed class RecycleBinEvent extends Equatable {
  const RecycleBinEvent();

  @override
  List<Object?> get props => const [];
}

/// Reads every bin.
class LoadBin extends RecycleBinEvent {
  const LoadBin({this.silent = false});

  /// True for a re-read after an action, where blanking the table to a spinner
  /// would make putting one file back feel like a page reload.
  final bool silent;

  @override
  List<Object?> get props => [silent];
}

class BinSearchChanged extends RecycleBinEvent {
  const BinSearchChanged(this.query);

  final String query;

  @override
  List<Object?> get props => [query];
}

/// Null shows every bin at once.
class BinLocationChanged extends RecycleBinEvent {
  const BinLocationChanged(this.locationId);

  final String? locationId;

  @override
  List<Object?> get props => [locationId];
}

class BinSortChanged extends RecycleBinEvent {
  const BinSortChanged(this.sort);

  final TrashSort sort;

  @override
  List<Object?> get props => [sort];
}

/// The "sitting there over a month" filter, driven by the summary tile.
class BinOldFilterToggled extends RecycleBinEvent {
  const BinOldFilterToggled({this.value});

  /// Null flips it.
  final bool? value;

  @override
  List<Object?> get props => [value];
}

class BinSelectionToggled extends RecycleBinEvent {
  const BinSelectionToggled(this.path);

  final String path;

  @override
  List<Object?> get props => [path];
}

/// Selects or clears everything currently visible — not everything in the bin.
/// A select-all that reaches past the filter is how someone deletes what they
/// were not looking at.
class BinSelectAllToggled extends RecycleBinEvent {
  const BinSelectAllToggled();
}

class BinSelectionCleared extends RecycleBinEvent {
  const BinSelectionCleared();
}

/// Puts items back. Those Tidy trashed go to where they came from; anything
/// else needs a folder, and the bloc asks for one.
class RestoreItems extends RecycleBinEvent {
  const RestoreItems(this.items);

  final List<TrashItem> items;

  @override
  List<Object?> get props => [items.map((item) => item.path).toList()];
}

/// Deletes for good. The page has already asked.
class DeleteItemsForever extends RecycleBinEvent {
  const DeleteItemsForever(this.items);

  final List<TrashItem> items;

  @override
  List<Object?> get props => [items.map((item) => item.path).toList()];
}

/// Clears the outcome once it has been shown.
class BinNoticeDismissed extends RecycleBinEvent {
  const BinNoticeDismissed();
}

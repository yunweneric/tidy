import 'package:mac_uninstaller/core/platform/system_bridge.dart';
import 'package:mac_uninstaller/core/platform/trash_ledger.dart';
import 'package:mac_uninstaller/features/recycle_bin/data/models/trash_item.dart';
import 'package:mac_uninstaller/features/recycle_bin/data/models/trash_location.dart';
import 'package:mac_uninstaller/features/recycle_bin/data/services/recycle_bin_bridge.dart';

/// Everything the Trash can be asked to do: read it, put things back, or empty
/// it for good.
///
/// The three verbs are deliberately not the scan contract's find → select →
/// remove. Nothing here is found — it is a folder the user already knows about
/// — and the useful action on most of it is the *opposite* of removal.
class RecycleBinService {
  RecycleBinService({TrashLedger? ledger})
    : _ledger = ledger ?? TrashLedger.instance;

  final TrashLedger _ledger;

  /// Every bin and everything in it, with origins filled in for the items Tidy
  /// trashed itself.
  Future<TrashSnapshot> load() async {
    await _ledger.ensureLoaded();
    final raw = await RecycleBinBridge.readBins();

    final locations =
        ((raw['locations'] as List?) ?? const [])
            .map((entry) => TrashLocation.fromMap((entry as Map).cast()))
            .toList();

    final items =
        ((raw['items'] as List?) ?? const [])
            .map((entry) => TrashItem.fromMap((entry as Map).cast()))
            .map((item) => item.withOrigin(_ledger.originOf(item.path)))
            .toList();

    return TrashSnapshot(locations: locations, items: items);
  }

  /// Puts items back where they came from. Only for items with a known origin —
  /// [restoreTo] is the answer for the rest.
  Future<RestoreResult> putBack(List<TrashItem> items) async {
    final moves = [
      for (final item in items)
        if (item.origin != null)
          {'from': item.path, 'to': item.origin!.originalParent},
    ];
    return _restore(moves);
  }

  /// Restores items into [folder], whatever they are and wherever they were.
  Future<RestoreResult> restoreTo(List<TrashItem> items, String folder) {
    return _restore([
      for (final item in items) {'from': item.path, 'to': folder},
    ]);
  }

  Future<RestoreResult> _restore(List<Map<String, String>> moves) async {
    final result = await RecycleBinBridge.restore(moves);
    // Anything that left the Trash no longer needs a put-back record, and its
    // path could be reused by something else deleted later.
    await _ledger.forget(result.restored.map((item) => item.from));
    return result;
  }

  /// Where should these go? Null when the user cancels.
  Future<String?> chooseFolder({required int itemCount}) {
    return RecycleBinBridge.chooseFolder(
      prompt: 'Restore Here',
      message:
          itemCount == 1
              ? 'Choose where to put this item back.'
              : 'Choose where to put these $itemCount items back.',
    );
  }

  /// Deletes for good. This is the one action in the app that genuinely frees
  /// space rather than moving it, and nothing survives it.
  ///
  /// Routed through [SystemBridge] rather than the Recycle Bin's own channel so
  /// it passes the same `isRemovable` guard as every other deletion — which,
  /// among other things, refuses the trash folders themselves.
  Future<RemovalResult> deleteForever(List<TrashItem> items) async {
    final result = await SystemBridge.deleteItems([
      for (final item in items) item.path,
    ]);
    await _ledger.forget(result.removed);
    return result;
  }
}

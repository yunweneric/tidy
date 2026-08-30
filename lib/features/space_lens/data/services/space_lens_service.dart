import 'dart:io';

import 'package:tidy/core/logging/logging.dart';
import 'package:tidy/core/platform/system_bridge.dart';
import 'package:tidy/core/store/models/store_models.dart';
import 'package:tidy/core/store/tidy_store.dart';
import 'package:tidy/features/space_lens/data/models/space_level.dart';

/// Where the map can be started from.
///
/// Two, and deliberately not the boot volume. `/` walks `/System` — ten
/// gigabytes of read-only OS nobody may remove — and descends into `/Volumes`,
/// where an attached backup drive turns a folder map into a twenty-minute
/// stall. Both roots below are places where finding something big is also
/// permission to do something about it, which is the only reason to draw the
/// map at all. Anything else is one drill-down away.
enum SpaceRoot {
  home('Home'),
  applications('Applications');

  const SpaceRoot(this.label);

  final String label;

  String? get path => switch (this) {
    SpaceRoot.home => Platform.environment['HOME'],
    SpaceRoot.applications => '/Applications',
  };
}

/// Measures one folder at a time, and remembers what it measured.
///
/// **Never walks the whole disk.** The map is built a level at a time: the
/// children of one folder, each sized recursively by the native `fts(3)`
/// walker. Drilling in costs that one subtree; coming back up costs nothing,
/// because the level is still here. That is what makes a rescan incremental —
/// [refresh] re-walks the folder in front of you and leaves the rest of the
/// map alone.
///
/// The cache is per-session and in memory. A folder map is a photograph of a
/// filesystem that moves under it, so a figure carried across a launch would be
/// a claim about a Mac that has since been used; every level carries the moment
/// it was measured and the page prints it.
class SpaceLensService {
  SpaceLensService({TidyStore? store}) : _store = store;

  final TidyStore? _store;

  /// How many paths go to the native sizer at once.
  ///
  /// It walks six subtrees in parallel — past that, contention on the APFS
  /// b-tree makes it slower rather than faster — so a batch of six keeps every
  /// worker busy and still reports progress six times a folder rather than
  /// once at the end.
  static const int _batch = 6;

  final Map<String, SpaceLevel> _levels = {};

  /// What has already been measured for [path], or null.
  SpaceLevel? cached(String path) => _levels[path];

  /// Measures [path], or hands back what was measured before.
  ///
  /// [onProgress] fires per batch, which is what the gauge counts. The whole
  /// folder is measured before anything is drawn: sizes land in the order the
  /// walker finishes rather than the order the map wants, and a packing that
  /// re-flowed six times while it filled in would move the bubble the user was
  /// reaching for.
  Future<SpaceLevel> measure(
    String path, {
    bool refresh = false,
    void Function(SpaceProgress progress)? onProgress,
  }) async {
    if (!refresh) {
      final held = _levels[path];
      if (held != null) return held;
    }

    final children = await _childrenOf(path);
    if (children.isEmpty) {
      return _levels[path] = SpaceLevel(
        path: path,
        entries: const [],
        measuredAt: DateTime.now(),
        unreadable: children.unreadable,
      );
    }

    final sizes = <String, int>{};
    for (var i = 0; i < children.length; i += _batch) {
      final batch = children.paths.skip(i).take(_batch).toList();
      onProgress?.call(
        SpaceProgress(
          measured: i,
          total: children.length,
          currentName: batch.first.split('/').last,
        ),
      );
      sizes.addAll(await SystemBridge.sizeOfPaths(batch));
    }
    onProgress?.call(
      SpaceProgress(measured: children.length, total: children.length),
    );

    final entries = [
      for (final child in children.entries)
        SpaceEntry(
          path: child.path,
          // A path the sizer could not read comes back absent rather than
          // zero, and drawing it as an empty bubble would say "this is
          // nothing" about a folder we simply could not open.
          sizeBytes: sizes[child.path] ?? 0,
          isDirectory: child.isDirectory,
          modified: child.modified,
        ),
    ]..sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));

    return _levels[path] = SpaceLevel(
      path: path,
      entries: entries,
      measuredAt: DateTime.now(),
      unreadable: children.unreadable,
    );
  }

  /// Forgets [path] and everything beneath it.
  ///
  /// Called after a removal: the folder that lost a child is wrong, and so is
  /// every ancestor whose total counted those bytes — but only the levels that
  /// were actually measured exist to be wrong, so this is a prefix sweep rather
  /// than a walk.
  void invalidate(String path) {
    _levels.remove(path);
    _levels.removeWhere((key, _) => key.startsWith('$path/'));

    // Every ancestor's total included those bytes. Dropped rather than adjusted:
    // the ancestor is one native call away, and a total patched by arithmetic
    // is a figure nothing on disk was asked to confirm.
    for (
      var parent = _parentOf(path);
      parent != null;
      parent = _parentOf(parent)
    ) {
      _levels.remove(parent);
    }
  }

  void clear() => _levels.clear();

  /// Moves one entry to the Trash and writes it into the record.
  ///
  /// Trash, never delete. Space Lens is a map rather than a scanner: nothing
  /// here has been judged safe to remove, the user picked it out of a picture,
  /// and the only honest removal for something nobody vetted is the reversible
  /// one.
  Future<bool> moveToTrash(SpaceEntry entry) async {
    final operationId = _store?.beginOperation(
      OperationDraft(
        kind: OperationKind.cleanup,
        label: 'Space Lens',
        module: 'spaceLens',
      ),
    );

    final result = await SystemBridge.trashItems([entry.path]);
    final removed = result.removed.contains(entry.path);

    if (removed) {
      _store?.recordRemovedItems(operationId, [
        RemovedItemDraft(
          path: entry.path,
          name: entry.name,
          sizeBytes: entry.sizeBytes,
          trashed: true,
          category: 'Space Lens',
        ),
      ]);
      invalidate(entry.path);
    }

    _store?.finishOperation(
      operationId,
      OperationOutcome(
        // Trashed, not deleted. The bytes are still on the disk until the user
        // empties the Trash, and only `bytesDeleted` is allowed to claim space
        // back — see `OperationOutcome`.
        bytesTrashed: removed ? entry.sizeBytes : 0,
        itemCount: removed ? 1 : 0,
        failureCount: result.failures.length,
      ),
    );

    if (!removed) {
      AppLog.platform.failed(
        'move an item to the Trash',
        result.failures.firstOrNull?.error ?? 'unknown',
        fields: {'path': entry.path},
      );
    }
    return removed;
  }

  /// The immediate children of [path], listed but not yet sized.
  ///
  /// Listed in Dart rather than through the native sizer's own listing: this
  /// half is a single `readdir` and costs nothing, and splitting it off is what
  /// lets the sizing report progress instead of returning once, at the end.
  Future<_Children> _childrenOf(String path) async {
    final entries = <_Child>[];
    var unreadable = 0;

    // Counted, not swallowed. A folder macOS will not open is not an error
    // worth a dialog — Space Lens is pointed at the user's own files — but a
    // map that silently leaves out what it could not read is a map whose totals
    // are quietly too small, and the panel says so on the strength of this.
    final children = Directory(
      path,
    ).list(followLinks: false).handleError((_) => unreadable++);

    try {
      await for (final entity in children) {
        entries.add(
          _Child(
            path: entity.path,
            isDirectory: entity is Directory,
            modified: _modifiedOf(entity),
          ),
        );
      }
    } on FileSystemException catch (e) {
      AppLog.platform.failed('list a folder', e, fields: {'path': path});
      unreadable++;
    }

    return _Children(entries: entries, unreadable: unreadable);
  }

  static DateTime? _modifiedOf(FileSystemEntity entity) {
    try {
      return entity.statSync().modified;
    } catch (_) {
      return null;
    }
  }

  static String? _parentOf(String path) {
    final cut = path.lastIndexOf('/');
    if (cut <= 0) return null;
    return path.substring(0, cut);
  }
}

class _Child {
  const _Child({required this.path, required this.isDirectory, this.modified});

  final String path;
  final bool isDirectory;
  final DateTime? modified;
}

class _Children {
  const _Children({required this.entries, required this.unreadable});

  final List<_Child> entries;
  final int unreadable;

  bool get isEmpty => entries.isEmpty;
  int get length => entries.length;
  Iterable<String> get paths => entries.map((child) => child.path);
}

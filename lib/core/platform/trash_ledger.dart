import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tidy/core/logging/logging.dart';
import 'package:tidy/core/design/brand.dart';
import 'package:path/path.dart' as p;

/// One thing Tidy moved to the Trash, and where it came from.
@immutable
class TrashOrigin {
  const TrashOrigin({
    required this.trashedPath,
    required this.originalPath,
    required this.at,
  });

  /// Where it sits in the Trash now. The row's identity.
  final String trashedPath;

  /// Where it was when Tidy took it.
  final String originalPath;

  final DateTime at;

  /// The folder it should go back into.
  String get originalParent => p.dirname(originalPath);

  Map<String, dynamic> toJson() => {
    'trashed': trashedPath,
    'origin': originalPath,
    'at': at.millisecondsSinceEpoch,
  };

  static TrashOrigin? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final trashed = raw['trashed'] as String?;
    final origin = raw['origin'] as String?;
    if (trashed == null || origin == null) return null;
    return TrashOrigin(
      trashedPath: trashed,
      originalPath: origin,
      at: DateTime.fromMillisecondsSinceEpoch((raw['at'] as num?)?.toInt() ?? 0),
    );
  }
}

/// Remembers where the things Tidy trashed came from, so Recycle Bin can put
/// them back.
///
/// macOS keeps its own put-back index inside the Trash's binary `.DS_Store`,
/// which is undocumented and unreadable from outside Finder, and
/// `FileManager.trashItem` writes no record at all. So a file Tidy trashes has
/// no origin anyone can recover — unless we write it down at the one moment
/// both halves are known, which is why [SystemBridge.trashItems] records here
/// rather than each call site remembering to. A ledger that depends on callers
/// is a ledger with holes in it.
///
/// It is only ever an optimisation: an item with no entry is restored to a
/// folder the user picks, and a missing or corrupt ledger costs that and
/// nothing else.
class TrashLedger {
  TrashLedger._();

  /// A singleton rather than a locator registration because [SystemBridge] is
  /// static and reachable from both engines. The file is small and read once.
  static final TrashLedger instance = TrashLedger._();

  /// Past this the oldest entries are dropped. Entries are ~150 bytes and only
  /// matter while the item is still in the Trash, so keeping every removal the
  /// app has ever made would be a growing file nobody reads the bottom of.
  static const int _maxEntries = 4000;

  final Map<String, TrashOrigin> _origins = {};

  File? _file;
  bool _loaded = false;

  /// Writes are chained rather than fired in parallel: two removals finishing
  /// together would otherwise both read, both merge, and one would win.
  Future<void> _pending = Future.value();

  /// Reads the file once, dropping anything no longer in the Trash.
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;

    _file = await _ledgerFile();
    final file = _file;
    if (file == null || !file.existsSync()) return;

    try {
      final decoded = jsonDecode(await file.readAsString());
      final entries = decoded is Map ? decoded['entries'] : null;
      if (entries is! List) return;

      for (final raw in entries) {
        final origin = TrashOrigin.fromJson(raw);
        if (origin == null) continue;
        // An entry for something that has left the Trash — restored by Finder,
        // or emptied elsewhere — is dead weight, and its path may since have
        // been reused by a different file.
        final type = FileSystemEntity.typeSync(
          origin.trashedPath,
          followLinks: false,
        );
        if (type != FileSystemEntityType.notFound) {
          _origins[origin.trashedPath] = origin;
        }
      }
    } catch (e) {
      AppLog.platform.failed('read the trash ledger', e);
    }
  }

  /// Where [trashedPath] came from, or null if nothing knows.
  TrashOrigin? originOf(String trashedPath) => _origins[trashedPath];

  /// Records a batch of removals. [trashedTo] maps original path to where the
  /// item landed in the Trash — exactly what the native side reports.
  Future<void> record(Map<String, String> trashedTo) async {
    if (trashedTo.isEmpty) return;
    await ensureLoaded();

    final now = DateTime.now();
    for (final entry in trashedTo.entries) {
      _origins[entry.value] = TrashOrigin(
        trashedPath: entry.value,
        originalPath: entry.key,
        at: now,
      );
    }
    await _persist();
  }

  /// Drops entries for items that have left the Trash.
  Future<void> forget(Iterable<String> trashedPaths) async {
    if (!_loaded) return;
    var changed = false;
    for (final path in trashedPaths) {
      changed = _origins.remove(path) != null || changed;
    }
    if (changed) await _persist();
  }

  Future<void> _persist() {
    return _pending = _pending.then((_) async {
      final file = _file;
      if (file == null) return;

      final entries = _origins.values.toList()..sort((a, b) => b.at.compareTo(a.at));
      final kept = entries.take(_maxEntries).toList();
      if (kept.length < entries.length) {
        _origins
          ..clear()
          ..addEntries(kept.map((o) => MapEntry(o.trashedPath, o)));
      }

      try {
        await file.writeAsString(
          jsonEncode({
            'version': 1,
            'entries': [for (final origin in kept) origin.toJson()],
          }),
        );
      } catch (e) {
        AppLog.platform.failed(
          'write the trash ledger',
          e,
          fields: {'entries': kept.length},
        );
      }
    });
  }

  /// Next to `settings.json`, for the same reasons.
  static Future<File?> _ledgerFile() async {
    final home = Platform.environment['HOME'];
    if (home == null) return null;

    final dir = Directory(
      p.join(home, 'Library', 'Application Support', Brand.supportDirectoryName),
    );
    try {
      if (!dir.existsSync()) await dir.create(recursive: true);
    } on FileSystemException catch (e) {
      AppLog.platform.failed(
        'create the support directory',
        e,
        fields: {'path': dir.path},
      );
      return null;
    }
    return File(p.join(dir.path, 'trash_ledger.json'));
  }
}

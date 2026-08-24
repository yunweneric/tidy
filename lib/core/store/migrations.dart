/// The boxes the store keeps, and the one-way steps between versions of them.
///
/// Hive is schemaless, so what used to be `CREATE TABLE` is now a list of box
/// names and nothing more — a box springs into existence the first time it is
/// opened. What this file still has to do is the part Hive does not: stamp a
/// version, and hold the steps that rewrite already-written rows when a shipped
/// change means their shape moved.
///
/// Every box holds plain `Map`s of primitives rather than `TypeAdapter`s.
/// Adapters would mean `build_runner`, which this repo does not have anywhere,
/// and they would pin each row to a Dart class — so a renamed field becomes a
/// migration instead of a `??`. The field names are the old column names,
/// unchanged, so a query in `tidy_store.dart` still reads like the SQL it
/// replaced.
library;

import 'package:hive/hive.dart';

/// Bump this and add a step to [_steps] for every stored-shape change that
/// ships.
const int schemaVersion = 1;

/// One box per thing the store records.
///
/// Prefixed, because Hive puts every box in one directory as `<name>.hive` and
/// this app is not guaranteed to be the only thing that ever opens it.
abstract final class Boxes {
  /// One entry per user-visible operation, keyed by an ascending int id. The
  /// unit the Activity feed lists and the unit a "reclaimed this month" figure
  /// sums.
  static const String operations = 'tidy_operations';

  /// One entry per file or folder actually removed, keyed by an ascending int
  /// id and carrying its `operation_id`. This is the part that makes a wrong
  /// deletion auditable, which nothing in the app could do before.
  ///
  /// `trashed` is not decoration: trashing frees nothing until the Trash is
  /// emptied, so a chart that adds trashed and deleted bytes together is
  /// claiming space the user does not have.
  static const String removedItems = 'tidy_removed_items';

  /// One entry per completed scan, including the ones that found nothing and
  /// removed nothing — which are the rows that answer "is junk coming back
  /// faster than I clear it?".
  static const String scans = 'tidy_scans';

  /// Every sampled metric, in three tiers, keyed `series|granularity|epochMs`.
  /// One box with a `granularity` field rather than a box per metric, so a new
  /// statistic is a new series name and not a migration.
  ///
  /// sum/min/max/count rather than a single value because compaction has to
  /// fold many entries into one without lying: an hour of CPU readings has a
  /// mean worth keeping *and* a peak worth keeping, and averaging averages of
  /// different sample counts is how a busy minute disappears.
  static const String metrics = 'tidy_metrics';

  /// Small key/value strings — the schema version and when recording started.
  static const String meta = 'tidy_meta';
}

/// The five open boxes, carried as one thing so nothing downstream has to know
/// which box a given read lives in.
class StoreBoxes {
  const StoreBoxes({
    required this.operations,
    required this.removedItems,
    required this.scans,
    required this.metrics,
    required this.meta,
  });

  final Box<Map> operations;
  final Box<Map> removedItems;
  final Box<Map> scans;
  final Box<Map> metrics;
  final Box<String> meta;

  Future<void> close() async {
    await operations.close();
    await removedItems.close();
    await scans.close();
    await metrics.close();
    await meta.close();
  }
}

/// Opens every box, in the directory Hive was pointed at.
Future<StoreBoxes> openBoxes() async => StoreBoxes(
  operations: await Hive.openBox<Map>(Boxes.operations),
  removedItems: await Hive.openBox<Map>(Boxes.removedItems),
  scans: await Hive.openBox<Map>(Boxes.scans),
  metrics: await Hive.openBox<Map>(Boxes.metrics),
  meta: await Hive.openBox<String>(Boxes.meta),
);

/// Rewrites already-stored entries into the shape version N expects.
typedef MigrationStep = Future<void> Function(StoreBoxes boxes);

/// Migration steps, keyed by the version they upgrade *to*.
///
/// Empty at version 1 — there is nothing older to come from. Every future entry
/// must be additive or must copy data forward: this map is the only thing
/// standing between a shape change and a user's removal history.
const Map<int, MigrationStep> _steps = {};

const String _versionKey = 'schema_version';

/// Brings [boxes] up to [schemaVersion].
///
/// Returns true when the store was empty before this call, which is how the
/// caller knows to stamp `started_at` — the value every chart uses to tell
/// "nothing happened" apart from "we were not recording yet".
Future<bool> migrate(StoreBoxes boxes) async {
  final current = int.tryParse(boxes.meta.get(_versionKey) ?? '') ?? 0;
  if (current >= schemaVersion) return false;

  // A store with no version stamp *and* nothing in it is a first run. One with
  // entries but no stamp is a half-written first run, and gets walked through
  // every step rather than being treated as brand new.
  final created =
      current == 0 &&
      boxes.operations.isEmpty &&
      boxes.removedItems.isEmpty &&
      boxes.scans.isEmpty &&
      boxes.metrics.isEmpty;

  if (!created) {
    for (var version = current + 1; version <= schemaVersion; version++) {
      await _steps[version]?.call(boxes);
    }
  }

  await boxes.meta.put(_versionKey, schemaVersion.toString());
  return created;
}

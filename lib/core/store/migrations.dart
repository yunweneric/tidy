/// The schema, and the one-way steps between versions of it.
///
/// Kept as literal SQL rather than generated from Dart classes: there is no
/// `build_runner` anywhere in this repo, and a handful of tables does not
/// justify introducing codegen. What you read here is exactly what the database
/// contains.
library;

import 'package:sqlite3/sqlite3.dart';

/// Bump this and add a step to [_steps] for every schema change that ships.
const int schemaVersion = 1;

/// Statements that build the schema from nothing.
///
/// A fresh install runs these and skips the migration steps entirely, so this
/// list and the accumulated steps must always agree about the end state.
const List<String> _createSchema = [
  // One row per user-visible operation. The unit the Activity feed lists and
  // the unit a "reclaimed this month" figure sums.
  '''
  CREATE TABLE operations (
    id                 INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid               TEXT    NOT NULL UNIQUE,
    kind               TEXT    NOT NULL,
    module             TEXT,
    label              TEXT    NOT NULL,
    started_at         INTEGER NOT NULL,
    finished_at        INTEGER,
    bytes_trashed      INTEGER NOT NULL DEFAULT 0,
    bytes_deleted      INTEGER NOT NULL DEFAULT 0,
    item_count         INTEGER NOT NULL DEFAULT 0,
    failure_count      INTEGER NOT NULL DEFAULT 0,
    permission_limited INTEGER NOT NULL DEFAULT 0
  )
  ''',
  'CREATE INDEX idx_operations_at ON operations(started_at)',

  // One row per file or folder actually removed. This is the part that makes a
  // wrong deletion auditable, which nothing in the app could do before.
  //
  // `trashed` is not decoration: trashing frees nothing until the Trash is
  // emptied, so a chart that adds trashed and deleted bytes together is
  // claiming space the user does not have.
  '''
  CREATE TABLE removed_items (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    operation_id INTEGER NOT NULL REFERENCES operations(id) ON DELETE CASCADE,
    path         TEXT    NOT NULL,
    name         TEXT    NOT NULL,
    size_bytes   INTEGER NOT NULL,
    category     TEXT,
    safety       TEXT,
    trashed      INTEGER NOT NULL,
    at           INTEGER NOT NULL,
    restored_at  INTEGER
  )
  ''',
  'CREATE INDEX idx_removed_operation ON removed_items(operation_id)',
  'CREATE INDEX idx_removed_at ON removed_items(at)',
  'CREATE INDEX idx_removed_path ON removed_items(path)',

  // Scans, including the ones that found nothing and removed nothing — which
  // are the rows that answer "is junk coming back faster than I clear it?".
  '''
  CREATE TABLE scans (
    id                 INTEGER PRIMARY KEY AUTOINCREMENT,
    module             TEXT    NOT NULL,
    started_at         INTEGER NOT NULL,
    duration_ms        INTEGER NOT NULL,
    bytes_found        INTEGER NOT NULL,
    items_found        INTEGER NOT NULL,
    permission_limited INTEGER NOT NULL DEFAULT 0
  )
  ''',
  'CREATE INDEX idx_scans_at ON scans(started_at)',

  // Every sampled metric, in three tiers. One table with a `granularity`
  // column rather than a table per metric, so a new statistic is a new series
  // name and not a migration.
  //
  // sum/min/max/count rather than a single value because compaction has to
  // fold many rows into one without lying: an hour of CPU readings has a mean
  // worth keeping *and* a peak worth keeping, and averaging averages of
  // different sample counts is how a busy minute disappears.
  '''
  CREATE TABLE metric_buckets (
    series      TEXT    NOT NULL,
    granularity TEXT    NOT NULL,
    at          INTEGER NOT NULL,
    sum_value   REAL    NOT NULL,
    min_value   REAL    NOT NULL,
    max_value   REAL    NOT NULL,
    count       INTEGER NOT NULL,
    PRIMARY KEY (series, granularity, at)
  ) WITHOUT ROWID
  ''',

  'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
];

/// Migration steps, keyed by the version they upgrade *to*.
///
/// Empty at version 1 — there is nothing older to come from. Every future entry
/// must be additive or must copy data forward: this file is the only thing
/// standing between a schema change and a user's removal history.
const Map<int, List<String>> _steps = {};

/// Brings [db] up to [schemaVersion], creating the schema if it is empty.
///
/// Returns true when the database was created by this call, which is how the
/// caller knows to stamp `started_at` — the value every chart uses to tell
/// "nothing happened" apart from "we were not recording yet".
bool migrate(Database db) {
  final current = db.userVersion;

  if (current == 0 && !_hasSchema(db)) {
    db.execute('BEGIN');
    try {
      for (final statement in _createSchema) {
        db.execute(statement);
      }
      db.userVersion = schemaVersion;
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
    return true;
  }

  if (current >= schemaVersion) return false;

  db.execute('BEGIN');
  try {
    for (var version = current + 1; version <= schemaVersion; version++) {
      for (final statement in _steps[version] ?? const <String>[]) {
        db.execute(statement);
      }
    }
    db.userVersion = schemaVersion;
    db.execute('COMMIT');
  } catch (_) {
    db.execute('ROLLBACK');
    rethrow;
  }
  return false;
}

/// A database that has tables but no `user_version` — belt and braces against
/// a half-written first run leaving a schema the migrator would try to build
/// a second time.
bool _hasSchema(Database db) {
  final rows = db.select(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'operations'",
  );
  return rows.isNotEmpty;
}

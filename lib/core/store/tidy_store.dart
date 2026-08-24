import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:tidy/core/design/brand.dart';
import 'package:tidy/core/store/migrations.dart';
import 'package:tidy/core/store/models/store_models.dart';

/// Everything Tidy has done, and how the machine has looked while it did it.
///
/// Before this existed the app forgot itself continuously: `CleanOutcome` and
/// `RemovalOutcome` lived for exactly one bloc emission, `ScanCache` overwrote
/// itself every scan, and `TrashLedger` deletes its own rows the moment an item
/// leaves the Trash. So "how much have I reclaimed this month?" and "what did
/// Tidy delete from my Mac?" had no answer — not because the data was hard to
/// get, but because nobody wrote it down.
///
/// **It never leaves this machine.** The table of every file the app has removed
/// is the single most sensitive thing Tidy holds, and the app's standing promise
/// is that it uploads nothing. Rows carry a UUID so a future opt-in sync would
/// not need a migration; nothing here sends one anywhere.
///
/// SQL lives in this class and `migrations.dart` and nowhere else — no other
/// file in the app imports `sqlite3`.
class TidyStore {
  TidyStore({@visibleForTesting String? path}) : _overridePath = path;

  final String? _overridePath;

  Database? _db;

  /// When the store started recording. Every chart needs it to tell "nothing
  /// happened" apart from "we were not running", and a chart that cannot tell
  /// those apart draws a confident flat zero across a week the app was closed.
  DateTime? _recordingSince;

  DateTime? get recordingSince => _recordingSince;

  bool get isOpen => _db != null;

  String? _path;

  /// Opens the database, migrates it, and folds aged-out samples down a tier.
  ///
  /// Never throws: a statistics store that takes the app down with it on a
  /// corrupt file has its priorities backwards. On failure the store stays
  /// closed and every method below becomes a no-op, which costs the user their
  /// charts and nothing else.
  Future<void> open() async {
    if (_db != null) return;

    try {
      final path = _overridePath ?? await _databaseFile();
      if (path == null) return;
      _path = path;

      final db = sqlite3.open(path);

      // WAL so the menu-bar popover reading does not block the main window
      // writing — they are separate isolates in one process and both open this
      // file. busy_timeout covers the moment they genuinely collide.
      db.execute('PRAGMA journal_mode = WAL');
      db.execute('PRAGMA busy_timeout = 5000');
      // Off by default in SQLite, and removed_items' ON DELETE CASCADE is
      // silently not a cascade without it.
      db.execute('PRAGMA foreign_keys = ON');
      db.execute('PRAGMA synchronous = NORMAL');

      final created = migrate(db);
      _db = db;

      if (created) {
        _putMeta('started_at', DateTime.now().millisecondsSinceEpoch.toString());
      }
      _recordingSince = _readRecordingSince();

      compact();
    } catch (e) {
      debugPrint('Could not open the history store: $e');
      _db = null;
    }
  }

  void close() {
    _db?.dispose();
    _db = null;
  }

  // ─── Writing ──────────────────────────────────────────────────────────────

  /// Opens an operation and returns its row id, or null if the store is closed.
  int? beginOperation(OperationDraft draft) {
    final db = _db;
    if (db == null) return null;

    try {
      final startedAt = draft.startedAt ?? DateTime.now();
      db.execute(
        'INSERT INTO operations (uuid, kind, module, label, started_at) '
        'VALUES (?, ?, ?, ?, ?)',
        [
          _uuid(),
          draft.kind.name,
          draft.module,
          draft.label,
          startedAt.millisecondsSinceEpoch,
        ],
      );
      return db.lastInsertRowId;
    } catch (e) {
      debugPrint('Could not record the start of an operation: $e');
      return null;
    }
  }

  /// Records the files an operation removed.
  ///
  /// One prepared statement inside one transaction. A cleanup can remove tens
  /// of thousands of files, and the same inserts auto-committed individually
  /// would each be their own fsync — tens of seconds with the window frozen,
  /// because `sqlite3`'s API is synchronous and this runs on the UI isolate.
  void recordRemovedItems(int? operationId, List<RemovedItemDraft> items) {
    final db = _db;
    if (db == null || operationId == null || items.isEmpty) return;

    try {
      final statement = db.prepare(
        'INSERT INTO removed_items '
        '(operation_id, path, name, size_bytes, category, safety, trashed, at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      );
      db.execute('BEGIN');
      try {
        for (final item in items) {
          statement.execute([
            operationId,
            item.path,
            item.name,
            item.sizeBytes,
            item.category,
            item.safety,
            item.trashed ? 1 : 0,
            (item.at ?? DateTime.now()).millisecondsSinceEpoch,
          ]);
        }
        db.execute('COMMIT');
      } catch (_) {
        db.execute('ROLLBACK');
        rethrow;
      } finally {
        statement.dispose();
      }
    } catch (e) {
      debugPrint('Could not record removed items: $e');
    }
  }

  /// Closes an operation with its totals.
  void finishOperation(int? operationId, OperationOutcome outcome) {
    final db = _db;
    if (db == null || operationId == null) return;

    try {
      db.execute(
        'UPDATE operations SET finished_at = ?, bytes_trashed = ?, '
        'bytes_deleted = ?, item_count = ?, failure_count = ?, '
        'permission_limited = ? WHERE id = ?',
        [
          DateTime.now().millisecondsSinceEpoch,
          outcome.bytesTrashed,
          outcome.bytesDeleted,
          outcome.itemCount,
          outcome.failureCount,
          outcome.permissionLimited ? 1 : 0,
          operationId,
        ],
      );
    } catch (e) {
      debugPrint('Could not record the end of an operation: $e');
    }
  }

  void recordScan(ScanRecord record) {
    final db = _db;
    if (db == null) return;

    try {
      db.execute(
        'INSERT INTO scans (module, started_at, duration_ms, bytes_found, '
        'items_found, permission_limited) VALUES (?, ?, ?, ?, ?, ?)',
        [
          record.module,
          record.startedAt.millisecondsSinceEpoch,
          record.duration.inMilliseconds,
          record.bytesFound,
          record.itemsFound,
          record.permissionLimited ? 1 : 0,
        ],
      );
    } catch (e) {
      debugPrint('Could not record a scan: $e');
    }
  }

  /// Marks trashed items as restored, so "reclaimed" does not keep counting
  /// bytes the user pulled back out of the Trash.
  void markRestored(Iterable<String> paths) {
    final db = _db;
    if (db == null) return;

    final list = paths.toList();
    if (list.isEmpty) return;

    try {
      final statement = db.prepare(
        'UPDATE removed_items SET restored_at = ? '
        'WHERE path = ? AND trashed = 1 AND restored_at IS NULL',
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      db.execute('BEGIN');
      try {
        for (final path in list) {
          statement.execute([now, path]);
        }
        db.execute('COMMIT');
      } catch (_) {
        db.execute('ROLLBACK');
        rethrow;
      } finally {
        statement.dispose();
      }
    } catch (e) {
      debugPrint('Could not mark items as restored: $e');
    }
  }

  /// Records one reading into the minute tier.
  ///
  /// Upserts, so two samples inside the same minute fold together rather than
  /// the second being dropped or overwriting the first.
  void sample(MetricSeries series, double value, {DateTime? at}) {
    final db = _db;
    if (db == null || value.isNaN || value.isInfinite) return;

    try {
      final bucket = _floor(at ?? DateTime.now(), Granularity.minute);
      db.execute(
        'INSERT INTO metric_buckets '
        '(series, granularity, at, sum_value, min_value, max_value, count) '
        'VALUES (?, ?, ?, ?, ?, ?, 1) '
        'ON CONFLICT(series, granularity, at) DO UPDATE SET '
        'sum_value = sum_value + excluded.sum_value, '
        'min_value = MIN(min_value, excluded.min_value), '
        'max_value = MAX(max_value, excluded.max_value), '
        'count = count + 1',
        [
          series.name,
          Granularity.minute.id,
          bucket.millisecondsSinceEpoch,
          value,
          value,
          value,
        ],
      );
    } catch (e) {
      debugPrint('Could not record a ${series.name} sample: $e');
    }
  }

  /// Records a value straight into the day tier, for things measured about once
  /// a day anyway (installed app count and size). Keeps a daily figure out of
  /// the minute tier, where compaction would average it into meaninglessness.
  void sampleDaily(MetricSeries series, double value, {DateTime? at}) {
    final db = _db;
    if (db == null || value.isNaN || value.isInfinite) return;

    try {
      final bucket = _floor(at ?? DateTime.now(), Granularity.day);
      db.execute(
        'INSERT INTO metric_buckets '
        '(series, granularity, at, sum_value, min_value, max_value, count) '
        'VALUES (?, ?, ?, ?, ?, ?, 1) '
        'ON CONFLICT(series, granularity, at) DO UPDATE SET '
        'sum_value = excluded.sum_value, '
        'min_value = excluded.min_value, '
        'max_value = excluded.max_value, '
        'count = 1',
        [
          series.name,
          Granularity.day.id,
          bucket.millisecondsSinceEpoch,
          value,
          value,
          value,
        ],
      );
    } catch (e) {
      debugPrint('Could not record a daily ${series.name} sample: $e');
    }
  }

  /// True when the day tier already has a row for [series] today, so a caller
  /// can skip work it would otherwise repeat on every launch.
  bool hasDailySample(MetricSeries series, {DateTime? on}) {
    final db = _db;
    if (db == null) return false;

    try {
      final day = _floor(on ?? DateTime.now(), Granularity.day);
      final rows = db.select(
        'SELECT 1 FROM metric_buckets WHERE series = ? AND granularity = ? '
        'AND at = ? LIMIT 1',
        [series.name, Granularity.day.id, day.millisecondsSinceEpoch],
      );
      return rows.isNotEmpty;
    } catch (e) {
      debugPrint('Could not check for a daily sample: $e');
      return false;
    }
  }

  // ─── Compaction ───────────────────────────────────────────────────────────

  /// Folds minutes into hours and hours into days, then drops what has aged out.
  ///
  /// The same three tiers and retention `NetworkStore.swift` settled on, for the
  /// same reason: nobody plots a year at one-minute resolution, and nobody can
  /// plot the last hour from daily rows. Day rows are never pruned — they are a
  /// few hundred bytes a year per series, so "forever" costs nothing.
  void compact({DateTime? now}) {
    final db = _db;
    if (db == null) return;

    final at = now ?? DateTime.now();

    try {
      db.execute('BEGIN');
      try {
        _rollUp(
          db,
          from: Granularity.minute,
          to: Granularity.hour,
          olderThan: at.subtract(const Duration(hours: 48)),
        );
        _rollUp(
          db,
          from: Granularity.hour,
          to: Granularity.day,
          olderThan: at.subtract(const Duration(days: 90)),
        );
        db.execute('COMMIT');
      } catch (_) {
        db.execute('ROLLBACK');
        rethrow;
      }
    } catch (e) {
      debugPrint('Could not compact the history store: $e');
    }
  }

  /// Merges every [from] row older than [olderThan] into its [to] bucket, then
  /// deletes the rows it merged.
  ///
  /// Sums and counts are added rather than averaged, which is what keeps the
  /// average honest: a minute with 60 readings and a minute with 1 must not
  /// carry equal weight in the hour that contains them.
  void _rollUp(
    Database db, {
    required Granularity from,
    required Granularity to,
    required DateTime olderThan,
  }) {
    final cutoff = olderThan.millisecondsSinceEpoch;
    final bucket = _localBucketSql(to);

    db.execute(
      'INSERT INTO metric_buckets '
      '(series, granularity, at, sum_value, min_value, max_value, count) '
      'SELECT series, ?, $bucket, SUM(sum_value), MIN(min_value), '
      'MAX(max_value), SUM(count) '
      'FROM metric_buckets WHERE granularity = ? AND at < ? '
      'GROUP BY series, $bucket '
      'ON CONFLICT(series, granularity, at) DO UPDATE SET '
      'sum_value = sum_value + excluded.sum_value, '
      'min_value = MIN(min_value, excluded.min_value), '
      'max_value = MAX(max_value, excluded.max_value), '
      'count = count + excluded.count',
      [to.id, from.id, cutoff],
    );

    db.execute(
      'DELETE FROM metric_buckets WHERE granularity = ? AND at < ?',
      [from.id, cutoff],
    );
  }

  /// SQL that truncates the `at` column to the start of its [granularity]
  /// **in the machine's own timezone**, and returns it back as epoch ms.
  ///
  /// Not `(at / step) * step`. Integer division buckets on UTC boundaries,
  /// while every read floors to local midnight — so in any timezone west or
  /// east of UTC the write and the read disagree about which day a row is in,
  /// and a day's bar silently splits across two. It also survives offsets that
  /// are not a whole number of hours (India, Nepal) and daylight saving, both
  /// of which arithmetic on a fixed step cannot.
  static String _localBucketSql(Granularity granularity) {
    final format = switch (granularity) {
      Granularity.minute => '%Y-%m-%d %H:%M:00',
      Granularity.hour => '%Y-%m-%d %H:00:00',
      Granularity.day => '%Y-%m-%d 00:00:00',
    };
    return "CAST(strftime('%s', strftime('$format', at / 1000, 'unixepoch', "
        "'localtime'), 'utc') AS INTEGER) * 1000";
  }

  // ─── Reading ──────────────────────────────────────────────────────────────

  List<OperationSummary> recentOperations({int limit = 20}) {
    final db = _db;
    if (db == null) return const [];

    try {
      final rows = db.select(
        'SELECT * FROM operations WHERE finished_at IS NOT NULL '
        'ORDER BY started_at DESC LIMIT ?',
        [limit],
      );
      return rows.map(_operationFrom).toList();
    } catch (e) {
      debugPrint('Could not read recent operations: $e');
      return const [];
    }
  }

  /// The buckets for one series between [from] and now, at [granularity], with
  /// periods the store has no row for filled in as [MetricBucket.missing].
  ///
  /// Filling the gaps here rather than in each chart is what makes the x axis
  /// time rather than "however many buckets happened to exist".
  List<MetricBucket> series(
    MetricSeries series, {
    required DateTime from,
    required Granularity granularity,
    DateTime? to,
  }) {
    final db = _db;
    if (db == null) return const [];

    final end = _floor(to ?? DateTime.now(), granularity);
    final start = _floor(from, granularity);
    if (!start.isBefore(end.add(granularity.step))) return const [];

    try {
      final rows = db.select(
        'SELECT at, sum_value, min_value, max_value, count '
        'FROM metric_buckets WHERE series = ? AND granularity = ? '
        'AND at >= ? AND at <= ? ORDER BY at',
        [
          series.name,
          granularity.id,
          start.millisecondsSinceEpoch,
          end.millisecondsSinceEpoch,
        ],
      );

      final byStart = <int, MetricBucket>{};
      for (final row in rows) {
        final at = DateTime.fromMillisecondsSinceEpoch(row['at'] as int);
        byStart[at.millisecondsSinceEpoch] = MetricBucket(
          at: at,
          sum: (row['sum_value'] as num).toDouble(),
          min: (row['min_value'] as num).toDouble(),
          max: (row['max_value'] as num).toDouble(),
          count: row['count'] as int,
        );
      }

      return _fill(start, end, granularity, byStart);
    } catch (e) {
      debugPrint('Could not read the ${series.name} series: $e');
      return const [];
    }
  }

  /// Bytes trashed and bytes freed per period, for the "reclaimed over time"
  /// chart. Restored items are excluded — pulling something back out of the
  /// Trash un-reclaims it.
  List<ReclaimBucket> reclaimSeries({
    required DateTime from,
    required Granularity granularity,
    DateTime? to,
  }) {
    final db = _db;
    if (db == null) return const [];

    final end = _floor(to ?? DateTime.now(), granularity);
    final start = _floor(from, granularity);
    final bucket = _localBucketSql(granularity);

    try {
      final rows = db.select(
        'SELECT $bucket AS bucket, '
        'SUM(CASE WHEN trashed = 1 THEN size_bytes ELSE 0 END) AS trashed, '
        'SUM(CASE WHEN trashed = 0 THEN size_bytes ELSE 0 END) AS deleted, '
        'COUNT(*) AS items '
        'FROM removed_items WHERE at >= ? AND at <= ? AND restored_at IS NULL '
        'GROUP BY bucket ORDER BY bucket',
        [
          start.millisecondsSinceEpoch,
          _advance(end, granularity).millisecondsSinceEpoch,
        ],
      );

      final byStart = <int, ReclaimBucket>{};
      for (final row in rows) {
        final at = DateTime.fromMillisecondsSinceEpoch(row['bucket'] as int);
        byStart[at.millisecondsSinceEpoch] = ReclaimBucket(
          at: at,
          trashedBytes: (row['trashed'] as num?)?.toInt() ?? 0,
          deletedBytes: (row['deleted'] as num?)?.toInt() ?? 0,
          itemCount: (row['items'] as num?)?.toInt() ?? 0,
        );
      }

      final slots = <ReclaimBucket>[];
      var cursor = start;
      var guard = 0;
      while (!cursor.isAfter(end) && guard++ < 4000) {
        slots.add(
          byStart[cursor.millisecondsSinceEpoch] ?? ReclaimBucket.empty(cursor),
        );
        cursor = _advance(cursor, granularity);
      }
      return slots;
    } catch (e) {
      debugPrint('Could not read the reclaim series: $e');
      return const [];
    }
  }

  ReclaimTotals reclaimed({required DateTime from, DateTime? to}) {
    final db = _db;
    if (db == null) return ReclaimTotals.empty;

    final end = to ?? DateTime.now();

    try {
      final rows = db.select(
        'SELECT '
        'SUM(CASE WHEN trashed = 1 THEN size_bytes ELSE 0 END) AS trashed, '
        'SUM(CASE WHEN trashed = 0 THEN size_bytes ELSE 0 END) AS deleted, '
        'COUNT(*) AS items, '
        'COUNT(DISTINCT operation_id) AS operations '
        'FROM removed_items WHERE at >= ? AND at <= ? AND restored_at IS NULL',
        [from.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
      );
      if (rows.isEmpty) return ReclaimTotals.empty;

      final row = rows.first;
      return ReclaimTotals(
        trashedBytes: (row['trashed'] as num?)?.toInt() ?? 0,
        deletedBytes: (row['deleted'] as num?)?.toInt() ?? 0,
        itemCount: (row['items'] as num?)?.toInt() ?? 0,
        operationCount: (row['operations'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      debugPrint('Could not read reclaim totals: $e');
      return ReclaimTotals.empty;
    }
  }

  List<CategoryTotal> removedByCategory({
    required DateTime from,
    DateTime? to,
    int limit = 8,
  }) {
    final db = _db;
    if (db == null) return const [];

    final end = to ?? DateTime.now();

    try {
      final rows = db.select(
        "SELECT COALESCE(category, 'Other') AS category, "
        'SUM(size_bytes) AS bytes, COUNT(*) AS items '
        'FROM removed_items WHERE at >= ? AND at <= ? AND restored_at IS NULL '
        'GROUP BY category ORDER BY bytes DESC LIMIT ?',
        [from.millisecondsSinceEpoch, end.millisecondsSinceEpoch, limit],
      );
      return [
        for (final row in rows)
          CategoryTotal(
            category: row['category'] as String,
            bytes: (row['bytes'] as num?)?.toInt() ?? 0,
            itemCount: (row['items'] as num?)?.toInt() ?? 0,
          ),
      ];
    } catch (e) {
      debugPrint('Could not read removals by category: $e');
      return const [];
    }
  }

  /// The audit list: what was removed, newest first.
  List<RemovedItemRecord> removedItems({
    DateTime? from,
    int? operationId,
    String? category,
    int limit = 200,
  }) {
    final db = _db;
    if (db == null) return const [];

    final where = <String>[];
    final args = <Object?>[];

    if (from != null) {
      where.add('r.at >= ?');
      args.add(from.millisecondsSinceEpoch);
    }
    if (operationId != null) {
      where.add('r.operation_id = ?');
      args.add(operationId);
    }
    if (category != null) {
      where.add('r.category = ?');
      args.add(category);
    }
    args.add(limit);

    try {
      final rows = db.select(
        'SELECT r.*, o.label AS op_label, o.kind AS op_kind '
        'FROM removed_items r JOIN operations o ON o.id = r.operation_id '
        '${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')} '}'
        'ORDER BY r.at DESC LIMIT ?',
        args,
      );
      return [
        for (final row in rows)
          RemovedItemRecord(
            path: row['path'] as String,
            name: row['name'] as String,
            sizeBytes: row['size_bytes'] as int,
            trashed: (row['trashed'] as int) == 1,
            at: DateTime.fromMillisecondsSinceEpoch(row['at'] as int),
            category: row['category'] as String?,
            safety: row['safety'] as String?,
            restoredAt: _dateOrNull(row['restored_at']),
            operationLabel: row['op_label'] as String?,
            operationKind: OperationKind.parse(row['op_kind'] as String?),
          ),
      ];
    } catch (e) {
      debugPrint('Could not read removed items: $e');
      return const [];
    }
  }

  /// Scan totals per module since [from] — how often each ran and what it found.
  List<ScanTotals> scanTotals({required DateTime from}) {
    final db = _db;
    if (db == null) return const [];

    try {
      final rows = db.select(
        'SELECT module, COUNT(*) AS runs, AVG(duration_ms) AS avg_ms, '
        'MAX(started_at) AS last_at, AVG(bytes_found) AS avg_bytes '
        'FROM scans WHERE started_at >= ? GROUP BY module ORDER BY runs DESC',
        [from.millisecondsSinceEpoch],
      );
      return [
        for (final row in rows)
          ScanTotals(
            module: row['module'] as String,
            runs: (row['runs'] as num).toInt(),
            averageDuration: Duration(
              milliseconds: (row['avg_ms'] as num?)?.round() ?? 0,
            ),
            averageBytesFound: (row['avg_bytes'] as num?)?.round() ?? 0,
            lastRunAt: _dateOrNull(row['last_at']),
          ),
      ];
    } catch (e) {
      debugPrint('Could not read scan totals: $e');
      return const [];
    }
  }

  StoreStats stats() {
    final db = _db;
    if (db == null) return StoreStats.empty;

    try {
      int count(String table) =>
          (db.select('SELECT COUNT(*) AS n FROM $table').first['n'] as num)
              .toInt();

      var size = 0;
      final path = _path;
      if (path != null) {
        for (final suffix in const ['', '-wal', '-shm']) {
          final file = File('$path$suffix');
          if (file.existsSync()) size += file.lengthSync();
        }
      }

      return StoreStats(
        operationCount: count('operations'),
        removedItemCount: count('removed_items'),
        scanCount: count('scans'),
        bucketCount: count('metric_buckets'),
        fileSizeBytes: size,
        recordingSince: _recordingSince,
      );
    } catch (e) {
      debugPrint('Could not read store stats: $e');
      return StoreStats.empty;
    }
  }

  // ─── Housekeeping ─────────────────────────────────────────────────────────

  /// Drops per-file records older than [maxAge], leaving operation totals and
  /// the day tier untouched so the long-run charts survive a trim.
  int trimRemovedItems(Duration maxAge) {
    final db = _db;
    if (db == null) return 0;

    try {
      final cutoff = DateTime.now().subtract(maxAge).millisecondsSinceEpoch;
      db.execute('DELETE FROM removed_items WHERE at < ?', [cutoff]);
      return db.updatedRows;
    } catch (e) {
      debugPrint('Could not trim removed items: $e');
      return 0;
    }
  }

  /// Erases the history. [keepMetrics] leaves the sampled machine readings,
  /// which hold no file paths, so "forget what I deleted" does not have to mean
  /// "forget how full my disk has been".
  Future<void> clear({bool keepMetrics = false}) async {
    final db = _db;
    if (db == null) return;

    try {
      db.execute('BEGIN');
      try {
        db.execute('DELETE FROM removed_items');
        db.execute('DELETE FROM operations');
        db.execute('DELETE FROM scans');
        if (!keepMetrics) db.execute('DELETE FROM metric_buckets');
        db.execute('COMMIT');
      } catch (_) {
        db.execute('ROLLBACK');
        rethrow;
      }
      // Recording starts again from now: saying "since March" over an empty
      // table would be a chart claiming months of quiet that were really
      // months of data the user asked us to forget.
      final now = DateTime.now();
      _putMeta('started_at', now.millisecondsSinceEpoch.toString());
      _recordingSince = now;
      db.execute('VACUUM');
    } catch (e) {
      debugPrint('Could not clear the history store: $e');
    }
  }

  /// Writes the whole history out as JSON, so it is the user's to keep.
  Future<File?> exportJson() async {
    final db = _db;
    if (db == null) return null;

    try {
      final directory = await _supportDirectory();
      if (directory == null) return null;

      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final file = File(p.join(directory.path, 'tidy-history-$stamp.json'));

      List<Map<String, Object?>> dump(String table, String order) => [
        for (final row in db.select('SELECT * FROM $table ORDER BY $order'))
          {for (final key in row.keys) key: row[key]},
      ];

      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'formatVersion': schemaVersion,
          'exportedAt': DateTime.now().toIso8601String(),
          'recordingSince': _recordingSince?.toIso8601String(),
          'operations': dump('operations', 'started_at'),
          'removedItems': dump('removed_items', 'at'),
          'scans': dump('scans', 'started_at'),
          'metricBuckets': dump('metric_buckets', 'series, granularity, at'),
        }),
      );
      return file;
    } catch (e) {
      debugPrint('Could not export the history store: $e');
      return null;
    }
  }

  // ─── Internals ────────────────────────────────────────────────────────────

  OperationSummary _operationFrom(Row row) => OperationSummary(
    id: row['id'] as int,
    uuid: row['uuid'] as String,
    kind: OperationKind.parse(row['kind'] as String?),
    label: row['label'] as String,
    module: row['module'] as String?,
    startedAt: DateTime.fromMillisecondsSinceEpoch(row['started_at'] as int),
    finishedAt: _dateOrNull(row['finished_at']),
    bytesTrashed: row['bytes_trashed'] as int? ?? 0,
    bytesDeleted: row['bytes_deleted'] as int? ?? 0,
    itemCount: row['item_count'] as int? ?? 0,
    failureCount: row['failure_count'] as int? ?? 0,
    permissionLimited: (row['permission_limited'] as int? ?? 0) == 1,
  );

  static DateTime? _dateOrNull(Object? raw) {
    if (raw is! int || raw == 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(raw);
  }

  List<MetricBucket> _fill(
    DateTime start,
    DateTime end,
    Granularity granularity,
    Map<int, MetricBucket> byStart,
  ) {
    final slots = <MetricBucket>[];
    var cursor = start;
    // Bounded so a row with a nonsense timestamp cannot spin here.
    var guard = 0;
    while (!cursor.isAfter(end) && guard++ < 4000) {
      slots.add(
        byStart[cursor.millisecondsSinceEpoch] ?? MetricBucket.missing(cursor),
      );
      cursor = _advance(cursor, granularity);
    }
    return slots;
  }

  /// Days are walked as calendar days rather than by adding 24 hours, so a
  /// daylight-saving change does not slide every later bucket by an hour.
  static DateTime _advance(DateTime from, Granularity granularity) {
    if (granularity != Granularity.day) return from.add(granularity.step);
    return DateTime(from.year, from.month, from.day + 1);
  }

  static DateTime _floor(DateTime at, Granularity granularity) =>
      switch (granularity) {
        Granularity.minute => DateTime(
          at.year,
          at.month,
          at.day,
          at.hour,
          at.minute,
        ),
        Granularity.hour => DateTime(at.year, at.month, at.day, at.hour),
        Granularity.day => DateTime(at.year, at.month, at.day),
      };

  DateTime? _readRecordingSince() {
    final raw = _readMeta('started_at');
    final ms = int.tryParse(raw ?? '');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  String? _readMeta(String key) {
    final db = _db;
    if (db == null) return null;
    try {
      final rows = db.select('SELECT value FROM meta WHERE key = ?', [key]);
      return rows.isEmpty ? null : rows.first['value'] as String?;
    } catch (_) {
      return null;
    }
  }

  void _putMeta(String key, String value) {
    final db = _db;
    if (db == null) return;
    try {
      db.execute(
        'INSERT INTO meta (key, value) VALUES (?, ?) '
        'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
        [key, value],
      );
    } catch (e) {
      debugPrint('Could not write meta $key: $e');
    }
  }

  /// Not a real UUID v4 — it does not need to be. It has to be unique across
  /// this machine's rows so a future sync has a stable key, and
  /// `Random.secure()` over 16 bytes is that.
  static String _uuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  /// Beside `settings.json` and the trash ledger, in the folder
  /// `AppSupport.swift` already migrates off the old MacUninstaller name.
  static Future<Directory?> _supportDirectory() async {
    final home = Platform.environment['HOME'];
    if (home == null) return null;

    final dir = Directory(
      p.join(home, 'Library', 'Application Support', Brand.supportDirectoryName),
    );
    try {
      if (!dir.existsSync()) await dir.create(recursive: true);
    } on FileSystemException catch (e) {
      debugPrint('Cannot create the support directory: ${e.message}');
      return null;
    }
    return dir;
  }

  static Future<String?> _databaseFile() async {
    final dir = await _supportDirectory();
    return dir == null ? null : p.join(dir.path, 'tidy.db');
  }
}

/// Bytes trashed and bytes freed in one period of the reclaim chart.
class ReclaimBucket {
  const ReclaimBucket({
    required this.at,
    required this.trashedBytes,
    required this.deletedBytes,
    required this.itemCount,
  });

  const ReclaimBucket.empty(this.at)
    : trashedBytes = 0,
      deletedBytes = 0,
      itemCount = 0;

  final DateTime at;
  final int trashedBytes;
  final int deletedBytes;
  final int itemCount;

  int get totalBytes => trashedBytes + deletedBytes;

  bool get isEmpty => itemCount == 0;
}

/// How a module's scans have gone.
class ScanTotals {
  const ScanTotals({
    required this.module,
    required this.runs,
    required this.averageDuration,
    required this.averageBytesFound,
    this.lastRunAt,
  });

  final String module;
  final int runs;
  final Duration averageDuration;
  final int averageBytesFound;
  final DateTime? lastRunAt;
}

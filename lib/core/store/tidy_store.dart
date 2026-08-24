import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
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
/// **It never leaves this machine.** The list of every file the app has removed
/// is the single most sensitive thing Tidy holds, and the app's standing promise
/// is that it uploads nothing. Entries carry a UUID so a future opt-in sync
/// would not need a migration; nothing here sends one anywhere.
///
/// Backed by Hive, which is pure Dart — the reason it is not SQLite is in
/// `pubspec.yaml`. Two consequences shape everything below:
///
/// 1. **Queries are Dart.** There is no `GROUP BY`, so the aggregates walk the
///    box themselves. Hive keeps a box's contents in memory, so a walk is a
///    list traversal rather than disk work, and the one genuinely large box —
///    removed items — is what `trimRemovedItems` exists to bound.
/// 2. **Writes are fire-and-forget.** Hive applies a write to the in-memory box
///    before the disk flush it returns a future for, so every read below
///    already sees it. Awaiting that future would make every writer `async` for
///    a flush no caller waits on, so [_flushLater] fires it and logs failures.
///
/// Hive lives in this class and `migrations.dart` and nowhere else — no other
/// file in the app imports `hive`.
class TidyStore {
  TidyStore({@visibleForTesting String? path}) : _overridePath = path;

  /// A *directory*, not a file: Hive writes one `.hive` file per box.
  final String? _overridePath;

  StoreBoxes? _boxes;

  /// When the store started recording. Every chart needs it to tell "nothing
  /// happened" apart from "we were not running", and a chart that cannot tell
  /// those apart draws a confident flat zero across a week the app was closed.
  DateTime? _recordingSince;

  DateTime? get recordingSince => _recordingSince;

  bool get isOpen => _boxes != null;

  String? _directory;

  // Hive's own `add()` hands back the key in a future, and `beginOperation`
  // has to return an id now. These carry the same ascending-int contract
  // SQLite's AUTOINCREMENT did, seeded from the highest key already stored.
  int _nextOperationId = 1;
  int _nextRemovedItemId = 1;
  int _nextScanId = 1;

  /// Opens the boxes, migrates them, and folds aged-out samples down a tier.
  ///
  /// Never throws: a statistics store that takes the app down with it on a
  /// corrupt file has its priorities backwards. On failure the store stays
  /// closed and every method below becomes a no-op, which costs the user their
  /// charts and nothing else.
  ///
  /// **One engine only.** Hive has no cross-isolate locking, so the menu-bar
  /// popover — which runs a second Flutter engine — must never call this. It
  /// does not: `setUpLocator` opens the store behind its `includeUi` flag.
  Future<void> open() async {
    if (_boxes != null) return;

    try {
      final directory = _overridePath ?? await _storeDirectory();
      if (directory == null) return;
      _directory = directory;

      Hive.init(directory);
      final boxes = await openBoxes();

      final created = await migrate(boxes);
      _boxes = boxes;

      _nextOperationId = _nextKey(boxes.operations);
      _nextRemovedItemId = _nextKey(boxes.removedItems);
      _nextScanId = _nextKey(boxes.scans);

      if (created) {
        _putMeta('started_at', DateTime.now().millisecondsSinceEpoch.toString());
      }
      _recordingSince = _readRecordingSince();

      compact();
      if (_overridePath == null) await _removeLegacyDatabase();
    } catch (e) {
      debugPrint('Could not open the history store: $e');
      _boxes = null;
    }
  }

  /// Flushes and closes every box.
  ///
  /// Returns a future where the SQLite version returned nothing, because Hive's
  /// close *is* the flush — callers that do not await it lose at most the last
  /// unwritten sample, which is why `main.dart` can still fire and forget.
  Future<void> close() async {
    final boxes = _boxes;
    _boxes = null;
    if (boxes == null) return;
    try {
      await boxes.close();
    } catch (e) {
      debugPrint('Could not close the history store: $e');
    }
  }

  // ─── Writing ──────────────────────────────────────────────────────────────

  /// Opens an operation and returns its id, or null if the store is closed.
  int? beginOperation(OperationDraft draft) {
    final boxes = _boxes;
    if (boxes == null) return null;

    try {
      final id = _nextOperationId++;
      final startedAt = draft.startedAt ?? DateTime.now();
      _flushLater(
        boxes.operations.put(id, <String, Object?>{
          'id': id,
          'uuid': _uuid(),
          'kind': draft.kind.name,
          'module': draft.module,
          'label': draft.label,
          'started_at': startedAt.millisecondsSinceEpoch,
          'finished_at': null,
          'bytes_trashed': 0,
          'bytes_deleted': 0,
          'item_count': 0,
          'failure_count': 0,
          'permission_limited': false,
        }),
        'record the start of an operation',
      );
      return id;
    } catch (e) {
      debugPrint('Could not record the start of an operation: $e');
      return null;
    }
  }

  /// Records the files an operation removed.
  ///
  /// One `putAll` rather than a loop of `put`s. A cleanup can remove tens of
  /// thousands of files, and Hive writes a `putAll` as a single batch — the
  /// same reason the SQLite version wrapped its inserts in one transaction.
  void recordRemovedItems(int? operationId, List<RemovedItemDraft> items) {
    final boxes = _boxes;
    if (boxes == null || operationId == null || items.isEmpty) return;

    try {
      final entries = <int, Map<String, Object?>>{};
      for (final item in items) {
        entries[_nextRemovedItemId++] = <String, Object?>{
          'operation_id': operationId,
          'path': item.path,
          'name': item.name,
          'size_bytes': item.sizeBytes,
          'category': item.category,
          'safety': item.safety,
          'trashed': item.trashed,
          'at': (item.at ?? DateTime.now()).millisecondsSinceEpoch,
          'restored_at': null,
        };
      }
      _flushLater(boxes.removedItems.putAll(entries), 'record removed items');
    } catch (e) {
      debugPrint('Could not record removed items: $e');
    }
  }

  /// Closes an operation with its totals.
  void finishOperation(int? operationId, OperationOutcome outcome) {
    final boxes = _boxes;
    if (boxes == null || operationId == null) return;

    try {
      final existing = boxes.operations.get(operationId);
      if (existing == null) return;

      _flushLater(
        boxes.operations.put(
          operationId,
          _mutable(existing)
            ..['finished_at'] = DateTime.now().millisecondsSinceEpoch
            ..['bytes_trashed'] = outcome.bytesTrashed
            ..['bytes_deleted'] = outcome.bytesDeleted
            ..['item_count'] = outcome.itemCount
            ..['failure_count'] = outcome.failureCount
            ..['permission_limited'] = outcome.permissionLimited,
        ),
        'record the end of an operation',
      );
    } catch (e) {
      debugPrint('Could not record the end of an operation: $e');
    }
  }

  void recordScan(ScanRecord record) {
    final boxes = _boxes;
    if (boxes == null) return;

    try {
      _flushLater(
        boxes.scans.put(_nextScanId++, <String, Object?>{
          'module': record.module,
          'started_at': record.startedAt.millisecondsSinceEpoch,
          'duration_ms': record.duration.inMilliseconds,
          'bytes_found': record.bytesFound,
          'items_found': record.itemsFound,
          'permission_limited': record.permissionLimited,
        }),
        'record a scan',
      );
    } catch (e) {
      debugPrint('Could not record a scan: $e');
    }
  }

  /// Marks trashed items as restored, so "reclaimed" does not keep counting
  /// bytes the user pulled back out of the Trash.
  void markRestored(Iterable<String> paths) {
    final boxes = _boxes;
    if (boxes == null) return;

    final wanted = paths.toSet();
    if (wanted.isEmpty) return;

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final updates = <dynamic, Map<String, Object?>>{};

      // One pass over the box with the paths in a set, rather than a pass per
      // path: emptying the Trash can put thousands of paths through here.
      for (final entry in boxes.removedItems.toMap().entries) {
        final row = entry.value;
        if (row['restored_at'] != null) continue;
        if (!_bool(row, 'trashed')) continue;
        if (!wanted.contains(row['path'])) continue;
        updates[entry.key] = _mutable(row)..['restored_at'] = now;
      }

      if (updates.isEmpty) return;
      _flushLater(
        boxes.removedItems.putAll(updates),
        'mark items as restored',
      );
    } catch (e) {
      debugPrint('Could not mark items as restored: $e');
    }
  }

  /// Records one reading into the minute tier.
  ///
  /// Folds into whatever is already in that minute, so two samples inside the
  /// same minute merge rather than the second being dropped or overwriting the
  /// first.
  void sample(MetricSeries series, double value, {DateTime? at}) {
    final boxes = _boxes;
    if (boxes == null || value.isNaN || value.isInfinite) return;

    try {
      final bucket = _floor(at ?? DateTime.now(), Granularity.minute);
      final key = _metricKey(series.name, Granularity.minute, bucket);
      final existing = boxes.metrics.get(key);

      final row = existing == null
          ? _metricRow(series.name, Granularity.minute, bucket, value)
          : (_mutable(existing)
              ..['sum_value'] = _double(existing, 'sum_value') + value
              ..['min_value'] = min(_double(existing, 'min_value'), value)
              ..['max_value'] = max(_double(existing, 'max_value'), value)
              ..['count'] = _int(existing, 'count') + 1);

      _flushLater(
        boxes.metrics.put(key, row),
        'record a ${series.name} sample',
      );
    } catch (e) {
      debugPrint('Could not record a ${series.name} sample: $e');
    }
  }

  /// Records a value straight into the day tier, for things measured about once
  /// a day anyway (installed app count and size). Keeps a daily figure out of
  /// the minute tier, where compaction would average it into meaninglessness.
  ///
  /// Replaces rather than folds: a second reading on the same day is a better
  /// answer to the same question, not another sample of it.
  void sampleDaily(MetricSeries series, double value, {DateTime? at}) {
    final boxes = _boxes;
    if (boxes == null || value.isNaN || value.isInfinite) return;

    try {
      final bucket = _floor(at ?? DateTime.now(), Granularity.day);
      _flushLater(
        boxes.metrics.put(
          _metricKey(series.name, Granularity.day, bucket),
          _metricRow(series.name, Granularity.day, bucket, value),
        ),
        'record a daily ${series.name} sample',
      );
    } catch (e) {
      debugPrint('Could not record a daily ${series.name} sample: $e');
    }
  }

  /// True when the day tier already has an entry for [series] today, so a
  /// caller can skip work it would otherwise repeat on every launch.
  bool hasDailySample(MetricSeries series, {DateTime? on}) {
    final boxes = _boxes;
    if (boxes == null) return false;

    try {
      final day = _floor(on ?? DateTime.now(), Granularity.day);
      return boxes.metrics.containsKey(
        _metricKey(series.name, Granularity.day, day),
      );
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
  /// plot the last hour from daily rows. Day entries are never pruned — they are
  /// a few hundred bytes a year per series, so "forever" costs nothing.
  void compact({DateTime? now}) {
    final boxes = _boxes;
    if (boxes == null) return;

    final at = now ?? DateTime.now();

    try {
      _rollUp(
        boxes,
        from: Granularity.minute,
        to: Granularity.hour,
        olderThan: at.subtract(const Duration(hours: 48)),
      );
      _rollUp(
        boxes,
        from: Granularity.hour,
        to: Granularity.day,
        olderThan: at.subtract(const Duration(days: 90)),
      );
    } catch (e) {
      debugPrint('Could not compact the history store: $e');
    }
  }

  /// Merges every [from] entry older than [olderThan] into its [to] bucket,
  /// then deletes the entries it merged.
  ///
  /// Sums and counts are added rather than averaged, which is what keeps the
  /// average honest: a minute with 60 readings and a minute with 1 must not
  /// carry equal weight in the hour that contains them.
  ///
  /// The write happens as one `putAll` and one `deleteAll`, in that order.
  /// SQLite gave this a transaction; Hive does not offer one, so the order is
  /// the safety: an interrupted roll-up leaves samples counted twice at worst,
  /// where the other order would lose them.
  void _rollUp(
    StoreBoxes boxes, {
    required Granularity from,
    required Granularity to,
    required DateTime olderThan,
  }) {
    final cutoff = olderThan.millisecondsSinceEpoch;
    final merged = <String, Map<String, Object?>>{};
    final consumed = <dynamic>[];

    for (final entry in boxes.metrics.toMap().entries) {
      final row = entry.value;
      if (row['granularity'] != from.id) continue;

      final at = _int(row, 'at');
      if (at >= cutoff) continue;

      final series = row['series'];
      if (series is! String) continue;

      final bucket = _floor(DateTime.fromMillisecondsSinceEpoch(at), to);
      final key = _metricKey(series, to, bucket);

      // Seeded from whatever is already in the target bucket, so a roll-up that
      // runs twice across a boundary adds to the hour instead of replacing it.
      final target = merged[key] ??= _mutable(
        boxes.metrics.get(key) ?? _emptyMetricRow(series, to, bucket),
      );

      target['sum_value'] =
          (target['sum_value']! as double) + _double(row, 'sum_value');
      target['min_value'] = min(
        target['min_value']! as double,
        _double(row, 'min_value'),
      );
      target['max_value'] = max(
        target['max_value']! as double,
        _double(row, 'max_value'),
      );
      target['count'] = (target['count']! as int) + _int(row, 'count');

      consumed.add(entry.key);
    }

    if (consumed.isEmpty) return;
    _flushLater(boxes.metrics.putAll(merged), 'fold ${from.id} samples up');
    _flushLater(boxes.metrics.deleteAll(consumed), 'drop folded ${from.id}s');
  }

  // ─── Reading ──────────────────────────────────────────────────────────────

  List<OperationSummary> recentOperations({int limit = 20}) {
    final boxes = _boxes;
    if (boxes == null) return const [];

    try {
      final rows =
          boxes.operations.values
              .where((row) => row['finished_at'] != null)
              .toList()
            ..sort(
              (a, b) => _int(b, 'started_at').compareTo(_int(a, 'started_at')),
            );
      return [for (final row in rows.take(limit)) _operationFrom(row)];
    } catch (e) {
      debugPrint('Could not read recent operations: $e');
      return const [];
    }
  }

  /// The buckets for one series between [from] and now, at [granularity], with
  /// periods the store has no entry for filled in as [MetricBucket.missing].
  ///
  /// Filling the gaps here rather than in each chart is what makes the x axis
  /// time rather than "however many buckets happened to exist". It also means
  /// this walks the timeline and looks each bucket up by key, rather than
  /// walking the box and filtering — the key is `series|granularity|at`, so a
  /// year of daily points is 365 map lookups and never touches another series.
  List<MetricBucket> series(
    MetricSeries series, {
    required DateTime from,
    required Granularity granularity,
    DateTime? to,
  }) {
    final boxes = _boxes;
    if (boxes == null) return const [];

    final end = _floor(to ?? DateTime.now(), granularity);
    final start = _floor(from, granularity);
    if (!start.isBefore(end.add(granularity.step))) return const [];

    try {
      final slots = <MetricBucket>[];
      var cursor = start;
      // Bounded so a nonsense range cannot spin here.
      var guard = 0;
      while (!cursor.isAfter(end) && guard++ < 4000) {
        final row = boxes.metrics.get(
          _metricKey(series.name, granularity, cursor),
        );
        slots.add(
          row == null
              ? MetricBucket.missing(cursor)
              : MetricBucket(
                  at: cursor,
                  sum: _double(row, 'sum_value'),
                  min: _double(row, 'min_value'),
                  max: _double(row, 'max_value'),
                  count: _int(row, 'count'),
                ),
        );
        cursor = _advance(cursor, granularity);
      }
      return slots;
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
    final boxes = _boxes;
    if (boxes == null) return const [];

    final end = _floor(to ?? DateTime.now(), granularity);
    final start = _floor(from, granularity);
    final startMs = start.millisecondsSinceEpoch;
    final endMs = _advance(end, granularity).millisecondsSinceEpoch;

    try {
      final tallies = <int, _ReclaimTally>{};
      for (final row in boxes.removedItems.values) {
        final at = _int(row, 'at');
        if (at < startMs || at > endMs) continue;
        if (row['restored_at'] != null) continue;

        final bucket = _floor(DateTime.fromMillisecondsSinceEpoch(at), granularity);
        (tallies[bucket.millisecondsSinceEpoch] ??= _ReclaimTally()).add(row);
      }

      final slots = <ReclaimBucket>[];
      var cursor = start;
      var guard = 0;
      while (!cursor.isAfter(end) && guard++ < 4000) {
        final tally = tallies[cursor.millisecondsSinceEpoch];
        slots.add(
          tally == null ? ReclaimBucket.empty(cursor) : tally.toBucket(cursor),
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
    final boxes = _boxes;
    if (boxes == null) return ReclaimTotals.empty;

    final startMs = from.millisecondsSinceEpoch;
    final endMs = (to ?? DateTime.now()).millisecondsSinceEpoch;

    try {
      final tally = _ReclaimTally();
      final operations = <Object?>{};
      for (final row in boxes.removedItems.values) {
        final at = _int(row, 'at');
        if (at < startMs || at > endMs) continue;
        if (row['restored_at'] != null) continue;
        tally.add(row);
        operations.add(row['operation_id']);
      }

      if (tally.itemCount == 0) return ReclaimTotals.empty;
      return ReclaimTotals(
        trashedBytes: tally.trashedBytes,
        deletedBytes: tally.deletedBytes,
        itemCount: tally.itemCount,
        operationCount: operations.length,
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
    final boxes = _boxes;
    if (boxes == null) return const [];

    final startMs = from.millisecondsSinceEpoch;
    final endMs = (to ?? DateTime.now()).millisecondsSinceEpoch;

    try {
      final bytes = <String, int>{};
      final items = <String, int>{};
      for (final row in boxes.removedItems.values) {
        final at = _int(row, 'at');
        if (at < startMs || at > endMs) continue;
        if (row['restored_at'] != null) continue;

        final category = (row['category'] as String?) ?? 'Other';
        bytes[category] = (bytes[category] ?? 0) + _int(row, 'size_bytes');
        items[category] = (items[category] ?? 0) + 1;
      }

      final totals = [
        for (final entry in bytes.entries)
          CategoryTotal(
            category: entry.key,
            bytes: entry.value,
            itemCount: items[entry.key] ?? 0,
          ),
      ]..sort((a, b) => b.bytes.compareTo(a.bytes));

      return totals.take(limit).toList();
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
    final boxes = _boxes;
    if (boxes == null) return const [];

    final startMs = from?.millisecondsSinceEpoch;

    try {
      final matched = <Map>[];
      for (final row in boxes.removedItems.values) {
        if (startMs != null && _int(row, 'at') < startMs) continue;
        if (operationId != null && row['operation_id'] != operationId) continue;
        if (category != null && row['category'] != category) continue;
        matched.add(row);
      }
      matched.sort((a, b) => _int(b, 'at').compareTo(_int(a, 'at')));

      // The old query joined `operations` for the label and kind. The join is
      // a keyed lookup now, and only for the entries that survived the limit.
      return [
        for (final row in matched.take(limit))
          _removedItemFrom(row, boxes.operations.get(row['operation_id'])),
      ];
    } catch (e) {
      debugPrint('Could not read removed items: $e');
      return const [];
    }
  }

  /// Scan totals per module since [from] — how often each ran and what it found.
  List<ScanTotals> scanTotals({required DateTime from}) {
    final boxes = _boxes;
    if (boxes == null) return const [];

    final startMs = from.millisecondsSinceEpoch;

    try {
      final runs = <String, int>{};
      final totalMs = <String, int>{};
      final totalBytes = <String, int>{};
      final lastAt = <String, int>{};

      for (final row in boxes.scans.values) {
        final at = _int(row, 'started_at');
        if (at < startMs) continue;

        final module = row['module'];
        if (module is! String) continue;

        runs[module] = (runs[module] ?? 0) + 1;
        totalMs[module] = (totalMs[module] ?? 0) + _int(row, 'duration_ms');
        totalBytes[module] =
            (totalBytes[module] ?? 0) + _int(row, 'bytes_found');
        if (at > (lastAt[module] ?? 0)) lastAt[module] = at;
      }

      final totals = [
        for (final entry in runs.entries)
          ScanTotals(
            module: entry.key,
            runs: entry.value,
            averageDuration: Duration(
              milliseconds: ((totalMs[entry.key] ?? 0) / entry.value).round(),
            ),
            averageBytesFound: ((totalBytes[entry.key] ?? 0) / entry.value)
                .round(),
            lastRunAt: _dateOrNull(lastAt[entry.key]),
          ),
      ]..sort((a, b) => b.runs.compareTo(a.runs));

      return totals;
    } catch (e) {
      debugPrint('Could not read scan totals: $e');
      return const [];
    }
  }

  StoreStats stats() {
    final boxes = _boxes;
    if (boxes == null) return StoreStats.empty;

    try {
      var size = 0;
      final directory = _directory;
      if (directory != null) {
        for (final name in const [
          Boxes.operations,
          Boxes.removedItems,
          Boxes.scans,
          Boxes.metrics,
          Boxes.meta,
        ]) {
          final file = File(p.join(directory, '$name.hive'));
          if (file.existsSync()) size += file.lengthSync();
        }
      }

      return StoreStats(
        operationCount: boxes.operations.length,
        removedItemCount: boxes.removedItems.length,
        scanCount: boxes.scans.length,
        bucketCount: boxes.metrics.length,
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
    final boxes = _boxes;
    if (boxes == null) return 0;

    try {
      final cutoff = DateTime.now().subtract(maxAge).millisecondsSinceEpoch;
      final stale = [
        for (final entry in boxes.removedItems.toMap().entries)
          if (_int(entry.value, 'at') < cutoff) entry.key,
      ];
      if (stale.isEmpty) return 0;

      _flushLater(boxes.removedItems.deleteAll(stale), 'trim removed items');
      // Hive only reclaims the deleted bytes on compaction — without this the
      // file still holds every trimmed entry as a tombstone, and the Settings
      // screen would report a store that got no smaller for being trimmed.
      _flushLater(boxes.removedItems.compact(), 'compact removed items');
      return stale.length;
    } catch (e) {
      debugPrint('Could not trim removed items: $e');
      return 0;
    }
  }

  /// Erases the history. [keepMetrics] leaves the sampled machine readings,
  /// which hold no file paths, so "forget what I deleted" does not have to mean
  /// "forget how full my disk has been".
  Future<void> clear({bool keepMetrics = false}) async {
    final boxes = _boxes;
    if (boxes == null) return;

    try {
      await boxes.removedItems.clear();
      await boxes.operations.clear();
      await boxes.scans.clear();
      if (!keepMetrics) await boxes.metrics.clear();

      _nextOperationId = 1;
      _nextRemovedItemId = 1;
      _nextScanId = 1;

      // Recording starts again from now: saying "since March" over an empty
      // store would be a chart claiming months of quiet that were really
      // months of data the user asked us to forget.
      final now = DateTime.now();
      _putMeta('started_at', now.millisecondsSinceEpoch.toString());
      _recordingSince = now;

      // The old `VACUUM`. `clear()` empties the box; this is what returns the
      // disk space, and a "clear my history" that leaves the file its old size
      // is not obviously a clear at all.
      await boxes.removedItems.compact();
      await boxes.operations.compact();
      await boxes.scans.compact();
      if (!keepMetrics) await boxes.metrics.compact();
    } catch (e) {
      debugPrint('Could not clear the history store: $e');
    }
  }

  /// Writes the whole history out as JSON, so it is the user's to keep.
  Future<File?> exportJson() async {
    final boxes = _boxes;
    if (boxes == null) return null;

    try {
      final directory = await _supportDirectory();
      if (directory == null) return null;

      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final file = File(p.join(directory.path, 'tidy-history-$stamp.json'));

      List<Map<String, Object?>> dump(Box<Map> box, String orderBy) {
        final rows = box.values.map(_mutable).toList()
          ..sort((a, b) => _int(a, orderBy).compareTo(_int(b, orderBy)));
        return rows;
      }

      final buckets = boxes.metrics.values.map(_mutable).toList()
        ..sort((a, b) {
          final bySeries = '${a['series']}'.compareTo('${b['series']}');
          if (bySeries != 0) return bySeries;
          final byGranularity = '${a['granularity']}'.compareTo(
            '${b['granularity']}',
          );
          if (byGranularity != 0) return byGranularity;
          return _int(a, 'at').compareTo(_int(b, 'at'));
        });

      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'formatVersion': schemaVersion,
          'exportedAt': DateTime.now().toIso8601String(),
          'recordingSince': _recordingSince?.toIso8601String(),
          'operations': dump(boxes.operations, 'started_at'),
          'removedItems': dump(boxes.removedItems, 'at'),
          'scans': dump(boxes.scans, 'started_at'),
          'metricBuckets': buckets,
        }),
      );
      return file;
    } catch (e) {
      debugPrint('Could not export the history store: $e');
      return null;
    }
  }

  // ─── Internals ────────────────────────────────────────────────────────────

  /// Fires a Hive write and logs it if the flush fails.
  ///
  /// See the class doc: the in-memory box is already updated by the time this
  /// is called, so the future is about durability and nothing else. Swallowing
  /// it silently would be the actual bug — an unwritable support directory
  /// would then look exactly like a working store.
  void _flushLater(Future<void> write, String what) {
    unawaited(
      write.catchError((Object e) {
        debugPrint('Could not $what: $e');
      }),
    );
  }

  /// Hive hands stored maps back as `Map<dynamic, dynamic>` and as *unmodifiable
  /// views of its own state*, so every update has to go through a copy.
  static Map<String, Object?> _mutable(Map row) => <String, Object?>{
    for (final key in row.keys) '$key': row[key],
  };

  static int _int(Map row, String key) => (row[key] as num?)?.toInt() ?? 0;

  static double _double(Map row, String key) =>
      (row[key] as num?)?.toDouble() ?? 0;

  /// Booleans survive a Hive round trip as booleans, but a store written before
  /// a field existed has null there — which is false, not a crash.
  static bool _bool(Map row, String key) => row[key] == true;

  static String _metricKey(
    String series,
    Granularity granularity,
    DateTime bucket,
  ) => '$series|${granularity.id}|${bucket.millisecondsSinceEpoch}';

  static Map<String, Object?> _metricRow(
    String series,
    Granularity granularity,
    DateTime bucket,
    double value,
  ) => <String, Object?>{
    'series': series,
    'granularity': granularity.id,
    'at': bucket.millisecondsSinceEpoch,
    'sum_value': value,
    'min_value': value,
    'max_value': value,
    'count': 1,
  };

  static Map<String, Object?> _emptyMetricRow(
    String series,
    Granularity granularity,
    DateTime bucket,
  ) => <String, Object?>{
    'series': series,
    'granularity': granularity.id,
    'at': bucket.millisecondsSinceEpoch,
    'sum_value': 0.0,
    // Seeded at the extremes so the first value folded in wins both. A zero
    // seed would pin every bucket's minimum to zero.
    'min_value': double.infinity,
    'max_value': double.negativeInfinity,
    'count': 0,
  };

  static int _nextKey(Box<Map> box) {
    var highest = 0;
    for (final key in box.keys) {
      if (key is int && key > highest) highest = key;
    }
    return highest + 1;
  }

  static OperationSummary _operationFrom(Map row) => OperationSummary(
    id: _int(row, 'id'),
    uuid: (row['uuid'] as String?) ?? '',
    kind: OperationKind.parse(row['kind'] as String?),
    label: (row['label'] as String?) ?? '',
    module: row['module'] as String?,
    startedAt: DateTime.fromMillisecondsSinceEpoch(_int(row, 'started_at')),
    finishedAt: _dateOrNull(row['finished_at']),
    bytesTrashed: _int(row, 'bytes_trashed'),
    bytesDeleted: _int(row, 'bytes_deleted'),
    itemCount: _int(row, 'item_count'),
    failureCount: _int(row, 'failure_count'),
    permissionLimited: _bool(row, 'permission_limited'),
  );

  static RemovedItemRecord _removedItemFrom(Map row, Map? operation) =>
      RemovedItemRecord(
        path: (row['path'] as String?) ?? '',
        name: (row['name'] as String?) ?? '',
        sizeBytes: _int(row, 'size_bytes'),
        trashed: _bool(row, 'trashed'),
        at: DateTime.fromMillisecondsSinceEpoch(_int(row, 'at')),
        category: row['category'] as String?,
        safety: row['safety'] as String?,
        restoredAt: _dateOrNull(row['restored_at']),
        operationLabel: operation?['label'] as String?,
        operationKind: operation == null
            ? null
            : OperationKind.parse(operation['kind'] as String?),
      );

  static DateTime? _dateOrNull(Object? raw) {
    if (raw is! int || raw == 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(raw);
  }

  /// Days are walked as calendar days rather than by adding 24 hours, so a
  /// daylight-saving change does not slide every later bucket by an hour.
  static DateTime _advance(DateTime from, Granularity granularity) {
    if (granularity != Granularity.day) return from.add(granularity.step);
    return DateTime(from.year, from.month, from.day + 1);
  }

  /// Truncates [at] to the start of its [granularity] **in the machine's own
  /// timezone**.
  ///
  /// Not `(ms ~/ step) * step`. Integer division buckets on UTC boundaries,
  /// while every read floors to local midnight — so in any timezone west or
  /// east of UTC the write and the read disagree about which day an entry is
  /// in, and a day's bar silently splits across two. Going through `DateTime`
  /// also survives offsets that are not a whole number of hours (India, Nepal)
  /// and daylight saving, both of which arithmetic on a fixed step cannot.
  ///
  /// This used to be `strftime(..., 'localtime')` inside the SQL, computed
  /// twice — once on write, once in the GROUP BY. One Dart function now, used
  /// by both, which is the one thing this rewrite made strictly simpler.
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
    final ms = int.tryParse(_boxes?.meta.get('started_at') ?? '');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  void _putMeta(String key, String value) {
    final boxes = _boxes;
    if (boxes == null) return;
    _flushLater(boxes.meta.put(key, value), 'write meta $key');
  }

  /// Not a real UUID v4 — it does not need to be. It has to be unique across
  /// this machine's entries so a future sync has a stable key, and
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

  /// Its own subfolder, because Hive writes a file per box and five of them
  /// loose beside `settings.json` reads as clutter the user did not ask for.
  static Future<String?> _storeDirectory() async {
    final support = await _supportDirectory();
    if (support == null) return null;

    final dir = Directory(p.join(support.path, 'history'));
    try {
      if (!dir.existsSync()) await dir.create(recursive: true);
    } on FileSystemException catch (e) {
      debugPrint('Cannot create the history directory: ${e.message}');
      return null;
    }
    return dir.path;
  }

  /// Deletes the SQLite database this store used to keep.
  ///
  /// Nothing can read it any more — the `sqlite3` dependency is gone — so
  /// leaving it would be leaving an unopenable file on the user's disk forever,
  /// in an app whose whole job is not doing that. Named exactly, so a stray
  /// file in the support folder is never what this removes.
  static Future<void> _removeLegacyDatabase() async {
    final support = await _supportDirectory();
    if (support == null) return;

    for (final name in const ['tidy.db', 'tidy.db-wal', 'tidy.db-shm']) {
      final file = File(p.join(support.path, name));
      try {
        if (file.existsSync()) await file.delete();
      } catch (e) {
        debugPrint('Could not remove the old $name: $e');
      }
    }
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

/// The running totals behind one reclaim bucket.
///
/// Mutable and private: what `SUM(CASE WHEN trashed ...)` did in one pass, the
/// Dart version has to do with an accumulator, and building an immutable
/// [ReclaimBucket] per removed file would allocate one object per row.
class _ReclaimTally {
  int trashedBytes = 0;
  int deletedBytes = 0;
  int itemCount = 0;

  void add(Map row) {
    final bytes = (row['size_bytes'] as num?)?.toInt() ?? 0;
    if (row['trashed'] == true) {
      trashedBytes += bytes;
    } else {
      deletedBytes += bytes;
    }
    itemCount++;
  }

  ReclaimBucket toBucket(DateTime at) => ReclaimBucket(
    at: at,
    trashedBytes: trashedBytes,
    deletedBytes: deletedBytes,
    itemCount: itemCount,
  );
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

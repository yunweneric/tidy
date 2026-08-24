import 'package:equatable/equatable.dart';

/// What a recorded operation was.
enum OperationKind {
  cleanup('Cleanup'),
  uninstall('Uninstall'),
  emptyTrash('Emptied from Trash'),
  putBack('Put back'),
  maintenance('Maintenance');

  const OperationKind(this.label);

  /// User-facing, and written the way it would be said out loud.
  final String label;

  static OperationKind parse(String? raw) => values.firstWhere(
    (kind) => kind.name == raw,
    orElse: () => OperationKind.cleanup,
  );
}

/// The resolution a series is stored at.
///
/// The same three tiers `NetworkStore.swift` uses, for the same reason: a year
/// of per-minute rows is millions of numbers nobody plots, and a chart of the
/// last hour cannot be drawn from daily ones.
enum Granularity {
  minute(Duration(minutes: 1), 'minute'),
  hour(Duration(hours: 1), 'hour'),
  day(Duration(days: 1), 'day');

  const Granularity(this.step, this.id);

  final Duration step;
  final String id;
}

/// The metric series the app records. Names are stored as strings, so adding
/// one is a new enum value and not a migration.
enum MetricSeries {
  diskFree,
  diskTotal,
  cpuPercent,
  memoryPressure,
  memoryUsed,
  swapUsed,
  thermal,
  appCount,
  appBytes,
  junkBytes,
  trashBytes;

  static MetricSeries? tryParse(String raw) {
    for (final series in values) {
      if (series.name == raw) return series;
    }
    return null;
  }
}

/// Opens an operation. The totals are not known yet — [OperationOutcome]
/// closes it.
class OperationDraft {
  const OperationDraft({
    required this.kind,
    required this.label,
    this.module,
    this.startedAt,
  });

  final OperationKind kind;
  final String label;
  final String? module;
  final DateTime? startedAt;
}

/// Closes an operation with what actually happened.
class OperationOutcome {
  const OperationOutcome({
    this.bytesTrashed = 0,
    this.bytesDeleted = 0,
    this.itemCount = 0,
    this.failureCount = 0,
    this.permissionLimited = false,
  });

  /// Moved to the Trash. Recoverable, and **not** yet freed.
  final int bytesTrashed;

  /// Permanently removed. Genuinely freed, and the only figure allowed to say so.
  final int bytesDeleted;

  final int itemCount;
  final int failureCount;
  final bool permissionLimited;
}

/// One file or folder that was removed.
class RemovedItemDraft {
  const RemovedItemDraft({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.trashed,
    this.category,
    this.safety,
    this.at,
  });

  final String path;
  final String name;
  final int sizeBytes;

  /// True when it went to the Trash rather than being deleted outright.
  final bool trashed;

  final String? category;
  final String? safety;
  final DateTime? at;
}

/// A completed operation, as the Activity feed reads it.
class OperationSummary extends Equatable {
  const OperationSummary({
    required this.id,
    required this.uuid,
    required this.kind,
    required this.label,
    required this.startedAt,
    this.module,
    this.finishedAt,
    this.bytesTrashed = 0,
    this.bytesDeleted = 0,
    this.itemCount = 0,
    this.failureCount = 0,
    this.permissionLimited = false,
  });

  final int id;
  final String uuid;
  final OperationKind kind;
  final String label;
  final String? module;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final int bytesTrashed;
  final int bytesDeleted;
  final int itemCount;
  final int failureCount;
  final bool permissionLimited;

  /// Everything this operation moved or removed. Correct as "how much did this
  /// touch", and wrong as "how much space did I get back" — for that, read
  /// [bytesDeleted] alone.
  int get bytesTotal => bytesTrashed + bytesDeleted;

  Duration? get duration => finishedAt?.difference(startedAt);

  @override
  List<Object?> get props => [id, uuid, kind, label, startedAt, finishedAt];
}

/// One removed file, as the audit list reads it.
class RemovedItemRecord extends Equatable {
  const RemovedItemRecord({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.trashed,
    required this.at,
    this.category,
    this.safety,
    this.restoredAt,
    this.operationLabel,
    this.operationKind,
  });

  final String path;
  final String name;
  final int sizeBytes;
  final bool trashed;
  final DateTime at;
  final String? category;
  final String? safety;
  final DateTime? restoredAt;
  final String? operationLabel;
  final OperationKind? operationKind;

  bool get restored => restoredAt != null;

  @override
  List<Object?> get props => [path, at, sizeBytes, trashed, restoredAt];
}

/// One completed scan.
class ScanRecord {
  const ScanRecord({
    required this.module,
    required this.startedAt,
    required this.duration,
    required this.bytesFound,
    required this.itemsFound,
    this.permissionLimited = false,
  });

  final String module;
  final DateTime startedAt;
  final Duration duration;
  final int bytesFound;
  final int itemsFound;
  final bool permissionLimited;
}

/// One point on a chart.
///
/// [count] is zero for a period the store has no row for. That is not the same
/// as a zero reading, and the charts draw the two differently — Tidy only
/// records while it is running, so a gap means "we were not here", and telling
/// someone they used nothing overnight is a claim this app cannot make.
class MetricBucket extends Equatable {
  const MetricBucket({
    required this.at,
    required this.sum,
    required this.min,
    required this.max,
    required this.count,
  });

  const MetricBucket.missing(this.at) : sum = 0, min = 0, max = 0, count = 0;

  final DateTime at;
  final double sum;
  final double min;
  final double max;
  final int count;

  bool get recorded => count > 0;

  /// The representative value for a bucket. Averaged rather than summed:
  /// every series here is a level (bytes free, percent busy), not a flow.
  double get average => count == 0 ? 0 : sum / count;

  @override
  List<Object?> get props => [at, sum, min, max, count];
}

/// Bytes moved to the Trash and bytes genuinely freed, kept apart on purpose.
class ReclaimTotals extends Equatable {
  const ReclaimTotals({
    this.trashedBytes = 0,
    this.deletedBytes = 0,
    this.itemCount = 0,
    this.operationCount = 0,
  });

  static const ReclaimTotals empty = ReclaimTotals();

  final int trashedBytes;
  final int deletedBytes;
  final int itemCount;
  final int operationCount;

  bool get isEmpty => operationCount == 0;

  @override
  List<Object?> get props => [
    trashedBytes,
    deletedBytes,
    itemCount,
    operationCount,
  ];
}

/// A slice of a composition chart.
class CategoryTotal extends Equatable {
  const CategoryTotal({
    required this.category,
    required this.bytes,
    required this.itemCount,
  });

  final String category;
  final int bytes;
  final int itemCount;

  @override
  List<Object?> get props => [category, bytes, itemCount];
}

/// What the store holds, for the Settings screen.
class StoreStats extends Equatable {
  const StoreStats({
    required this.operationCount,
    required this.removedItemCount,
    required this.scanCount,
    required this.bucketCount,
    required this.fileSizeBytes,
    this.recordingSince,
  });

  static const StoreStats empty = StoreStats(
    operationCount: 0,
    removedItemCount: 0,
    scanCount: 0,
    bucketCount: 0,
    fileSizeBytes: 0,
  );

  final int operationCount;
  final int removedItemCount;
  final int scanCount;
  final int bucketCount;
  final int fileSizeBytes;
  final DateTime? recordingSince;

  @override
  List<Object?> get props => [
    operationCount,
    removedItemCount,
    scanCount,
    bucketCount,
    fileSizeBytes,
    recordingSince,
  ];
}

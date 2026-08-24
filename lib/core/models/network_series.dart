import 'package:equatable/equatable.dart';

/// How far back a chart looks.
enum NetworkRange {
  hour('Hour', 'hour'),
  day('Day', 'day'),
  week('Week', 'week'),
  month('Month', 'month'),
  sixMonths('6 Months', 'sixMonths'),
  year('Year', 'year'),
  all('All', 'all');

  const NetworkRange(this.label, this.id);

  /// Shown on the segmented control.
  final String label;

  /// What crosses the channel. The native store switches on it.
  final String id;
}

/// The width of one bar.
///
/// Chosen natively so a year is twelve numbers by the time it reaches Dart, not
/// three hundred and sixty-five.
enum NetworkGranularity {
  minute,
  hour,
  day,
  week,
  month;

  static NetworkGranularity fromName(String? name) => values.firstWhere(
    (granularity) => granularity.name == name,
    orElse: () => NetworkGranularity.day,
  );
}

/// One period's traffic.
class NetworkBucket extends Equatable {
  const NetworkBucket({
    required this.at,
    required this.downBytes,
    required this.upBytes,
  });

  factory NetworkBucket.fromMap(Map<String, dynamic> map) => NetworkBucket(
    at: DateTime.fromMillisecondsSinceEpoch((map['t'] as int? ?? 0) * 1000),
    downBytes: map['d'] as int? ?? 0,
    upBytes: map['u'] as int? ?? 0,
  );

  /// The period's start.
  final DateTime at;
  final int downBytes;
  final int upBytes;

  int get totalBytes => downBytes + upBytes;

  @override
  List<Object?> get props => [at, downBytes, upBytes];
}

/// One interface's share of a range.
class NetworkInterfaceTotal extends Equatable {
  const NetworkInterfaceTotal({
    required this.name,
    required this.downBytes,
    required this.upBytes,
  });

  final String name;
  final int downBytes;
  final int upBytes;

  int get totalBytes => downBytes + upBytes;

  @override
  List<Object?> get props => [name, downBytes, upBytes];
}

/// What one range's chart is drawn from.
///
/// **A missing bucket means "not recorded", never "zero".** Tidy only samples
/// while Tidy is running, so a gap in this list is a stretch the app was quit
/// for. The chart draws those as gaps; rendering them as zero-height bars would
/// tell the user they used no data overnight, which is a claim this feature is
/// in no position to make.
class NetworkSeries extends Equatable {
  const NetworkSeries({
    required this.range,
    required this.granularity,
    required this.buckets,
    required this.totalDownBytes,
    required this.totalUpBytes,
    this.byInterface = const [],
    this.startedAt,
  });

  factory NetworkSeries.fromMap(Map<String, dynamic> map) {
    final split =
        (map['byInterface'] as Map?)?.cast<String, dynamic>() ?? const {};

    final totals =
        split.entries.map((entry) {
            final values = (entry.value as List?)?.cast<int>() ?? const [0, 0];
            return NetworkInterfaceTotal(
              name: entry.key,
              downBytes: values.isNotEmpty ? values[0] : 0,
              upBytes: values.length > 1 ? values[1] : 0,
            );
          }).toList()
          ..sort((a, b) => b.totalBytes.compareTo(a.totalBytes));

    return NetworkSeries(
      range: NetworkRange.values.firstWhere(
        (value) => value.id == map['range'],
        orElse: () => NetworkRange.day,
      ),
      granularity: NetworkGranularity.fromName(map['granularity'] as String?),
      buckets:
          (map['buckets'] as List?)
              ?.whereType<Map>()
              .map((raw) => NetworkBucket.fromMap(raw.cast<String, dynamic>()))
              .toList() ??
          const [],
      totalDownBytes: map['totalDown'] as int? ?? 0,
      totalUpBytes: map['totalUp'] as int? ?? 0,
      byInterface: totals,
      startedAt: _dateFrom(map['startedAt']),
    );
  }

  static const NetworkSeries empty = NetworkSeries(
    range: NetworkRange.day,
    granularity: NetworkGranularity.hour,
    buckets: [],
    totalDownBytes: 0,
    totalUpBytes: 0,
  );

  final NetworkRange range;
  final NetworkGranularity granularity;
  final List<NetworkBucket> buckets;
  final int totalDownBytes;
  final int totalUpBytes;
  final List<NetworkInterfaceTotal> byInterface;

  /// When this Mac first recorded anything. Null before the first sample is
  /// written — which is the first second of the first ever launch.
  final DateTime? startedAt;

  int get totalBytes => totalDownBytes + totalUpBytes;

  bool get isEmpty => buckets.isEmpty;

  /// The tallest bar, for the axis. Never zero — a flat range still needs a
  /// scale to divide by.
  int get peakBytes => buckets.fold<int>(
    1,
    (peak, bucket) => bucket.totalBytes > peak ? bucket.totalBytes : peak,
  );

  @override
  List<Object?> get props => [
    range,
    granularity,
    buckets,
    totalDownBytes,
    totalUpBytes,
    byInterface,
    startedAt,
  ];
}

/// The numbers on the stat tiles, read straight off the daily tier so they
/// agree with the month chart rather than being summed a second way.
class NetworkHeadline extends Equatable {
  const NetworkHeadline({
    this.todayDownBytes = 0,
    this.todayUpBytes = 0,
    this.monthDownBytes = 0,
    this.monthUpBytes = 0,
    this.busiestDay,
    this.busiestDayBytes = 0,
    this.startedAt,
  });

  factory NetworkHeadline.fromMap(Map<String, dynamic> map) => NetworkHeadline(
    todayDownBytes: map['todayDown'] as int? ?? 0,
    todayUpBytes: map['todayUp'] as int? ?? 0,
    monthDownBytes: map['monthDown'] as int? ?? 0,
    monthUpBytes: map['monthUp'] as int? ?? 0,
    busiestDay: _dateFrom(map['busiestDay']),
    busiestDayBytes: map['busiestDayBytes'] as int? ?? 0,
    startedAt: _dateFrom(map['startedAt']),
  );

  static const NetworkHeadline empty = NetworkHeadline();

  final int todayDownBytes;
  final int todayUpBytes;
  final int monthDownBytes;
  final int monthUpBytes;
  final DateTime? busiestDay;
  final int busiestDayBytes;
  final DateTime? startedAt;

  int get todayBytes => todayDownBytes + todayUpBytes;
  int get monthBytes => monthDownBytes + monthUpBytes;

  @override
  List<Object?> get props => [
    todayDownBytes,
    todayUpBytes,
    monthDownBytes,
    monthUpBytes,
    busiestDay,
    busiestDayBytes,
    startedAt,
  ];
}

DateTime? _dateFrom(Object? raw) {
  final seconds = (raw as num?)?.toDouble();
  if (seconds == null || seconds <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round());
}

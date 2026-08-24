import 'package:equatable/equatable.dart';
import 'package:tidy/features/network/data/models/network_sample.dart';
import 'package:tidy/features/network/data/models/network_series.dart';

enum NetworkStatus { initial, loading, ready }

class NetworkState extends Equatable {
  const NetworkState({
    this.status = NetworkStatus.initial,
    this.range = NetworkRange.day,
    this.series = NetworkSeries.empty,
    this.headline = NetworkHeadline.empty,
    this.sample = NetworkSample.unknown,
    this.ticks = const [],
    this.live = false,
  });

  /// How many readings the live chart holds. Five minutes at one a second,
  /// matching the native ring — anything the sampler has already dropped cannot
  /// be drawn anyway.
  static const int liveCapacity = 300;

  final NetworkStatus status;
  final NetworkRange range;
  final NetworkSeries series;
  final NetworkHeadline headline;

  /// The latest reading. [NetworkSample.unknown] until the first one lands —
  /// a rate that has not arrived is not 0 B/s.
  final NetworkSample sample;

  /// The live chart's points, oldest first.
  final List<NetworkTick> ticks;

  /// Whether the native tap is open. False while the page is off screen.
  final bool live;

  bool get isLoading => status == NetworkStatus.loading;

  /// True once history has been read at least once.
  bool get hasLoaded => status == NetworkStatus.ready;

  /// Nothing has ever been recorded — a first launch, or just after a reset.
  bool get hasNoHistory => hasLoaded && headline.startedAt == null;

  /// The selected range starts before this Mac began recording, so the chart is
  /// showing a window Tidy cannot fully account for. Drives the coverage line,
  /// which is the difference between "you used nothing" and "we were not
  /// running".
  bool get rangeOutrunsHistory {
    final startedAt = headline.startedAt;
    if (startedAt == null) return false;
    final span = switch (range) {
      NetworkRange.hour => const Duration(hours: 1),
      NetworkRange.day => const Duration(days: 1),
      NetworkRange.week => const Duration(days: 7),
      NetworkRange.month => const Duration(days: 30),
      NetworkRange.sixMonths => const Duration(days: 183),
      NetworkRange.year => const Duration(days: 365),
      NetworkRange.all => Duration.zero,
    };
    if (span == Duration.zero) return false;
    return DateTime.now().difference(startedAt) < span;
  }

  List<double> get downTicks => ticks.map((tick) => tick.down).toList();
  List<double> get upTicks => ticks.map((tick) => tick.up).toList();

  NetworkState copyWith({
    NetworkStatus? status,
    NetworkRange? range,
    NetworkSeries? series,
    NetworkHeadline? headline,
    NetworkSample? sample,
    List<NetworkTick>? ticks,
    bool? live,
  }) => NetworkState(
    status: status ?? this.status,
    range: range ?? this.range,
    series: series ?? this.series,
    headline: headline ?? this.headline,
    sample: sample ?? this.sample,
    ticks: ticks ?? this.ticks,
    live: live ?? this.live,
  );

  @override
  List<Object?> get props => [
    status,
    range,
    series,
    headline,
    sample,
    ticks,
    live,
  ];
}

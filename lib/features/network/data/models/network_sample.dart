import 'package:equatable/equatable.dart';
import 'package:tidy/features/network/data/models/network_units.dart';

/// One interface's share of a reading.
class NetworkInterfaceRate extends Equatable {
  const NetworkInterfaceRate({
    required this.name,
    required this.displayName,
    required this.downBytesPerSecond,
    required this.upBytesPerSecond,
    required this.downBytes,
    required this.upBytes,
    required this.sinceBootDown,
    required this.sinceBootUp,
  });

  factory NetworkInterfaceRate.fromMap(Map<String, dynamic> map) =>
      NetworkInterfaceRate(
        name: map['name'] as String? ?? '',
        displayName: map['displayName'] as String? ?? '',
        downBytesPerSecond: (map['downBytesPerSecond'] as num?)?.toDouble() ?? 0,
        upBytesPerSecond: (map['upBytesPerSecond'] as num?)?.toDouble() ?? 0,
        downBytes: map['downBytes'] as int? ?? 0,
        upBytes: map['upBytes'] as int? ?? 0,
        sinceBootDown: map['sinceBootDown'] as int? ?? 0,
        sinceBootUp: map['sinceBootUp'] as int? ?? 0,
      );

  /// The BSD name — `en0`, `en5`, `pdp_ip0`.
  final String name;

  /// What macOS calls it in Network settings — "Wi-Fi", "Ethernet". Falls back
  /// to [name] when SystemConfiguration has nothing to say about it.
  final String displayName;

  final double downBytesPerSecond;
  final double upBytesPerSecond;
  final int downBytes;
  final int upBytes;

  /// Since this interface's counters last reset — boot for a built-in one,
  /// plug-in for a USB adapter.
  final int sinceBootDown;
  final int sinceBootUp;

  String get label => displayName.isEmpty ? name : displayName;

  bool get isActive => downBytesPerSecond > 0 || upBytesPerSecond > 0;

  @override
  List<Object?> get props => [
    name,
    displayName,
    downBytesPerSecond,
    upBytesPerSecond,
    downBytes,
    upBytes,
    sinceBootDown,
    sinceBootUp,
  ];
}

/// One reading: how fast the machine is moving bytes right now.
class NetworkSample extends Equatable {
  const NetworkSample({
    required this.at,
    required this.downBytesPerSecond,
    required this.upBytesPerSecond,
    required this.downBytes,
    required this.upBytes,
    required this.interfaces,
    this.recent = const [],
    this.units = NetworkUnits.bytes,
  });

  factory NetworkSample.fromMap(Map<String, dynamic> map) => NetworkSample(
    at: _dateFrom(map['at']),
    downBytesPerSecond: (map['downBytesPerSecond'] as num?)?.toDouble() ?? 0,
    upBytesPerSecond: (map['upBytesPerSecond'] as num?)?.toDouble() ?? 0,
    downBytes: map['downBytes'] as int? ?? 0,
    upBytes: map['upBytes'] as int? ?? 0,
    interfaces:
        (map['interfaces'] as List?)
            ?.whereType<Map>()
            .map((raw) => NetworkInterfaceRate.fromMap(raw.cast<String, dynamic>()))
            .toList() ??
        const [],
    recent:
        (map['recent'] as List?)
            ?.whereType<Map>()
            .map((raw) => NetworkTick.fromMap(raw.cast<String, dynamic>()))
            .toList() ??
        const [],
    units:
        (map['useBits'] as bool? ?? false)
            ? NetworkUnits.bits
            : NetworkUnits.bytes,
  );

  /// Nothing has been read yet. Distinct from a reading of zero, which is why
  /// [isKnown] exists — a rate that has not arrived is not 0 B/s, the same
  /// distinction `SystemVitals` draws for a CPU percentage.
  static const NetworkSample unknown = NetworkSample(
    at: null,
    downBytesPerSecond: 0,
    upBytesPerSecond: 0,
    downBytes: 0,
    upBytes: 0,
    interfaces: [],
  );

  final DateTime? at;
  final double downBytesPerSecond;
  final double upBytesPerSecond;
  final int downBytes;
  final int upBytes;
  final List<NetworkInterfaceRate> interfaces;

  /// The last five minutes of per-second readings, newest last. Only arrives
  /// with the first payload of a live subscription — the pushes that follow are
  /// single readings, and the panel appends them itself.
  final List<NetworkTick> recent;

  /// The units the user asked for, carried along by the native side.
  ///
  /// The menu bar popover runs in an engine started with `includeUi: false` and
  /// has no `AppSettings` to read, so the preference rides with the reading
  /// rather than being looked up. The main window reads `AppSettings` directly
  /// and ignores this.
  final NetworkUnits units;

  bool get isKnown => at != null;

  /// The interface actually carrying traffic, or the busiest one seen this
  /// tick. Null when nothing is moving on any of them.
  NetworkInterfaceRate? get busiest {
    final active = interfaces.where((i) => i.isActive).toList();
    if (active.isEmpty) return null;
    active.sort(
      (a, b) => (b.downBytesPerSecond + b.upBytesPerSecond).compareTo(
        a.downBytesPerSecond + a.upBytesPerSecond,
      ),
    );
    return active.first;
  }

  NetworkSample copyWith({List<NetworkTick>? recent}) => NetworkSample(
    at: at,
    downBytesPerSecond: downBytesPerSecond,
    upBytesPerSecond: upBytesPerSecond,
    downBytes: downBytes,
    upBytes: upBytes,
    interfaces: interfaces,
    recent: recent ?? this.recent,
    units: units,
  );

  NetworkTick get tick => NetworkTick(
    at: at ?? DateTime.now(),
    down: downBytesPerSecond,
    up: upBytesPerSecond,
  );

  @override
  List<Object?> get props => [
    at,
    downBytesPerSecond,
    upBytesPerSecond,
    downBytes,
    upBytes,
    interfaces,
    recent,
    units,
  ];
}

/// One point on the live chart.
class NetworkTick extends Equatable {
  const NetworkTick({required this.at, required this.down, required this.up});

  factory NetworkTick.fromMap(Map<String, dynamic> map) => NetworkTick(
    at: _dateFrom(map['at']) ?? DateTime.now(),
    down: (map['down'] as num?)?.toDouble() ?? 0,
    up: (map['up'] as num?)?.toDouble() ?? 0,
  );

  final DateTime at;
  final double down;
  final double up;

  @override
  List<Object?> get props => [at, down, up];
}

DateTime? _dateFrom(Object? raw) {
  final seconds = (raw as num?)?.toDouble();
  if (seconds == null || seconds <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round());
}

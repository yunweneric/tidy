import 'package:equatable/equatable.dart';

/// How hot the machine says it is running.
enum ThermalState {
  nominal,
  fair,
  serious,
  critical;

  static ThermalState parse(String? raw) => switch (raw) {
    'fair' => ThermalState.fair,
    'serious' => ThermalState.serious,
    'critical' => ThermalState.critical,
    _ => ThermalState.nominal,
  };

  /// Below this the fans and the clock speed are the machine's own business.
  bool get isNotable => index >= ThermalState.serious.index;

  String get label => switch (this) {
    ThermalState.nominal => 'Running cool',
    ThermalState.fair => 'Warm',
    ThermalState.serious => 'Running hot',
    ThermalState.critical => 'Overheating',
  };
}

/// One machine-wide reading, from `macos/Runner/SystemVitals.swift`.
///
/// Everything is nullable-by-absence rather than zero-by-default: a CPU
/// reading that has not arrived is not 0%, and painting it as one is a
/// confident wrong answer in the one place — a menu bar — where the number is
/// the entire point.
class SystemVitals extends Equatable {
  const SystemVitals({
    this.cpuPercent,
    this.cpuUserPercent,
    this.cpuSystemPercent,
    this.loadAverage,
    this.coreCount = 0,
    this.memoryTotalBytes = 0,
    this.memoryUsedBytes = 0,
    this.memoryAppBytes = 0,
    this.memoryWiredBytes = 0,
    this.memoryCompressedBytes = 0,
    this.memoryCachedBytes = 0,
    this.memoryPressurePercent,
    this.swapUsedBytes = 0,
    this.swapTotalBytes = 0,
    this.uptime = Duration.zero,
    this.thermal = ThermalState.nominal,
  });

  factory SystemVitals.fromMap(Map<String, dynamic> map) {
    int bytes(String key) => (map[key] as num?)?.toInt() ?? 0;
    double? percent(String key) => (map[key] as num?)?.toDouble();

    return SystemVitals(
      cpuPercent: percent('cpuPercent'),
      cpuUserPercent: percent('cpuUserPercent'),
      cpuSystemPercent: percent('cpuSystemPercent'),
      loadAverage: percent('loadAverage'),
      coreCount: (map['coreCount'] as num?)?.toInt() ?? 0,
      memoryTotalBytes: bytes('memoryTotalBytes'),
      memoryUsedBytes: bytes('memoryUsedBytes'),
      memoryAppBytes: bytes('memoryAppBytes'),
      memoryWiredBytes: bytes('memoryWiredBytes'),
      memoryCompressedBytes: bytes('memoryCompressedBytes'),
      memoryCachedBytes: bytes('memoryCachedBytes'),
      memoryPressurePercent: percent('memoryPressurePercent'),
      swapUsedBytes: bytes('swapUsedBytes'),
      swapTotalBytes: bytes('swapTotalBytes'),
      uptime: Duration(
        seconds: ((map['uptimeSeconds'] as num?)?.toDouble() ?? 0).round(),
      ),
      thermal: ThermalState.parse(map['thermalState'] as String?),
    );
  }

  static const SystemVitals empty = SystemVitals();

  /// Machine-wide CPU use, 0–100 however many cores there are. Null until the
  /// first reading lands.
  final double? cpuPercent;
  final double? cpuUserPercent;
  final double? cpuSystemPercent;

  /// One-minute load average — runnable threads, not a percentage. Worth
  /// showing next to CPU because a load above the core count is the difference
  /// between "busy" and "queueing".
  final double? loadAverage;

  final int coreCount;

  /// Physical RAM.
  final int memoryTotalBytes;

  /// App + wired + compressed, which is what Activity Monitor calls Memory
  /// Used. Cached files are deliberately not in here: macOS can hand them back
  /// the moment anything needs the space.
  final int memoryUsedBytes;

  final int memoryAppBytes;
  final int memoryWiredBytes;
  final int memoryCompressedBytes;
  final int memoryCachedBytes;

  /// Wired + compressed over physical, as a stand-in for Activity Monitor's
  /// pressure gauge. See the Swift side for why that is the honest proxy.
  final double? memoryPressurePercent;

  final int swapUsedBytes;
  final int swapTotalBytes;

  final Duration uptime;
  final ThermalState thermal;

  /// False before the first reading, so the panel can say "reading…" instead
  /// of painting an empty machine.
  bool get isKnown => memoryTotalBytes > 0;

  double get memoryUsedFraction =>
      memoryTotalBytes == 0 ? 0 : memoryUsedBytes / memoryTotalBytes;

  double get cpuFraction => (cpuPercent ?? 0) / 100;

  double get pressureFraction => (memoryPressurePercent ?? 0) / 100;

  /// The machine has *any* swap in use — which on macOS is most machines most
  /// of the time, and so on its own says nothing.
  bool get isSwapping => swapUsedBytes > 0;

  /// Swap has grown to a quarter of physical memory. That is the point where
  /// swapping stops being housekeeping and starts being something the user can
  /// feel, so it is the only swap figure the UI reacts to.
  bool get isSwapHeavy =>
      memoryTotalBytes > 0 && swapUsedBytes >= memoryTotalBytes ~/ 4;

  /// "3d 4h", "6h 12m", "18m".
  String get uptimeLabel {
    final days = uptime.inDays;
    final hours = uptime.inHours % 24;
    final minutes = uptime.inMinutes % 60;
    if (days > 0) return '${days}d ${hours}h';
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }

  @override
  List<Object?> get props => [
    cpuPercent,
    memoryUsedBytes,
    memoryPressurePercent,
    swapUsedBytes,
    thermal,
    uptime,
  ];
}

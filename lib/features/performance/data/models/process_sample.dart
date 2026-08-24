import 'package:equatable/equatable.dart';

/// One running process at one moment.
class ProcessSample extends Equatable {
  const ProcessSample({
    required this.pid,
    required this.name,
    required this.memoryBytes,
    required this.isApp,
    required this.quittable,
    this.cpuPercent,
    this.path,
    this.bundlePath,
  });

  factory ProcessSample.fromMap(Map<String, dynamic> map) {
    return ProcessSample(
      pid: (map['pid'] as num?)?.toInt() ?? 0,
      name: map['name'] as String? ?? 'Unknown',
      memoryBytes: (map['memoryBytes'] as num?)?.toInt() ?? 0,
      isApp: map['isApp'] as bool? ?? false,
      quittable: map['quittable'] as bool? ?? true,
      cpuPercent: (map['cpuPercent'] as num?)?.toDouble(),
      path: map['path'] as String?,
      bundlePath: map['bundlePath'] as String?,
    );
  }

  final int pid;
  final String name;

  /// Physical footprint — what Activity Monitor calls "Memory". Resident size
  /// counts shared pages once per process and over-reports badly when summed.
  final int memoryBytes;

  final bool isApp;

  /// False for the handful of processes that would end the login session.
  final bool quittable;

  /// Null on the first tick: CPU use is a rate, and one sample cannot express
  /// one. Showing 0% would be a confident wrong answer.
  final double? cpuPercent;

  final String? path;

  /// The `.app` this process belongs to, when it is an app. Used for the icon.
  final String? bundlePath;

  @override
  List<Object?> get props => [pid, name, memoryBytes, cpuPercent];
}

/// One tick of the monitor.
class ProcessSnapshot extends Equatable {
  const ProcessSnapshot({required this.processes, required this.restrictedCount});

  static const ProcessSnapshot empty = ProcessSnapshot(
    processes: [],
    restrictedCount: 0,
  );

  final List<ProcessSample> processes;

  /// Processes owned by macOS rather than by you. Reading their usage needs
  /// privileges we do not have, so they are counted and named as absent rather
  /// than listed as a row of dashes.
  final int restrictedCount;

  int get totalMemoryBytes =>
      processes.fold<int>(0, (sum, process) => sum + process.memoryBytes);

  /// Null until at least one process has been sampled twice.
  double? get totalCpuPercent {
    var total = 0.0;
    var measured = false;
    for (final process in processes) {
      final cpu = process.cpuPercent;
      if (cpu != null) {
        total += cpu;
        measured = true;
      }
    }
    return measured ? total : null;
  }

  @override
  List<Object?> get props => [processes, restrictedCount];
}

/// Which column the table is ordered by.
enum ProcessSort {
  cpu('CPU'),
  memory('Memory'),
  name('Name');

  const ProcessSort(this.label);

  final String label;
}

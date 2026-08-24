import 'dart:typed_data';

import 'package:mac_uninstaller/core/platform/system_bridge.dart';
import 'package:mac_uninstaller/features/performance/data/models/process_sample.dart';
import 'package:mac_uninstaller/features/performance/data/services/performance_bridge.dart';

/// Samples what is running, and quits it when asked.
class ProcessMonitorService {
  /// App icons keyed by bundle path, fetched once and reused. Re-rendering
  /// thirty icons every two seconds would cost more than the sampling does.
  final Map<String, Uint8List> _icons = {};

  Map<String, Uint8List> get icons => Map.unmodifiable(_icons);

  /// Drops the native sampling history, so the next tick measures from now
  /// rather than from whenever this page was last open.
  Future<void> start() => PerformanceBridge.resetProcessSamples();

  Future<ProcessSnapshot> sample() async {
    final raw = await PerformanceBridge.processSamples();
    final rows = (raw['processes'] as List?) ?? const [];

    final processes =
        rows
            .map(
              (entry) =>
                  ProcessSample.fromMap((entry as Map).cast<String, dynamic>()),
            )
            .toList();

    await _loadIcons(processes);

    return ProcessSnapshot(
      processes: processes,
      restrictedCount: (raw['restrictedCount'] as num?)?.toInt() ?? 0,
    );
  }

  /// [force] skips the app's chance to save. Offered only as a second step,
  /// after a polite quit has visibly not worked.
  Future<ActionOutcome> quit(int pid, {bool force = false}) =>
      PerformanceBridge.terminateProcess(pid: pid, force: force);

  Future<void> _loadIcons(List<ProcessSample> processes) async {
    final wanted = <String>{
      for (final process in processes)
        if (process.bundlePath != null &&
            !_icons.containsKey(process.bundlePath))
          process.bundlePath!,
    };
    if (wanted.isEmpty) return;

    final fetched = await SystemBridge.iconsForPaths(wanted.toList(), size: 32);
    _icons.addAll(fetched);
  }

  /// Orders a snapshot for display. Processes still waiting on their second
  /// sample sort last under CPU — they have no reading yet, and floating them
  /// to the top as zeroes would bury whatever is actually busy.
  static List<ProcessSample> sorted(
    List<ProcessSample> processes,
    ProcessSort by,
  ) {
    final ordered = List.of(processes);
    switch (by) {
      case ProcessSort.cpu:
        ordered.sort(
          (a, b) => (b.cpuPercent ?? -1).compareTo(a.cpuPercent ?? -1),
        );
      case ProcessSort.memory:
        ordered.sort((a, b) => b.memoryBytes.compareTo(a.memoryBytes));
      case ProcessSort.name:
        ordered.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
    }
    return ordered;
  }
}

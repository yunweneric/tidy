import 'package:tidy/core/platform/system_bridge.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/vitals/process_sample.dart';
import 'package:tidy/core/vitals/system_vitals.dart';

/// How worried a reading should make you.
enum VitalLevel { good, watch, urgent }

/// The single most relevant thing about the machine right now.
///
/// The old popover led with "largest apps", which answers a question nobody
/// standing in the menu bar is asking: it is a list of things you deliberately
/// installed, ranked by a number that does not change, offering the most
/// destructive action in the app one click away from a hover. This picks the
/// one fact that *is* time-sensitive — the disk filling up, memory under
/// pressure, the machine throttling, junk worth clearing — and says it.
///
/// Lives in `core/` because the menu bar popover and the Dashboard both read
/// it, and `docs/feature.md` §2 forbids a feature importing from a sibling.
/// That shared home is also the point: the two must never disagree about
/// whether the disk is a problem, so they resolve the same ladder rather than
/// each carrying their own thresholds.
enum HealthInsightKind {
  diskCritical,
  diskFilling,
  memoryPressure,
  thermal,
  cpuBusy,
  reclaimable,
  healthy,
}

/// The button an insight offers, if any.
enum HealthInsightAction { cleanJunk, openApp }

class HealthInsight {
  const HealthInsight({
    required this.kind,
    required this.level,
    required this.headline,
    required this.detail,
    this.action,
    this.actionLabel,
  });

  final HealthInsightKind kind;
  final VitalLevel level;

  /// One line, in the app's voice, saying what is true.
  final String headline;

  /// The number or the culprit behind it.
  final String detail;

  final HealthInsightAction? action;
  final String? actionLabel;

  /// Reads the machine and returns the one thing worth saying.
  ///
  /// Order is severity, not category: a disk with 2 GB left outranks a hot CPU,
  /// which outranks junk worth clearing, which outranks saying everything is
  /// fine. Only one is ever shown — a panel with four warnings on it has told
  /// the user to ignore all four.
  static HealthInsight of({
    required SystemVitals vitals,
    required DiskUsage disk,
    required int junkBytes,
    required int trashBytes,
    ProcessSample? topCpu,
    ProcessSample? topMemory,
  }) {
    final diskKnown = disk.totalBytes > 0;
    final free = formatBytes(disk.freeBytes);

    if (diskKnown && disk.usedFraction >= 0.95) {
      return HealthInsight(
        kind: HealthInsightKind.diskCritical,
        level: VitalLevel.urgent,
        headline: 'Your startup disk is almost full',
        detail:
            junkBytes > 0
                ? '$free left · ${formatBytes(junkBytes)} can go right now'
                : '$free left of ${formatBytes(disk.totalBytes)}',
        action:
            junkBytes > 0
                ? HealthInsightAction.cleanJunk
                : HealthInsightAction.openApp,
        actionLabel: junkBytes > 0 ? 'Clean' : 'Find space',
      );
    }

    final pressure = vitals.pressureFraction;
    if (pressure >= 0.85 || (vitals.isSwapHeavy && pressure >= 0.70)) {
      return HealthInsight(
        kind: HealthInsightKind.memoryPressure,
        level: VitalLevel.urgent,
        headline:
            vitals.isSwapHeavy
                ? 'Memory is full — macOS is swapping to disk'
                : 'Memory is under pressure',
        detail:
            topMemory == null
                ? '${formatBytes(vitals.memoryUsedBytes)} of '
                    '${formatBytes(vitals.memoryTotalBytes)} in use'
                : '${topMemory.name} is holding '
                    '${formatBytes(topMemory.memoryBytes)}',
      );
    }

    if (vitals.thermal.isNotable) {
      return HealthInsight(
        kind: HealthInsightKind.thermal,
        level:
            vitals.thermal == ThermalState.critical
                ? VitalLevel.urgent
                : VitalLevel.watch,
        headline: 'Your Mac is running hot',
        detail:
            topCpu?.cpuPercent == null
                ? 'macOS is slowing things down to cool off'
                : '${topCpu!.name} is using '
                    '${topCpu.cpuPercent!.toStringAsFixed(0)}% of the CPU',
      );
    }

    if (diskKnown && disk.usedFraction >= 0.88) {
      return HealthInsight(
        kind: HealthInsightKind.diskFilling,
        level: VitalLevel.watch,
        headline: 'Your disk is filling up',
        detail: '$free left of ${formatBytes(disk.totalBytes)}',
        action:
            junkBytes > 0
                ? HealthInsightAction.cleanJunk
                : HealthInsightAction.openApp,
        actionLabel: junkBytes > 0 ? 'Clean' : 'Find space',
      );
    }

    if (pressure >= 0.70) {
      return HealthInsight(
        kind: HealthInsightKind.memoryPressure,
        level: VitalLevel.watch,
        headline: 'Memory is getting tight',
        detail:
            topMemory == null
                ? '${formatBytes(vitals.memoryUsedBytes)} of '
                    '${formatBytes(vitals.memoryTotalBytes)} in use'
                : '${topMemory.name} is holding '
                    '${formatBytes(topMemory.memoryBytes)}',
      );
    }

    final cpu = vitals.cpuPercent;
    if (cpu != null && cpu >= 85) {
      return HealthInsight(
        kind: HealthInsightKind.cpuBusy,
        level: VitalLevel.watch,
        headline: 'The CPU is pinned',
        detail:
            topCpu?.cpuPercent == null
                ? '${cpu.toStringAsFixed(0)}% across ${vitals.coreCount} cores'
                : '${topCpu!.name} is using '
                    '${topCpu.cpuPercent!.toStringAsFixed(0)}%',
      );
    }

    // A gigabyte is the point at which clearing junk is worth interrupting
    // someone for. Below that it stays in the reclaimable section, where it is
    // information rather than a prompt.
    final reclaimable = junkBytes + trashBytes;
    if (reclaimable >= 1024 * 1024 * 1024) {
      return HealthInsight(
        kind: HealthInsightKind.reclaimable,
        level: VitalLevel.watch,
        headline: '${formatBytes(reclaimable)} can be reclaimed',
        detail:
            trashBytes == 0
                ? 'Caches, logs and saved app state'
                : '${formatBytes(junkBytes)} in caches and logs · '
                    '${formatBytes(trashBytes)} in the Trash',
        action: junkBytes > 0 ? HealthInsightAction.cleanJunk : null,
        actionLabel: junkBytes > 0 ? 'Clean' : null,
      );
    }

    return HealthInsight(
      kind: HealthInsightKind.healthy,
      level: VitalLevel.good,
      headline: 'Everything looks healthy',
      detail:
          diskKnown
              ? '$free free · up ${vitals.uptimeLabel}'
              : 'Up ${vitals.uptimeLabel}',
    );
  }
}

/// Threshold helpers for the three vitals tiles, so the tile and the insight
/// agree about what "high" means.
VitalLevel levelForFraction(
  double fraction, {
  double watch = 0.75,
  double urgent = 0.90,
}) {
  if (fraction >= urgent) return VitalLevel.urgent;
  if (fraction >= watch) return VitalLevel.watch;
  return VitalLevel.good;
}

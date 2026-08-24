import 'package:equatable/equatable.dart';
import 'package:tidy/core/platform/system_bridge.dart';
import 'package:tidy/core/vitals/system_vitals.dart';

/// The five tiers a Mac's health lands in.
enum HealthTier {
  excellent('Excellent', 90),
  good('Good', 75),
  fair('Fair', 55),
  needsAttention('Requires attention', 35),
  critical('Critical', 0);

  const HealthTier(this.label, this.floor);

  final String label;

  /// The lowest score that still counts as this tier.
  final int floor;

  static HealthTier of(int score) =>
      values.firstWhere((tier) => score >= tier.floor);
}

/// One thing the score looked at.
class HealthSignal extends Equatable {
  const HealthSignal({
    required this.label,
    required this.goodness,
    required this.weight,
    required this.detail,
  });

  final String label;

  /// 0 is as bad as this signal gets, 1 is perfect.
  final double goodness;

  final int weight;

  /// The number behind it, in plain words.
  final String detail;

  /// Worth showing as something to act on.
  bool get isDragging => goodness < 0.7;

  @override
  List<Object?> get props => [label, goodness, weight, detail];
}

/// A single reading of how the Mac is doing, and what went into it.
///
/// **A signal that was not measured does not count.** It is left out of both
/// halves of the average rather than scored as perfect, and [signalsUsed] says
/// how many made it in — so a machine that has never been scanned reads as
/// "from 5 of 8 checks" rather than as a confident 100. Treating unmeasured as
/// fine is the same lie as a scanner that reports "0 threats found" without
/// having looked, and this screen exists to be trusted.
class HealthScore extends Equatable {
  const HealthScore({
    required this.score,
    required this.signals,
    required this.signalsTotal,
  });

  static const HealthScore unknown = HealthScore(
    score: 0,
    signals: [],
    signalsTotal: _totalSignals,
  );

  /// Every check this score knows how to make. Signals arrive as the data
  /// behind them does, so this is the denominator in "from 6 of 8 checks".
  static const int _totalSignals = 8;

  /// 0–100, over the signals that were actually measured.
  final int score;

  final List<HealthSignal> signals;
  final int signalsTotal;

  int get signalsUsed => signals.length;

  bool get isKnown => signals.isNotEmpty;

  HealthTier get tier => HealthTier.of(score);

  /// Whether the score is built on enough to be worth quoting without a caveat.
  bool get isComplete => signalsUsed == signalsTotal;

  /// The weakest signals first — what to fix, in order.
  List<HealthSignal> get dragging {
    final list = signals.where((s) => s.isDragging).toList()
      ..sort((a, b) {
        final byImpact = (a.goodness * a.weight).compareTo(
          b.goodness * b.weight,
        );
        return byImpact != 0 ? byImpact : b.weight.compareTo(a.weight);
      });
    return list;
  }

  /// Builds a score from whatever is known.
  ///
  /// Every parameter is nullable and every null is an absence rather than a
  /// zero. `junkBytes: null` means "no scan has run"; `junkBytes: 0` means "a
  /// scan ran and found nothing", and those two must not produce the same
  /// number.
  static HealthScore of({
    DiskUsage? disk,
    SystemVitals? vitals,
    int? junkBytes,
    int? trashBytes,
    int? brokenLaunchItems,
    int? unusedApps,
    bool? fullDiskAccess,
  }) {
    final signals = <HealthSignal>[];

    if (disk != null && disk.totalBytes > 0) {
      final used = disk.usedFraction;
      signals.add(
        HealthSignal(
          label: 'Free space',
          // Flat until 70% full, then falls away to nothing at 97%. A disk at
          // half capacity is not "half healthy" — free space only becomes a
          // problem near the top, and a linear scale would make every ordinary
          // Mac look mediocre.
          goodness: _ramp(used, good: 0.70, bad: 0.97),
          weight: 25,
          detail: '${(used * 100).round()}% of the disk is in use',
        ),
      );
    }

    if (vitals != null) {
      final pressure = vitals.memoryPressurePercent;
      if (pressure != null) {
        signals.add(
          HealthSignal(
            label: 'Memory',
            goodness: _ramp(pressure / 100, good: 0.60, bad: 0.90),
            weight: 15,
            detail: 'Memory pressure at ${pressure.round()}%',
          ),
        );
      }

      signals.add(
        HealthSignal(
          label: 'Temperature',
          goodness: switch (vitals.thermal) {
            ThermalState.nominal => 1,
            ThermalState.fair => 0.8,
            ThermalState.serious => 0.4,
            ThermalState.critical => 0,
          },
          weight: 10,
          detail: vitals.thermal.label,
        ),
      );
    }

    if (junkBytes != null) {
      // A gigabyte is the point the menu bar decides junk is worth mentioning;
      // the same threshold is used here so the two never disagree.
      signals.add(
        HealthSignal(
          label: 'Junk files',
          goodness: _ramp(
            junkBytes / _gigabyte,
            good: 1,
            bad: 20,
          ),
          weight: 15,
          detail:
              junkBytes == 0
                  ? 'Nothing to clear'
                  : '${_gb(junkBytes)} of caches and logs can go',
        ),
      );
    }

    if (trashBytes != null) {
      signals.add(
        HealthSignal(
          label: 'Trash',
          goodness: _ramp(trashBytes / _gigabyte, good: 1, bad: 25),
          weight: 10,
          detail:
              trashBytes == 0
                  ? 'Empty'
                  : '${_gb(trashBytes)} waiting to be emptied',
        ),
      );
    }

    if (brokenLaunchItems != null) {
      signals.add(
        HealthSignal(
          label: 'Startup items',
          goodness: _ramp(brokenLaunchItems.toDouble(), good: 0, bad: 6),
          weight: 10,
          detail: switch (brokenLaunchItems) {
            0 => 'All accounted for',
            1 => '1 points at something that is not there',
            _ => '$brokenLaunchItems point at things that are not there',
          },
        ),
      );
    }

    if (unusedApps != null) {
      signals.add(
        HealthSignal(
          label: 'Unused apps',
          goodness: _ramp(unusedApps.toDouble(), good: 2, bad: 25),
          weight: 10,
          detail: switch (unusedApps) {
            0 => 'Everything has been opened recently',
            1 => '1 app has not been opened in months',
            _ => '$unusedApps apps have not been opened in months',
          },
        ),
      );
    }

    if (fullDiskAccess != null) {
      signals.add(
        HealthSignal(
          label: 'Full Disk Access',
          goodness: fullDiskAccess ? 1 : 0,
          weight: 5,
          detail:
              fullDiskAccess
                  ? 'Granted — Tidy can see everything'
                  : 'Not granted, so some results are incomplete',
        ),
      );
    }

    if (signals.isEmpty) return HealthScore.unknown;

    // Weighted over the signals present, not over every signal that could
    // exist — otherwise a machine with two readings would be capped at a
    // fraction of 100 for no reason the user could act on.
    var weighted = 0.0;
    var weights = 0;
    for (final signal in signals) {
      weighted += signal.goodness.clamp(0.0, 1.0) * signal.weight;
      weights += signal.weight;
    }

    return HealthScore(
      score: (weighted / weights * 100).round().clamp(0, 100),
      signals: signals,
      signalsTotal: _totalSignals,
    );
  }

  static const double _gigabyte = 1024 * 1024 * 1024;

  static String _gb(int bytes) {
    final gb = bytes / _gigabyte;
    return gb < 0.1 ? '<0.1 GB' : '${gb.toStringAsFixed(1)} GB';
  }

  /// 1 at or below [good], 0 at or above [bad], straight line between.
  static double _ramp(double value, {required double good, required double bad}) {
    if (value <= good) return 1;
    if (value >= bad) return 0;
    return 1 - (value - good) / (bad - good);
  }

  @override
  List<Object?> get props => [score, signals, signalsTotal];
}

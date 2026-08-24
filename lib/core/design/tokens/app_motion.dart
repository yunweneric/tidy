import 'package:flutter/material.dart';

/// Durations and curves.
///
/// Most of what reads as "polish" in a cleaner is motion: counters that count
/// rather than snap, rings that sweep, rows that settle. Centralising it is
/// also what makes Reduce Motion a one-line change instead of a scavenger hunt.
@immutable
class AppMotion extends ThemeExtension<AppMotion> {
  const AppMotion({required this.reduced});

  /// When true every duration collapses to zero and animated counters land on
  /// their final value immediately.
  final bool reduced;

  Duration get instant => Duration.zero;

  /// Hover / press feedback.
  Duration get fast => reduced ? Duration.zero : const Duration(milliseconds: 120);

  /// The default: expand, select, swap.
  Duration get normal => reduced ? Duration.zero : const Duration(milliseconds: 180);

  /// Page and panel transitions.
  Duration get slow => reduced ? Duration.zero : const Duration(milliseconds: 320);

  /// The scan ring sweep and the byte counter tween.
  Duration get hero => reduced ? Duration.zero : const Duration(milliseconds: 900);

  /// One full rotation of the indeterminate scan ring.
  Duration get ringSpin => const Duration(milliseconds: 2400);

  /// Standard easing. `easeOutCubic` decelerates hard, which reads as
  /// responsive rather than floaty.
  Curve get standard => Curves.easeOutCubic;

  /// Entering elements.
  Curve get enter => Curves.easeOutBack;

  /// Symmetric, for things that both grow and shrink.
  Curve get smooth => Curves.easeInOutCubic;

  @override
  AppMotion copyWith({bool? reduced}) =>
      AppMotion(reduced: reduced ?? this.reduced);

  @override
  AppMotion lerp(ThemeExtension<AppMotion>? other, double t) {
    if (other is! AppMotion) return this;
    return t < 0.5 ? this : other;
  }
}

import 'package:flutter/widgets.dart';

/// The 4pt spacing scale.
///
/// Every gap, pad and inset in the app comes from here. Before this existed the
/// same handful of magic numbers (20, 28, 16, 14, 12, 8, 4) were retyped at
/// every call site, which is how spacing rhythm drifts.
@immutable
class AppSpacing {
  const AppSpacing._();

  /// 2 — hairline separation inside a control.
  static const double xxs = 2;

  /// 4 — icon-to-label, chip padding.
  static const double xs = 4;

  /// 8 — related elements in a row.
  static const double sm = 8;

  /// 12 — default gap between siblings.
  static const double md = 12;

  /// 16 — card padding, list row padding.
  static const double lg = 16;

  /// 20 — sidebar gutter, section padding.
  static const double xl = 20;

  /// 28 — page gutter, gap between major blocks.
  static const double xxl = 28;

  /// 40 — hero padding, empty-state breathing room.
  static const double xxxl = 40;

  /// 64 — the vertical space around a scan hero.
  static const double huge = 64;

  // ─── Common composites ───────────────────────────────────────────────────
  /// Page content gutter.
  static const EdgeInsets page = EdgeInsets.symmetric(horizontal: xxl);

  /// Standard card interior.
  static const EdgeInsets card = EdgeInsets.all(lg);

  /// A table/list row.
  static const EdgeInsets row = EdgeInsets.symmetric(
    horizontal: xl,
    vertical: md,
  );
}

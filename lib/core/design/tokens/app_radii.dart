import 'package:flutter/widgets.dart';

/// Corner radii.
///
/// The old code used seven different inline values (4, 6, 8, 10, 12, 14, 20)
/// with no rule about which went where. These five have jobs.
@immutable
class AppRadii {
  const AppRadii._();

  /// 4 — checkboxes, progress bars.
  static const double xs = 4;

  /// 6 — badges, small chips, page buttons.
  static const double sm = 6;

  /// 10 — buttons, inputs, nav items, icon tiles.
  static const double md = 10;

  /// 14 — cards, tiles, panels.
  static const double lg = 14;

  /// 20 — dialogs, sheets, hero surfaces.
  static const double xl = 20;

  /// Fully rounded (pills, avatars).
  static const double pill = 999;

  static const BorderRadius xsAll = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));
}

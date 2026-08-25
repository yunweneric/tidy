import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';

/// Which hue each thing on the Dashboard wears.
///
/// For the charts that carry a **legend** — the disk bar and the removal chart
/// — where the hue is what tells the reader which band is which, and the same
/// subject appears in both. Colour is only telling the truth there if it
/// follows the subject across them; picked at each call site instead, the page
/// says the blue band and the amber band are different subjects when they are
/// the same one, which is what it used to say.
///
/// The ranked lists do not use this. Every row there is named beside its bar,
/// so the hue is separating rows rather than identifying them, and they take
/// [AppColorTokens.seriesAt] straight down the list instead.
///
/// Slots are indexes into [AppColorTokens.chartSeries], whose order is what
/// holds neighbouring hues apart under colour-blindness. A new subject takes
/// the next slot rather than the prettiest one, and anything past what the
/// palette can carry becomes a remainder rather than a ninth hue.
enum DashboardSeries {
  /// Everything installed, as a segment of the disk.
  applications(0),

  /// Space that can be had back: junk on the disk bar, and what was deleted
  /// outright in the removal chart.
  reclaimable(1),

  /// Deleted but still taking up room: the disk segment, and the trashed half
  /// of the removal chart.
  trash(2),

  /// What is left on the disk, over time.
  ///
  /// Its own hue rather than the neutral the disk bar's Free segment uses: a
  /// track is the shape of an absence, but a line across a chart is a series
  /// and has to be as legible as any other.
  freeSpace(3);

  const DashboardSeries(this.slot);

  final int slot;

  Color of(BuildContext context) => context.colors.chartSeries[slot];
}

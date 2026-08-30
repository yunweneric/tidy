/// How far back the Activity page looks.
///
/// Ranges rather than a date picker: the questions people actually ask a
/// history are "what did I do today", "this month", and "ever" — and a picker
/// makes them specify a boundary they do not have in mind before they can see
/// anything at all.
enum ActivityRange {
  week('7 days', 7),
  month('30 days', 30),
  quarter('90 days', 90),

  /// Everything the store still holds.
  ///
  /// Not the same as "everything that ever happened": `TidyStore.compact()`
  /// trims per-file rows past their retention, so the operations outlive the
  /// files they removed. The page says so where that starts to show.
  all('All', null);

  const ActivityRange(this.label, this.days);

  final String label;

  /// Null for [all], which has no cutoff.
  final int? days;

  /// The cutoff to query from, or null for everything.
  ///
  /// Midnight rather than "now minus N×24h": a range labelled "7 days" that
  /// silently drops this morning's cleanup because it happened 7 days and 20
  /// minutes ago is a history that appears to lose things.
  DateTime? from({DateTime? now}) {
    final days = this.days;
    if (days == null) return null;
    final at = now ?? DateTime.now();
    return DateTime(
      at.year,
      at.month,
      at.day,
    ).subtract(Duration(days: days - 1));
  }
}

/// Which half of the record is on screen.
enum ActivityView {
  /// What Tidy did, one row per run.
  operations,

  /// What it removed, one row per file — the audit list.
  files,
}

import 'package:tidy/core/design/app_icons.dart';
import 'package:flutter/widgets.dart';

/// One thing inside a folder, with everything underneath it counted.
///
/// [sizeBytes] is *allocated* size, walked natively with `fts(3)` — never
/// logical size. On APFS that distinction is the difference between a map that
/// says where your disk went and one that says where it might have gone: a
/// sparse file like Docker's `Docker.raw` reports 64 GB logically while
/// occupying 8, and a bubble drawn to the larger figure promises the user 56 GB
/// that removing it would not give back.
class SpaceEntry {
  const SpaceEntry({
    required this.path,
    required this.sizeBytes,
    required this.isDirectory,
    this.modified,
    this.hiddenCount = 0,
  });

  final String path;
  final int sizeBytes;
  final bool isDirectory;
  final DateTime? modified;

  /// How many entries this one stands in for.
  ///
  /// Zero for a real file or folder. A map is only readable while the bubbles
  /// can be told apart, so a folder with four thousand children draws its
  /// largest and gathers the rest into one bubble — which has to say so rather
  /// than looking like a folder you can open. See `SpaceLevel.visible`.
  final int hiddenCount;

  bool get isGroup => hiddenCount > 0;

  String get name =>
      isGroup ? '$hiddenCount smaller items' : path.split('/').last;

  /// Openable only when there is something inside to open.
  bool get isDrillable => isDirectory && !isGroup;

  IconData get icon =>
      isGroup
          ? AppIcons.sort
          : isDirectory
          ? AppIcons.folder
          : AppIcons.document;
}

/// One folder, measured: what is in it and how big each of those is.
///
/// The unit of work *and* the unit of caching. Space Lens never walks a whole
/// disk — it measures one folder at a time and keeps what it measured, so
/// drilling in costs one folder and coming back up costs nothing. That is what
/// makes a rescan incremental: only the folder you are looking at is re-walked.
class SpaceLevel {
  SpaceLevel({
    required this.path,
    required this.entries,
    required this.measuredAt,
    this.unreadable = 0,
  });

  /// Nothing has been measured here yet — the map draws its empty state rather
  /// than a folder that genuinely contains nothing.
  static SpaceLevel empty(String path) =>
      SpaceLevel(path: path, entries: const [], measuredAt: DateTime.now());

  final String path;

  /// Biggest first. The map, the list and the packing all rely on this order,
  /// so it is established once here rather than re-sorted at each of them.
  final List<SpaceEntry> entries;

  final DateTime measuredAt;

  /// Children macOS would not let us look inside.
  ///
  /// Counted rather than swallowed: a folder that reads as 2 GB when 40 GB of
  /// it was unreadable is a map with a hole in it, and the page says so.
  final int unreadable;

  late final int totalBytes = entries.fold(0, (sum, e) => sum + e.sizeBytes);

  bool get isEmpty => entries.isEmpty;

  /// The entries the map draws: the largest [limit], with the tail gathered
  /// into one group bubble.
  ///
  /// The tail is genuinely small — past the fortieth bubble in a folder the
  /// circles are a few points across and carry no label — so gathering it
  /// loses nothing readable and keeps the packing fast. Nothing is *hidden*:
  /// the group carries the count and the bytes, and the list beside the map
  /// still lists everything.
  List<SpaceEntry> visible({int limit = 40}) {
    if (entries.length <= limit) return entries;

    final head = entries.take(limit - 1).toList();
    final tail = entries.skip(limit - 1);
    final tailBytes = tail.fold<int>(0, (sum, e) => sum + e.sizeBytes);

    return [
      ...head,
      SpaceEntry(
        path: path,
        sizeBytes: tailBytes,
        isDirectory: false,
        hiddenCount: tail.length,
      ),
    ];
  }
}

/// How far through measuring one folder we are.
class SpaceProgress {
  const SpaceProgress({
    required this.measured,
    required this.total,
    this.currentName,
  });

  final int measured;
  final int total;

  /// What is being sized right now, for the line under the gauge.
  final String? currentName;

  double get fraction => total == 0 ? 0 : (measured / total).clamp(0.0, 1.0);
}

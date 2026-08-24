import 'package:flutter/widgets.dart';
import 'package:hugeicons/hugeicons.dart';

/// Every glyph in the app, named by what it means rather than what it looks like.
///
/// Material's icon set mixes stroke weights and filled shapes, and reads as a
/// generic Android app on macOS. HugeIcons is a single stroke-rounded family at
/// a consistent weight, which is most of why a dense UI looks deliberate.
///
/// Routing everything through here means the whole set can be swapped in one
/// file, and no widget ever hard-codes an icon package.
@immutable
class AppIcons {
  const AppIcons._();

  // ─── Navigation ──────────────────────────────────────────────────────────
  static const IconData brand = HugeIcons.strokeRoundedSparkles;
  static const IconData smartCare = HugeIcons.strokeRoundedAiMagic;
  static const IconData cleanup = HugeIcons.strokeRoundedClean;
  static const IconData protection = HugeIcons.strokeRoundedShield01;
  static const IconData performance = HugeIcons.strokeRoundedDashboardSpeed01;
  static const IconData applications = HugeIcons.strokeRoundedDashboardSquare01;
  static const IconData clutter = HugeIcons.strokeRoundedFolderLibrary;
  static const IconData spaceLens = HugeIcons.strokeRoundedChartRing;
  static const IconData allTools = HugeIcons.strokeRoundedTools;
  static const IconData activity = HugeIcons.strokeRoundedClock01;
  static const IconData assistant = HugeIcons.strokeRoundedActivity01;
  static const IconData settings = HugeIcons.strokeRoundedSettings01;

  // ─── Modules ─────────────────────────────────────────────────────────────
  static const IconData developerJunk = HugeIcons.strokeRoundedCpu;
  static const IconData trash = HugeIcons.strokeRoundedDelete02;
  static const IconData mail = HugeIcons.strokeRoundedMail01;
  static const IconData browser = HugeIcons.strokeRoundedGlobe;
  static const IconData snapshot = HugeIcons.strokeRoundedLayers01;
  static const IconData photos = HugeIcons.strokeRoundedImage01;
  static const IconData duplicates = HugeIcons.strokeRoundedCopy01;
  static const IconData largeFiles = HugeIcons.strokeRoundedFile01;
  static const IconData downloads = HugeIcons.strokeRoundedDownload01;
  static const IconData loginItems = HugeIcons.strokeRoundedRocket01;
  static const IconData privacy = HugeIcons.strokeRoundedEye;
  static const IconData storage = HugeIcons.strokeRoundedHardDrive;
  static const IconData analytics = HugeIcons.strokeRoundedPieChart;

  // ─── Actions ─────────────────────────────────────────────────────────────
  static const IconData search = HugeIcons.strokeRoundedSearch01;
  static const IconData refresh = HugeIcons.strokeRoundedRefresh;
  static const IconData sort = HugeIcons.strokeRoundedSortByDown01;
  static const IconData sortAscending = HugeIcons.strokeRoundedArrowUp01;
  static const IconData sortDescending = HugeIcons.strokeRoundedArrowDown01;
  static const IconData delete = HugeIcons.strokeRoundedDelete02;
  static const IconData revealInFinder = HugeIcons.strokeRoundedFolderOpen;
  static const IconData restore = HugeIcons.strokeRoundedRecycle01;
  static const IconData openExternal = HugeIcons.strokeRoundedLinkSquare01;
  static const IconData back = HugeIcons.strokeRoundedArrowLeft01;
  static const IconData forward = HugeIcons.strokeRoundedArrowRight01;
  static const IconData expand = HugeIcons.strokeRoundedArrowDown01;
  static const IconData collapse = HugeIcons.strokeRoundedArrowRight01;
  static const IconData close = HugeIcons.strokeRoundedCancel01;

  // ─── Status ──────────────────────────────────────────────────────────────
  static const IconData safe = HugeIcons.strokeRoundedCheckmarkCircle02;
  static const IconData review = HugeIcons.strokeRoundedEye;
  static const IconData risky = HugeIcons.strokeRoundedAlert02;
  static const IconData locked = HugeIcons.strokeRoundedSquareLock01;
  static const IconData unlocked = HugeIcons.strokeRoundedSquareUnlock01;
  static const IconData info = HugeIcons.strokeRoundedInformationCircle;
  static const IconData error = HugeIcons.strokeRoundedAlertCircle;
  static const IconData sharedStorage = HugeIcons.strokeRoundedLink01;
  static const IconData check = HugeIcons.strokeRoundedTick02;
  static const IconData nothingFound = HugeIcons.strokeRoundedSearchRemove;

  // ─── Appearance ──────────────────────────────────────────────────────────
  static const IconData light = HugeIcons.strokeRoundedSun01;
  static const IconData dark = HugeIcons.strokeRoundedMoon02;
  static const IconData system = HugeIcons.strokeRoundedComputer;
  static const IconData motion = HugeIcons.strokeRoundedLoading03;

  /// Fallback for an app whose icon has not streamed in yet.
  static const IconData appPlaceholder = HugeIcons.strokeRoundedDashboardSquare01;
}

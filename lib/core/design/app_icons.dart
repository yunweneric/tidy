import 'package:flutter/material.dart';
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

  /// A house rather than another grid or dial: Performance already wears a
  /// speedometer and Applications a square grid, and a third dashboard-ish
  /// glyph at the top of the same rail would read as a duplicate of one of them.
  static const IconData dashboard = HugeIcons.strokeRoundedHome01;
  static const IconData smartCare = HugeIcons.strokeRoundedAiMagic;
  static const IconData cleanup = HugeIcons.strokeRoundedClean;
  static const IconData protection = HugeIcons.strokeRoundedShield01;
  static const IconData performance = HugeIcons.strokeRoundedDashboardSpeed01;
  static const IconData applications = HugeIcons.strokeRoundedDashboardSquare01;
  static const IconData clutter = HugeIcons.strokeRoundedFolderLibrary;
  static const IconData spaceLens = HugeIcons.strokeRoundedChartRing;
  static const IconData allTools = HugeIcons.strokeRoundedTools;

  /// The navigation sheet on a narrow window. A hamburger rather than the
  /// wrench [allTools] wears: on a phone the affordance has to be recognised
  /// on sight, and this is the one glyph every visitor already knows.
  static const IconData menu = HugeIcons.strokeRoundedMenu01;
  static const IconData activity = HugeIcons.strokeRoundedClock01;
  static const IconData assistant = HugeIcons.strokeRoundedActivity01;
  static const IconData settings = HugeIcons.strokeRoundedSettings01;
  static const IconData recycleBin = HugeIcons.strokeRoundedDelete03;
  static const IconData clipboard = HugeIcons.strokeRoundedClipboard;
  static const IconData network = HugeIcons.strokeRoundedWifi01;

  /// AI Usage. A brain rather than a chart or a coin: Space Lens already wears
  /// a ring chart and Data & History a pie, and the subject here is the tools
  /// doing the thinking, not the money — which the page is careful not to
  /// claim it is measuring.
  static const IconData aiUsage = HugeIcons.strokeRoundedAiBrain01;

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
  static const IconData backgroundItems = HugeIcons.strokeRoundedLayers02;
  static const IconData maintenance = HugeIcons.strokeRoundedWrench01;
  static const IconData cpu = HugeIcons.strokeRoundedCpu;
  static const IconData memory = HugeIcons.strokeRoundedDatabase02;
  static const IconData storage = HugeIcons.strokeRoundedHardDrive;
  static const IconData analytics = HugeIcons.strokeRoundedPieChart;

  // ─── Traffic ─────────────────────────────────────────────────────────────
  // Direction, not a file transfer: these label the two series on the network
  // charts, so they read as "coming in" and "going out" rather than as actions.
  static const IconData downstream = HugeIcons.strokeRoundedArrowDown01;
  static const IconData upstream = HugeIcons.strokeRoundedArrowUp01;
  static const IconData ethernet = HugeIcons.strokeRoundedRouter01;

  // ─── Clipboard kinds ─────────────────────────────────────────────────────
  static const IconData plainText = HugeIcons.strokeRoundedText;
  static const IconData richText = HugeIcons.strokeRoundedTextBold;
  static const IconData link = HugeIcons.strokeRoundedLink01;

  // ─── File kinds ──────────────────────────────────────────────────────────
  // Coarse on purpose: enough to tell a folder from a film at a glance, in a
  // table where the name is doing the real work.
  static const IconData folder = HugeIcons.strokeRoundedFolder01;
  static const IconData image = HugeIcons.strokeRoundedImage01;
  static const IconData video = HugeIcons.strokeRoundedFileVideo;
  static const IconData audio = HugeIcons.strokeRoundedFileMusic;
  static const IconData archive = HugeIcons.strokeRoundedFileZip;
  static const IconData document = HugeIcons.strokeRoundedFile01;
  static const IconData externalDrive = HugeIcons.strokeRoundedExternalDrive;

  // ─── Actions ─────────────────────────────────────────────────────────────
  static const IconData search = HugeIcons.strokeRoundedSearch01;
  static const IconData refresh = HugeIcons.strokeRoundedRefresh;
  static const IconData sort = HugeIcons.strokeRoundedSortByDown01;
  static const IconData sortAscending = HugeIcons.strokeRoundedArrowUp01;
  static const IconData sortDescending = HugeIcons.strokeRoundedArrowDown01;
  static const IconData delete = HugeIcons.strokeRoundedDelete02;
  static const IconData revealInFinder = HugeIcons.strokeRoundedFolderOpen;
  static const IconData restore = HugeIcons.strokeRoundedRecycle01;

  /// Back to exactly where it came from, as opposed to [restore], which asks.
  static const IconData putBack = HugeIcons.strokeRoundedDeletePutBack;
  static const IconData openExternal = HugeIcons.strokeRoundedLinkSquare01;

  /// The repository. GitHub's own mark rather than a generic link glyph,
  /// because the chip it sits in carries a bare number — and a mark and a
  /// count only read as "stars on GitHub" together.
  static const IconData github = HugeIcons.strokeRoundedGithub01;

  /// The star badge pinned to [github], and the **one** Material glyph in this
  /// file. It is drawn at ten points, and a stroke star that small is a grey
  /// smudge — HugeIcons ships stroke weights only, so a filled star has to come
  /// from somewhere else. Not for use at any size where the stroke family works.
  static const IconData starFilled = Icons.star_rounded;
  static const IconData back = HugeIcons.strokeRoundedArrowLeft01;
  static const IconData forward = HugeIcons.strokeRoundedArrowRight01;
  static const IconData expand = HugeIcons.strokeRoundedArrowDown01;
  static const IconData collapse = HugeIcons.strokeRoundedArrowRight01;
  static const IconData close = HugeIcons.strokeRoundedCancel01;
  static const IconData quit = HugeIcons.strokeRoundedLogout01;
  static const IconData run = HugeIcons.strokeRoundedPlay;
  static const IconData copy = HugeIcons.strokeRoundedCopy02;
  static const IconData pin = HugeIcons.strokeRoundedPin;
  static const IconData unpin = HugeIcons.strokeRoundedPinOff;

  /// Un-blurs something the clipboard guard hid.
  static const IconData reveal = HugeIcons.strokeRoundedView;
  static const IconData conceal = HugeIcons.strokeRoundedViewOff;

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

  /// Built, but not yet. Deliberately not [close]: a cross reads as "this
  /// failed" where the truth is "this has not shipped".
  static const IconData pending = HugeIcons.strokeRoundedClock01;
  static const IconData nothingFound = HugeIcons.strokeRoundedSearchRemove;

  // ─── Appearance ──────────────────────────────────────────────────────────
  static const IconData light = HugeIcons.strokeRoundedSun01;
  static const IconData dark = HugeIcons.strokeRoundedMoon02;
  static const IconData system = HugeIcons.strokeRoundedComputer;
  static const IconData motion = HugeIcons.strokeRoundedLoading03;

  /// Fallback for an app whose icon has not streamed in yet.
  static const IconData appPlaceholder =
      HugeIcons.strokeRoundedDashboardSquare01;
}

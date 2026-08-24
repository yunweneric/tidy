import 'package:flutter/widgets.dart';
import 'package:mac_uninstaller/core/scanning/domain/scan_node.dart';

/// Every scanner the app can run.
///
/// One enum rather than per-feature constants so the sidebar, the Smart Care
/// composite and the All Tools catalog can all be driven from the same list.
enum ModuleId {
  smartCare('Smart Care', 'Every check that is built, in one pass.'),
  unusedApps('Unused Apps', 'Apps you have not opened in months, and their leftovers.'),
  systemJunk('System Junk', 'Caches, logs and temporary files macOS rebuilds on demand.'),
  developerJunk('Developer Junk', 'Build artefacts and package caches from your dev tools.'),
  trashBins('Trash Bins', 'Every trash on every volume, not just the Finder one.'),
  mailAttachments('Mail Attachments', 'Locally cached attachments. Your messages stay put.'),
  browserData('Browser Data', 'Browser caches. Never your cookies, logins or history.'),
  timeMachine('Time Machine Snapshots', 'Local snapshots — the "purgeable" space macOS reports.'),
  photoJunk('Photo Caches', 'Thumbnail and preview caches outside your photo library.'),
  uninstaller('Uninstaller', 'Remove an app and everything it left around the system.'),
  appLeftovers('App Leftovers', 'Files from apps that are already gone.'),
  appUpdater('App Updater', 'Apps with a newer version available.'),
  largeAndOld('Large & Old Files', 'Big files you have not opened in a long time.'),
  duplicates('Duplicates', 'Byte-identical copies of the same file.'),
  similarImages('Similar Images', 'Near-duplicate shots — bursts, edits, re-saves.'),
  downloadsClutter('Downloads', 'Installers and one-time files still sitting in Downloads.'),
  spaceLens('Space Lens', 'A map of what is actually using your disk.'),
  loginItems('Login Items', 'What launches when you log in.'),
  backgroundItems('Background Items', 'Agents and daemons running in the background.'),
  maintenance('Maintenance', 'Routine macOS upkeep tasks.'),
  heavyConsumers('Heavy Consumers', 'Apps using the most CPU and memory right now.'),
  suspiciousItems('Suspicious Items', 'Known adware and unusual launch agents.'),
  privacyItems('Privacy', 'Browsing traces, recent items and saved networks.');

  const ModuleId(this.label, this.description);

  /// Shown as the tile / page title.
  final String label;

  /// One plain-language line. Deliberately non-technical.
  final String description;
}

/// What a scan should look at.
@immutable
class ScanRequest {
  const ScanRequest({
    this.root,
    this.includeAdminItems = true,
    this.hasFullDiskAccess = false,
  });

  /// Restricts the scan to a folder or volume. Null means the module's own
  /// default roots.
  final String? root;

  /// When false, root-owned findings are skipped entirely rather than being
  /// listed as "needs administrator".
  final bool includeAdminItems;

  /// Lets a module decide whether to attempt TCC-protected roots at all, so a
  /// denied read is a deliberate skip rather than a silent empty result.
  final bool hasFullDiskAccess;
}

/// A snapshot of a scan in flight.
///
/// Modules emit these continuously so the UI fills in as results arrive rather
/// than blocking on the slowest root — a full sweep of `~/Library` takes tens
/// of seconds and an empty screen for that long reads as a hang.
@immutable
class ScanProgress {
  const ScanProgress({
    required this.roots,
    this.fraction,
    this.currentPath,
    this.done = false,
    this.skippedForPermission = false,
  });

  const ScanProgress.done(List<ScanNode> roots, {bool skippedForPermission = false})
    : this(roots: roots, fraction: 1, done: true, skippedForPermission: skippedForPermission);

  /// Top-level categories found so far. These become the result tiles.
  final List<ScanNode> roots;

  /// 0–1, or null when the total is not knowable yet.
  final double? fraction;

  /// What the scanner is looking at right now, for the rolling status line.
  final String? currentPath;

  final bool done;

  /// At least one root could not be read — almost always Full Disk Access.
  /// The UI must say so rather than reporting a confident zero.
  final bool skippedForPermission;

  int get totalBytes => roots.fold<int>(0, (sum, node) => sum + node.totalBytes);

  int get reclaimableBytes =>
      roots.fold<int>(0, (sum, node) => sum + node.reclaimableBytes);

  bool get isEmpty => roots.every((node) => node.totalBytes == 0);
}

/// The contract every scanner implements.
///
/// This is the whole point of the architecture: modules differ only in where
/// they look, and the scan → tiles → review → clean UI is written once.
abstract class ScanModule {
  ModuleId get id;

  /// The glyph shown on the tile and in the sidebar.
  IconData get icon;

  /// True when this module cannot produce complete results without Full Disk
  /// Access, so the UI can prompt before wasting the user's time.
  bool get needsFullDiskAccess => false;

  /// True when some findings will need the privileged helper.
  bool get mayNeedAdmin => false;

  Stream<ScanProgress> scan(ScanRequest request);
}

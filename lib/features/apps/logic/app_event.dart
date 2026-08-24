import 'package:tidy/features/apps/data/models/mac_app_model.dart';

abstract class AppsEvent {}

/// Initial load: paints the cached scan first, then refreshes in the background.
class LoadApps extends AppsEvent {
  LoadApps({this.useCache = true});

  final bool useCache;
}

/// Explicit user-triggered rescan.
class RefreshApps extends AppsEvent {}

/// Cheap consistency check after the window regains focus: drops apps that no
/// longer exist on disk (removed from the menu bar popover, Finder, or another
/// uninstaller) without paying for a full rescan.
class ReconcileApps extends AppsEvent {}

/// Removes one or more apps together with the leftover paths the user kept
/// selected in the preview.
class UninstallAppsEvent extends AppsEvent {
  UninstallAppsEvent({
    required this.apps,
    required this.paths,
    required this.toTrash,
    required this.expectedBytes,
  });

  /// Apps to drop from the list once removal succeeds.
  final List<MacApp> apps;

  /// Every path to remove — bundles and leftovers alike.
  final List<String> paths;

  /// Move to Trash (recoverable) rather than deleting outright.
  final bool toTrash;

  /// Bytes the preview promised to free, used for the result message.
  final int expectedBytes;
}

/// Removes selected junk paths (caches, logs, saved state, orphans).
class ClearJunkEvent extends AppsEvent {
  ClearJunkEvent({
    required this.paths,
    required this.expectedBytes,
    this.toTrash = true,
  });

  final List<String> paths;
  final int expectedBytes;
  final bool toTrash;
}

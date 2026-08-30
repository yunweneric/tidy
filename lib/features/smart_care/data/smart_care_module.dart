import 'package:tidy/core/design/app_icons.dart';
import 'package:tidy/core/scanning/domain/composite_scan_module.dart';
import 'package:tidy/core/scanning/domain/scan_module.dart';
import 'package:tidy/features/apps/data/services/unused_apps_module.dart';
import 'package:tidy/features/cleanup/data/cleanup_scan_module.dart';
import 'package:tidy/features/cleanup/data/scanners/developer_junk_module.dart';

/// One pass over every check that exists, reviewed in one place.
///
/// Smart Care is a [CompositeScanModule] and nothing else — it owns no scanning
/// logic of its own. Adding a module to [modules] is all it takes to widen the
/// sweep, and each sub-scan keeps working exactly as it did alone.
///
/// This is the app's only sweep. There was a separate Cleanup page running the
/// junk half of this list on its own, which meant two scans of `~/Library` and
/// two answers to "how much can I get back" — one of them always the smaller.
///
/// Order is deliberate, because the merge hands a contested path to the earlier
/// module. Developer Junk runs first so the folders it and the system sweep
/// both find under `~/Library/Caches` — Homebrew, CocoaPods, JetBrains — keep
/// the label and the safety level of the tool that owns them. Unused Apps runs
/// last so a leftover folder stays filed as junk rather than being attached to
/// an application the user may well decide to keep.
class SmartCareModule extends CompositeScanModule {
  SmartCareModule({
    required DeveloperJunkModule developerJunk,
    required CleanupScanModule systemJunk,
    required UnusedAppsModule unusedApps,
  }) : super(
         id: ModuleId.smartCare,
         icon: AppIcons.smartCare,
         modules: [developerJunk, systemJunk, unusedApps],
       );

  /// What this sweep currently covers, for the coverage note on the page.
  ///
  /// Kept next to the module list on purpose: if the two drift, the app starts
  /// claiming checks it does not run, which is the one thing a cleaner must
  /// never do.
  static const List<String> covered = [
    'Caches, logs and saved window state',
    'Xcode build output and package-manager caches',
    'Leftovers from apps that are already gone',
    'Apps you have not opened in six months',
  ];

  /// Checks that are not built yet. Listed so the sweep never implies it is
  /// more thorough than it is.
  static const List<String> notYetCovered = [
    'Malware and suspicious launch agents',
    'Login items and maintenance tasks',
    'Duplicates and large old files',
  ];
}

import 'package:tidy/core/design/app_icons.dart';
import 'package:tidy/core/scanning/domain/composite_scan_module.dart';
import 'package:tidy/core/scanning/domain/scan_module.dart';
import 'package:tidy/features/apps/data/services/unused_apps_module.dart';
import 'package:tidy/features/cleanup/data/cleanup_scan_module.dart';

/// One pass over every check that exists, reviewed in one place.
///
/// Smart Care is a [CompositeScanModule] and nothing else — it owns no scanning
/// logic of its own. Adding a module to [coverage] is all it takes to widen the
/// sweep, and the module keeps working exactly as it does on its own page.
///
/// Order is deliberate: Cleanup runs first, so when it and the unused-apps pass
/// both claim a leftover folder, it stays filed under junk rather than being
/// attached to an app the user may well decide to keep.
class SmartCareModule extends CompositeScanModule {
  SmartCareModule({
    required CleanupScanModule cleanup,
    required UnusedAppsModule unusedApps,
  }) : super(
         id: ModuleId.smartCare,
         icon: AppIcons.smartCare,
         modules: [cleanup, unusedApps],
       );

  /// What this sweep currently covers, for the coverage note on the page.
  ///
  /// Kept next to the module list on purpose: if the two drift, the app starts
  /// claiming checks it does not run, which is the one thing a cleaner must
  /// never do.
  static const List<String> covered = [
    'Caches, logs and saved window state',
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

import 'package:tidy/core/design/app_icons.dart';
import 'package:tidy/core/scanning/domain/composite_scan_module.dart';
import 'package:tidy/core/scanning/domain/scan_module.dart';
import 'package:tidy/features/clutter/data/downloads_scan_module.dart';
import 'package:tidy/features/clutter/data/large_and_old_scan_module.dart';

/// Files that pile up quietly — large old files, and forgotten downloads.
///
/// My Clutter is a [CompositeScanModule] and nothing else: it owns no scanning
/// logic of its own, just fans out to its sub-scanners and merges their
/// findings. Adding a sub-scan (duplicates, similar photos) means adding it to
/// [modules], and each stays reviewable on its own terms.
///
/// Order matters: Downloads runs after Large & Old, so when both claim the same
/// old file in Downloads, it stays filed as a large old file.
class ClutterModule extends CompositeScanModule {
  ClutterModule({
    required LargeAndOldScanModule largeAndOld,
    required DownloadsClutterScanModule downloads,
  }) : super(
         id: ModuleId.myClutter,
         icon: AppIcons.clutter,
         modules: [largeAndOld, downloads],
       );

  /// What this sweep currently covers, for the coverage note on the page.
  static const List<String> covered = [
    'Large files you have not opened in months',
    'Installers and old downloads still in Downloads',
  ];

  /// Sub-scans that are not built yet, so the page never implies it is more
  /// thorough than it is.
  static const List<String> notYetCovered = [
    'Byte-identical duplicates',
    'Near-identical photos',
  ];
}

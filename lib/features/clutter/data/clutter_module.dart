import 'package:tidy/core/design/app_icons.dart';
import 'package:tidy/core/scanning/domain/composite_scan_module.dart';
import 'package:tidy/core/scanning/domain/scan_module.dart';
import 'package:tidy/features/clutter/data/downloads_scan_module.dart';
import 'package:tidy/features/clutter/data/duplicates_scan_module.dart';
import 'package:tidy/features/clutter/data/large_and_old_scan_module.dart';

/// Files that pile up quietly — large old files, and forgotten downloads.
///
/// My Clutter is a [CompositeScanModule] and nothing else: it owns no scanning
/// logic of its own, just fans out to its sub-scanners and merges their
/// findings. Adding a sub-scan (duplicates, similar photos) means adding it to
/// [modules], and each stays reviewable on its own terms.
///
/// Order matters: the composite gives a contested path to the earliest module
/// that claimed it. Duplicates runs first because "this is the third copy of a
/// file you already have" is a better reason to remove something than "this is
/// big and old"; Downloads runs last, so an old file in Downloads stays filed as
/// a large old file rather than being listed twice.
class ClutterModule extends CompositeScanModule {
  ClutterModule({
    required DuplicatesScanModule duplicates,
    required LargeAndOldScanModule largeAndOld,
    required DownloadsClutterScanModule downloads,
  }) : super(
         id: ModuleId.myClutter,
         icon: AppIcons.clutter,
         modules: [duplicates, largeAndOld, downloads],
       );

  /// What this sweep currently covers, for the coverage note on the page.
  static const List<String> covered = [
    'Byte-identical duplicates',
    'Large files you have not opened in months',
    'Installers and old downloads still in Downloads',
  ];

  /// Sub-scans that are not built yet, so the page never implies it is more
  /// thorough than it is.
  static const List<String> notYetCovered = ['Near-identical photos'];
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tidy/core/di/service_locator.dart';
import 'package:tidy/core/platform/full_disk_access_service.dart';
import 'package:tidy/core/scanning/logic/scan_bloc.dart';
import 'package:tidy/core/scanning/presentation/coverage_note.dart';
import 'package:tidy/core/scanning/presentation/scan_view.dart';
import 'package:tidy/core/settings/app_settings.dart';
import 'package:tidy/core/store/tidy_store.dart';
import 'package:tidy/features/clutter/data/clutter_module.dart';

/// The My Clutter module.
///
/// Built on the generic [ScanView] like every other module. Like Smart Care, it
/// gets its own `ScanBloc` nested inside the shell's: the shell's `ScanBloc`
/// belongs to Cleanup, and My Clutter is a different scan that must not
/// overwrite it. The only addition over the bare scan view is the shared
/// [CoverageNote], so the page never implies it is more thorough than it is.
class ClutterPage extends StatelessWidget {
  const ClutterPage({super.key});

  @override
  Widget build(BuildContext context) {
    final fullDiskAccess = locator<FullDiskAccessService>();
    final settings = locator<AppSettings>();

    return BlocProvider(
      create:
          (_) => ScanBloc(
            locator<ClutterModule>(),
            hasFullDiskAccess: fullDiskAccess.granted ?? true,
            store: locator<TidyStore>(),
          ),
      child: ScanView(
        title: 'My Clutter',
        subtitle:
            'Duplicates, forgotten downloads, and files you stopped using.',
        idleHeadline: 'Reclaim the files you have forgotten',
        idleMessage:
            'Byte-identical copies of the same file, large files you have not '
            'touched in months, and old downloads and installers still in '
            'Downloads. Nothing is removed until you have looked at it.',
        actionLabel: 'Scan for clutter',
        onGrantAccess: fullDiskAccess.openSettings,
        banner: CoverageNote(
          covered: ClutterModule.covered,
          notYetCovered: ClutterModule.notYetCovered,
          seen: settings.hasSeenClutterCoverage,
          onSeen: settings.markClutterCoverageSeen,
          footnote:
              'Duplicates keep their oldest copy, which is never listed — so '
              'nothing here can remove the last copy of a file. Copies that '
              'share their storage on APFS are marked, because deleting those '
              'frees far less than their size suggests.',
        ),
      ),
    );
  }
}

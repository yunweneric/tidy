import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/di/service_locator.dart';
import 'package:mac_uninstaller/core/platform/full_disk_access_service.dart';
import 'package:mac_uninstaller/core/scanning/presentation/scan_view.dart';

/// The Cleanup module.
///
/// Almost nothing here: the page is the generic [ScanView] pointed at a module,
/// reading its `ScanBloc` from the shell above so the sidebar can show the same
/// reclaimable figure without running a second scan. That is the payoff of the
/// scan contract — every module from here on is a data source plus some copy.
class CleanupPage extends StatelessWidget {
  const CleanupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ScanView(
      title: 'Cleanup',
      subtitle: 'Reclaim space macOS and your apps will rebuild on their own.',
      idleHeadline: 'Find space you can get back',
      idleMessage:
          'Caches, logs and window-restore data pile up quietly. None of it is '
          'your work — apps recreate what they need the next time they run.',
      actionLabel: 'Scan for junk',
      onGrantAccess: locator<FullDiskAccessService>().openSettings,
    );
  }
}

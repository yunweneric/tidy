import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mac_uninstaller/core/design/design.dart';
import 'package:mac_uninstaller/core/di/service_locator.dart';
import 'package:mac_uninstaller/core/platform/full_disk_access_service.dart';
import 'package:mac_uninstaller/core/platform/system_bridge.dart';
import 'package:mac_uninstaller/core/scanning/logic/scan_bloc.dart';
import 'package:mac_uninstaller/core/scanning/logic/scan_state.dart';
import 'package:mac_uninstaller/core/settings/app_settings.dart';
import 'package:mac_uninstaller/core/utils/byte_format.dart';
import 'package:mac_uninstaller/features/apps/data/services/apps_service.dart';
import 'package:mac_uninstaller/features/apps/logic/app_bloc.dart';
import 'package:mac_uninstaller/features/apps/logic/app_event.dart';
import 'package:mac_uninstaller/features/apps/presentation/screens/applications_page.dart';
import 'package:mac_uninstaller/features/cleanup/data/cleanup_scan_module.dart';
import 'package:mac_uninstaller/features/cleanup/presentation/cleanup_page.dart';
import 'package:mac_uninstaller/features/settings/presentation/settings_page.dart';
import 'package:mac_uninstaller/features/shell/domain/app_destination.dart';
import 'package:mac_uninstaller/features/shell/presentation/widgets/coming_soon_page.dart';
import 'package:mac_uninstaller/features/shell/presentation/widgets/nav_sidebar.dart';

/// The window: a permanent sidebar and whichever module is selected.
///
/// Pages live in an [IndexedStack] rather than behind a router. There are no
/// deep links to serve, and a scan that keeps running while you look at another
/// module is worth more than route history — losing a two-minute sweep because
/// you clicked away would be its own bug report.
class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  AppDestination _current = AppDestination.initial;
  DiskUsage _disk = DiskUsage.empty;

  late final FullDiskAccessService _fullDiskAccess =
      locator<FullDiskAccessService>();

  @override
  void initState() {
    super.initState();
    _refreshDisk();
    _fullDiskAccess.refresh();
  }

  Future<void> _refreshDisk() async {
    final disk = await SystemBridge.diskUsage();
    if (mounted) setState(() => _disk = disk);
  }

  void _select(AppDestination destination) {
    if (destination == _current) return;
    setState(() => _current = destination);
    // Cheap, and keeps the sidebar honest after a clean in another module.
    _refreshDisk();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => AppsBloc(locator<AppManagerService>())..add(LoadApps()),
        ),
        // Hoisted above the module so the sidebar can show the reclaimable
        // figure without running a second scan of its own.
        BlocProvider(
          create: (_) => ScanBloc(
            locator<CleanupScanModule>(),
            hasFullDiskAccess: _fullDiskAccess.granted ?? true,
          ),
        ),
      ],
      child: Scaffold(
        backgroundColor: context.colors.canvas,
        body: AnimatedBuilder(
          animation: _fullDiskAccess,
          builder: (context, _) {
            return BlocBuilder<ScanBloc, ScanState>(
              builder: (context, cleanupState) {
                return Row(
                  children: [
                    NavSidebar(
                      current: _current,
                      onSelect: _select,
                      disk: _disk,
                      badges: _badges(cleanupState),
                      reclaimableBytes: cleanupState.totalBytes,
                      fullDiskAccessGranted: _fullDiskAccess.granted,
                      onGrantAccess: _fullDiskAccess.openSettings,
                      onReclaim: () => _select(AppDestination.cleanup),
                    ),
                    Expanded(
                      child: IndexedStack(
                        index: AppDestination.values.indexOf(_current),
                        children: [
                          for (final destination in AppDestination.values)
                            _pageFor(destination),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Map<AppDestination, String> _badges(ScanState cleanup) => {
    if (cleanup.totalBytes > 0)
      AppDestination.cleanup: formatBytes(cleanup.totalBytes),
  };

  Widget _pageFor(AppDestination destination) => switch (destination) {
    AppDestination.cleanup =>
      CleanupPage(onGrantAccess: _fullDiskAccess.openSettings),
    AppDestination.applications => const ApplicationsPage(),
    AppDestination.settings => SettingsPage(
      settings: locator<AppSettings>(),
      fullDiskAccess: _fullDiskAccess,
    ),
    AppDestination.smartCare => const ComingSoonPage(
      destination: AppDestination.smartCare,
      planned: [
        'Run Cleanup, Protection, Performance and Applications in one pass',
        'Present everything found as one reviewable list',
        'Apply it all with a single confirmation',
      ],
    ),
    AppDestination.protection => const ComingSoonPage(
      destination: AppDestination.protection,
      planned: [
        'Flag launch agents whose binary is missing, unsigned, or hiding in /tmp',
        'Check installed apps against a list of known adware and browser hijackers',
        'Audit browser extensions for search hijacking and over-broad permissions',
        'Clear browsing traces, recent items and saved Wi-Fi networks',
      ],
    ),
    AppDestination.performance => const ComingSoonPage(
      destination: AppDestination.performance,
      planned: [
        'Turn login items and background agents on or off',
        'Run macOS maintenance: flush DNS, reindex Spotlight, thin snapshots',
        'Quit apps that are eating CPU or memory',
      ],
    ),
    AppDestination.clutter => const ComingSoonPage(
      destination: AppDestination.clutter,
      planned: [
        'Find byte-identical duplicates, and flag APFS clones that free nothing',
        'Group near-identical photos — bursts, edits, re-saves',
        'Surface large files you have not opened in months',
        'Clear one-time installers out of Downloads',
      ],
    ),
    AppDestination.spaceLens => const ComingSoonPage(
      destination: AppDestination.spaceLens,
      planned: [
        'Map the disk as nested bubbles sized by what they actually occupy',
        'Drill into any folder and remove from the map',
        'Cache results so a rescan is incremental, not a full walk',
      ],
    ),
    AppDestination.allTools => const ComingSoonPage(
      destination: AppDestination.allTools,
      planned: [
        'Every scanner listed on its own, for when the modules get in the way',
      ],
    ),
    AppDestination.activity => const ComingSoonPage(
      destination: AppDestination.activity,
      planned: [
        'A record of what was removed, and when',
        'What is worth looking at next',
      ],
    ),
    AppDestination.assistant => const ComingSoonPage(
      destination: AppDestination.assistant,
      planned: [
        'A single health reading from free space, battery, updates and findings',
        'Specific suggestions rather than a score with no next step',
      ],
    ),
  };
}

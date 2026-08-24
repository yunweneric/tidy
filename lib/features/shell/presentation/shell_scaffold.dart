import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:mac_uninstaller/core/design/design.dart';
import 'package:mac_uninstaller/core/di/service_locator.dart';
import 'package:mac_uninstaller/core/platform/full_disk_access_service.dart';
import 'package:mac_uninstaller/core/platform/system_bridge.dart';
import 'package:mac_uninstaller/core/scanning/logic/scan_bloc.dart';
import 'package:mac_uninstaller/core/scanning/logic/scan_state.dart';
import 'package:mac_uninstaller/core/utils/byte_format.dart';
import 'package:mac_uninstaller/core/widgets/widgets.dart';
import 'package:mac_uninstaller/features/apps/data/services/apps_service.dart';
import 'package:mac_uninstaller/features/apps/logic/app_bloc.dart';
import 'package:mac_uninstaller/features/apps/logic/app_event.dart';
import 'package:mac_uninstaller/features/cleanup/data/cleanup_scan_module.dart';
import 'package:mac_uninstaller/features/shell/domain/app_destination.dart';
import 'package:mac_uninstaller/features/shell/presentation/widgets/nav_sidebar.dart';

/// The window chrome: permanent sidebar, plus whichever branch is active.
///
/// Wraps a [StatefulNavigationShell], so every destination is a real route with
/// its own navigator whose state survives being navigated away from. That
/// matters more here than route history does — a Cleanup sweep takes tens of
/// seconds, and losing it because someone glanced at Applications would be its
/// own bug report.
class ShellScaffold extends StatefulWidget {
  const ShellScaffold({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  State<ShellScaffold> createState() => _ShellScaffoldState();
}

class _ShellScaffoldState extends State<ShellScaffold>
    with WidgetsBindingObserver {
  DiskUsage _disk = DiskUsage.empty;

  late final FullDiskAccessService _fullDiskAccess =
      locator<FullDiskAccessService>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshDisk();
    _fullDiskAccess.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from System Settings, Finder, or the popover: re-read both,
    // so the sidebar is never quoting numbers from before the user acted.
    if (state == AppLifecycleState.resumed) {
      _refreshDisk();
      _fullDiskAccess.refresh();
    }
  }

  Future<void> _refreshDisk() async {
    final disk = await SystemBridge.diskUsage();
    if (mounted) setState(() => _disk = disk);
  }

  void _select(AppDestination destination) {
    final index = destination.branchIndex;
    widget.navigationShell.goBranch(
      index,
      // Tapping the destination you are already on resets that branch to its
      // root rather than doing nothing — the standard shell-route behaviour.
      initialLocation: index == widget.navigationShell.currentIndex,
    );
    _refreshDisk();
  }

  @override
  Widget build(BuildContext context) {
    final current = AppDestination.fromBranchIndex(
      widget.navigationShell.currentIndex,
    );

    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => AppsBloc(locator<AppManagerService>())..add(LoadApps()),
        ),
        // Hoisted above the branches so the sidebar can show the reclaimable
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
                      current: current,
                      onSelect: _select,
                      disk: _disk,
                      badges: _badges(cleanupState),
                      reclaimableBytes: cleanupState.totalBytes,
                      fullDiskAccessGranted: _fullDiskAccess.granted,
                      onGrantAccess: _fullDiskAccess.openSettings,
                      onReclaim: () => _select(AppDestination.cleanup),
                    ),
                    Expanded(
                      child: FadeThrough(
                        trigger: widget.navigationShell.currentIndex,
                        child: widget.navigationShell,
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
}

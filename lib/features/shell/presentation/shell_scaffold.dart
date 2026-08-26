import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/feedback/feedback.dart';
import 'package:tidy/core/di/service_locator.dart';
import 'package:tidy/core/store/metric_sampler.dart';
import 'package:tidy/core/settings/app_settings.dart';
import 'package:tidy/core/store/tidy_store.dart';
import 'package:tidy/core/updates/logic/update_bloc.dart';
import 'package:tidy/core/updates/update_service.dart';
import 'package:tidy/core/platform/full_disk_access_service.dart';
import 'package:tidy/core/platform/system_bridge.dart';
import 'package:tidy/core/scanning/logic/scan_bloc.dart';
import 'package:tidy/core/scanning/logic/scan_state.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/features/apps/data/services/apps_service.dart';
import 'package:tidy/features/apps/logic/app_bloc.dart';
import 'package:tidy/features/apps/logic/app_event.dart';
import 'package:tidy/features/cleanup/data/cleanup_scan_module.dart';
import 'package:tidy/features/shell/domain/app_destination.dart';
import 'package:tidy/features/shell/presentation/active_destination.dart';
import 'package:tidy/features/shell/presentation/widgets/nav_sidebar.dart';

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

  /// Held as a field rather than built inside the provider below, so the
  /// lifecycle hook can nudge it: a Mac that was asleep at the timer's slot
  /// wakes up with a stale answer, and coming back to the window is the
  /// cheapest moment to ask again. The service still gates the real request to
  /// once a day, so an app that is activated twenty times an hour makes no
  /// requests at all.
  late final UpdateBloc _updates = UpdateBloc(
    locator<UpdateService>(),
    settings: locator<AppSettings>(),
  )..add(const CheckForUpdates());

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
    // Provided by value, so nothing else closes it.
    _updates.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from System Settings, Finder, or the popover: re-read both,
    // so the sidebar is never quoting numbers from before the user acted.
    if (state == AppLifecycleState.resumed) {
      _refreshDisk();
      _fullDiskAccess.refresh();
      _updates.add(const CheckForUpdates());
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
          create:
              (_) => AppsBloc(
                locator<AppManagerService>(),
                store: locator<TidyStore>(),
                sampler: locator<MetricSampler>(),
              )..add(LoadApps()),
        ),
        // Hoisted above the branches so the sidebar can show the reclaimable
        // figure without running a second scan of its own.
        BlocProvider(
          create:
              (_) => ScanBloc(
                locator<CleanupScanModule>(),
                hasFullDiskAccess: _fullDiskAccess.granted ?? true,
                store: locator<TidyStore>(),
              ),
        ),
        // Hoisted for the same reason from the other direction: the check runs
        // at launch whether or not anyone opens Settings, and the toast below
        // is the shell's, while the rail's chip and the controls belong to the
        // sidebar and the Settings page.
        BlocProvider.value(value: _updates),
      ],
      child: BlocListener<UpdateBloc, UpdateState>(
        // Only the arrival of an update is announced, and only once — the
        // download, the check and the install all have a visible home in
        // Settings, and a toast for each step would narrate a process the user
        // is already watching.
        listenWhen:
            (previous, current) =>
                current.status == UpdateStatus.available &&
                previous.status != UpdateStatus.available,
        listener: (context, updateState) {
          final release = updateState.release;
          if (release == null) return;
          context.toastInfo(
            'Version ${release.version.display} is ready to download.',
            title: '${Brand.name} update available',
            duration: Duration.zero,
            action: ToastAction(
              label: 'View',
              onPressed:
                  () => context.go(
                    '${AppDestination.settings.path}?section=updates',
                  ),
            ),
          );
        },
        child: Scaffold(
          // The flat canvas is only a fallback; AmbientBackground paints the
          // module's own colour over it.
          backgroundColor: context.colors.canvas,
          body: AnimatedBuilder(
            animation: _fullDiskAccess,
            builder: (context, _) {
              return BlocBuilder<ScanBloc, ScanState>(
                builder: (context, cleanupState) {
                  return AmbientBackground(
                    // The module owns the window's colour, so switching branches
                    // repaints the whole frame, sidebar included.
                    tone: current.tone,
                    child: Row(
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
                          // Branches stay mounted when you navigate away, so a page
                          // that polls has no other way to know it is off screen.
                          child: ActiveDestination(
                            destination: current,
                            child: FadeThrough(
                              trigger: widget.navigationShell.currentIndex,
                              child: widget.navigationShell,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Map<AppDestination, String> _badges(ScanState cleanup) => {
    if (cleanup.totalBytes > 0)
      AppDestination.cleanup: formatBytes(cleanup.totalBytes),
  };
}

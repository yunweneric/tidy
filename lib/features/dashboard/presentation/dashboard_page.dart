import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/di/service_locator.dart';
import 'package:tidy/core/insights/dashboard_repository.dart';
import 'package:tidy/core/insights/health_insight.dart';
import 'package:tidy/core/platform/full_disk_access_service.dart';
import 'package:tidy/core/scanning/logic/scan_bloc.dart';
import 'package:tidy/core/scanning/logic/scan_state.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/features/dashboard/logic/dashboard_bloc.dart';
import 'package:tidy/features/dashboard/logic/dashboard_event.dart';
import 'package:tidy/features/dashboard/logic/dashboard_state.dart';
import 'package:tidy/features/dashboard/presentation/widgets/dashboard_counters.dart';
import 'package:tidy/features/dashboard/presentation/widgets/dashboard_trends.dart';
import 'package:tidy/features/dashboard/presentation/widgets/health_hero.dart';
import 'package:tidy/features/dashboard/presentation/widgets/recent_activity.dart';
import 'package:tidy/features/dashboard/presentation/widgets/storage_breakdown.dart';
import 'package:tidy/features/shell/domain/app_destination.dart';
import 'package:tidy/features/shell/presentation/active_destination.dart';

/// Where the app opens: how the Mac is doing, and what Tidy has done about it.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create:
          (_) => DashboardBloc(locator<DashboardRepository>())
            ..add(const LoadDashboard()),
      child: const _DashboardView(),
    );
  }
}

class _DashboardView extends StatefulWidget {
  const _DashboardView();

  @override
  State<_DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<_DashboardView> {
  Timer? _ticker;

  /// Matches the Performance page's cadence, so two screens reading the same
  /// vitals never disagree about how busy the machine is.
  static const Duration _tick = Duration(seconds: 2);

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Starts and stops the live meters with the page.
  ///
  /// Branches stay mounted in the shell's `IndexedStack`, so a timer left
  /// running would keep polling the machine from behind whatever screen the
  /// user actually moved to.
  void _syncTicker(bool visible) {
    if (visible == (_ticker != null)) return;

    if (visible) {
      _ticker = Timer.periodic(_tick, (_) {
        if (mounted) context.read<DashboardBloc>().add(const DashboardTicked());
      });
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncTicker(ActiveDestination.isVisible(context, AppDestination.dashboard));

    // The Cleanup scan is hoisted above every branch by `ShellScaffold`, so its
    // total is already known if a scan has run. Reading it here rather than
    // scanning again is the difference between one sweep of ~/Library and two.
    final scan = context.watch<ScanBloc>().state;
    final junk = _junkFrom(scan);
    if (junk != null) {
      context.read<DashboardBloc>().add(JunkObserved(junk));
    }

    return BlocBuilder<DashboardBloc, DashboardState>(
      builder: (context, state) {
        final bloc = context.read<DashboardBloc>();

        return ModuleScaffold(
          title: AppDestination.dashboard.label,
          subtitle: AppDestination.dashboard.blurb,
          actions: [
            TextButton.icon(
              onPressed:
                  state.refreshing
                      ? null
                      : () => bloc.add(const RefreshDashboard()),
              icon: Icon(AppIcons.refresh, size: 17),
              label: Text(state.refreshing ? 'Refreshing…' : 'Refresh'),
            ),
          ],
          banner:
              state.fullDiskAccess == false
                  ? PermissionBanner(
                    compact: true,
                    onOpenSettings:
                        locator<FullDiskAccessService>().openSettings,
                  )
                  : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HealthHero(
                state: state,
                onAction: () => _act(context, state),
              ),
              const SizedBox(height: AppSpacing.lg),
              VitalsRow(state: state),
              const SizedBox(height: AppSpacing.xl),
              DashboardCounters(
                state: state,
                onOpen: (destination) => context.go(destination.path),
              ),
              const SizedBox(height: AppSpacing.xl),
              StorageBreakdown(state: state),
              const SizedBox(height: AppSpacing.xl),
              DashboardTrends(
                state: state,
                onRange: (range) => bloc.add(TrendRangeChanged(range)),
              ),
              const SizedBox(height: AppSpacing.xl),
              _BottomRow(state: state),
            ],
          ),
        );
      },
    );
  }

  /// The hero's one action, resolved through the same insight the menu bar uses.
  void _act(BuildContext context, DashboardState state) {
    final action = state.insight?.action;
    context.go(
      switch (action) {
        HealthInsightAction.cleanJunk => AppDestination.cleanup.path,
        HealthInsightAction.openApp || null => AppDestination.smartCare.path,
      },
    );
  }

  /// The scan's total, but only once it means something.
  ///
  /// While a scan is still running the figure climbs as roots land, and a
  /// partial sweep reported as "reclaimable" would be a number that shrinks
  /// when you look at it properly.
  static int? _junkFrom(ScanState scan) => switch (scan.phase) {
    ScanPhase.results || ScanPhase.finished => scan.totalBytes,
    ScanPhase.clean => 0,
    _ => null,
  };
}

/// Activity beside the compositions — two columns at full width, stacked when
/// the window is narrow.
class _BottomRow extends StatelessWidget {
  const _BottomRow({required this.state});

  final DashboardState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final removed = CompositionCard(
      title: 'REMOVED BY CATEGORY',
      color: colors.safe,
      emptyMessage:
          'Once Tidy has cleaned something up, what it was is broken down here.',
      rows: [
        for (final category in state.removedByCategory)
          (
            label: category.category,
            bytes: category.bytes,
            detail:
                '${formatBytes(category.bytes)} · ${category.itemCount} items',
          ),
      ],
    );

    final trash = CompositionCard(
      title: 'TRASH BY KIND',
      color: colors.review,
      emptyMessage: 'The Trash is empty.',
      rows: _trashRows(state),
    );

    final developers = CompositionCard(
      title: 'APPS BY DEVELOPER',
      color: colors.info,
      emptyMessage: 'Open Applications once to take stock.',
      rows: [
        for (final developer in state.apps.byDeveloper)
          (
            label: developer.name,
            bytes: developer.bytes,
            detail: formatBytes(developer.bytes),
          ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RecentActivity(state: state),
              const SizedBox(height: AppSpacing.lg),
              removed,
              const SizedBox(height: AppSpacing.lg),
              trash,
              const SizedBox(height: AppSpacing.lg),
              developers,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: RecentActivity(state: state)),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  removed,
                  const SizedBox(height: AppSpacing.lg),
                  trash,
                  const SizedBox(height: AppSpacing.lg),
                  developers,
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static List<({String label, int bytes, String detail})> _trashRows(
    DashboardState state,
  ) {
    final trash = state.trash;
    if (trash == null) return const [];

    final byKind = <String, ({int bytes, int count})>{};
    for (final item in trash.items) {
      final key = item.kind.label;
      final current = byKind[key] ?? (bytes: 0, count: 0);
      byKind[key] = (
        bytes: current.bytes + item.sizeBytes,
        count: current.count + 1,
      );
    }

    final rows =
        byKind.entries
            .map(
              (entry) => (
                label: entry.key,
                bytes: entry.value.bytes,
                detail:
                    '${formatBytes(entry.value.bytes)} · '
                    '${entry.value.count} items',
              ),
            )
            .toList()
          ..sort((a, b) => b.bytes.compareTo(a.bytes));
    return rows.take(5).toList();
  }
}

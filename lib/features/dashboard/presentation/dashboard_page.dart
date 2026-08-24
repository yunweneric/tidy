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
          (_) =>
              DashboardBloc(locator<DashboardRepository>())
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
              HealthHero(state: state, onAction: () => _act(context, state)),
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
              _ActivityAndCompositions(state: state),
            ],
          ),
        );
      },
    );
  }

  /// The hero's one action, resolved through the same insight the menu bar uses.
  void _act(BuildContext context, DashboardState state) {
    final action = state.insight?.action;
    context.go(switch (action) {
      HealthInsightAction.cleanJunk => AppDestination.cleanup.path,
      HealthInsightAction.openApp || null => AppDestination.smartCare.path,
    });
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

/// What Tidy has done, and what the machine is made of.
///
/// Two bands rather than two columns. The compositions are three readings of
/// the same shape — a label, a figure, a proportional bar — and they belong
/// beside each other, at one height, so the bars can be compared by eye. Recent
/// activity is not that shape at all: it is a feed, it grows without limit, and
/// its rows need the width to say what happened without ellipsing it away.
///
/// Stacking the three compositions into a column beside it, which is what this
/// used to do, made the two sides disagree about how tall the section was — a
/// long stack on one side and a short card marooned at the top of an empty
/// column on the other.
class _ActivityAndCompositions extends StatelessWidget {
  const _ActivityAndCompositions({required this.state});

  final DashboardState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RecentActivity(state: state),
        const SizedBox(height: AppSpacing.lg),
        _Compositions(state: state),
      ],
    );
  }
}

/// The three breakdowns, side by side and all the same height.
class _Compositions extends StatelessWidget {
  const _Compositions({required this.state});

  final DashboardState state;

  /// Under this the three cards no longer have the width to hold a name, a
  /// figure and a bar, and the names start ellipsing to nothing.
  static const double _threeAcross = 900;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final across = constraints.maxWidth >= _threeAcross;
        final cards = _cards(context, filled: across);

        if (!across) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpacing.lg),
                cards[i],
              ],
            ],
          );
        }

        // IntrinsicHeight, not a stretched Row: the page lives in a scroll
        // view, so its height is unbounded, and stretching into that hands the
        // cards an infinite constraint and throws in layout. This measures the
        // tallest card and matches the other two to it.
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.lg),
                Expanded(child: cards[i]),
              ],
            ],
          ),
        );
      },
    );
  }

  /// [filled] says the cards are about to be stretched to a shared height, so
  /// an empty one should centre its message rather than leave it stranded
  /// against the top of a box sized by a fuller neighbour.
  List<Widget> _cards(BuildContext context, {required bool filled}) {
    final colors = context.colors;

    return [
      CompositionCard(
        title: 'REMOVED BY CATEGORY',
        color: colors.safe,
        filled: filled,
        emptyMessage:
            'Once Tidy has cleaned something up, what it was is broken down '
            'here.',
        rows: [
          for (final category in state.removedByCategory)
            (
              label: category.category,
              bytes: category.bytes,
              detail:
                  '${formatBytes(category.bytes)} · ${category.itemCount} items',
            ),
        ],
      ),
      CompositionCard(
        title: 'TRASH BY KIND',
        color: colors.review,
        filled: filled,
        emptyMessage: 'The Trash is empty.',
        rows: _trashRows(state),
      ),
      CompositionCard(
        title: 'APPS BY DEVELOPER',
        color: colors.info,
        filled: filled,
        emptyMessage: 'Open Applications once to take stock.',
        rows: [
          for (final developer in state.apps.byDeveloper)
            (
              label: developer.name,
              bytes: developer.bytes,
              detail: formatBytes(developer.bytes),
            ),
        ],
      ),
    ];
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

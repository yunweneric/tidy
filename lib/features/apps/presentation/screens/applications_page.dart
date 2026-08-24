import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mac_uninstaller/core/design/design.dart';
import 'package:mac_uninstaller/core/widgets/widgets.dart';
import 'package:mac_uninstaller/features/apps/data/models/mac_app_model.dart';
import 'package:mac_uninstaller/features/apps/logic/app_bloc.dart';
import 'package:mac_uninstaller/features/apps/logic/app_event.dart';
import 'package:mac_uninstaller/features/apps/logic/app_states.dart';
import 'package:mac_uninstaller/features/apps/presentation/widgets/widgets.dart'
    as app_widgets;
import 'package:mac_uninstaller/features/apps/utils/size_utils.dart';

const int _pageSize = 10;
const int _largeAppThresholdBytes = 1024 * 1024 * 1024; // 1 GB
const int _unusedThresholdDays = 180; // Six months, matching "unused" elsewhere.

/// The Applications module: uninstall apps and everything they left behind.
///
/// Filter, sort, search and selection stay local `setState` rather than moving
/// into the bloc — they are view state, they reset when you leave the page, and
/// putting them in the bloc would mean the menu-bar popover carried them too.
class ApplicationsPage extends StatefulWidget {
  const ApplicationsPage({super.key});

  @override
  State<ApplicationsPage> createState() => _ApplicationsPageState();
}

class _ApplicationsPageState extends State<ApplicationsPage>
    with WidgetsBindingObserver {
  String _searchQuery = '';
  app_widgets.AppFilter _filter = app_widgets.AppFilter.all;
  app_widgets.AppSort _sort = app_widgets.AppSort.size;

  /// Keyed by install path so it survives list rebuilds — icons arrive after
  /// the first paint and replace the model objects wholesale.
  final Set<String> _selectedPaths = {};
  int _currentPage = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Apps may have been removed from the popover (a separate isolate) or in
    // Finder while this window was in the background.
    if (state == AppLifecycleState.resumed) {
      context.read<AppsBloc>().add(ReconcileApps());
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AppsBloc, AppsState>(
      listenWhen: (previous, current) {
        if (current is! AppsLoaded || current.lastOutcome == null) return false;
        final previousOutcome =
            previous is AppsLoaded ? previous.lastOutcome : null;
        return !identical(previousOutcome, current.lastOutcome);
      },
      listener: (context, state) =>
          _showOutcome(context, (state as AppsLoaded).lastOutcome!),
      child: BlocBuilder<AppsBloc, AppsState>(
        builder: (context, state) {
          final loaded = state is AppsLoaded ? state : null;

          return ModuleScaffold(
            title: 'Applications',
            subtitle:
                'Remove an app and the support files, caches and launch agents '
                'it leaves scattered around the system.',
            actions: [
              AppSearchField(
                width: 260,
                hintText: 'Filter by name or bundle id…',
                onChanged: (query) => setState(() {
                  _searchQuery = query.trim().toLowerCase();
                  _currentPage = 1;
                }),
              ),
              _RefreshButton(
                busy: loaded?.isRefreshing ?? state is AppsLoading,
                onPressed: () => context.read<AppsBloc>().add(RefreshApps()),
              ),
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _summaryCards(context, loaded),
                const SizedBox(height: AppSpacing.xl),
                _toolbarAndTable(context, state),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _summaryCards(BuildContext context, AppsLoaded? state) {
    final removable = state?.removableApps ?? const <MacApp>[];
    final unused = removable.where(_isUnused).toList();
    final colors = context.colors;

    return Row(
      children: [
        Expanded(
          child: _Stat(
            label: 'Apps installed',
            value: '${removable.length}',
            icon: Icons.grid_view_rounded,
            color: colors.accent,
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: _Stat(
            label: 'Space used by apps',
            value: formatBytes(totalBytes(removable)),
            icon: Icons.pie_chart_outline_rounded,
            color: colors.info,
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: _Stat(
            label: 'Not opened in 6 months',
            value: '${unused.length}',
            icon: Icons.hourglass_empty_rounded,
            color: unused.isEmpty ? colors.safe : colors.review,
            onTap: unused.isEmpty
                ? null
                : () => _changeFilter(app_widgets.AppFilter.unused),
          ),
        ),
      ],
    );
  }

  Widget _toolbarAndTable(BuildContext context, AppsState state) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        app_widgets.AppListToolbar(
          filter: _filter,
          onFilterChanged: _changeFilter,
          sort: _sort,
          onSortChanged: (sort) => setState(() => _sort = sort),
          selectedCount: _selectedPaths.length,
          onBulkUninstallPressed: () => _uninstallSelected(context, state),
        ),
        Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(AppRadii.lg),
              bottomRight: Radius.circular(AppRadii.lg),
            ),
            border: Border(
              left: BorderSide(color: colors.border),
              right: BorderSide(color: colors.border),
              bottom: BorderSide(color: colors.border),
            ),
          ),
          child: _table(context, state),
        ),
      ],
    );
  }

  Widget _table(BuildContext context, AppsState state) {
    if (state is AppsLoading || state is AppsInitial) {
      return SizedBox(
        height: 420,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: AppSpacing.lg),
              Text('Reading your applications…', style: context.text.bodyM),
            ],
          ),
        ),
      );
    }

    if (state is AppsError) {
      return SizedBox(
        height: 320,
        child: EmptyState(
          icon: Icons.error_outline_rounded,
          accent: context.colors.risky,
          title: 'Could not read your applications',
          message: state.message,
          action: ElevatedButton(
            onPressed: () => context.read<AppsBloc>().add(RefreshApps()),
            child: const Text('Try again'),
          ),
        ),
      );
    }

    if (state is! AppsLoaded) return const SizedBox(height: 200);

    final filtered = _visibleApps(state);
    final totalPages = (filtered.length / _pageSize).ceil().clamp(1, 9999);
    final page = _currentPage.clamp(1, totalPages);
    final start = (page - 1) * _pageSize;
    final end = (start + _pageSize).clamp(0, filtered.length);
    final pageApps = filtered.isEmpty ? <MacApp>[] : filtered.sublist(start, end);

    final selectable = pageApps.where((app) => !app.isSystem).toList();
    final selectedOnPage =
        selectable.where((app) => _selectedPaths.contains(app.path)).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DataTableHeader(
          columnLabels: const [
            'APPLICATION',
            'DEVELOPER',
            'VERSION',
            'LAST OPENED',
            'SIZE',
          ],
          flexValues: const [3, 2, 1, 2, 1],
          showSelectAll: true,
          selectAllValue: selectedOnPage == 0
              ? false
              : (selectedOnPage == selectable.length ? true : null),
          onSelectAll: (_) => _toggleSelectAll(selectable),
        ),
        if (pageApps.isEmpty)
          SizedBox(
            height: 240,
            child: EmptyState(
              icon: Icons.search_off_rounded,
              title: _searchQuery.isEmpty
                  ? 'Nothing matches this filter'
                  : 'Nothing matches “$_searchQuery”',
              message: _searchQuery.isEmpty
                  ? 'Try a different filter.'
                  : 'Check the spelling, or search by bundle id instead.',
            ),
          )
        else
          ...pageApps.map(
            (app) => app_widgets.AppTableRow(
              app: app,
              selected: _selectedPaths.contains(app.path),
              onSelectionChanged: (selected) => setState(() {
                if (selected) {
                  _selectedPaths.add(app.path);
                } else {
                  _selectedPaths.remove(app.path);
                }
              }),
              onUninstall: () => _confirmUninstall(context, [app]),
            ),
          ),
        app_widgets.AppTableFooter(
          itemCount: filtered.length,
          totalSize: formatAppsTotalSize(filtered.where((a) => !a.isSystem)),
          currentPage: page,
          totalPages: totalPages,
          onPageChanged: (p) => setState(() => _currentPage = p),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ filtering

  List<MacApp> _visibleApps(AppsLoaded state) {
    var apps = state.apps;

    switch (_filter) {
      case app_widgets.AppFilter.all:
        break;
      case app_widgets.AppFilter.large:
        apps = apps.where((a) => a.sizeBytes >= _largeAppThresholdBytes).toList();
      case app_widgets.AppFilter.unused:
        apps = apps.where((a) => !a.isSystem && _isUnused(a)).toList();
    }

    if (_searchQuery.isNotEmpty) {
      apps = apps
          .where(
            (a) =>
                a.name.toLowerCase().contains(_searchQuery) ||
                a.bundleId.toLowerCase().contains(_searchQuery),
          )
          .toList();
    }

    final sorted = List<MacApp>.from(apps);
    switch (_sort) {
      case app_widgets.AppSort.size:
        sorted.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
      case app_widgets.AppSort.name:
        sorted.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case app_widgets.AppSort.lastUsed:
        // Most recently used first; never-used apps sink to the bottom.
        sorted.sort((a, b) {
          final aDate = a.lastUsed;
          final bDate = b.lastUsed;
          if (aDate == null && bDate == null) return 0;
          if (aDate == null) return 1;
          if (bDate == null) return -1;
          return bDate.compareTo(aDate);
        });
    }
    return sorted;
  }

  static bool _isUnused(MacApp app) {
    final days = app.daysSinceLastUsed;
    return days == null || days >= _unusedThresholdDays;
  }

  void _changeFilter(app_widgets.AppFilter filter) {
    setState(() {
      _filter = filter;
      _currentPage = 1;
    });
  }

  void _toggleSelectAll(List<MacApp> selectable) {
    setState(() {
      final allSelected = selectable.isNotEmpty &&
          selectable.every((app) => _selectedPaths.contains(app.path));
      for (final app in selectable) {
        if (allSelected) {
          _selectedPaths.remove(app.path);
        } else {
          _selectedPaths.add(app.path);
        }
      }
    });
  }

  // ------------------------------------------------------------------- actions

  Future<void> _confirmUninstall(BuildContext context, List<MacApp> apps) async {
    final bloc = context.read<AppsBloc>();
    final plan = await app_widgets.UninstallConfirmDialog.show(context, apps);
    if (plan == null || !mounted) return;

    bloc.add(
      UninstallAppsEvent(
        apps: plan.apps,
        paths: plan.paths,
        toTrash: plan.toTrash,
        expectedBytes: plan.totalBytes,
      ),
    );
    setState(() => _selectedPaths.removeAll(plan.apps.map((app) => app.path)));
  }

  void _uninstallSelected(BuildContext context, AppsState state) {
    if (state is! AppsLoaded) return;
    final selected = state.apps
        .where((app) => _selectedPaths.contains(app.path) && !app.isSystem)
        .toList();
    if (selected.isEmpty) return;
    _confirmUninstall(context, selected);
  }

  void _showOutcome(BuildContext context, RemovalOutcome outcome) {
    final messenger = ScaffoldMessenger.of(context);
    final colors = context.colors;

    // "Moved to Trash" rather than "freed": nothing is actually reclaimed until
    // the Trash is emptied, and claiming otherwise is a lie the disk will
    // contradict a moment later.
    final destination = outcome.movedToTrash ? 'moved to Trash' : 'deleted';
    final message = outcome.hasFailures
        ? '${formatBytes(outcome.freedBytes)} $destination · '
              '${outcome.failures.length} item(s) stayed put'
        : '${formatBytes(outcome.freedBytes)} $destination';

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: outcome.hasFailures ? colors.review : colors.surfaceRaised,
        content: Text(
          message,
          style: context.text.bodyL.copyWith(
            color: outcome.hasFailures ? colors.canvas : colors.textPrimary,
          ),
        ),
        action: outcome.hasFailures
            ? SnackBarAction(
                label: 'Details',
                textColor: colors.canvas,
                onPressed: () => _showFailureDetails(context, outcome),
              )
            : null,
      ),
    );
  }

  void _showFailureDetails(BuildContext context, RemovalOutcome outcome) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${outcome.failures.length} item(s) stayed put'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'These usually need administrator rights or Full Disk Access.',
                  style: ctx.text.bodyM,
                ),
                const SizedBox(height: AppSpacing.md),
                for (final failure in outcome.failures)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(failure.path, style: ctx.text.mono),
                        Text(
                          failure.error,
                          style: ctx.text.caption.copyWith(color: ctx.colors.review),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

/// A headline figure with a label. Replaces `SummaryCard`, which returned an
/// `Expanded` and so could only ever live inside a `Row`.
class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TidyCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const Spacer(),
              if (onTap != null)
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: context.colors.textMuted,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(value, style: context.text.displayL.copyWith(color: color)),
          const SizedBox(height: AppSpacing.xxs),
          Text(label, style: context.text.bodyS),
        ],
      ),
    );
  }
}

class _RefreshButton extends StatelessWidget {
  const _RefreshButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: busy ? null : onPressed,
      tooltip: 'Rescan applications',
      icon: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh_rounded, size: 18),
    );
  }
}

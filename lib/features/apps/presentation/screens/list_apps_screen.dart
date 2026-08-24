import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mac_uninstaller/core/platform/system_bridge.dart';
import 'package:mac_uninstaller/core/theme/app_theme.dart';
import 'package:mac_uninstaller/core/widgets/widgets.dart';
import 'package:mac_uninstaller/features/apps/data/models/mac_app_model.dart';
import 'package:mac_uninstaller/features/apps/logic/app_bloc.dart';
import 'package:mac_uninstaller/features/apps/logic/app_event.dart';
import 'package:mac_uninstaller/features/apps/logic/app_states.dart';
import 'package:mac_uninstaller/features/apps/presentation/widgets/widgets.dart'
    as app_widgets;
import 'package:mac_uninstaller/features/apps/utils/size_utils.dart';

const int _pageSize = 8;
const int _largeAppThresholdBytes = 1024 * 1024 * 1024; // 1 GB
const int _unusedThresholdDays = 90;

class ListAppsScreen extends StatefulWidget {
  const ListAppsScreen({super.key});

  @override
  State<ListAppsScreen> createState() => _ListAppsScreenState();
}

class _ListAppsScreenState extends State<ListAppsScreen>
    with WidgetsBindingObserver {
  String _searchQuery = '';
  app_widgets.AppFilter _filter = app_widgets.AppFilter.all;
  app_widgets.AppSort _sort = app_widgets.AppSort.size;

  /// Selection is keyed by install path so it survives list rebuilds (icons
  /// arrive after the first paint and replace the model objects).
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
    // Apps may have been removed from the menu bar popover (a separate isolate)
    // or in Finder while this window was in the background.
    if (state == AppLifecycleState.resumed) {
      context.read<AppsBloc>().add(ReconcileApps());
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AppsBloc, AppsState>(
      listenWhen: (previous, current) {
        if (current is! AppsLoaded || current.lastOutcome == null) return false;
        final previousOutcome = previous is AppsLoaded ? previous.lastOutcome : null;
        return !identical(previousOutcome, current.lastOutcome);
      },
      listener: (context, state) => _showOutcome(context, (state as AppsLoaded).lastOutcome!),
      child: Scaffold(
        backgroundColor: AppTheme.backgroundPrimary,
        body: BlocBuilder<AppsBloc, AppsState>(
          builder: (context, state) {
            final loaded = state is AppsLoaded ? state : null;
            return Row(
              children: [
                app_widgets.AppSidebar(
                  filter: _filter,
                  onFilterChanged: _changeFilter,
                  disk: loaded?.disk ?? DiskUsage.empty,
                  reclaimableBytes: loaded?.junk.safeBytes ?? 0,
                  onCleanupPressed: loaded == null ? null : () => _openJunkDialog(loaded),
                ),
                Expanded(child: _buildMainContent(context, state)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildMainContent(BuildContext context, AppsState state) {
    final loaded = state is AppsLoaded ? state : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        app_widgets.AppListHeader(
          title: 'Application Manager',
          selectedCount: _selectedPaths.length,
          searchHint: 'Filter by name or bundle id…',
          isRefreshing: loaded?.isRefreshing ?? state is AppsLoading,
          onRefreshPressed: () => context.read<AppsBloc>().add(RefreshApps()),
          onSearchChanged: (q) => setState(() {
            _searchQuery = q.trim().toLowerCase();
            _currentPage = 1;
          }),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 25),
                _buildSummaryCards(loaded),
                const SizedBox(height: 25),
                _buildTabsAndTable(context, state),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCards(AppsLoaded? state) {
    final removable = state?.removableApps ?? const <MacApp>[];
    final unused = removable.where(_isUnused).length;

    return app_widgets.AppSummaryCards(
      totalApps: removable.length,
      appsSpaceBytes: totalBytes(removable),
      reclaimableBytes: state?.junk.safeBytes ?? 0,
      unusedCount: unused,
      isScanningJunk: state?.isScanningJunk ?? false,
      onReclaimablePressed: state == null ? null : () => _openJunkDialog(state),
    );
  }

  Widget _buildTabsAndTable(BuildContext context, AppsState state) {
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
          decoration: const BoxDecoration(
            color: AppTheme.surfaceCard,
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(12),
              bottomRight: Radius.circular(12),
            ),
            border: Border(
              left: BorderSide(color: AppTheme.borderSubtle),
              right: BorderSide(color: AppTheme.borderSubtle),
              bottom: BorderSide(color: AppTheme.borderSubtle),
            ),
          ),
          child: _buildTable(context, state),
        ),
      ],
    );
  }

  Widget _buildTable(BuildContext context, AppsState state) {
    if (state is AppsLoading || state is AppsInitial) {
      return const SizedBox(
        height: 480,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppTheme.accentBlue),
              SizedBox(height: 16),
              Text('Scanning your applications…', style: AppTheme.bodySecondary),
            ],
          ),
        ),
      );
    }

    if (state is AppsError) {
      return SizedBox(
        height: 320,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppTheme.accentRed, size: 32),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  state.message,
                  textAlign: TextAlign.center,
                  style: AppTheme.bodySecondary,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => context.read<AppsBloc>().add(RefreshApps()),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Try again'),
              ),
            ],
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

    final selectableOnPage = pageApps.where((app) => !app.isSystem).toList();
    final selectedOnPage =
        selectableOnPage.where((app) => _selectedPaths.contains(app.path)).length;

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
              : (selectedOnPage == selectableOnPage.length ? true : null),
          onSelectAll: (_) => _toggleSelectAll(selectableOnPage),
        ),
        if (pageApps.isEmpty)
          SizedBox(
            height: 220,
            child: Center(
              child: Text(
                _searchQuery.isEmpty
                    ? 'No applications match this filter.'
                    : 'No applications match "$_searchQuery".',
                style: AppTheme.bodySecondary,
              ),
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

  Future<void> _openJunkDialog(AppsLoaded state) async {
    final bloc = context.read<AppsBloc>();

    if (state.junk.groups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.surfaceElevated,
          content: Text(
            state.isScanningJunk
                ? 'Still scanning for reclaimable space…'
                : 'Nothing to clean up right now.',
            style: AppTheme.bodyPrimary,
          ),
        ),
      );
      return;
    }

    final plan = await app_widgets.JunkDialog.show(context, state.junk);
    if (plan == null) return;

    bloc.add(
      ClearJunkEvent(paths: plan.paths, expectedBytes: plan.totalBytes),
    );
  }

  void _showOutcome(BuildContext context, RemovalOutcome outcome) {
    final messenger = ScaffoldMessenger.of(context);
    final destination = outcome.movedToTrash ? 'moved to Trash' : 'deleted';

    final message = outcome.hasFailures
        ? '${formatBytes(outcome.freedBytes)} $destination · '
              '${outcome.failures.length} item(s) could not be removed'
        : '${formatBytes(outcome.freedBytes)} $destination';

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: outcome.hasFailures
            ? AppTheme.accentOrange
            : AppTheme.surfaceElevated,
        content: Text(
          message,
          style: AppTheme.bodyPrimary.copyWith(
            color: outcome.hasFailures ? Colors.black : AppTheme.textPrimary,
          ),
        ),
        action: outcome.hasFailures
            ? SnackBarAction(
                label: 'Details',
                textColor: Colors.black,
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
        backgroundColor: AppTheme.surfaceCard,
        title: Text(
          'Could not remove ${outcome.failures.length} item(s)',
          style: AppTheme.bodyPrimary.copyWith(fontSize: 17),
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'These usually need administrator rights or Full Disk Access.',
                  style: AppTheme.bodySecondary,
                ),
                const SizedBox(height: 12),
                for (final failure in outcome.failures)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(failure.path, style: AppTheme.bodyPrimary),
                        Text(
                          failure.error,
                          style: AppTheme.labelSmall.copyWith(
                            color: AppTheme.accentOrange,
                          ),
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

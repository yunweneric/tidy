import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tidy/core/utils/paged.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/feedback/feedback.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/features/apps/data/models/mac_app_model.dart';
import 'package:tidy/features/apps/logic/app_bloc.dart';
import 'package:tidy/features/apps/logic/app_event.dart';
import 'package:tidy/features/apps/logic/app_states.dart';
import 'package:tidy/features/apps/presentation/widgets/widgets.dart'
    as app_widgets;
import 'package:tidy/features/apps/utils/size_utils.dart';

const int _pageSize = 10;
const int _largeAppThresholdBytes = 1024 * 1024 * 1024; // 1 GB
const int _unusedThresholdDays =
    180; // Six months, matching "unused" elsewhere.

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
  bool _ascending = _defaultAscending(app_widgets.AppSort.size);

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
      listener:
          (context, state) =>
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
                onChanged:
                    (query) => setState(() {
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
            label: 'Apps you can remove',
            value: '${removable.length}',
            icon: AppIcons.applications,
            color: colors.accent,
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: _Stat(
            label: 'Space they use',
            value: formatBytes(totalBytes(removable)),
            icon: AppIcons.analytics,
            color: colors.info,
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: _Stat(
            label: 'Not opened in 6 months',
            value: '${unused.length}',
            icon: AppIcons.activity,
            color: unused.isEmpty ? colors.safe : colors.review,
            onTap:
                unused.isEmpty
                    ? null
                    : () => _changeFilter(app_widgets.AppFilter.unused),
          ),
        ),
      ],
    );
  }

  Widget _toolbarAndTable(BuildContext context, AppsState state) {
    final colors = context.colors;
    final loaded = state is AppsLoaded ? state : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        app_widgets.AppListToolbar(
          filter: _filter,
          onFilterChanged: _changeFilter,
          counts: _filterCounts(loaded),
          selectedCount: _selectedPaths.length,
          onBulkUninstallPressed: () => _uninstallSelected(context, state),
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors.surfaceGradient,
            ),
            borderRadius: AppRadii.lgAll,
            border: Border.all(color: colors.border),
          ),
          child: _table(context, state),
        ),
      ],
    );
  }

  /// Row counts per filter, so the segmented control answers "is there anything
  /// in there?" before it is clicked.
  List<int> _filterCounts(AppsLoaded? state) {
    if (state == null) return const [];
    final apps = state.apps;
    return [
      apps.length,
      apps.where((a) => a.sizeBytes >= _largeAppThresholdBytes).length,
      apps.where((a) => !a.isSystem && _isUnused(a)).length,
    ];
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
          icon: AppIcons.error,
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
    final paged = Paged.of(filtered, page: _currentPage, pageSize: _pageSize);
    final pageApps = paged.items;

    final selectable = pageApps.where((app) => !app.isSystem).toList();
    final selectedOnPage =
        selectable.where((app) => _selectedPaths.contains(app.path)).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DataTableHeader(
          columnLabels: const [],
          trailingWidth: app_widgets.AppTableLayout.actions,
          columns: [
            TableColumn(
              'APPLICATION',
              flex: app_widgets.AppTableLayout.appFlex,
              sort: _sortIndicatorFor(app_widgets.AppSort.name),
              onTap: () => _applySort(app_widgets.AppSort.name),
            ),
            TableColumn(
              'DEVELOPER',
              flex: app_widgets.AppTableLayout.developerFlex,
              sort: _sortIndicatorFor(app_widgets.AppSort.developer),
              onTap: () => _applySort(app_widgets.AppSort.developer),
            ),
            TableColumn(
              'VERSION',
              width: app_widgets.AppTableLayout.version,
              sort: _sortIndicatorFor(app_widgets.AppSort.version),
              onTap: () => _applySort(app_widgets.AppSort.version),
            ),
            TableColumn(
              'LAST OPENED',
              flex: app_widgets.AppTableLayout.lastOpenedFlex,
              sort: _sortIndicatorFor(app_widgets.AppSort.lastUsed),
              onTap: () => _applySort(app_widgets.AppSort.lastUsed),
            ),
            TableColumn(
              'SIZE',
              width: app_widgets.AppTableLayout.size,
              align: TextAlign.right,
              sort: _sortIndicatorFor(app_widgets.AppSort.size),
              onTap: () => _applySort(app_widgets.AppSort.size),
            ),
          ],
          showSelectAll: true,
          selectAllValue:
              selectedOnPage == 0
                  ? false
                  : (selectedOnPage == selectable.length ? true : null),
          onSelectAll: (_) => _toggleSelectAll(selectable),
        ),
        if (pageApps.isEmpty)
          SizedBox(
            height: 240,
            child: EmptyState(
              icon: AppIcons.nothingFound,
              title:
                  _searchQuery.isEmpty
                      ? 'Nothing matches this filter'
                      : 'Nothing matches “$_searchQuery”',
              message:
                  _searchQuery.isEmpty
                      ? 'Try a different filter.'
                      : 'Check the spelling, or search by bundle id instead.',
            ),
          )
        else
          for (var i = 0; i < pageApps.length; i++)
            app_widgets.AppTableRow(
              app: pageApps[i],
              isLast: i == pageApps.length - 1,
              selected: _selectedPaths.contains(pageApps[i].path),
              onSelectionChanged:
                  (selected) => setState(() {
                    if (selected) {
                      _selectedPaths.add(pageApps[i].path);
                    } else {
                      _selectedPaths.remove(pageApps[i].path);
                    }
                  }),
              onUninstall: () => _confirmUninstall(context, [pageApps[i]]),
            ),
        app_widgets.AppTableFooter(
          itemCount: filtered.length,
          totalSize: formatAppsTotalSize(filtered.where((a) => !a.isSystem)),
          currentPage: paged.page,
          totalPages: paged.totalPages,
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
        apps =
            apps.where((a) => a.sizeBytes >= _largeAppThresholdBytes).toList();
      case app_widgets.AppFilter.unused:
        apps = apps.where((a) => !a.isSystem && _isUnused(a)).toList();
    }

    if (_searchQuery.isNotEmpty) {
      apps =
          apps
              .where(
                (a) =>
                    a.name.toLowerCase().contains(_searchQuery) ||
                    a.bundleId.toLowerCase().contains(_searchQuery),
              )
              .toList();
    }

    return List<MacApp>.from(apps)..sort(_compare);
  }

  /// Every column sorts, in both directions.
  ///
  /// Missing values sink to the bottom whichever way the column is pointing.
  /// Flipping the direction is meant to answer "which is the oldest?", not to
  /// dredge up the rows that have no answer at all.
  int _compare(MacApp a, MacApp b) {
    final sign = _ascending ? 1 : -1;

    switch (_sort) {
      case app_widgets.AppSort.size:
        return sign * a.sizeBytes.compareTo(b.sizeBytes);
      case app_widgets.AppSort.name:
        return sign * a.name.toLowerCase().compareTo(b.name.toLowerCase());
      case app_widgets.AppSort.developer:
        return _nullsLast(
          a.developer,
          b.developer,
          (x, y) => sign * x.toLowerCase().compareTo(y.toLowerCase()),
        );
      case app_widgets.AppSort.version:
        return _nullsLast(
          a.version.isEmpty ? null : a.version,
          b.version.isEmpty ? null : b.version,
          (x, y) => sign * _compareVersions(x, y),
        );
      case app_widgets.AppSort.lastUsed:
        return _nullsLast(
          a.lastUsed,
          b.lastUsed,
          (x, y) => sign * x.compareTo(y),
        );
    }
  }

  static int _nullsLast<T>(T? a, T? b, int Function(T, T) compare) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return compare(a, b);
  }

  /// Compares versions segment by segment, numerically where both sides are
  /// numbers. A plain string sort puts 10.0 before 9.0, which is exactly the
  /// column someone opens this table to check.
  static int _compareVersions(String a, String b) {
    final left = a.split(RegExp(r'[._\-]'));
    final right = b.split(RegExp(r'[._\-]'));

    for (var i = 0; i < left.length || i < right.length; i++) {
      final x = i < left.length ? left[i] : '';
      final y = i < right.length ? right[i] : '';
      final xn = int.tryParse(x);
      final yn = int.tryParse(y);

      final result =
          xn != null && yn != null
              ? xn.compareTo(yn)
              : x.toLowerCase().compareTo(y.toLowerCase());
      if (result != 0) return result;
    }
    return 0;
  }

  /// Which way a column points the first time you tap it. Text reads forwards;
  /// size and dates are asked about biggest-and-newest first.
  static bool _defaultAscending(app_widgets.AppSort sort) => switch (sort) {
    app_widgets.AppSort.name ||
    app_widgets.AppSort.developer ||
    app_widgets.AppSort.version => true,
    app_widgets.AppSort.size || app_widgets.AppSort.lastUsed => false,
  };

  static bool _isUnused(MacApp app) {
    final days = app.daysSinceLastUsed;
    return days == null || days >= _unusedThresholdDays;
  }

  SortDirection _sortIndicatorFor(app_widgets.AppSort candidate) {
    if (_sort != candidate) return SortDirection.none;
    return _ascending ? SortDirection.ascending : SortDirection.descending;
  }

  /// Tapping a new column sorts it the way that column is usually asked about;
  /// tapping the one already sorted flips it.
  void _applySort(app_widgets.AppSort sort) {
    setState(() {
      _ascending = sort == _sort ? !_ascending : _defaultAscending(sort);
      _sort = sort;
      _currentPage = 1;
    });
  }

  void _changeFilter(app_widgets.AppFilter filter) {
    setState(() {
      _filter = filter;
      _currentPage = 1;
    });
  }

  void _toggleSelectAll(List<MacApp> selectable) {
    setState(() {
      final allSelected =
          selectable.isNotEmpty &&
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

  /// Opens the preview and waits for it to finish.
  ///
  /// The dialog dispatches the removal itself and stays on screen while it
  /// runs, so by the time this resolves the work is done — all that is left is
  /// to drop what went from the selection. The result toast comes from the
  /// outcome listener, which fires for removals started anywhere.
  Future<void> _confirmUninstall(
    BuildContext context,
    List<MacApp> apps,
  ) async {
    final plan = await app_widgets.UninstallConfirmDialog.show(context, apps);
    if (plan == null || !mounted) return;

    setState(() => _selectedPaths.removeAll(plan.apps.map((app) => app.path)));
  }

  void _uninstallSelected(BuildContext context, AppsState state) {
    if (state is! AppsLoaded) return;
    final selected =
        state.apps
            .where((app) => _selectedPaths.contains(app.path) && !app.isSystem)
            .toList();
    if (selected.isEmpty) return;
    _confirmUninstall(context, selected);
  }

  /// The result of a removal, as a toast rather than a page state.
  ///
  /// A finished uninstall is news, not a decision — nothing here needs
  /// acknowledging, so nothing here blocks. The one case with more to say than
  /// fits on a toast hands off to an alert behind a "Details" button.
  void _showOutcome(BuildContext context, RemovalOutcome outcome) {
    // "Moved to Trash" rather than "freed": nothing is actually reclaimed until
    // the Trash is emptied, and claiming otherwise is a lie the disk will
    // contradict a moment later.
    final freed = formatBytes(outcome.freedBytes);
    final removed = _count(outcome.removedCount, 'item');

    if (outcome.hasFailures) {
      final stuck = _count(outcome.failures.length, 'item');
      context.showToast(
        tone: FeedbackTone.warning,
        title:
            outcome.movedToTrash ? '$freed moved to Trash' : '$freed deleted',
        message:
            '$stuck stayed put — usually because it needs administrator '
            'rights or Full Disk Access.',
        action: ToastAction(
          label: 'See what stayed',
          onPressed: () => _showFailureDetails(context, outcome),
        ),
      );
      return;
    }

    context.toastSuccess(
      outcome.movedToTrash
          ? 'Your disk will not show the space as free until you empty the '
              'Trash.'
          : 'Removed for good — there is nothing left to put back.',
      title:
          outcome.movedToTrash
              ? '$removed moved to Trash · $freed'
              : '$removed deleted · $freed',
    );
  }

  void _showFailureDetails(BuildContext context, RemovalOutcome outcome) {
    TidyAlert.notify(
      context,
      tone: FeedbackTone.warning,
      icon: AppIcons.locked,
      title: '${_count(outcome.failures.length, 'item')} stayed put',
      message:
          'These were left exactly as they were. Most of the time that means '
          'the file belongs to the system and needs administrator rights, or '
          'that Tidy has not been given Full Disk Access to the folder it '
          'lives in.',
      details: [
        for (final failure in outcome.failures)
          AlertDetail(
            title: failure.path,
            detail: failure.error,
            tone: FeedbackTone.warning,
          ),
      ],
    );
  }

  /// "1 item" / "4 items". Pluralising inline is how a UI ends up saying
  /// "1 items" on exactly the removal the user is looking closely at.
  static String _count(int n, String noun) =>
      n == 1 ? '1 $noun' : '$n ${noun}s';
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
      // The colour is the information here — amber for apps gone unopened,
      // green for a clean result — so the whole tile carries it, not just the
      // glyph. Rows in the table below stay untinted for exactly that reason.
      tint: color,
      accent: color,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconTile(icon: icon, color: color),
              const Spacer(),
              if (onTap != null)
                Icon(
                  AppIcons.forward,
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

/// The glyph on a summary tile, on its own gradient chip.
class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.28),
            color.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: AppRadii.mdAll,
      ),
      child: Icon(icon, size: 18, color: color),
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
      icon:
          busy
              ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
              : const Icon(AppIcons.refresh, size: 18),
    );
  }
}

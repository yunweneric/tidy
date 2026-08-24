import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mac_uninstaller/core/design/design.dart';
import 'package:mac_uninstaller/core/di/service_locator.dart';
import 'package:mac_uninstaller/core/feedback/feedback.dart';
import 'package:mac_uninstaller/core/platform/full_disk_access_service.dart';
import 'package:mac_uninstaller/core/platform/system_bridge.dart';
import 'package:mac_uninstaller/core/utils/byte_format.dart';
import 'package:mac_uninstaller/core/utils/home_dir.dart';
import 'package:mac_uninstaller/core/widgets/widgets.dart';
import 'package:mac_uninstaller/features/recycle_bin/data/models/trash_item.dart';
import 'package:mac_uninstaller/features/recycle_bin/data/services/recycle_bin_service.dart';
import 'package:mac_uninstaller/features/recycle_bin/logic/recycle_bin_bloc.dart';
import 'package:mac_uninstaller/features/recycle_bin/logic/recycle_bin_event.dart';
import 'package:mac_uninstaller/features/recycle_bin/logic/recycle_bin_state.dart';
import 'package:mac_uninstaller/features/recycle_bin/presentation/widgets/widgets.dart';
import 'package:mac_uninstaller/features/shell/domain/app_destination.dart';
import 'package:mac_uninstaller/features/shell/presentation/active_destination.dart';

/// The Recycle Bin.
///
/// A plain page rather than a [ScanView], for the same reason Performance is
/// one. The scan contract is find → select → remove, and this is none of those
/// three: nothing is *found* — the Trash is a folder the user put things in
/// themselves — and the action that matters most here is the opposite of
/// removal. Wrapping "Put Back" in a byte counter and a "Move to Trash" button
/// would be reusing the pipeline for the wrong verb.
///
/// It is also the only place in the app that deletes without a way back, which
/// is why every route to that runs through one confirmation that names the
/// count and the size.
class RecycleBinPage extends StatelessWidget {
  const RecycleBinPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create:
          (_) =>
              RecycleBinBloc(locator<RecycleBinService>())
                ..add(const LoadBin()),
      child: const _RecycleBinView(),
    );
  }
}

class _RecycleBinView extends StatefulWidget {
  const _RecycleBinView();

  @override
  State<_RecycleBinView> createState() => _RecycleBinViewState();
}

class _RecycleBinViewState extends State<_RecycleBinView>
    with WidgetsBindingObserver {
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    super.dispose();
  }

  /// The Trash changes while the app is not looking — Finder is the usual way
  /// things get into it. Coming back to a window that still lists a file the
  /// user restored ten seconds ago in Finder reads as broken, so a re-read on
  /// resume is cheap honesty.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    if (!ActiveDestination.isVisible(context, AppDestination.recycleBin)) return;
    context.read<RecycleBinBloc>().add(const LoadBin(silent: true));
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<RecycleBinBloc, RecycleBinState>(
      listenWhen:
          (previous, current) =>
              current.notice != null && previous.notice != current.notice,
      listener: (context, state) {
        _report(context, state.notice!);
        context.read<RecycleBinBloc>().add(const BinNoticeDismissed());
      },
      builder: (context, state) {
        final bloc = context.read<RecycleBinBloc>();

        return ModuleScaffold(
          title: AppDestination.recycleBin.label,
          subtitle: AppDestination.recycleBin.blurb,
          scrollable: false,
          // Only alongside a table. With nothing listed the empty state says the
          // same thing at full size, and two prompts to grant the same
          // permission read as a nag.
          banner:
              state.hasUnreadableLocation && !state.isEmpty
                  ? PermissionBanner(
                    message:
                        'macOS keeps the Trash behind Full Disk Access. Without '
                        'it ${Brand.name} cannot list what is in there, and the '
                        'figures on this page would be missing whatever it '
                        'cannot see — grant access, then reopen ${Brand.name}.',
                    onOpenSettings:
                        locator<FullDiskAccessService>().openSettings,
                  )
                  : null,
          actions: [
            TextButton.icon(
              onPressed:
                  state.status == RecycleBinStatus.loading || state.busy
                      ? null
                      : () => bloc.add(const LoadBin(silent: true)),
              icon: const Icon(AppIcons.refresh, size: 15),
              label: const Text('Refresh'),
            ),
            OutlinedButton.icon(
              onPressed:
                  state.isEmpty || state.busy
                      ? null
                      : () => _confirmEmpty(context, state),
              icon: const Icon(AppIcons.delete, size: 16),
              label: Text(
                state.locationId == null ? 'Empty Bin' : 'Empty This Bin',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.colors.risky,
                side: BorderSide(
                  color: context.colors.risky.withValues(alpha: 0.45),
                ),
              ),
            ),
          ],
          child: _body(context, state),
        );
      },
    );
  }

  Widget _body(BuildContext context, RecycleBinState state) {
    if (state.status == RecycleBinStatus.failed) {
      return EmptyState(
        icon: AppIcons.error,
        accent: context.colors.risky,
        title: 'That did not work',
        message: state.error,
        action: ElevatedButton(
          onPressed:
              () => context.read<RecycleBinBloc>().add(const LoadBin()),
          child: const Text('Try again'),
        ),
      );
    }

    if (state.status == RecycleBinStatus.initial ||
        state.status == RecycleBinStatus.loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: AppSpacing.lg),
            Text('Measuring what is in the Trash…', style: context.text.bodyM),
          ],
        ),
      );
    }

    if (state.isEmpty) return _emptyBin(context, state);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BinSummary(
          state: state,
          onShowStale:
              () => context.read<RecycleBinBloc>().add(
                const BinOldFilterToggled(),
              ),
        ),
        const SizedBox(height: AppSpacing.xl),
        _toolbar(context, state),
        const SizedBox(height: AppSpacing.md),
        Expanded(child: _table(context, state)),
      ],
    );
  }

  /// Nothing in there at all. Two very different reasons for that, and they
  /// must not read the same: an empty bin is a good outcome, an unreadable one
  /// is a permission the app has not been given.
  Widget _emptyBin(BuildContext context, RecycleBinState state) {
    if (state.hasUnreadableLocation) {
      return EmptyState(
        icon: AppIcons.locked,
        accent: context.colors.review,
        title: '${Brand.name} cannot see your Trash',
        message:
            'macOS keeps it behind Full Disk Access. Until that is granted this '
            'page would be reporting an empty bin it has never actually looked '
            'inside.',
        action: OutlinedButton(
          onPressed: locator<FullDiskAccessService>().openSettings,
          child: const Text('Open Settings'),
        ),
      );
    }

    return EmptyState(
      icon: AppIcons.recycleBin,
      accent: context.colors.safe,
      title: 'The bin is empty',
      message:
          'Nothing to put back, and nothing left to reclaim. That is a good '
          'sign, not a failed check.',
    );
  }

  Widget _toolbar(BuildContext context, RecycleBinState state) {
    final bloc = context.read<RecycleBinBloc>();

    return Row(
      children: [
        if (state.hasMultipleLocations)
          SegmentedTabs(
            labels: ['All', for (final location in state.locations) location.label],
            counts: [
              state.countIn(null),
              for (final location in state.locations) state.countIn(location.id),
            ],
            selectedIndex:
                state.locationId == null
                    ? 0
                    : state.locations.indexWhere(
                          (location) => location.id == state.locationId,
                        ) +
                        1,
            onChanged:
                (index) => bloc.add(
                  BinLocationChanged(
                    index == 0 ? null : state.locations[index - 1].id,
                  ),
                ),
          ),
        if (state.onlyOld) ...[
          if (state.hasMultipleLocations) const SizedBox(width: AppSpacing.md),
          _FilterPill(
            label: 'There over a month',
            onClear: () => bloc.add(const BinOldFilterToggled(value: false)),
          ),
        ],
        const Spacer(),
        AppSearchField(
          width: 260,
          hintText: 'Search the bin…',
          controller: _search,
          onChanged: (value) => bloc.add(BinSearchChanged(value)),
        ),
      ],
    );
  }

  Widget _table(BuildContext context, RecycleBinState state) {
    final colors = context.colors;
    final bloc = context.read<RecycleBinBloc>();
    final visible = state.visibleItems;

    final selectedOnScreen =
        visible.where((item) => state.selected.contains(item.path)).length;

    return Container(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DataTableHeader(
            columnLabels: const [],
            trailingWidth: TrashTableLayout.actions,
            showSelectAll: true,
            selectAllValue:
                selectedOnScreen == 0
                    ? false
                    : (selectedOnScreen == visible.length ? true : null),
            onSelectAll: (_) => bloc.add(const BinSelectAllToggled()),
            columns: [
              TableColumn(
                'ITEM',
                flex: TrashTableLayout.itemFlex,
                sort: _sortFor(state, TrashSort.name),
                onTap: () => bloc.add(const BinSortChanged(TrashSort.name)),
              ),
              const TableColumn(
                'CAME FROM',
                flex: TrashTableLayout.originFlex,
              ),
              TableColumn(
                'DELETED',
                width: TrashTableLayout.deleted,
                sort: _sortFor(state, TrashSort.deleted),
                onTap: () => bloc.add(const BinSortChanged(TrashSort.deleted)),
              ),
              TableColumn(
                'SIZE',
                width: TrashTableLayout.size,
                align: TextAlign.right,
                sort: _sortFor(state, TrashSort.size),
                onTap: () => bloc.add(const BinSortChanged(TrashSort.size)),
              ),
            ],
          ),
          Expanded(
            child:
                visible.isEmpty
                    ? EmptyState(
                      icon: AppIcons.nothingFound,
                      title:
                          state.query.isEmpty
                              ? 'Nothing matches this filter'
                              : 'Nothing matches “${state.query}”',
                      message:
                          state.query.isEmpty
                              ? 'There is still plenty in the bin — try the '
                                  'other tabs.'
                              : 'Search looks at the name and where it came '
                                  'from.',
                    )
                    // Built lazily: a Downloads folder emptied in one go can put
                    // several thousand rows in here.
                    : ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final item = visible[index];
                        return TrashTableRow(
                          key: ValueKey(item.path),
                          item: item,
                          selected: state.selected.contains(item.path),
                          enabled: !state.busy,
                          isLast: index == visible.length - 1,
                          onSelectionChanged:
                              (_) => bloc.add(BinSelectionToggled(item.path)),
                          onRestore: () => bloc.add(RestoreItems([item])),
                          onReveal: () => SystemBridge.revealInFinder(item.path),
                          onDelete: () => _confirmDelete(context, [item]),
                        );
                      },
                    ),
          ),
          BinActionBar(
            state: state,
            onRestore: () => bloc.add(RestoreItems(state.selectedItems)),
            onDelete: () => _confirmDelete(context, state.selectedItems),
            onClearSelection: () => bloc.add(const BinSelectionCleared()),
          ),
        ],
      ),
    );
  }

  SortDirection _sortFor(RecycleBinState state, TrashSort sort) =>
      state.sort == sort ? SortDirection.descending : SortDirection.none;

  // ─── Asking first ─────────────────────────────────────────────────────────

  Future<void> _confirmDelete(
    BuildContext context,
    List<TrashItem> items,
  ) async {
    if (items.isEmpty) return;
    final bytes = items.fold<int>(0, (sum, item) => sum + item.sizeBytes);

    final confirmed = await TidyAlert.confirm(
      context,
      title:
          items.length == 1
              ? 'Delete “${items.first.name}” permanently?'
              : 'Delete ${items.length} items permanently?',
      message:
          'This frees ${formatBytes(bytes)}. Nothing here can be recovered '
          'afterwards — not from the Trash, and not from ${Brand.name}.',
      confirmLabel: 'Delete Permanently',
      tone: FeedbackTone.danger,
      icon: AppIcons.delete,
      destructive: true,
      details: _preview(items),
    );

    if (!confirmed || !context.mounted) return;
    context.read<RecycleBinBloc>().add(DeleteItemsForever(items));
  }

  /// Empties the bin the user is looking at — every bin, or the one volume's,
  /// according to the tab. Deliberately not narrowed by the search box: a
  /// button that says "Empty Bin" and quietly leaves things behind is worse
  /// than one that says exactly how many are about to go, which the
  /// confirmation does.
  Future<void> _confirmEmpty(
    BuildContext context,
    RecycleBinState state,
  ) async {
    final items =
        state.locationId == null
            ? state.items
            : state.items
                .where((item) => item.locationId == state.locationId)
                .toList();
    if (items.isEmpty) return;

    final bytes = items.fold<int>(0, (sum, item) => sum + item.sizeBytes);
    final restorable = items.where((item) => item.canPutBack).length;

    final confirmed = await TidyAlert.confirm(
      context,
      title: 'Empty the bin?',
      message:
          'All ${items.length} items go for good, freeing ${formatBytes(bytes)}.'
          '${restorable > 0 ? ' $restorable of them could still be put back where they came from.' : ''}'
          ' Nothing here can be recovered afterwards.',
      confirmLabel: 'Empty Bin',
      tone: FeedbackTone.danger,
      icon: AppIcons.delete,
      destructive: true,
      details: _preview(items),
    );

    if (!confirmed || !context.mounted) return;
    context.read<RecycleBinBloc>().add(DeleteItemsForever(items));
  }

  /// The first few items by name, largest first, and an honest count of the
  /// rest. A dialog listing four hundred paths is one nobody reads.
  List<AlertDetail> _preview(List<TrashItem> items) {
    const shown = 5;
    final sorted = [...items]..sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));

    return [
      for (final item in sorted.take(shown))
        AlertDetail(
          title: item.name,
          detail:
              '${formatBytes(item.sizeBytes)} · '
              '${item.origin == null ? 'origin not known' : 'from ${collapseHome(item.origin!.originalParent, kHomeDir)}'}',
        ),
      if (sorted.length > shown)
        AlertDetail(
          title: 'and ${sorted.length - shown} more',
          monospace: false,
        ),
    ];
  }

  // ─── Saying what happened ─────────────────────────────────────────────────

  /// A clean result is a toast; a partial failure is an alert, because the user
  /// has to decide what to do about the parts that did not work.
  void _report(BuildContext context, RecycleBinNotice notice) {
    if (notice.details.isEmpty) {
      context.showToast(
        message: notice.message,
        title: notice.title,
        tone: notice.tone,
      );
      return;
    }

    TidyAlert.notify(
      context,
      title: notice.title ?? 'Some of that did not work',
      message: notice.message,
      tone: notice.tone,
      details: [
        for (final detail in notice.details)
          AlertDetail(
            title: collapseHome(detail.path, kHomeDir),
            detail: detail.error,
            tone: FeedbackTone.danger,
          ),
      ],
    );
  }
}

/// A filter that is on and can be taken off again.
///
/// Without this the summary tile is a trap: it silently narrows the table, and
/// the only way back is to notice the tile is highlighted and click it again.
class _FilterPill extends StatelessWidget {
  const _FilterPill({required this.label, required this.onClear});

  final String label;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.only(left: AppSpacing.md, right: AppSpacing.xs),
      height: 30,
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: AppRadii.smAll,
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: context.text.label),
          IconButton(
            icon: const Icon(AppIcons.close, size: 13),
            color: colors.textMuted,
            tooltip: 'Show everything again',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            padding: EdgeInsets.zero,
            onPressed: onClear,
          ),
        ],
      ),
    );
  }
}

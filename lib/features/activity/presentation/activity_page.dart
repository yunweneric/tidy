import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/di/service_locator.dart';
import 'package:tidy/core/store/models/store_models.dart';
import 'package:tidy/core/store/tidy_store.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/features/activity/domain/activity_range.dart';
import 'package:tidy/features/activity/logic/activity_bloc.dart';
import 'package:tidy/features/activity/presentation/widgets/activity_file_table.dart';
import 'package:tidy/features/activity/presentation/widgets/activity_operation_row.dart';
import 'package:tidy/features/shell/domain/app_destination.dart';

/// What Tidy has done, and what it removed doing it.
///
/// The store has recorded every operation and every file since it arrived, and
/// until now nothing read the per-file half of it: the Dashboard shows the last
/// eight runs and a month of totals, which answers "is it working" and not "what
/// happened to that file". This is the other question — the one a cleaner has to
/// be able to answer to be trusted with a disk.
///
/// Two views of one record, because the two questions have different shapes. The
/// **operations** feed is what Tidy did, one row per run, opening onto the files
/// that run touched. The **files** list is the audit: every removal, newest
/// first, searchable by name or path.
class ActivityPage extends StatelessWidget {
  const ActivityPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create:
          (_) => ActivityBloc(locator<TidyStore>())..add(const LoadActivity()),
      child: const _ActivityView(),
    );
  }
}

class _ActivityView extends StatelessWidget {
  const _ActivityView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ActivityBloc, ActivityState>(
      builder: (context, state) {
        final bloc = context.read<ActivityBloc>();

        return ModuleScaffold(
          title: AppDestination.activity.label,
          subtitle: AppDestination.activity.blurb,
          scrollable: false,
          actions: [
            TextButton.icon(
              onPressed:
                  state.isLoading
                      ? null
                      : () => bloc.add(const LoadActivity(silent: true)),
              icon: const Icon(AppIcons.refresh, size: 15),
              label: const Text('Refresh'),
            ),
          ],
          child: switch (state.status) {
            ActivityStatus.initial => const SizedBox.shrink(),
            _ when state.isEmpty => _empty(context, state),
            _ => _body(context, state, bloc),
          },
        );
      },
    );
  }

  /// Nothing recorded — which is a different fact depending on the range, and
  /// the copy has to say which. "You have not cleaned anything this week" and
  /// "Tidy has never removed anything" are not the same message.
  Widget _empty(BuildContext context, ActivityState state) => EmptyState(
    icon: AppIcons.activity,
    title:
        state.range == ActivityRange.all
            ? 'Nothing recorded yet'
            : 'Nothing in the last ${state.range.label.toLowerCase()}',
    message:
        state.range == ActivityRange.all
            ? 'Everything ${Brand.name} removes is written down here — what it '
                'was, where it lived, how big it was, and whether it went to '
                'the Trash or straight out. Run a cleanup and this fills in.'
            : 'Nothing was removed in this range. Try a longer one.',
  );

  Widget _body(BuildContext context, ActivityState state, ActivityBloc bloc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Totals(state: state),
        const SizedBox(height: AppSpacing.lg),
        _Toolbar(state: state, bloc: bloc),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: FadeThrough(
            trigger: state.view,
            child: switch (state.view) {
              ActivityView.operations => _OperationsFeed(state: state),
              ActivityView.files => ActivityFileTable(state: state),
            },
          ),
        ),
      ],
    );
  }
}

/// What the range came to, in the two figures that are not interchangeable.
class _Totals extends StatelessWidget {
  const _Totals({required this.state});

  final ActivityState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final totals = state.totals;

    return Row(
      children: [
        Expanded(
          child: StatTile(
            label: 'Freed',
            value: formatBytes(state.freedBytes),
            detail: 'Deleted outright — space you have back',
            icon: AppIcons.cleanup,
            color: colors.safe,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: StatTile(
            label: 'In the Trash',
            // The figure this page is most likely to be misread over, so it
            // says what it is on the tile rather than in a footnote: bytes in
            // the Trash are not bytes back until the Trash is emptied.
            value: formatBytes(state.trashedBytes),
            detail: 'Recoverable, and not freed until emptied',
            icon: AppIcons.recycleBin,
            color: colors.review,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: StatTile(
            label: 'Items',
            value: formatCount(totals.itemCount),
            detail: 'Files and folders removed',
            icon: AppIcons.document,
            color: colors.info,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: StatTile(
            label: 'Runs',
            value: formatCount(totals.operationCount),
            detail: 'Cleanups, uninstalls and upkeep',
            icon: AppIcons.activity,
            color: colors.accent,
          ),
        ),
      ],
    );
  }
}

/// View switch, range, and — in the files view — the search and category pills.
class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.state, required this.bloc});

  final ActivityState state;
  final ActivityBloc bloc;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SegmentedTabs(
              labels: const ['Operations', 'Files'],
              counts: [state.operations.length, state.items.length],
              selectedIndex: state.view.index,
              onChanged:
                  (index) =>
                      bloc.add(ActivityViewChanged(ActivityView.values[index])),
            ),
            const Spacer(),
            if (state.view == ActivityView.files) ...[
              AppSearchField(
                hintText: 'Search removed files…',
                width: 260,
                onChanged: (value) => bloc.add(ActivitySearchChanged(value)),
              ),
              const SizedBox(width: AppSpacing.md),
            ],
            _RangePicker(state: state, bloc: bloc),
          ],
        ),
        // Category pills, and only where they filter something. The operations
        // feed is not a list of files, so a file-category filter above it would
        // be a control with nothing under it.
        if (state.view == ActivityView.files &&
            state.categories.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final category in state.categories)
                _CategoryPill(
                  label: category.category,
                  bytes: category.bytes,
                  selected: state.category == category.category,
                  onTap:
                      () =>
                          bloc.add(ActivityCategoryChanged(category.category)),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _RangePicker extends StatelessWidget {
  const _RangePicker({required this.state, required this.bloc});

  final ActivityState state;
  final ActivityBloc bloc;

  @override
  Widget build(BuildContext context) => SegmentedTabs(
    labels: [for (final range in ActivityRange.values) range.label],
    selectedIndex: state.range.index,
    onChanged:
        (index) => bloc.add(ActivityRangeChanged(ActivityRange.values[index])),
  );
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({
    required this.label,
    required this.bytes,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int bytes;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: context.motion.fast,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm - 2,
          ),
          decoration: BoxDecoration(
            color: selected ? colors.accentMuted : colors.surface,
            borderRadius: AppRadii.pillAll,
            border: Border.all(color: selected ? colors.accent : colors.border),
          ),
          child: Text(
            '$label · ${formatBytes(bytes)}',
            style: context.text.caption.copyWith(
              color: selected ? colors.accent : colors.textSecondary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// The operations feed, newest first, grouped under the day they ran.
class _OperationsFeed extends StatelessWidget {
  const _OperationsFeed({required this.state});

  final ActivityState state;

  @override
  Widget build(BuildContext context) {
    final operations = state.operations;
    if (operations.isEmpty) {
      return EmptyState(
        icon: AppIcons.activity,
        title: 'No runs recorded',
        message:
            'Nothing ${Brand.name} did in this range. The Files view may still '
            'have removals from an operation that has since been trimmed.',
      );
    }

    // Grouped by day rather than listed flat: a history is read by "when", and
    // twenty rows with twenty datestamps makes the reader do the grouping.
    final days = <DateTime, List<OperationSummary>>{};
    for (final operation in operations) {
      final at = operation.startedAt;
      final day = DateTime(at.year, at.month, at.day);
      (days[day] ??= []).add(operation);
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      children: [
        for (final entry in days.entries) ...[
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.sm,
              bottom: AppSpacing.sm,
            ),
            child: Text(_dayLabel(entry.key), style: context.text.overline),
          ),
          for (final operation in entry.value)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: ActivityOperationRow(
                operation: operation,
                expanded: state.expandedOperationId == operation.id,
                items: state.operationItems,
                onToggle:
                    () => context.read<ActivityBloc>().add(
                      ActivityOperationToggled(operation.id),
                    ),
              ),
            ),
        ],
        if (state.retentionReached)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Text(
              'Older per-file records have been trimmed to keep the history '
              'small. The runs above are still complete.',
              style: context.text.caption.copyWith(
                color: context.colors.textMuted,
              ),
            ),
          ),
      ],
    );
  }

  static String _dayLabel(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final difference = today.difference(day).inDays;

    return switch (difference) {
      0 => 'TODAY',
      1 => 'YESTERDAY',
      < 7 => '$difference DAYS AGO',
      _ =>
        '${day.day.toString().padLeft(2, '0')}/'
            '${day.month.toString().padLeft(2, '0')}/${day.year}',
    };
  }
}

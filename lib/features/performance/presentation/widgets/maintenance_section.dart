import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/features/performance/data/models/maintenance_task.dart';
import 'package:tidy/features/performance/logic/performance_bloc.dart';
import 'package:tidy/features/performance/logic/performance_event.dart';
import 'package:tidy/features/performance/logic/performance_state.dart';

/// Routine macOS upkeep.
///
/// Most of these want root, and Tidy does not have it yet. They are still
/// listed, marked, and explained rather than hidden — a maintenance page that
/// silently shows only two of eight tasks looks like a thin feature; one that
/// shows all eight and says which are waiting on administrator rights is an
/// honest account of where the app is.
class MaintenanceSection extends StatelessWidget {
  const MaintenanceSection({super.key, required this.state});

  final PerformanceState state;

  @override
  Widget build(BuildContext context) {
    final runnable = state.tasks.where((task) => task.runnable).length;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Text(
          'One-off jobs that fix a specific problem. None of them touch your '
          'files — they rebuild caches and indexes macOS maintains for itself.',
          style: context.text.bodyM,
        ),
        if (runnable < state.tasks.length) ...[
          const SizedBox(height: AppSpacing.md),
          _AdminNote(waiting: state.tasks.length - runnable),
        ],
        const SizedBox(height: AppSpacing.lg),
        if (state.tasks.isEmpty)
          const EmptyState(
            icon: AppIcons.maintenance,
            title: 'No maintenance tasks available',
            message:
                'Tidy could not find any of the tools macOS normally ships '
                'these with.',
          )
        else
          for (final task in state.tasks) ...[
            _TaskCard(task: task, busy: state.isBusy(task.id)),
            const SizedBox(height: AppSpacing.md),
          ],
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}

class _AdminNote extends StatelessWidget {
  const _AdminNote({required this.waiting});

  final int waiting;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return TidyCard(
      accent: colors.review,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Icon(AppIcons.locked, size: 17, color: colors.review),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              '$waiting of these change things macOS only lets an administrator '
              'change. Tidy will not ask you for your password to run a one-off '
              'command — that is coming as a properly signed helper instead.',
              style: context.text.bodyM,
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, required this.busy});

  final MaintenanceTask task;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = task.runnable && !busy;
    final tint = enabled ? colors.accent : colors.textMuted;

    return TidyCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.13),
              borderRadius: AppRadii.mdAll,
            ),
            child: Icon(AppIcons.maintenance, size: 17, color: tint),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        task.title,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.titleS,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    if (task.requiresAdmin)
                      StatusChip(
                        label: 'Needs administrator',
                        color: colors.review,
                        icon: AppIcons.locked,
                      )
                    else if (!task.available)
                      StatusChip(
                        label: 'Unavailable',
                        color: colors.textMuted,
                        icon: AppIcons.info,
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(task.description, style: context.text.bodyM),
                if (!task.available && task.unavailableReason != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    task.unavailableReason!,
                    style: context.text.caption.copyWith(color: colors.review),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          SizedBox(
            width: 110,
            child: Align(
              alignment: Alignment.centerRight,
              child:
                  busy
                      ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : OutlinedButton(
                        onPressed:
                            enabled
                                ? () => context.read<PerformanceBloc>().add(
                                  RunMaintenanceTask(task),
                                )
                                : null,
                        child: Text(task.actionLabel),
                      ),
            ),
          ),
        ],
      ),
    );
  }
}

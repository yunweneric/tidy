import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/core/models/launch_item.dart';
import 'package:tidy/features/performance/logic/performance_bloc.dart';
import 'package:tidy/features/performance/logic/performance_event.dart';
import 'package:tidy/features/performance/logic/performance_state.dart';
import 'package:tidy/features/performance/presentation/widgets/launch_item_row.dart';
import 'package:tidy/features/performance/presentation/widgets/remove_launch_item_dialog.dart';

/// A list of launchd jobs — used for both Login Items and Background Items.
///
/// One widget for both because they differ only in copy and in whether the
/// controls do anything. Writing a second, nearly identical list is how two
/// screens drift apart on spacing and wording.
class LaunchItemsSection extends StatelessWidget {
  const LaunchItemsSection({
    super.key,
    required this.state,
    required this.items,
    required this.explanation,
    required this.emptyTitle,
    required this.emptyMessage,
    this.footer,
  });

  final PerformanceState state;
  final List<LaunchItem> items;

  /// What this list is, before the user has to work it out from the rows.
  final String explanation;

  final String emptyTitle;
  final String emptyMessage;

  /// Anything that has to be said after the list — the note about login items
  /// macOS will not let us enumerate, for instance.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final broken =
        items.where((item) => item.health == LaunchItemHealth.broken).toList();

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _Explainer(text: explanation),
        if (broken.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _BrokenSummary(count: broken.length),
        ],
        const SizedBox(height: AppSpacing.lg),
        if (items.isEmpty)
          EmptyState(
            icon: AppIcons.nothingFound,
            title: emptyTitle,
            message: emptyMessage,
          )
        else
          TidyCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++)
                  LaunchItemRow(
                    item: items[i],
                    icon:
                        items[i].appPath == null
                            ? null
                            : state.icons[items[i].appPath],
                    busy: state.isBusy(items[i].path),
                    isLast: i == items.length - 1,
                    onToggle:
                        (enabled) => context.read<PerformanceBloc>().add(
                          SetLaunchItemEnabled(items[i], enabled: enabled),
                        ),
                    onRemove: () => _confirmRemove(context, items[i]),
                  ),
              ],
            ),
          ),
        if (footer != null) ...[const SizedBox(height: AppSpacing.lg), footer!],
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }

  Future<void> _confirmRemove(BuildContext context, LaunchItem item) async {
    final bloc = context.read<PerformanceBloc>();
    final confirmed = await showRemoveLaunchItemDialog(context, item);
    if (confirmed) bloc.add(RemoveLaunchItem(item));
  }
}

class _Explainer extends StatelessWidget {
  const _Explainer({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: context.text.bodyM);
  }
}

/// The one finding on this page with an unambiguous recommendation.
///
/// An agent whose program no longer exists cannot start anything and nothing
/// depends on the leftover, which is why it is the only launch item this app is
/// willing to describe as safe to remove.
class _BrokenSummary extends StatelessWidget {
  const _BrokenSummary({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return TidyCard(
      accent: colors.safe,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Icon(AppIcons.safe, size: 17, color: colors.safe),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              count == 1
                  ? 'One item cannot start anything — the program it points at is '
                      'gone, or the file is empty. It is safe to remove.'
                  : '$count items cannot start anything — the programs they point '
                      'at are gone, or the files are empty. They are safe to remove.',
              style: context.text.bodyM,
            ),
          ),
        ],
      ),
    );
  }
}

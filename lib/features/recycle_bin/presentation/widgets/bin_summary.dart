import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/features/recycle_bin/logic/recycle_bin_state.dart';

/// The three figures worth reading before the table: how much is in there, what
/// it is holding on to, and how much of it has been there long enough to let go
/// of.
class BinSummary extends StatelessWidget {
  const BinSummary({super.key, required this.state, required this.onShowStale});

  final RecycleBinState state;

  /// Filters the table down to the long-forgotten items.
  final VoidCallback onShowStale;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final stale = state.staleItems;

    return Row(
      children: [
        Expanded(
          child: StatTile(
            label:
                state.items.length == 1
                    ? 'Item in the bin'
                    : 'Items in the bin',
            value: '${state.items.length}',
            icon: AppIcons.recycleBin,
            color: colors.accent,
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: StatTile(
            label: 'Space you would get back',
            value: formatBytes(state.totalBytes),
            icon: AppIcons.storage,
            color: colors.info,
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: StatTile(
            label: 'There over a month',
            value: '${stale.length}',
            icon: AppIcons.activity,
            // Nothing sitting around is a good result, not an absent one.
            color: stale.isEmpty ? colors.safe : colors.review,
            onTap: stale.isEmpty ? null : onShowStale,
            selected: state.onlyOld,
          ),
        ),
      ],
    );
  }
}

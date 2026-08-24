import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';
import 'package:mac_uninstaller/core/utils/byte_format.dart';
import 'package:mac_uninstaller/core/widgets/widgets.dart';
import 'package:mac_uninstaller/features/recycle_bin/logic/recycle_bin_state.dart';

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
          child: _Stat(
            label: state.items.length == 1 ? 'Item in the bin' : 'Items in the bin',
            value: '${state.items.length}',
            icon: AppIcons.recycleBin,
            color: colors.accent,
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: _Stat(
            label: 'Space you would get back',
            value: formatBytes(state.totalBytes),
            icon: AppIcons.storage,
            color: colors.info,
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: _Stat(
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

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
    this.selected = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return TidyCard(
      onTap: onTap,
      accent: color,
      selected: selected,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconTile(icon: icon, color: color),
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

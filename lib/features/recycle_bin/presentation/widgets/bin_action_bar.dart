import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/features/recycle_bin/logic/recycle_bin_state.dart';

/// The strip under the table: what is in front of you, what you have picked,
/// and the two things you can do with it.
class BinActionBar extends StatelessWidget {
  const BinActionBar({
    super.key,
    required this.state,
    required this.onRestore,
    required this.onDelete,
    required this.onClearSelection,
  });

  final RecycleBinState state;
  final VoidCallback onRestore;
  final VoidCallback onDelete;
  final VoidCallback onClearSelection;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final selection = state.selectedItems;
    final hasSelection = selection.isNotEmpty;
    final enabled = hasSelection && !state.busy;

    // Every selected item has a recorded origin, so "Put Back" is a promise the
    // app can keep. With even one unknown among them the label has to admit
    // that a folder is going to be asked for.
    final allKnown = hasSelection && selection.every((item) => item.canPutBack);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              hasSelection
                  ? '${selection.length} selected · ${formatBytes(state.selectedBytes)}'
                  : '${state.visibleItems.length} shown · ${formatBytes(state.visibleBytes)}',
              style: context.text.bodyM,
            ),
          ),
          if (hasSelection) ...[
            TextButton(
              onPressed: state.busy ? null : onClearSelection,
              child: const Text('Clear'),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          OutlinedButton.icon(
            onPressed: enabled ? onRestore : null,
            icon: Icon(allKnown ? AppIcons.putBack : AppIcons.restore, size: 16),
            label: Text(allKnown ? 'Put Back' : 'Restore…'),
          ),
          const SizedBox(width: AppSpacing.sm),
          // Solid red is reserved for the confirmation dialog. A permanent
          // delete sitting on the page in full colour invites the click it
          // should be discouraging.
          OutlinedButton.icon(
            onPressed: enabled ? onDelete : null,
            icon: const Icon(AppIcons.delete, size: 16),
            label: const Text('Delete Permanently'),
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.risky,
              side: BorderSide(color: colors.risky.withValues(alpha: 0.45)),
            ),
          ),
        ],
      ),
    );
  }
}

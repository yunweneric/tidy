import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/landing/preview/preview_chrome.dart';
import 'package:tidy/landing/preview/preview_mac.dart';

/// See what is in the Trash, put things back, or clear it for good.
///
/// The only place in the app that deletes irreversibly, and the only place in
/// the preview where the free-space bar actually moves.
class PreviewRecycleBinPane extends StatelessWidget {
  const PreviewRecycleBinPane({super.key, required this.mac});

  final PreviewMac mac;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final items = mac.trash;

    return ModuleScaffold(
      title: PreviewScreen.recycleBin.label,
      subtitle: PreviewScreen.recycleBin.blurb,
      actions: [
        if (items.isNotEmpty)
          OutlineActionButton(
            label: 'Empty Trash',
            icon: AppIcons.delete,
            onPressed: mac.emptyTrash,
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: 'In the Trash',
                  value: formatBytes(mac.trashBytes),
                  detail: '${items.length} items',
                  icon: AppIcons.recycleBin,
                  color: colors.review,
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: StatTile(
                  label: 'Older than a month',
                  value: '${mac.staleTrashCount}',
                  detail: 'Safe to clear, probably forgotten',
                  icon: AppIcons.activity,
                  color: colors.textMuted,
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: StatTile(
                  label: 'Reclaimed this session',
                  value: formatBytes(mac.reclaimedBytes),
                  detail: 'Actually returned to the disk',
                  icon: AppIcons.safe,
                  color: colors.safe,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          if (items.isEmpty)
            const EmptyState(
              icon: AppIcons.recycleBin,
              title: 'The Trash is empty',
              message:
                  'Everything Tidy moved here has been cleared, and the space '
                  'is back on the disk.',
            )
          else
            PreviewTable(
              header: const PreviewTableHeader(
                cells: [(8, 'Item'), (4, 'Deleted'), (3, 'Size'), (3, '')],
              ),
              rows: [
                for (var i = 0; i < items.length; i++)
                  _TrashRow(
                    mac: mac,
                    item: items[i],
                    last: i == items.length - 1,
                  ),
              ],
            ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Icon(AppIcons.risky, size: 14, color: colors.risky),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Emptying is the one thing here that cannot be undone, so it '
                  'always sits behind a confirmation naming the count and the '
                  'size. Everything else is a Put Back away.',
                  style: context.text.caption,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrashRow extends StatelessWidget {
  const _TrashRow({required this.mac, required this.item, required this.last});

  final PreviewMac mac;
  final PreviewTrashItem item;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return PreviewRow(
      last: last,
      onTap: () => mac.putBack(item),
      child: Row(
        children: [
          Expanded(
            flex: 8,
            child: Row(
              children: [
                Icon(AppIcons.trash, size: 15, color: colors.textMuted),
                const SizedBox(width: AppSpacing.md),
                Flexible(
                  child: Text(
                    item.name,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.titleS,
                  ),
                ),
                if (item.stale) ...[
                  const SizedBox(width: AppSpacing.sm),
                  StatusChip(label: 'Stale', color: colors.textMuted),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(item.deleted, style: context.text.bodyM),
          ),
          Expanded(
            flex: 3,
            child: Text(
              formatBytes(item.bytes),
              style: context.text.titleS.copyWith(color: colors.textSecondary),
            ),
          ),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(AppIcons.putBack, size: 15, color: colors.accent),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Put back',
                    style: context.text.caption.copyWith(color: colors.accent),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

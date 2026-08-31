import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/store/models/store_models.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/widgets/widgets.dart';

/// One recorded run, and — when opened — the files it removed.
///
/// The files are the point. A row saying "Cleanup · 1.2 GB · 340 items" is a
/// receipt with no line items on it, and the question anyone brings to a
/// cleaner's history is about one particular file.
class ActivityOperationRow extends StatelessWidget {
  const ActivityOperationRow({
    super.key,
    required this.operation,
    required this.expanded,
    required this.items,
    required this.onToggle,
  });

  final OperationSummary operation;
  final bool expanded;

  /// The removed files, loaded only while this row is the open one.
  final List<RemovedItemRecord> items;

  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return TidyCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context),
          if (expanded) ...[
            Divider(height: 1, color: colors.border),
            _files(context),
          ],
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final colors = context.colors;
    final text = context.text;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onToggle,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: colors.surfaceRaised,
                  borderRadius: AppRadii.smAll,
                ),
                alignment: Alignment.center,
                child: Icon(
                  _glyph(operation.kind),
                  size: 15,
                  color: colors.textMuted,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            operation.label,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleS,
                          ),
                        ),
                        if (operation.module case final module?) ...[
                          const SizedBox(width: AppSpacing.sm),
                          Text(module, style: text.caption),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      _subtitle(),
                      style: text.bodyS.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              // Two figures, never added together. Trashed bytes are not freed
              // bytes, and one number covering both would be the page's
              // central claim being wrong.
              if (operation.bytesDeleted > 0)
                _Figure(
                  value: formatBytes(operation.bytesDeleted),
                  label: 'freed',
                  color: colors.safe,
                ),
              if (operation.bytesTrashed > 0) ...[
                const SizedBox(width: AppSpacing.lg),
                _Figure(
                  value: formatBytes(operation.bytesTrashed),
                  label: 'to Trash',
                  color: colors.review,
                ),
              ],
              const SizedBox(width: AppSpacing.md),
              if (operation.failureCount > 0) ...[
                StatusChip(
                  label: '${operation.failureCount} failed',
                  color: colors.risky,
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              // Said on the run it applies to rather than once at the top of
              // the page: a run that could not see part of the disk removed
              // less than it looks like it did, and that is a fact about that
              // run.
              if (operation.permissionLimited) ...[
                StatusChip(
                  label: 'Partial',
                  color: colors.review,
                  icon: AppIcons.locked,
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              AnimatedRotation(
                turns: expanded ? 0.25 : 0,
                duration: context.motion.fast,
                child: Icon(
                  AppIcons.collapse,
                  size: 16,
                  color: colors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _files(BuildContext context) {
    final colors = context.colors;

    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(
          // The operation totals survive the trim, so a run can honestly say it
          // removed 340 items and have no rows left to list. Better said than
          // shown as an empty box.
          operation.itemCount > 0
              ? 'The per-file records for this run have been trimmed. The '
                  'totals above are still what it did.'
              : 'This run removed nothing.',
          style: context.text.bodyS.copyWith(color: colors.textSecondary),
        ),
      );
    }

    return ConstrainedBox(
      // Capped rather than unbounded: an operation can carry thousands of rows,
      // and a card that grows to the height of all of them makes the feed
      // unscrollable past it.
      constraints: const BoxConstraints(maxHeight: 320),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        itemCount: items.length,
        separatorBuilder: (_, _) => Divider(height: 1, color: colors.border),
        itemBuilder: (context, index) => ActivityFileRow(item: items[index]),
      ),
    );
  }

  String _subtitle() {
    final at = operation.startedAt;
    final clock =
        '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
    final items =
        '${formatCount(operation.itemCount)} '
        '${operation.itemCount == 1 ? 'item' : 'items'}';

    final duration = operation.duration;
    if (duration == null) {
      // No finish time: the app was quit or crashed mid-run. Worth showing as
      // what it is rather than as a run with a blank duration.
      return '$clock · $items · did not finish';
    }
    return '$clock · $items · ${_took(duration)}';
  }

  static String _took(Duration duration) {
    if (duration.inSeconds < 1) return 'under a second';
    if (duration.inSeconds < 60) return '${duration.inSeconds}s';
    return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
  }

  static IconData _glyph(OperationKind kind) => switch (kind) {
    OperationKind.cleanup => AppIcons.cleanup,
    OperationKind.uninstall => AppIcons.applications,
    OperationKind.emptyTrash => AppIcons.trash,
    OperationKind.putBack => AppIcons.putBack,
    OperationKind.maintenance => AppIcons.maintenance,
  };
}

/// One removed file: what it was, where it lived, and what happened to it.
class ActivityFileRow extends StatelessWidget {
  const ActivityFileRow({super.key, required this.item, this.showWhen = false});

  final RemovedItemRecord item;

  /// Whether to stamp the row with its time. On in the flat audit list, off
  /// inside an operation — every row there shares the run's own timestamp.
  final bool showWhen;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyM.copyWith(
                    // A restored file is still part of the record — struck
                    // through rather than dropped, because "it was removed and
                    // then put back" is the answer someone is looking for.
                    decoration:
                        item.restored ? TextDecoration.lineThrough : null,
                    color:
                        item.restored ? colors.textMuted : colors.textPrimary,
                  ),
                ),
                Text(
                  item.path,
                  overflow: TextOverflow.ellipsis,
                  style: text.caption.copyWith(color: colors.textMuted),
                ),
              ],
            ),
          ),
          if (item.category case final category?) ...[
            const SizedBox(width: AppSpacing.md),
            SizedBox(
              width: 110,
              child: Text(
                category,
                overflow: TextOverflow.ellipsis,
                style: text.caption.copyWith(color: colors.textSecondary),
              ),
            ),
          ],
          const SizedBox(width: AppSpacing.md),
          SizedBox(
            width: 96,
            child: Text(
              item.trashed ? 'To Trash' : 'Deleted',
              style: text.caption.copyWith(
                color: item.trashed ? colors.review : colors.safe,
              ),
            ),
          ),
          if (showWhen) ...[
            const SizedBox(width: AppSpacing.md),
            SizedBox(
              width: 104,
              child: Text(
                _when(item.at),
                style: text.caption.copyWith(color: colors.textMuted),
              ),
            ),
          ],
          const SizedBox(width: AppSpacing.md),
          SizedBox(
            width: 84,
            child: Text(
              formatBytes(item.sizeBytes),
              textAlign: TextAlign.right,
              style: text.bodyS.copyWith(color: colors.textSecondary),
            ),
          ),
          if (item.restored) ...[
            const SizedBox(width: AppSpacing.sm),
            StatusChip(label: 'Put back', color: colors.info),
          ],
        ],
      ),
    );
  }

  static String _when(DateTime at) =>
      '${at.day.toString().padLeft(2, '0')}/'
      '${at.month.toString().padLeft(2, '0')} '
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';
}

/// A figure with its unit under it, for the two byte totals on a run.
class _Figure extends StatelessWidget {
  const _Figure({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(value, style: context.text.titleS.copyWith(color: color)),
      Text(label, style: context.text.caption),
    ],
  );
}

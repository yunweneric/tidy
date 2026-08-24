import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/store/models/store_models.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/features/dashboard/logic/dashboard_state.dart';

/// What Tidy has done lately.
///
/// The first time the app has been able to answer that at all: before the
/// history store, every outcome lived for one bloc emission and was thrown away.
class RecentActivity extends StatelessWidget {
  const RecentActivity({super.key, required this.state});

  final DashboardState state;

  @override
  Widget build(BuildContext context) {
    final operations = state.recentOperations;

    return TidyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('RECENT ACTIVITY', style: context.text.overline),
          const SizedBox(height: AppSpacing.md),
          if (operations.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Text(
                'Nothing yet. Anything Tidy removes from here on is listed '
                'here, with what it was and how much it came to.',
                style: context.text.bodyM,
              ),
            )
          else
            for (final operation in operations)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _OperationRow(operation: operation),
              ),
        ],
      ),
    );
  }
}

class _OperationRow extends StatelessWidget {
  const _OperationRow({required this.operation});

  final OperationSummary operation;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final trashed = operation.bytesTrashed > 0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: colors.surfaceRaised,
            borderRadius: AppRadii.smAll,
          ),
          alignment: Alignment.center,
          child: Icon(_glyph(operation.kind), size: 15, color: colors.textMuted),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                operation.label,
                style: context.text.titleS,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                '${operation.kind.label} · ${operation.itemCount} items · '
                '${_ago(operation.startedAt)}'
                '${operation.failureCount > 0 ? ' · ${operation.failureCount} refused' : ''}',
                style: context.text.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatBytes(operation.bytesTotal),
              style: context.text.titleS,
            ),
            const SizedBox(height: AppSpacing.xxs),
            // Never just "freed". Something moved to the Trash is still on the
            // disk until the Trash is emptied, and the row has to say which of
            // the two happened.
            Text(
              trashed ? 'moved to Trash' : 'freed',
              style: context.text.caption.copyWith(
                color: trashed ? colors.review : colors.safe,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static IconData _glyph(OperationKind kind) => switch (kind) {
    OperationKind.cleanup => AppIcons.cleanup,
    OperationKind.uninstall => AppIcons.applications,
    OperationKind.emptyTrash => AppIcons.recycleBin,
    OperationKind.putBack => AppIcons.restore,
    OperationKind.maintenance => AppIcons.performance,
  };

  static String _ago(DateTime at) {
    final delta = DateTime.now().difference(at);
    if (delta.inMinutes < 1) return 'just now';
    if (delta.inMinutes < 60) return '${delta.inMinutes} min ago';
    if (delta.inHours < 24) return '${delta.inHours} h ago';
    if (delta.inDays == 1) return 'yesterday';
    if (delta.inDays < 30) return '${delta.inDays} days ago';
    if (delta.inDays < 365) return '${delta.inDays ~/ 30} months ago';
    return '${(delta.inDays / 365).toStringAsFixed(1)} years ago';
  }
}

/// Proportional bars for the things worth breaking down.
class CompositionCard extends StatelessWidget {
  const CompositionCard({
    super.key,
    required this.title,
    required this.rows,
    this.emptyMessage = 'Nothing to show yet.',
    this.color,
    this.filled = false,
  });

  final String title;
  final List<({String label, int bytes, String detail})> rows;
  final String emptyMessage;
  final Color? color;

  /// Whether this card is being stretched to a height its own content did not
  /// ask for — true when it shares a row with fuller siblings.
  ///
  /// It only changes the empty state, which is the case that suffers: one line
  /// of text pinned to the top of a box sized by a neighbour's five rows reads
  /// as a card that failed to load rather than one with nothing to say.
  /// Centred in the space, it reads as deliberate.
  ///
  /// A flag rather than always centring, because centring needs a flex child
  /// to claim the leftover height, and the stacked layout drops these cards
  /// straight into a scrolling column where the height is unbounded — a flex
  /// child of an unbounded column throws in layout.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tone = color ?? colors.accent;
    final peak = rows.isEmpty
        ? 0
        : rows.map((r) => r.bytes).reduce((a, b) => a > b ? a : b);

    return TidyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: context.text.overline),
          const SizedBox(height: AppSpacing.md),
          if (rows.isEmpty)
            _emptyState(context)
          else
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            row.label,
                            style: context.text.bodyM.copyWith(
                              color: colors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(row.detail, style: context.text.caption),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    SizeBar(
                      fraction: peak == 0 ? 0 : row.bytes / peak,
                      color: tone,
                      height: 4,
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  /// The message, centred into the leftover height when there is any.
  Widget _emptyState(BuildContext context) {
    final message = Text(
      emptyMessage,
      style: context.text.bodyM,
      textAlign: filled ? TextAlign.center : TextAlign.start,
    );
    if (!filled) return message;
    return Expanded(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: message,
        ),
      ),
    );
  }
}

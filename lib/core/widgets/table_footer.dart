import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/widgets/pagination_bar.dart';

/// The bar under a table: what it is showing on the left, which page of it on
/// the right.
///
/// The two ends are the point. A summary that has drifted into the middle of
/// the row reads as a caption for the pager rather than as a fact about the
/// table, and a pager that stops short of the edge reads as an accident.
class TableFooter extends StatelessWidget {
  const TableFooter({
    super.key,
    required this.summary,
    required this.currentPage,
    required this.totalPages,
    required this.onPageChanged,
    this.divider = false,
  });

  /// Usually a line of text: how many rows, and what they come to.
  final Widget summary;

  /// 1-based.
  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onPageChanged;

  /// Draws a hairline above the footer, for a table whose rows run right into
  /// it. A footer under a card that has already ended does not need one.
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          // One flex child, claiming the whole gap. A Flexible beside a Spacer
          // carries the same flex as the Spacer does, so the row splits the
          // free width between them and leaves a margin of it stranded after
          // the pager — which is how the pager ends up short of the edge.
          Expanded(child: summary),
          // A single page has nothing to navigate. Drawing "Previous 1 Next"
          // over a table that fits on one screen is furniture, not a control.
          if (totalPages > 1)
            PaginationBar(
              currentPage: currentPage,
              totalPages: totalPages,
              onPageChanged: onPageChanged,
            ),
        ],
      ),
    );

    if (!divider) return content;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.colors.border)),
      ),
      child: content,
    );
  }
}

/// The usual summary: a count, and something it comes to.
///
/// Bolds the figures and leaves the words around them quiet, so the numbers
/// are what the eye lands on.
class TableSummary extends StatelessWidget {
  const TableSummary({
    super.key,
    required this.count,
    required this.countNoun,
    this.total,
    this.totalNoun,
  });

  /// How many rows the table is showing, across all its pages.
  final int count;

  /// What follows the count — "shown", "items", "processes".
  final String countNoun;

  /// An optional second figure, usually a size.
  final String? total;

  /// What follows [total] — "on disk", "in the bin".
  final String? totalNoun;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final emphasis = context.text.bodyM.copyWith(
      fontWeight: FontWeight.w700,
      color: colors.textPrimary,
    );

    return Text.rich(
      overflow: TextOverflow.ellipsis,
      TextSpan(
        style: context.text.bodyM,
        children: [
          TextSpan(text: '$count', style: emphasis),
          TextSpan(text: ' $countNoun'),
          if (total != null) ...[
            const TextSpan(text: ' · '),
            TextSpan(text: total, style: emphasis),
            if (totalNoun != null) TextSpan(text: ' $totalNoun'),
          ],
        ],
      ),
    );
  }
}

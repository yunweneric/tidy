import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';

/// Previous / page numbers / Next. [currentPage] and [totalPages] are 1-based.
///
/// Long ranges collapse to a window around the current page (1 … 7 8 9 … 19) so
/// the bar keeps a fixed width no matter how many pages there are.
class PaginationBar extends StatelessWidget {
  const PaginationBar({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.onPageChanged,
    this.maxVisiblePages = 7,
  });

  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onPageChanged;
  final int maxVisiblePages;

  /// Page numbers to render; null marks an ellipsis gap.
  List<int?> get _pages {
    if (totalPages <= maxVisiblePages) {
      return List<int?>.generate(totalPages, (i) => i + 1);
    }

    final window = <int>{1, totalPages};
    final side = (maxVisiblePages - 4) ~/ 2;
    for (var page = currentPage - side; page <= currentPage + side; page++) {
      if (page > 1 && page < totalPages) window.add(page);
    }

    final ordered = window.toList()..sort();
    final result = <int?>[];
    for (var i = 0; i < ordered.length; i++) {
      if (i > 0 && ordered[i] != ordered[i - 1] + 1) result.add(null);
      result.add(ordered[i]);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed:
              currentPage > 1 ? () => onPageChanged(currentPage - 1) : null,
          child: const Text('Previous'),
        ),
        // The numbers are their own group, set apart from Previous and Next so
        // the row does not read as one undifferentiated run of words.
        const SizedBox(width: AppSpacing.sm),
        for (final page in _pages)
          if (page == null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Text('…', style: context.text.bodyM),
            )
          else
            _PageButton(
              page: page,
              active: page == currentPage,
              onPressed: () => onPageChanged(page),
            ),
        const SizedBox(width: AppSpacing.sm),
        TextButton(
          onPressed:
              currentPage < totalPages
                  ? () => onPageChanged(currentPage + 1)
                  : null,
          child: const Text('Next'),
        ),
      ],
    );
  }
}

class _PageButton extends StatelessWidget {
  const _PageButton({
    required this.page,
    required this.active,
    required this.onPressed,
  });

  final int page;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Material(
        color: active ? colors.accent : Colors.transparent,
        borderRadius: AppRadii.smAll,
        child: InkWell(
          onTap: onPressed,
          borderRadius: AppRadii.smAll,
          // A floor rather than a fixed size: single and double digits get the
          // same footprint, so the row does not resize as you page through it,
          // and three-digit pages still fit instead of being clipped.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 32, minHeight: 30),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.sm,
              ),
              child: Center(
                widthFactor: 1,
                child: Text(
                  '$page',
                  style: context.text.label.copyWith(
                    color: active ? colors.textOnAccent : colors.textSecondary,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/theme/app_theme.dart';

/// Previous / page numbers / Next pagination. [currentPage] and [totalPages]
/// are 1-based.
///
/// Long ranges collapse to a window around the current page (1 … 7 8 9 … 19)
/// so the bar keeps a fixed width no matter how many pages there are.
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

    final window = <int?>{1};
    final side = (maxVisiblePages - 4) ~/ 2;
    for (var page = currentPage - side; page <= currentPage + side; page++) {
      if (page > 1 && page < totalPages) window.add(page);
    }
    window.add(totalPages);

    final ordered = window.whereType<int>().toList()..sort();

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
          onPressed: currentPage > 1 ? () => onPageChanged(currentPage - 1) : null,
          child: const Text('Previous'),
        ),
        for (final page in _pages)
          if (page == null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text('…', style: AppTheme.bodySecondary),
            )
          else
            _PageButton(
              page: page,
              active: page == currentPage,
              onPressed: () => onPageChanged(page),
            ),
        TextButton(
          onPressed: currentPage < totalPages
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: active ? AppTheme.accentBlue : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Text(
              '$page',
              style: TextStyle(
                color: active ? Colors.white : AppTheme.textSecondary,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

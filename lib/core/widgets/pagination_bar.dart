import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/theme/app_theme.dart';

/// Previous / page numbers / Next pagination. [currentPage] and [totalPages] are 1-based.
class PaginationBar extends StatelessWidget {
  const PaginationBar({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.onPageChanged,
    this.maxVisiblePages = 15,
  });

  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onPageChanged;
  final int maxVisiblePages;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: currentPage > 1 ? () => onPageChanged(currentPage - 1) : null,
          child: const Text('Previous'),
        ),
        ...List.generate(totalPages.clamp(1, maxVisiblePages), (i) {
          final page = i + 1;
          final active = currentPage == page;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Material(
              color: active ? AppTheme.accentBlue : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                onTap: () => onPageChanged(page),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
        }),
        if (totalPages > maxVisiblePages)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('...', style: AppTheme.bodySecondary),
          ),
        if (totalPages > maxVisiblePages)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Material(
              color: currentPage == totalPages ? AppTheme.accentBlue : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                onTap: () => onPageChanged(totalPages),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    '$totalPages',
                    style: TextStyle(
                      color: currentPage == totalPages ? Colors.white : AppTheme.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        TextButton(
          onPressed: currentPage < totalPages ? () => onPageChanged(currentPage + 1) : null,
          child: const Text('Next'),
        ),
      ],
    );
  }
}

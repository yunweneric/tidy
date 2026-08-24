import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/theme/app_theme.dart';
import 'package:mac_uninstaller/core/widgets/widgets.dart';

/// Table footer with "Displaying X applications  Total size on disk: Y" and pagination.
class AppTableFooter extends StatelessWidget {
  const AppTableFooter({
    super.key,
    required this.itemCount,
    required this.totalSize,
    required this.currentPage,
    required this.totalPages,
    required this.onPageChanged,
  });

  final int itemCount;
  final String totalSize;
  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Flexible(
            child: Text.rich(
              overflow: TextOverflow.ellipsis,
              TextSpan(
                text: 'Displaying ',
                style: AppTheme.bodySecondary,
                children: [
                  TextSpan(
                    text: '$itemCount',
                    style: AppTheme.bodySecondary.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const TextSpan(text: ' applications  Total size on disk: '),
                  TextSpan(
                    text: totalSize,
                    style: AppTheme.bodySecondary.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          PaginationBar(
            currentPage: currentPage,
            totalPages: totalPages,
            onPageChanged: onPageChanged,
          ),
        ],
      ),
    );
  }
}

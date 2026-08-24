import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/widgets/widgets.dart';

/// Row count, total size and pagination.
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
    final colors = context.colors;
    final emphasis = context.text.bodyM.copyWith(
      fontWeight: FontWeight.w700,
      color: colors.textPrimary,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Flexible(
            child: Text.rich(
              overflow: TextOverflow.ellipsis,
              TextSpan(
                style: context.text.bodyM,
                children: [
                  TextSpan(text: '$itemCount', style: emphasis),
                  const TextSpan(text: ' shown · '),
                  TextSpan(text: totalSize, style: emphasis),
                  const TextSpan(text: ' on disk'),
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

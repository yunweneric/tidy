import 'package:flutter/material.dart';
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
    return TableFooter(
      currentPage: currentPage,
      totalPages: totalPages,
      onPageChanged: onPageChanged,
      summary: TableSummary(
        count: itemCount,
        countNoun: 'shown',
        total: totalSize,
        totalNoun: 'on disk',
      ),
    );
  }
}

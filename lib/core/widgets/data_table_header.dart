import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/theme/app_theme.dart';

/// Table header row with optional leading checkbox and column labels.
/// [columnLabels] order matches [flexValues]; if [flexValues] is null, all columns get flex 1.
class DataTableHeader extends StatelessWidget {
  const DataTableHeader({
    super.key,
    required this.columnLabels,
    this.flexValues,
    this.showSelectAll = false,
    this.onSelectAll,
  });

  final List<String> columnLabels;
  final List<int>? flexValues;
  final bool showSelectAll;
  final ValueChanged<bool?>? onSelectAll;

  @override
  Widget build(BuildContext context) {
    final flex = flexValues ?? List.filled(columnLabels.length, 1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          if (showSelectAll)
            SizedBox(
              width: 40,
              child: Checkbox(
                value: false,
                onChanged: onSelectAll,
                fillColor: WidgetStateProperty.all(Colors.transparent),
                side: const BorderSide(color: AppTheme.borderLight),
              ),
            ),
          ...List.generate(columnLabels.length, (i) {
            return Expanded(
              flex: flex[i],
              child: Text(columnLabels[i], style: AppTheme.tableHeader),
            );
          }),
        ],
      ),
    );
  }
}

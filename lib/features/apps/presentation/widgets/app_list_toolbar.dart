import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/widgets/widgets.dart';

/// Tabs (All Apps, Large Apps, System Services) plus Sort and Bulk Uninstall buttons.
class AppListToolbar extends StatelessWidget {
  const AppListToolbar({
    super.key,
    required this.selectedTabIndex,
    required this.onTabChanged,
    this.selectedCount = 0,
    this.onSortPressed,
    this.onBulkUninstallPressed,
  });

  final int selectedTabIndex;
  final ValueChanged<int> onTabChanged;
  final int selectedCount;
  final VoidCallback? onSortPressed;
  final VoidCallback? onBulkUninstallPressed;

  static const List<String> _tabs = ['All Apps', 'Large Apps', 'System Services'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SegmentedTabs(
          labels: _tabs,
          selectedIndex: selectedTabIndex,
          onChanged: onTabChanged,
        ),
        const Spacer(),
        OutlineActionButton(
          label: 'Sort by: Date',
          icon: Icons.sort,
          onPressed: onSortPressed,
        ),
        const SizedBox(width: 12),
        ActionButton(
          label: 'Bulk Uninstall',
          icon: Icons.delete_outline,
          variant: ActionButtonVariant.danger,
          onPressed: selectedCount > 0 ? onBulkUninstallPressed : null,
        ),
      ],
    );
  }
}

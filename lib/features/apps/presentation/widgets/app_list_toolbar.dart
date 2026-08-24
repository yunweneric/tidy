import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/theme/app_theme.dart';
import 'package:mac_uninstaller/core/widgets/widgets.dart';

/// Which subset of the scan the table shows.
enum AppFilter {
  all('All Apps'),
  large('Large Apps'),
  unused('Unused');

  const AppFilter(this.label);

  final String label;
}

/// Table ordering.
enum AppSort {
  size('Size'),
  name('Name'),
  lastUsed('Last used');

  const AppSort(this.label);

  final String label;
}

/// Filter tabs plus Sort and Bulk Uninstall actions.
class AppListToolbar extends StatelessWidget {
  const AppListToolbar({
    super.key,
    required this.filter,
    required this.onFilterChanged,
    required this.sort,
    required this.onSortChanged,
    this.selectedCount = 0,
    this.onBulkUninstallPressed,
  });

  final AppFilter filter;
  final ValueChanged<AppFilter> onFilterChanged;
  final AppSort sort;
  final ValueChanged<AppSort> onSortChanged;
  final int selectedCount;
  final VoidCallback? onBulkUninstallPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SegmentedTabs(
          labels: AppFilter.values.map((f) => f.label).toList(),
          selectedIndex: AppFilter.values.indexOf(filter),
          onChanged: (i) => onFilterChanged(AppFilter.values[i]),
        ),
        const Spacer(),
        PopupMenuButton<AppSort>(
          tooltip: 'Change sort order',
          color: AppTheme.surfaceElevated,
          initialValue: sort,
          onSelected: onSortChanged,
          itemBuilder: (_) => [
            for (final option in AppSort.values)
              PopupMenuItem<AppSort>(
                value: option,
                child: Text(option.label, style: AppTheme.bodyPrimary),
              ),
          ],
          child: IgnorePointer(
            child: OutlineActionButton(
              label: 'Sort by: ${sort.label}',
              icon: Icons.sort,
              onPressed: () {},
            ),
          ),
        ),
        const SizedBox(width: 12),
        ActionButton(
          label: selectedCount > 1
              ? 'Uninstall $selectedCount apps'
              : 'Bulk Uninstall',
          icon: Icons.delete_outline,
          variant: ActionButtonVariant.danger,
          onPressed: selectedCount > 0 ? onBulkUninstallPressed : null,
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';
import 'package:mac_uninstaller/core/widgets/widgets.dart';

/// Which subset of the scan the table shows.
enum AppFilter {
  all('All apps'),
  large('Large'),
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

/// Filter tabs plus sort and bulk-uninstall actions.
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
          initialValue: sort,
          onSelected: onSortChanged,
          itemBuilder: (_) => [
            for (final option in AppSort.values)
              PopupMenuItem<AppSort>(
                value: option,
                child: Text(option.label, style: context.text.bodyL),
              ),
          ],
          child: IgnorePointer(
            child: OutlineActionButton(
              label: 'Sort: ${sort.label}',
              icon: Icons.swap_vert_rounded,
              onPressed: () {},
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        ActionButton(
          label: selectedCount > 1
              ? 'Uninstall $selectedCount apps'
              : 'Uninstall selected',
          icon: Icons.delete_outline_rounded,
          variant: ActionButtonVariant.danger,
          onPressed: selectedCount > 0 ? onBulkUninstallPressed : null,
        ),
      ],
    );
  }
}

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

/// Table ordering. Driven from the column headers now, not a dropdown — the
/// header is where people reach for sorting in a table.
enum AppSort {
  size('Size'),
  name('Name'),
  developer('Developer'),
  version('Version'),
  lastUsed('Last used');

  const AppSort(this.label);

  final String label;
}

/// Filter segments on the left, the destructive bulk action on the right.
class AppListToolbar extends StatelessWidget {
  const AppListToolbar({
    super.key,
    required this.filter,
    required this.onFilterChanged,
    this.counts = const [],
    this.selectedCount = 0,
    this.onBulkUninstallPressed,
  });

  final AppFilter filter;
  final ValueChanged<AppFilter> onFilterChanged;
  final List<int> counts;
  final int selectedCount;
  final VoidCallback? onBulkUninstallPressed;

  @override
  Widget build(BuildContext context) {
    final hasSelection = selectedCount > 0;

    return Row(
      children: [
        SegmentedTabs(
          labels: AppFilter.values.map((f) => f.label).toList(),
          counts: counts,
          selectedIndex: AppFilter.values.indexOf(filter),
          onChanged: (i) => onFilterChanged(AppFilter.values[i]),
        ),
        const Spacer(),
        // The uninstall button only turns destructive once something is
        // actually selected; a permanently red button stops meaning anything.
        AnimatedOpacity(
          duration: context.motion.normal,
          opacity: hasSelection ? 1 : 0.45,
          child: ActionButton(
            label:
                hasSelection
                    ? 'Uninstall $selectedCount'
                        '${selectedCount == 1 ? ' app' : ' apps'}'
                    : 'Uninstall selected',
            icon: AppIcons.delete,
            variant: ActionButtonVariant.danger,
            onPressed: hasSelection ? onBulkUninstallPressed : null,
          ),
        ),
      ],
    );
  }
}

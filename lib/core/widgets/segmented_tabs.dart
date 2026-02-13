import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/theme/app_theme.dart';

/// Horizontal tab bar where one tab is selected. Tabs have rounded top corners.
class SegmentedTabs extends StatelessWidget {
  const SegmentedTabs({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(labels.length, (i) {
        final active = selectedIndex == i;
        return Padding(
          padding: const EdgeInsets.only(right: 0),
          child: Material(
            color: active ? AppTheme.accentBlue : AppTheme.surfaceCard,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(10),
              topRight: const Radius.circular(10),
              bottomLeft: Radius.circular(i == 0 ? 0 : 10),
              bottomRight: Radius.circular(i == labels.length - 1 ? 0 : 10),
            ),
            child: InkWell(
              onTap: () => onChanged(i),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(10),
                topRight: const Radius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Text(
                  labels[i],
                  style: AppTheme.bodyPrimary.copyWith(
                    color: active ? Colors.white : AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

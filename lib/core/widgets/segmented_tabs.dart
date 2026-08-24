import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';

/// Horizontal tab strip. Corners are squared where the strip meets the panel
/// below it, so the two read as one surface rather than two stacked boxes.
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
    final colors = context.colors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(labels.length, (i) {
        final active = selectedIndex == i;
        final radius = BorderRadius.only(
          topLeft: const Radius.circular(AppRadii.md),
          topRight: const Radius.circular(AppRadii.md),
          bottomLeft: Radius.circular(i == 0 ? 0 : AppRadii.md),
          bottomRight: Radius.circular(i == labels.length - 1 ? 0 : AppRadii.md),
        );

        return Material(
          color: active ? colors.accent : colors.surface,
          borderRadius: radius,
          child: InkWell(
            onTap: () => onChanged(i),
            borderRadius: radius,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.md,
              ),
              child: Text(
                labels[i],
                style: context.text.label.copyWith(
                  color: active ? colors.textOnAccent : colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

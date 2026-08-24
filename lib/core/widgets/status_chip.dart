import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/scanning/domain/scan_node.dart';

/// A small tinted label. Used for safety tiers, "needs admin", counts.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.filled = false,
  });

  /// The chip for a finding's safety tier, with copy that says what the tier
  /// means rather than naming it — "Safe to remove" beats "safe".
  factory StatusChip.safety(SafetyLevel level, BuildContext context) {
    final colors = context.colors;
    return switch (level) {
      SafetyLevel.safe => StatusChip(
        label: 'Safe to remove',
        color: colors.safe,
        icon: AppIcons.safe,
      ),
      SafetyLevel.review => StatusChip(
        label: 'Worth a look',
        color: colors.review,
        icon: AppIcons.review,
      ),
      SafetyLevel.risky => StatusChip(
        label: 'Your data',
        color: colors.risky,
        icon: AppIcons.risky,
      ),
    };
  }

  final String label;
  final Color color;
  final IconData? icon;

  /// Solid rather than tinted. Reserve for the one chip that must dominate.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final foreground = filled ? context.colors.textOnAccent : color;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.13),
        borderRadius: AppRadii.smAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            label,
            style: context.text.caption.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

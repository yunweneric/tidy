import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';

/// A small rounded label. Eyebrows, badges, "built" / "planned" markers.
class LandingPill extends StatelessWidget {
  const LandingPill({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.emphasis = false,
  });

  final String label;
  final IconData? icon;

  /// Overrides the ink and wash. Used by the module cards, where the pill is
  /// the module's own tone.
  final Color? color;

  /// Fills with the brand wash instead of the neutral veil.
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ink = color ?? (emphasis ? colors.accent : colors.textSecondary);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color:
            color != null
                ? color!.withValues(alpha: 0.14)
                : (emphasis ? colors.accentMuted : colors.surfaceHover),
        borderRadius: AppRadii.pillAll,
        border: Border.all(
          color:
              color != null
                  ? color!.withValues(alpha: 0.30)
                  : (emphasis ? colors.accentMuted : colors.border),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: ink),
            const SizedBox(width: AppSpacing.xs + 2),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/theme/app_theme.dart';

/// Primary (blue) or danger (red) action button with optional icon.
class ActionButton extends StatelessWidget {
  const ActionButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.variant = ActionButtonVariant.primary,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final ActionButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    final isDanger = variant == ActionButtonVariant.danger;
    final style = ElevatedButton.styleFrom(
      backgroundColor: isDanger ? AppTheme.accentRed : AppTheme.accentBlue,
      foregroundColor: Colors.white,
    );
    if (icon != null) {
      return ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: style,
      );
    }
    return ElevatedButton(
      onPressed: onPressed,
      style: style,
      child: Text(label),
    );
  }
}

enum ActionButtonVariant { primary, danger }

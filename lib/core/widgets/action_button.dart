import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';

/// Primary or danger action button with optional icon.
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
    final colors = context.colors;
    final style = ElevatedButton.styleFrom(
      backgroundColor: variant == ActionButtonVariant.danger
          ? colors.risky
          : colors.accent,
      foregroundColor: colors.textOnAccent,
    );

    if (icon != null) {
      return ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: style,
      );
    }
    return ElevatedButton(onPressed: onPressed, style: style, child: Text(label));
  }
}

enum ActionButtonVariant { primary, danger }

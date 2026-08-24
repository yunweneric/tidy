import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';

/// Outlined secondary button with optional icon (e.g. "Sort by: Size").
class OutlineActionButton extends StatelessWidget {
  const OutlineActionButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = OutlinedButton.styleFrom(
      foregroundColor: colors.textSecondary,
      side: BorderSide(color: colors.border),
    );

    if (icon != null) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16, color: colors.textSecondary),
        label: Text(label, style: context.text.label),
        style: style,
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: style,
      child: Text(label, style: context.text.label),
    );
  }
}

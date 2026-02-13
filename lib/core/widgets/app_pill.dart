import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/theme/app_theme.dart';

/// A small pill/chip for status or counts (e.g. "Selected: 0").
class AppPill extends StatelessWidget {
  const AppPill({
    super.key,
    required this.label,
    this.style,
  });

  final String label;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: style ?? AppTheme.labelSmall),
    );
  }
}

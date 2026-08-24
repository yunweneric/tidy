import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';

/// A small pill for status or counts (e.g. "3 selected").
class AppPill extends StatelessWidget {
  const AppPill({super.key, required this.label, this.style});

  final String label;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs + 1,
      ),
      decoration: BoxDecoration(
        color: context.colors.surfaceRaised,
        borderRadius: AppRadii.pillAll,
      ),
      child: Text(label, style: style ?? context.text.caption),
    );
  }
}

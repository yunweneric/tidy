import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';

/// Small uppercase section label.
class SectionLabel extends StatelessWidget {
  const SectionLabel({super.key, required this.label, this.padding});

  final String label;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ??
          const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Text(label, style: context.text.overline),
    );
  }
}

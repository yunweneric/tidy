import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/theme/app_theme.dart';

/// Search input with prefix icon. Use [onChanged] for filtering.
class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    this.hintText = 'Search...',
    this.width,
    this.onChanged,
    this.controller,
  });

  final String hintText;
  final double? width;
  final ValueChanged<String>? onChanged;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    final child = TextField(
      controller: controller,
      style: AppTheme.bodyPrimary,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(Icons.search, size: 20, color: AppTheme.textMuted),
      ),
      onChanged: onChanged,
    );
    if (width != null) {
      return SizedBox(width: width, child: child);
    }
    return child;
  }
}

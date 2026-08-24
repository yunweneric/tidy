import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';

/// Search input with a prefix glyph. Filtering happens in [onChanged].
class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    this.hintText = 'Search…',
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
      style: context.text.bodyL,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: Icon(
          AppIcons.search,
          size: 17,
          color: context.colors.textMuted,
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      ),
      onChanged: onChanged,
    );
    return width == null ? child : SizedBox(width: width, child: child);
  }
}

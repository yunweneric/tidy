import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';

/// Small section heading inside the popover, with an optional trailing note.
class MenuBarSection extends StatelessWidget {
  const MenuBarSection({super.key, required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md + 2,
        AppSpacing.sm + 2,
        AppSpacing.md + 2,
        AppSpacing.xs + 2,
      ),
      child: Row(
        children: [
          Text(title.toUpperCase(), style: context.text.overline),
          const Spacer(),
          if (trailing != null) Text(trailing!, style: context.text.caption),
        ],
      ),
    );
  }
}

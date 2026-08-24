import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/theme/app_theme.dart';

/// Small section heading inside the popover, with an optional trailing note.
class MenuBarSection extends StatelessWidget {
  const MenuBarSection({super.key, required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Row(
        children: [
          Text(title.toUpperCase(), style: AppTheme.sectionHeader),
          const Spacer(),
          if (trailing != null)
            Text(
              trailing!,
              style: AppTheme.labelSmall.copyWith(color: AppTheme.textMuted),
            ),
        ],
      ),
    );
  }
}

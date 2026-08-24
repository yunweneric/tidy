import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';

/// Small section heading inside the popover, with an optional trailing note or
/// control.
class MenuBarSection extends StatelessWidget {
  const MenuBarSection({
    super.key,
    required this.title,
    this.trailing,
    this.action,
  });

  final String title;

  /// A note — a count, a state. Ignored when [action] is given.
  final String? trailing;

  /// A control that belongs to the section rather than to any one row, such as
  /// the sort toggle over the process list.
  final Widget? action;

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
          if (action != null)
            action!
          else if (trailing != null)
            Text(trailing!, style: context.text.caption),
        ],
      ),
    );
  }
}

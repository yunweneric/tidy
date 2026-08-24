import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';

/// How loudly a menu bar button asks to be pressed.
enum MenuBarButtonTone { filled, quiet, danger }

/// The panel's one button.
///
/// The app's [ActionButton] and [OutlineActionButton] are sized for a window;
/// dropped into a popover row they are taller than the row they sit in. This is
/// the same idea at menu bar scale, defined once so the Clean button, the Quit
/// button and the confirmations in the process list are the same object rather
/// than three hand-tuned `TextButton.styleFrom` calls.
class MenuBarButton extends StatelessWidget {
  const MenuBarButton({
    super.key,
    required this.label,
    this.onPressed,
    this.tone = MenuBarButtonTone.quiet,
  });

  final String label;
  final VoidCallback? onPressed;
  final MenuBarButtonTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = switch (tone) {
      MenuBarButtonTone.filled => colors.accent,
      MenuBarButtonTone.quiet => colors.textSecondary,
      MenuBarButtonTone.danger => colors.risky,
    };

    final style = TextButton.styleFrom(
      foregroundColor:
          tone == MenuBarButtonTone.filled ? colors.textOnAccent : color,
      backgroundColor:
          tone == MenuBarButtonTone.filled ? color : Colors.transparent,
      textStyle: context.text.label,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md - 2),
      minimumSize: const Size(0, 26),
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.smAll),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    return TextButton(onPressed: onPressed, style: style, child: Text(label));
  }
}

/// A borderless icon button sized for the panel's header rows.
class MenuBarIconButton extends StatelessWidget {
  const MenuBarIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 15),
      color: color ?? context.colors.textSecondary,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
    );
  }
}

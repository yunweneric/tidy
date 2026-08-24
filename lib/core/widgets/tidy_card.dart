import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';

/// The standard surface: flat fill, 1px border, generous radius.
///
/// Everything in the app that looks like a card is this widget. No Material
/// elevation anywhere — shadows read as heavy next to macOS's own chrome, and
/// a consistent border is what makes a dense screen legible.
class TidyCard extends StatefulWidget {
  const TidyCard({
    super.key,
    required this.child,
    this.padding = AppSpacing.card,
    this.onTap,
    this.selected = false,
    this.accent,
    this.borderRadius = AppRadii.lgAll,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// Draws the accent border and wash, for a chosen tile.
  final bool selected;

  /// Overrides the accent used when [selected] or hovered — lets a status card
  /// glow in its own semantic colour.
  final Color? accent;

  final BorderRadius borderRadius;

  @override
  State<TidyCard> createState() => _TidyCardState();
}

class _TidyCardState extends State<TidyCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = widget.accent ?? colors.accent;
    final interactive = widget.onTap != null;

    final borderColor = widget.selected
        ? accent
        : (_hovered && interactive ? colors.borderStrong : colors.border);

    final fill = widget.selected
        ? Color.alphaBlend(accent.withValues(alpha: 0.07), colors.surface)
        : (_hovered && interactive ? colors.surfaceHover : colors.surface);

    return MouseRegion(
      cursor: interactive ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: interactive ? (_) => setState(() => _hovered = true) : null,
      onExit: interactive ? (_) => setState(() => _hovered = false) : null,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: context.motion.fast,
          curve: context.motion.standard,
          padding: widget.padding,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: widget.borderRadius,
            border: Border.all(
              color: borderColor,
              width: widget.selected ? 1.5 : 1,
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';

/// The standard surface: a barely-there vertical sheen, 1px border, generous
/// radius.
///
/// Everything in the app that looks like a card is this widget. No Material
/// elevation anywhere — shadows read as heavy next to macOS's own chrome, and
/// a consistent border is what makes a dense screen legible. The fill is a
/// two-stop gradient rather than a flat colour so a card catches the window's
/// light the way the chrome around it does; the two stops are close enough
/// together that the card still reads as one surface.
class TidyCard extends StatefulWidget {
  const TidyCard({
    super.key,
    required this.child,
    this.padding = AppSpacing.card,
    this.onTap,
    this.selected = false,
    this.accent,
    this.tint,
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

  /// Washes the card's fill in a semantic colour without claiming it is
  /// selected. For summary tiles, where the colour *is* the information —
  /// amber for "not opened in six months", green for "nothing to do".
  ///
  /// Never for a row in a list: a table where every card is tinted is a table
  /// with no signal left.
  final Color? tint;

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
    final active = _hovered && interactive;

    final borderColor =
        widget.selected
            ? accent
            : widget.tint != null
            ? Color.alphaBlend(
              widget.tint!.withValues(alpha: active ? 0.42 : 0.26),
              colors.border,
            )
            : (active ? colors.borderStrong : colors.border);

    final fill = switch ((widget.selected, widget.tint)) {
      (true, _) => colors.tintedSurface(accent, strength: 1.4),
      (false, final Color tint) => colors.tintedSurface(
        tint,
        strength: active ? 1.35 : 1,
      ),
      _ =>
        active ? [colors.surfaceHover, colors.surface] : colors.surfaceGradient,
    };

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
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: fill,
            ),
            borderRadius: widget.borderRadius,
            border: Border.all(
              color: borderColor,
              width: widget.selected ? 1.5 : 1,
            ),
            // Light mode only. There a near-white card sits on a tinted
            // backdrop and needs the lift to read as a separate plane; in dark
            // the card is a lighter veil on a darker base, which separates on
            // its own, and a shadow there just reads as grime.
            boxShadow:
                colors.isDark
                    ? null
                    : [
                      BoxShadow(
                        color: colors.shadow,
                        blurRadius: 12,
                        offset: const Offset(0, 2),
                      ),
                    ],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

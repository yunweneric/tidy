import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/widgets/ambient_background.dart';

/// The primary call to action, wearing the brand gradient.
///
/// Material's [ElevatedButton] takes a single background colour, so a gradient
/// CTA has to be built rather than themed. This keeps the same geometry, text
/// style and disabled treatment as the themed button, so the two can sit next
/// to each other — a page usually has one gradient button and several plain
/// ones, and they should look like the same family.
///
/// One per screen. A page where everything glows has told the user nothing
/// about what to press.
class GradientButton extends StatefulWidget {
  const GradientButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.size = GradientButtonSize.regular,
    this.expand = false,
    this.gradient,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final GradientButtonSize size;

  /// Fills the available width — the sidebar's Reclaim button.
  final bool expand;

  /// Overrides the ramp. Left null, the button wears the active module's own
  /// colours — a call to action should never sit on a green page in violet.
  /// Outside a module it falls back to the brand ramp.
  final List<Color>? gradient;

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

enum GradientButtonSize {
  /// Matches the themed [ElevatedButton] — header and dialog actions.
  regular,

  /// The scan hero's single button. Nothing else should be this large.
  large,

  /// Fits inside a sidebar card or a table toolbar.
  compact,
}

class _GradientButtonState extends State<GradientButton> {
  bool _hovered = false;
  bool _pressed = false;

  EdgeInsets get _padding => switch (widget.size) {
    GradientButtonSize.large => const EdgeInsets.symmetric(
      horizontal: AppSpacing.xxl + AppSpacing.sm,
      vertical: AppSpacing.lg,
    ),
    GradientButtonSize.regular => const EdgeInsets.symmetric(
      horizontal: AppSpacing.xl,
      vertical: AppSpacing.md,
    ),
    GradientButtonSize.compact => const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.sm + 1,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final motion = context.motion;
    final enabled = widget.onPressed != null;

    final stops =
        widget.gradient ??
        ModuleTint.of(context)?.ramp ??
        colors.accentGradient;
    final foreground = enabled ? colors.textOnAccent : colors.textMuted;

    final radius =
        widget.size == GradientButtonSize.large
            ? AppRadii.lgAll
            : AppRadii.mdAll;

    final label = Text(
      widget.label,
      style: (widget.size == GradientButtonSize.large
              ? context.text.bodyL
              : context.text.label)
          .copyWith(color: foreground, fontWeight: FontWeight.w600),
    );

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: enabled ? (_) => setState(() => _hovered = false) : null,
      child: GestureDetector(
        onTap: widget.onPressed,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        child: AnimatedContainer(
          duration: motion.fast,
          curve: motion.standard,
          width: widget.expand ? double.infinity : null,
          padding: _padding,
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient:
                enabled
                    ? LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: stops,
                    )
                    : null,
            color: enabled ? null : colors.surfaceHover,
            // The glow is the press affordance, standing in for the elevation
            // this app does not use anywhere else.
            boxShadow:
                enabled && _hovered && !_pressed
                    ? [
                      BoxShadow(
                        color: stops.last.withValues(alpha: 0.35),
                        blurRadius: 18,
                        offset: const Offset(0, 4),
                      ),
                    ]
                    : null,
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: radius,
            color:
                _pressed
                    ? colors.overlay.withValues(alpha: 0.18)
                    : Colors.transparent,
          ),
          child: Row(
            mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 16, color: foreground),
                const SizedBox(width: AppSpacing.sm),
              ],
              Flexible(child: label),
            ],
          ),
        ),
      ),
    );
  }
}

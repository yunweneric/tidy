import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/landing/widgets/external_link.dart';

export 'package:tidy/landing/widgets/external_link.dart' show openExternalUrl;

enum LandingButtonKind {
  /// The one action that matters in a band. Wears the brand ramp.
  primary,

  /// A hairline outline. Everything else.
  secondary,

  /// No chrome until hovered.
  ghost,
}

/// The page's only button.
///
/// The app's rule is one gradient action per screen and translucent pills for
/// the rest ([docs/ui.md] §3). A landing page has more bands than a screen, so
/// the rule becomes one primary per *band* — but a secondary never gets a
/// colour, which is what keeps the primary unmistakable.
class LandingButton extends StatefulWidget {
  const LandingButton({
    super.key,
    required this.label,
    this.onPressed,
    this.url,
    this.icon,
    this.kind = LandingButtonKind.primary,
    this.busy = false,
    this.large = false,
    this.height,
    this.iconOnly = false,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Convenience for the common case: a button that is really a link.
  final String? url;

  final IconData? icon;
  final LandingButtonKind kind;
  final bool busy;
  final bool large;

  /// Pins the button to an exact height, so a row of mixed controls (the
  /// navigation bar) lines up instead of each one sizing to its own padding.
  final double? height;

  /// Drops the label and squares the button off, moving the text into a
  /// tooltip. The navigation bar uses it once it has drawn in and the full
  /// label no longer earns its width.
  final bool iconOnly;

  @override
  State<LandingButton> createState() => _LandingButtonState();
}

class _LandingButtonState extends State<LandingButton> {
  bool _hovered = false;

  bool get _enabled =>
      !widget.busy && (widget.onPressed != null || widget.url != null);

  void _activate() {
    final onPressed = widget.onPressed;
    if (onPressed != null) {
      onPressed();
      return;
    }
    final url = widget.url;
    if (url != null) openExternalUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final motion = context.motion;
    final isPrimary = widget.kind == LandingButtonKind.primary;

    final foreground = isPrimary ? colors.textOnAccent : colors.textPrimary;
    final border = switch (widget.kind) {
      LandingButtonKind.primary => null,
      LandingButtonKind.secondary => Border.all(
        color: _hovered ? colors.borderStrong : colors.border,
        width: 1.2,
      ),
      LandingButtonKind.ghost => null,
    };

    // Squaring off needs a height to be square against.
    final square = widget.iconOnly && widget.height != null;
    final lift = _hovered && _enabled ? -2.0 : 0.0;

    final button = MouseRegion(
      cursor: _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: _enabled ? _activate : null,
        child: AnimatedContainer(
          duration: motion.fast,
          curve: motion.standard,
          transform: Matrix4.translationValues(0, lift, 0),
          height: widget.height,
          width: square ? widget.height : null,
          // A fixed width hands the Row tight constraints, so MainAxisSize.min
          // cannot shrink it and the icon would sit against the left edge
          // without this.
          alignment: square ? Alignment.center : null,
          padding:
              square
                  ? EdgeInsets.zero
                  : EdgeInsets.symmetric(
                    horizontal: widget.large ? AppSpacing.xxl : AppSpacing.xl,
                    vertical:
                        widget.height != null ? 0 : (widget.large ? 18 : 14),
                  ),
          decoration: BoxDecoration(
            gradient:
                isPrimary
                    ? LinearGradient(
                      colors: colors.accentGradient,
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    )
                    : null,
            color: switch (widget.kind) {
              LandingButtonKind.primary => null,
              LandingButtonKind.secondary => Colors.transparent,
              LandingButtonKind.ghost =>
                _hovered ? colors.surfaceHover : Colors.transparent,
            },
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: border,
            boxShadow:
                isPrimary && _hovered && _enabled
                    ? [
                      BoxShadow(
                        color: colors.accent.withValues(alpha: 0.45),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ]
                    : null,
          ),
          child: Opacity(
            opacity: _enabled ? 1 : 0.6,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.busy)
                  SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(foreground),
                    ),
                  )
                else if (widget.icon != null)
                  Icon(
                    widget.icon,
                    size: widget.large ? 20 : 18,
                    color: foreground,
                  ),
                if (!square && (widget.busy || widget.icon != null))
                  const SizedBox(width: AppSpacing.sm),
                if (!square)
                  // Flexible, so a long label squeezes rather than overflowing
                  // the row it sits in — the navigation bar has no spare width.
                  Flexible(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: widget.large ? 16 : 14.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.1,
                        color: foreground,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    // The label still has to be reachable when it is not drawn.
    return square ? Tooltip(message: widget.label, child: button) : button;
  }
}

/// An inline text link that underlines on hover.
class LandingLink extends StatefulWidget {
  const LandingLink({
    super.key,
    required this.label,
    this.url,
    this.onPressed,
    this.muted = true,
    this.fontSize = 14.5,
  });

  final String label;
  final String? url;
  final VoidCallback? onPressed;
  final bool muted;
  final double fontSize;

  @override
  State<LandingLink> createState() => _LandingLinkState();
}

class _LandingLinkState extends State<LandingLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final base = widget.muted ? colors.textSecondary : colors.textPrimary;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () {
          final onPressed = widget.onPressed;
          if (onPressed != null) {
            onPressed();
            return;
          }
          final url = widget.url;
          if (url != null) openExternalUrl(url);
        },
        child: AnimatedDefaultTextStyle(
          duration: context.motion.fast,
          style: TextStyle(
            fontSize: widget.fontSize,
            fontWeight: FontWeight.w600,
            color: _hovered ? colors.accent : base,
            decoration: _hovered ? TextDecoration.underline : null,
            decorationColor: colors.accent,
          ),
          child: Text(widget.label),
        ),
      ),
    );
  }
}

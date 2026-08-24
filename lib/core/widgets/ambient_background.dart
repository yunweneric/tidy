import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';

/// The window backdrop: a canvas wash plus two soft ambient glows.
///
/// Everything the user sees sits on top of this, which is the whole point — a
/// utility that spends its day showing tables of file sizes needs the frame
/// around them to feel like a place rather than a spreadsheet. The gradients
/// are deliberately weak: they are lighting, not decoration, and anything that
/// competes with a size column has gone too far.
///
/// The glows are painted, not blurred. A `BackdropFilter` or `ImageFiltered`
/// here would cost a full-window offscreen render pass on every frame of every
/// scan, and a wide radial gradient is visually indistinguishable from one.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({
    super.key,
    required this.child,
    this.intensity = 1,
    this.glowAlignment = const (
      Alignment(-0.85, -1.05),
      Alignment(1.05, 1.0),
    ),
  });

  final Widget child;

  /// Scales both glows. Below 1 for dense screens (a table is busy enough);
  /// above 1 for a hero or an empty state, where the window is mostly backdrop.
  final double intensity;

  /// Where the two glows sit, primary first. Defaults to opposite corners.
  final (Alignment, Alignment) glowAlignment;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (primaryAt, secondaryAt) = glowAlignment;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors.canvasGradient,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Ignore pointers so the glows never sit between the user and a row.
          IgnorePointer(
            child: CustomPaint(
              painter: _GlowPainter(
                primary: colors.glowPrimary,
                secondary: colors.glowSecondary,
                primaryAt: primaryAt,
                secondaryAt: secondaryAt,
                intensity: intensity,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _GlowPainter extends CustomPainter {
  const _GlowPainter({
    required this.primary,
    required this.secondary,
    required this.primaryAt,
    required this.secondaryAt,
    required this.intensity,
  });

  final Color primary;
  final Color secondary;
  final Alignment primaryAt;
  final Alignment secondaryAt;
  final double intensity;

  /// Each glow spans roughly this fraction of the window's long edge. Wide
  /// enough that the falloff is never visible as an edge.
  static const double _radiusFactor = 0.62;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final radius = size.longestSide * _radiusFactor;

    void glow(Color color, Alignment at) {
      final centre = at.alongSize(size);
      final rect = Rect.fromCircle(center: centre, radius: radius);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(
                alpha: (color.a * intensity).clamp(0.0, 1.0),
              ),
              color.withValues(alpha: 0),
            ],
            // Most of the falloff happens in the outer half, so the centre
            // reads as a soft pool rather than a dot with a halo.
            stops: const [0, 1],
          ).createShader(rect),
      );
    }

    glow(primary, primaryAt);
    glow(secondary, secondaryAt);
  }

  @override
  bool shouldRepaint(_GlowPainter old) =>
      old.primary != primary ||
      old.secondary != secondary ||
      old.primaryAt != primaryAt ||
      old.secondaryAt != secondaryAt ||
      old.intensity != intensity;
}

import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';

/// The window backdrop: one continuous wash, two soft glows, a few large
/// shapes and a dot grid.
///
/// It spans the *whole* window — sidebar included. Every in-window surface
/// above it is translucent (see `surface` and `sidebar` in `AppColorTokens`),
/// so the same backdrop carries through the rail, the cards and the tables
/// rather than each panel being its own flat rectangle. That continuity is the
/// entire effect; an opaque sidebar over this would cut the window in half.
///
/// Everything here is deliberately weak. The glows are lighting, the shapes are
/// depth, the dots are texture — none of it should ever compete with a size
/// column. If a pattern is legible enough to count, it is too strong.
///
/// It is all painted, not blurred. A `BackdropFilter` or `ImageFiltered` here
/// would cost a full-window offscreen pass on every frame of every scan, and a
/// wide radial gradient is visually indistinguishable from one.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({
    super.key,
    required this.child,
    this.intensity = 1,
    this.pattern = true,
    this.tint,
  });

  final Widget child;

  /// Scales the glows and shapes. Below 1 for dense screens (a table is busy
  /// enough); above 1 for a hero or an empty state, where the window is mostly
  /// backdrop.
  final double intensity;

  /// The dot grid and the ring outlines. Off for small surfaces — the menu-bar
  /// popover is 360pt wide, and a grid at that size reads as noise.
  final bool pattern;

  /// The module's own colour of light, from `AppColorTokens.moduleTint`. It
  /// replaces the primary glow and washes a few percent into the top of the
  /// canvas, so each module's window is recognisably its own — Protection is
  /// pink, Performance is amber, Cleanup is blue — without any of the content
  /// being restyled.
  ///
  /// Null keeps the theme's own `glowPrimary`. Changing it cross-fades over
  /// `motion.slow`; snapping between two saturated washes is jarring, and the
  /// fade is what makes it read as the same window rather than a new one.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final motion = context.motion;
    final glow = tint ?? colors.glowPrimary;

    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: glow),
      duration: motion.slow,
      curve: motion.smooth,
      child: child,
      builder: (context, animatedGlow, child) {
        final lit = animatedGlow ?? glow;

        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _wash(colors.canvasGradient, lit),
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Isolated so the backdrop is rasterised once and reused instead
              // of being repainted behind every frame of a spinning scan ring.
              RepaintBoundary(
                child: IgnorePointer(
                  child: CustomPaint(
                    isComplex: true,
                    willChange: false,
                    painter: _BackdropPainter(
                      glowPrimary: lit,
                      glowSecondary: colors.glowSecondary,
                      accent: colors.accent,
                      ink: colors.pattern,
                      intensity: intensity,
                      pattern: pattern,
                    ),
                  ),
                ),
              ),
              child!,
            ],
          ),
        );
      },
    );
  }

  /// Pulls the top of the canvas a few percent toward the module's hue. The
  /// glow alone is a pool of light in one corner; without this the rest of the
  /// window stays the same colour on every module and the effect reads as a
  /// smudge rather than as a theme.
  static List<Color> _wash(List<Color> canvas, Color lit) {
    final strong = lit.withValues(alpha: 0.16);
    final faint = lit.withValues(alpha: 0.05);
    return [
      for (var i = 0; i < canvas.length; i++)
        Color.alphaBlend(i == 0 ? strong : faint, canvas[i]),
    ];
  }
}

class _BackdropPainter extends CustomPainter {
  const _BackdropPainter({
    required this.glowPrimary,
    required this.glowSecondary,
    required this.accent,
    required this.ink,
    required this.intensity,
    required this.pattern,
  });

  final Color glowPrimary;
  final Color glowSecondary;
  final Color accent;
  final Color ink;
  final double intensity;
  final bool pattern;

  /// Grid pitch. Wide enough that the dots read as texture rather than as a
  /// surface you could align something to.
  static const double _dotPitch = 26;
  static const double _dotRadius = 0.9;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    _glows(canvas, size);
    if (!pattern) return;
    _rings(canvas, size);
    _dots(canvas, size);
  }

  /// Three overlapping pools of light, sized off the window so they stay the
  /// same shape whether the window is at its 1100pt minimum or full screen.
  void _glows(Canvas canvas, Size size) {
    final long = size.longestSide;

    void pool(Color color, Alignment at, double radiusFactor, double scale) {
      final alpha = (color.a * intensity * scale).clamp(0.0, 1.0);
      if (alpha <= 0) return;
      final rect = Rect.fromCircle(
        center: at.alongSize(size),
        radius: long * radiusFactor,
      );
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0),
            ],
          ).createShader(rect),
      );
    }

    pool(glowPrimary, const Alignment(-0.85, -1.05), 0.62, 1);
    pool(glowSecondary, const Alignment(1.05, 1.0), 0.62, 1);
    // A third, weaker pool off the right shoulder, so the middle of a wide
    // window is not a dead flat band between two corner glows.
    pool(accent, const Alignment(1.15, -0.6), 0.45, 0.14);
  }

  /// Two oversized circle outlines, mostly off-canvas. They give the backdrop
  /// something with an edge in it — a wash of pure gradient has no scale, and
  /// reads as flat however many stops it has.
  void _rings(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = ink.withValues(
            alpha: (ink.a * 1.8 * intensity).clamp(0.0, 1.0),
          );

    final long = size.longestSide;
    final topRight = Offset(size.width * 1.02, -size.height * 0.18);
    canvas.drawCircle(topRight, long * 0.34, stroke);
    canvas.drawCircle(topRight, long * 0.24, stroke);

    final bottomLeft = Offset(-size.width * 0.06, size.height * 1.12);
    canvas.drawCircle(bottomLeft, long * 0.30, stroke);
  }

  /// The dot grid. ~2–3k points on a typical window, drawn once into the
  /// repaint boundary's cache.
  void _dots(Canvas canvas, Size size) {
    final alpha = (ink.a * intensity).clamp(0.0, 1.0);
    if (alpha <= 0) return;

    final paint =
        Paint()
          ..color = ink.withValues(alpha: alpha)
          ..strokeCap = StrokeCap.round
          ..strokeWidth = _dotRadius * 2;

    final columns = (size.width / _dotPitch).ceil() + 1;
    final rows = (size.height / _dotPitch).ceil() + 1;
    final points = <Offset>[
      for (var y = 0; y < rows; y++)
        for (var x = 0; x < columns; x++) Offset(x * _dotPitch, y * _dotPitch),
    ];

    canvas.drawPoints(PointMode.points, points, paint);
  }

  @override
  bool shouldRepaint(_BackdropPainter old) =>
      old.glowPrimary != glowPrimary ||
      old.glowSecondary != glowSecondary ||
      old.accent != accent ||
      old.ink != ink ||
      old.intensity != intensity ||
      old.pattern != pattern;
}

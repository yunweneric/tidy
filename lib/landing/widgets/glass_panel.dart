import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';

/// Frosted glass, for the one thing on the page that floats over the rest.
///
/// Only the navigation bar uses it. Everything else is a flat veil, the same as
/// everything else in the app — a page where several things blur is a page with
/// no hierarchy left.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    required this.borderRadius,
    this.blur = 22,
    this.opacity = 1,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double blur;

  /// Scales the whole treatment — tint, ground, border and specular edge — so
  /// the bar can fade its glass in as the page scrolls under it.
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.isDarkTheme;

    final tint =
        isDark
            ? Colors.white.withValues(alpha: 0.07 * opacity)
            : Colors.white.withValues(alpha: 0.62 * opacity);
    final ground = colors.canvas.withValues(
      alpha: (isDark ? 0.46 : 0.30) * opacity,
    );

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        // One filter pass, not two.
        //
        // This used to compose the blur with a saturation matrix, to pull back
        // the colour that blurring averages away. It looked marginally better
        // and cost twice the work — and this panel is the pinned navigation
        // bar, so its backdrop is re-read on every frame the page scrolls.
        // Two full-width filter passes per frame is where the scroll stutter
        // was coming from. The tint below carries the colour instead.
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color.alphaBlend(tint, ground), ground],
            ),
            border: Border.all(
              color:
                  isDark
                      ? Colors.white.withValues(alpha: 0.14 * opacity)
                      : Colors.black.withValues(alpha: 0.07 * opacity),
            ),
          ),
          child: Stack(
            children: [
              child,
              // The specular edge: a one-pixel highlight that stops short of
              // the corners, the way a rim light would.
              Positioned(
                top: 0,
                left: borderRadius.topLeft.x,
                right: borderRadius.topRight.x,
                child: IgnorePointer(
                  child: Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0),
                          Colors.white.withValues(
                            alpha: (isDark ? 0.34 : 0.85) * opacity,
                          ),
                          Colors.white.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

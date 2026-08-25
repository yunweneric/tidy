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
        filter: ImageFilter.compose(
          outer: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          // Blurring averages colour away; pulling saturation back up is what
          // keeps the module tone underneath still reading as that module.
          inner: const ColorFilter.matrix(<double>[
            1.34, -0.17, -0.17, 0, 0, //
            -0.17, 1.34, -0.17, 0, 0, //
            -0.17, -0.17, 1.34, 0, 0, //
            0, 0, 0, 1, 0, //
          ]),
        ),
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

import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';

/// The window backdrop: the active module's colour, edge to edge.
///
/// The module colour is not a tint on a neutral window — it *is* the window.
/// It runs under the sidebar, the cards and the tables alike, and every surface
/// above it is a neutral veil (see `surface` in `AppColorTokens`), so a card
/// reads as a lighter patch of the same colour rather than a panel pasted on
/// top. That is the entire effect; one opaque surface anywhere breaks it.
///
/// On top of the colour: a pool of light pulled toward [ModulePalette.lift], a
/// couple of oversized ring outlines, and a dot grid. All of it deliberately
/// weak — the light is depth, the shapes are scale, the dots are texture, and
/// none of it should ever compete with a size column.
///
/// It is painted, not blurred. A `BackdropFilter` here would cost a full-window
/// offscreen pass on every frame of every scan, and a wide radial gradient is
/// visually indistinguishable from one.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({
    super.key,
    required this.child,
    this.tone,
    this.intensity = 1,
    this.pattern = true,
  });

  final Widget child;

  /// Whose colour the window wears. Null keeps the brand tone, which is what
  /// the views no module owns (Settings, onboarding) use.
  final ModuleTone? tone;

  /// Scales the light and the shapes. Below 1 for dense screens (a table is
  /// busy enough); above 1 for a hero, where the window is mostly backdrop.
  final double intensity;

  /// The dot grid and the ring outlines. Off for small surfaces — the menu-bar
  /// popover is 360pt wide, and a grid at that size reads as noise.
  final bool pattern;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final motion = context.motion;
    final palette = colors.modulePalette(tone ?? ModuleTone.brand);

    // Changing module cross-fades rather than snapping. Two saturated colours
    // swapping instantly reads as a different window, not a different page.
    //
    // The Theme override sits *outside* the tween on purpose: it takes the
    // target palette, so it changes once per module switch rather than on
    // every frame of the fade. A ThemeData change rebuilds every descendant
    // that reads it, and doing that sixty times a second behind a long table
    // is exactly the kind of thing that shows up as jank.
    return Theme(
      data: _tuned(context, palette),
      child: TweenAnimationBuilder<ModulePalette>(
        tween: _PaletteTween(end: palette),
        duration: motion.slow,
        curve: motion.smooth,
        child: child,
        builder: (context, animated, child) {
          return _Backdrop(
            palette: animated,
            colors: colors,
            intensity: intensity,
            pattern: pattern,
            child: child!,
          );
        },
      ),
    );
  }

  /// Rebinds the accent — and the Material widgets that were built against it —
  /// to the module's own colour.
  ///
  /// Without this a Performance toggle is brand violet on an amber page and a
  /// Cleanup checkbox is violet on green. The component themes have to be
  /// rebuilt individually: they captured `accent` when the base theme was
  /// built, so overriding `colorScheme.primary` alone does nothing to them.
  ThemeData _tuned(BuildContext context, ModulePalette palette) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColorTokens>();
    if (colors == null || colors.accent == palette.accent) return theme;

    final tuned = colors.copyWith(
      accent: palette.accent,
      accentMuted: palette.accent.withValues(alpha: 0.22),
    );

    return theme.copyWith(
      extensions: [
        tuned,
        ...theme.extensions.values.where((e) => e is! AppColorTokens),
      ],
      colorScheme: theme.colorScheme.copyWith(primary: palette.accent),
      switchTheme: theme.switchTheme.copyWith(
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected)
                  ? palette.accent
                  : tuned.surfaceHover,
        ),
      ),
      checkboxTheme: theme.checkboxTheme.copyWith(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected)
                  ? palette.accent
                  : Colors.transparent,
        ),
      ),
      progressIndicatorTheme: theme.progressIndicatorTheme.copyWith(
        color: palette.accent,
      ),
    );
  }
}

/// Interpolates a whole [ModulePalette], so base and lift move together and
/// the window never passes through a hue neither module owns.
class _PaletteTween extends Tween<ModulePalette> {
  _PaletteTween({super.end});

  @override
  ModulePalette lerp(double t) => ModulePalette.lerp(begin!, end!, t);
}

/// Exposes the active module's palette to the widgets inside it, so a primary
/// action can wear the module's ramp without every page threading it down by
/// hand. Absent outside a module — [ModuleTint.of] returns null there, and the
/// caller falls back to the brand ramp.
class ModuleTint extends InheritedWidget {
  const ModuleTint({super.key, required this.palette, required super.child});

  final ModulePalette palette;

  static ModulePalette? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ModuleTint>()?.palette;

  /// Reads the palette *without* subscribing to it.
  ///
  /// For capturing the module colour at the moment a dialog or a toast is
  /// created. Those live in the root overlay, above `AmbientBackground` in the
  /// tree, so they cannot look the palette up for themselves — the call site
  /// hands it over and re-provides it. Subscribing here would rebuild whatever
  /// widget happened to open the dialog every frame of a module cross-fade.
  static ModulePalette? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ModuleTint>()?.palette;

  @override
  bool updateShouldNotify(ModuleTint old) =>
      old.palette.base != palette.base || old.palette.lift != palette.lift;
}

class _Backdrop extends StatelessWidget {
  const _Backdrop({
    required this.palette,
    required this.colors,
    required this.intensity,
    required this.pattern,
    required this.child,
  });

  final ModulePalette palette;
  final AppColorTokens colors;
  final double intensity;
  final bool pattern;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ModuleTint(
      palette: palette,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              palette.base,
              Color.lerp(palette.base, palette.lift, 0.18)!,
              palette.base,
            ],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Isolated so the backdrop rasterises once and is reused, instead
            // of repainting behind every frame of a spinning scan ring.
            RepaintBoundary(
              child: IgnorePointer(
                child: CustomPaint(
                  isComplex: true,
                  willChange: false,
                  painter: _BackdropPainter(
                    lift: palette.lift,
                    ink: colors.pattern,
                    strength: colors.glowStrength * intensity,
                    pattern: pattern,
                  ),
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  const _BackdropPainter({
    required this.lift,
    required this.ink,
    required this.strength,
    required this.pattern,
  });

  final Color lift;
  final Color ink;
  final double strength;
  final bool pattern;

  /// Grid pitch. Wide enough that the dots read as texture rather than as a
  /// surface you could align something to.
  static const double _dotPitch = 26;
  static const double _dotRadius = 0.9;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    _light(canvas, size);
    if (!pattern) return;
    _rings(canvas, size);
    _dots(canvas, size);
  }

  /// Two overlapping pools of the module's own light, sized off the window so
  /// they hold their shape from the 1100pt minimum up to full screen.
  void _light(Canvas canvas, Size size) {
    final long = size.longestSide;

    void pool(Alignment at, double radiusFactor, double alpha) {
      final a = (alpha * strength).clamp(0.0, 1.0);
      if (a <= 0) return;
      final rect = Rect.fromCircle(
        center: at.alongSize(size),
        radius: long * radiusFactor,
      );
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [lift.withValues(alpha: a), lift.withValues(alpha: 0)],
          ).createShader(rect),
      );
    }

    // The main pool sits high and slightly left of centre — where the page
    // title and the hero ring are, so the brightest part of the window is the
    // part being read.
    pool(const Alignment(-0.25, -0.95), 0.72, 0.62);
    // A weaker counterweight low and right, so the bottom of a long table is
    // not a flat slab of the base colour.
    pool(const Alignment(1.0, 1.05), 0.55, 0.30);
  }

  /// Two oversized circle outlines, mostly off-canvas. A wash of pure gradient
  /// has no scale in it and reads as flat however many stops it has; an edge
  /// somewhere gives the eye something to measure against.
  void _rings(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = ink.withValues(alpha: (ink.a * 1.6).clamp(0.0, 1.0));

    final long = size.longestSide;
    final topRight = Offset(size.width * 1.02, -size.height * 0.18);
    canvas.drawCircle(topRight, long * 0.34, stroke);
    canvas.drawCircle(topRight, long * 0.24, stroke);
    canvas.drawCircle(
      Offset(-size.width * 0.06, size.height * 1.12),
      long * 0.30,
      stroke,
    );
  }

  /// The dot grid — a few thousand points, drawn once into the repaint
  /// boundary's cache.
  void _dots(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = ink
          ..strokeCap = StrokeCap.round
          ..strokeWidth = _dotRadius * 2;

    final columns = (size.width / _dotPitch).ceil() + 1;
    final rows = (size.height / _dotPitch).ceil() + 1;
    canvas.drawPoints(PointMode.points, [
      for (var y = 0; y < rows; y++)
        for (var x = 0; x < columns; x++) Offset(x * _dotPitch, y * _dotPitch),
    ], paint);
  }

  @override
  bool shouldRepaint(_BackdropPainter old) =>
      old.lift != lift ||
      old.ink != ink ||
      old.strength != strength ||
      old.pattern != pattern;
}

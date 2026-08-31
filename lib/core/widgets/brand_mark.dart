import 'package:flutter/material.dart';
import 'package:tidy/core/config/flavor.dart';
import 'package:tidy/core/design/design.dart';

/// The app icon, drawn rather than shipped.
///
/// Same geometry as `assets/icon/src/app_icon.svg` — a Mac screen with a
/// four-point spark inside it — so the splash, the Dock tile and the macOS
/// status item are one mark at three sizes instead of three drawings that
/// drift apart.
///
/// **And the same colours, per flavour.** `scripts/generate_icons.py` renders
/// the Dock tile from a ramp per build: violet for prod, amber for dev. This
/// reads [currentFlavor] and paints the matching one, so a dev build's rail,
/// splash and About card carry the icon that is actually in its Dock. Getting
/// that wrong is the whole failure mode the drawn mark exists to avoid — a dev
/// window wearing the shipping icon is a window you act on thinking it is the
/// real app.
///
/// Drawn with a painter and not a PNG because this appears at 96pt on the
/// splash and 20pt in a rail: an asset would need a variant per size and would
/// still be soft on a scaled display, and the whole thing is four paths.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 96, this.tile = true});

  /// Edge length of the whole mark, tile included.
  final double size;

  /// Draw the tile behind the glyph. Off gives the bare glyph in
  /// [AppColorTokens.textPrimary] — for a rail or a title bar, where a
  /// saturated tile would compete with the page. A bare glyph carries no
  /// flavour: there is no tile to colour, and a title bar is not where a build
  /// announces itself.
  final bool tile;

  /// The shipping tile ramp. Fixed rather than theme-derived: this is the
  /// product's identity, and an icon that changes colour with the OS
  /// appearance is not an identity.
  ///
  /// Stops match `FLAVORS['prod'].ramp` in `scripts/generate_icons.py`.
  static const List<Color> ramp = [
    Color(0xFFD8CCFF),
    Color(0xFF9B7CF6),
    Color(0xFF5B21B6),
  ];

  /// The dev ramp, matching `FLAVORS['dev'].ramp` in the generator.
  ///
  /// Amber, because it is the furthest thing from the brand violet that still
  /// looks deliberate: at rail size the two are never confusable, which is the
  /// entire job of a dev icon.
  static const List<Color> devRamp = [
    Color(0xFFFFE6BE),
    Color(0xFFF59E0B),
    Color(0xFFB45309),
  ];

  /// What the tile casts onto the canvas, per flavour — the generator's
  /// `shadow`. It moves with the ramp rather than being one colour for both:
  /// an amber tile over a violet shadow reads as a rendering bug rather than
  /// as a different build.
  static const Color _shadow = Color(0xFF2A0E5E);
  static const Color _devShadow = Color(0xFF5C2C06);

  /// The ramp and shadow this binary was built for.
  static ({List<Color> ramp, Color shadow}) get tileColors =>
      switch (currentFlavor) {
        Flavor.dev => (ramp: devRamp, shadow: _devShadow),
        Flavor.prod => (ramp: ramp, shadow: _shadow),
      };

  @override
  Widget build(BuildContext context) {
    if (!tile) {
      return CustomPaint(
        size: Size.square(size),
        painter: _MarkPainter(ink: context.colors.textPrimary),
      );
    }

    final tint = tileColors;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        // Apple's continuous corner. The ratio is the one from the icon grid:
        // a plain circular radius at this size reads as a web favicon.
        borderRadius: BorderRadius.circular(size * 0.225),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: tint.ramp,
          stops: const [0, 0.34, 1],
        ),
        boxShadow: [
          BoxShadow(
            color: tint.shadow.withValues(alpha: 0.45),
            blurRadius: size * 0.22,
            offset: Offset(0, size * 0.09),
          ),
        ],
      ),
      // 0.55 is the glyph-to-tile ratio from the icon source; anything larger
      // loses the margin the ramp needs to read as a lit surface.
      child: Center(
        child: CustomPaint(
          size: Size.square(size * 0.55),
          painter: const _MarkPainter(ink: Colors.white),
        ),
      ),
    );
  }
}

/// The glyph, on the 48x48 grid the SVG source uses.
class _MarkPainter extends CustomPainter {
  const _MarkPainter({required this.ink});

  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 48;
    canvas.save();
    canvas.scale(s);

    final stroke =
        Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    final fill =
        Paint()
          ..color = ink
          ..style = PaintingStyle.fill;

    // The screen.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(7, 10, 34, 23),
        const Radius.circular(5),
      ),
      stroke,
    );

    // Neck and foot.
    canvas.drawPath(
      Path()
        ..moveTo(20.5, 33)
        ..lineTo(20.5, 37)
        ..lineTo(27.5, 37)
        ..lineTo(27.5, 33),
      stroke,
    );
    canvas.drawLine(const Offset(16, 39), const Offset(32, 39), stroke);

    // The spark.
    canvas.drawPath(
      Path()
        ..moveTo(24, 14.5)
        ..cubicTo(25.3, 19.3, 27.2, 21.2, 32, 22.5)
        ..cubicTo(27.2, 23.8, 25.3, 25.7, 24, 30.5)
        ..cubicTo(22.7, 25.7, 20.8, 23.8, 16, 22.5)
        ..cubicTo(20.8, 21.2, 22.7, 19.3, 24, 14.5)
        ..close(),
      fill,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.ink != ink;
}

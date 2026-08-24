import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';

/// The app icon, drawn rather than shipped.
///
/// Same geometry as `assets/icon/src/app_icon.svg` — a Mac screen with a
/// four-point spark inside it, on the brand violet ramp — so the splash, the
/// Dock tile and the macOS status item are one mark at three sizes instead of
/// three drawings that drift apart.
///
/// Drawn with a painter and not a PNG because this appears at 96pt on the
/// splash and 20pt in a rail: an asset would need a variant per size and would
/// still be soft on a scaled display, and the whole thing is four paths.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 96, this.tile = true});

  /// Edge length of the whole mark, tile included.
  final double size;

  /// Draw the violet tile behind the glyph. Off gives the bare glyph in
  /// [AppColorTokens.textPrimary] — for a rail or a title bar, where a
  /// saturated tile would compete with the page.
  final bool tile;

  /// The tile ramp. Fixed rather than theme-derived: this is the product's
  /// identity, and an icon that changes colour with the OS appearance is not
  /// an identity.
  static const List<Color> ramp = [
    Color(0xFFD8CCFF),
    Color(0xFF9B7CF6),
    Color(0xFF5B21B6),
  ];

  @override
  Widget build(BuildContext context) {
    if (!tile) {
      return CustomPaint(
        size: Size.square(size),
        painter: _MarkPainter(ink: context.colors.textPrimary),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        // Apple's continuous corner. The ratio is the one from the icon grid:
        // a plain circular radius at this size reads as a web favicon.
        borderRadius: BorderRadius.circular(size * 0.225),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: ramp,
          stops: [0, 0.34, 1],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2A0E5E).withValues(alpha: 0.45),
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

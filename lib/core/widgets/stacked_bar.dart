import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';

/// One slice of a [StackedBar].
class BarSlice {
  const BarSlice({
    required this.label,
    required this.bytes,
    required this.color,
  });

  final String label;
  final int bytes;
  final Color color;
}

/// A composition as one horizontal bar — what makes up a whole, in proportion.
///
/// A bar rather than a pie. At the sizes this app has room for, a donut's small
/// slices are unreadable and unlabellable, while a bar puts every segment on the
/// same baseline where the eye compares lengths well. It is also the same shape
/// as [SizeBar], which the rest of the app already uses to mean "this much of
/// that".
class StackedBar extends StatelessWidget {
  const StackedBar({
    super.key,
    required this.slices,
    this.height = 10,
    this.remainderLabel,
    this.total,
  });

  final List<BarSlice> slices;
  final double height;

  /// The whole the slices are part of. When it exceeds their sum, the gap is
  /// drawn as an unfilled remainder — which is the honest way to show a disk
  /// where we have measured apps and junk but not everything else.
  final int? total;

  final String? remainderLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final measured = slices.fold<int>(0, (sum, slice) => sum + slice.bytes);
    final whole = (total ?? measured).clamp(1, 1 << 62);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: context.motion.slow,
          curve: context.motion.standard,
          builder: (context, progress, _) {
            return SizedBox(
              height: height,
              width: width,
              child: ClipRRect(
                borderRadius: AppRadii.xsAll,
                child: CustomPaint(
                  painter: _StackedBarPainter(
                    slices: slices,
                    whole: whole.toDouble(),
                    progress: progress,
                    trackColor: colors.surfaceRaised,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _StackedBarPainter extends CustomPainter {
  const _StackedBarPainter({
    required this.slices,
    required this.whole,
    required this.progress,
    required this.trackColor,
  });

  final List<BarSlice> slices;
  final double whole;
  final double progress;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = trackColor);

    var x = 0.0;
    for (final slice in slices) {
      if (slice.bytes <= 0) continue;
      final width = (slice.bytes / whole).clamp(0.0, 1.0) * size.width * progress;
      // A slice too thin to see is still a slice that exists; a hairline says
      // so, where rounding it to nothing would silently drop it.
      final drawn = width < 1 ? 1.0 : width;
      canvas.drawRect(
        Rect.fromLTWH(x, 0, drawn, size.height),
        Paint()..color = slice.color,
      );
      x += width;
      if (x >= size.width) break;
    }
  }

  @override
  bool shouldRepaint(_StackedBarPainter old) =>
      old.progress != progress ||
      old.whole != whole ||
      old.trackColor != trackColor ||
      !identical(old.slices, slices);
}

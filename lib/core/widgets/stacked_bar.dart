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

  /// The sliver of track left between one segment and the next.
  ///
  /// Two touching fills read as one shape with a colour change in the middle,
  /// and the eye has to work out where the boundary is from the hue alone —
  /// which is exactly the job that fails first for a colour-blind reader. A gap
  /// draws the boundary instead, so the count of segments survives the colours
  /// being hard to tell apart.
  static const double _gap = 2;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = trackColor);

    final drawable = slices.where((slice) => slice.bytes > 0).toList();
    var x = 0.0;
    for (var i = 0; i < drawable.length; i++) {
      final slice = drawable[i];
      final width =
          (slice.bytes / whole).clamp(0.0, 1.0) * size.width * progress;

      // The gap comes out of the segment's own width rather than being added
      // between them, so the segments still sum to the proportion they stand
      // for. The last one keeps its full width — there is nothing after it to
      // be separated from but the remainder, which is already a different
      // thing.
      final trimmed = i == drawable.length - 1 ? width : width - _gap;
      // A slice too thin to see is still a slice that exists; a hairline says
      // so, where rounding it to nothing would silently drop it.
      final drawn = trimmed < 1 ? 1.0 : trimmed;
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

import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';

/// One period on a [BucketBarChart].
class ChartBucket {
  const ChartBucket({
    required this.at,
    required this.primary,
    this.secondary = 0,
    this.recorded = true,
  });

  /// A period nothing was recorded for. Drawn as a gap, never as a zero.
  const ChartBucket.missing(this.at)
    : primary = 0,
      secondary = 0,
      recorded = false;

  final DateTime at;

  /// Sits on the axis, so the eye reads it first.
  final double primary;

  /// Stacked on top of [primary].
  final double secondary;

  final bool recorded;

  double get total => primary + secondary;
}

/// A time series as stacked bars.
///
/// **A gap is not a zero.** Tidy only records while it is running, and nothing
/// exists before the history store was created — so a period with no data is
/// drawn as a faint stub on the baseline rather than a bar of height zero.
/// Telling someone they reclaimed nothing during a week the app was never open
/// is a claim this chart is in no position to make.
///
/// The structure follows `NetworkUsageChart`, which solved the same problem
/// first; this one is in `core/` because more than one feature draws it.
class BucketBarChart extends StatelessWidget {
  const BucketBarChart({
    super.key,
    required this.buckets,
    required this.primaryColor,
    required this.secondaryColor,
    this.height = 140,
    this.animationKey,
  });

  final List<ChartBucket> buckets;
  final Color primaryColor;
  final Color secondaryColor;
  final double height;

  /// Changing this replays the grow-in, so switching range reads as new data
  /// arriving rather than as two static charts cross-fading.
  final Object? animationKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    var peak = 0.0;
    for (final bucket in buckets) {
      if (bucket.total > peak) peak = bucket.total;
    }

    return SizedBox(
      height: height,
      child: TweenAnimationBuilder<double>(
        key: ValueKey(animationKey),
        tween: Tween(begin: 0, end: 1),
        duration: context.motion.hero,
        curve: context.motion.standard,
        builder: (context, progress, _) {
          return CustomPaint(
            size: Size.infinite,
            painter: _BucketBarsPainter(
              buckets: buckets,
              peak: peak,
              progress: progress,
              primaryColor: primaryColor,
              secondaryColor: secondaryColor,
              gapColor: colors.border,
              gridColor: colors.border,
            ),
          );
        },
      ),
    );
  }
}

class _BucketBarsPainter extends CustomPainter {
  const _BucketBarsPainter({
    required this.buckets,
    required this.peak,
    required this.progress,
    required this.primaryColor,
    required this.secondaryColor,
    required this.gapColor,
    required this.gridColor,
  });

  final List<ChartBucket> buckets;
  final double peak;
  final double progress;
  final Color primaryColor;
  final Color secondaryColor;
  final Color gapColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      Paint()
        ..color = gridColor
        ..strokeWidth = 1,
    );

    if (buckets.isEmpty || peak <= 0) return;

    final slotWidth = size.width / buckets.length;
    // A hairline of breathing room, but never so much that a year of daily
    // bars disappears into the gaps between them.
    final barWidth = (slotWidth - 2).clamp(1.0, 28.0);
    final radius = Radius.circular(barWidth < 4 ? 0 : 2);

    for (var i = 0; i < buckets.length; i++) {
      final bucket = buckets[i];
      final left = i * slotWidth + (slotWidth - barWidth) / 2;

      if (!bucket.recorded) {
        // Visibly a slot with no answer, rather than an answer of zero.
        canvas.drawRect(
          Rect.fromLTWH(left, size.height - 2, barWidth, 2),
          Paint()..color = gapColor,
        );
        continue;
      }

      final total = bucket.total * progress;
      if (total <= 0) continue;

      final height = (total / peak).clamp(0.0, 1.0) * size.height;
      final primaryHeight =
          bucket.total == 0 ? 0.0 : height * (bucket.primary / bucket.total);
      final secondaryHeight = height - primaryHeight;

      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(left, size.height - height, barWidth, secondaryHeight),
          topLeft: radius,
          topRight: radius,
        ),
        Paint()..color = secondaryColor,
      );
      canvas.drawRect(
        Rect.fromLTWH(
          left,
          size.height - primaryHeight,
          barWidth,
          primaryHeight,
        ),
        Paint()..color = primaryColor,
      );
    }
  }

  @override
  bool shouldRepaint(_BucketBarsPainter old) =>
      old.progress != progress ||
      old.peak != peak ||
      old.primaryColor != primaryColor ||
      old.secondaryColor != secondaryColor ||
      old.gapColor != gapColor ||
      !identical(old.buckets, buckets);
}

/// A single series as a filled line — for a level that moves, like free space.
///
/// Separate from [BucketBarChart] because bars mean "how much happened in this
/// period" and a line means "what the value was at this moment", and drawing a
/// level as bars implies the periods add up when they do not.
class BucketLineChart extends StatelessWidget {
  const BucketLineChart({
    super.key,
    required this.buckets,
    required this.color,
    this.height = 140,
    this.animationKey,
  });

  final List<ChartBucket> buckets;
  final Color color;
  final double height;
  final Object? animationKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    var peak = 0.0;
    var trough = double.infinity;
    for (final bucket in buckets) {
      if (!bucket.recorded) continue;
      if (bucket.primary > peak) peak = bucket.primary;
      if (bucket.primary < trough) trough = bucket.primary;
    }
    if (trough == double.infinity) trough = 0;

    return SizedBox(
      height: height,
      child: TweenAnimationBuilder<double>(
        key: ValueKey(animationKey),
        tween: Tween(begin: 0, end: 1),
        duration: context.motion.hero,
        curve: context.motion.standard,
        builder: (context, progress, _) {
          return CustomPaint(
            size: Size.infinite,
            painter: _BucketLinePainter(
              buckets: buckets,
              peak: peak,
              trough: trough,
              progress: progress,
              color: color,
              gridColor: colors.border,
            ),
          );
        },
      ),
    );
  }
}

class _BucketLinePainter extends CustomPainter {
  const _BucketLinePainter({
    required this.buckets,
    required this.peak,
    required this.trough,
    required this.progress,
    required this.color,
    required this.gridColor,
  });

  final List<ChartBucket> buckets;
  final double peak;
  final double trough;
  final double progress;
  final Color color;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      Paint()
        ..color = gridColor
        ..strokeWidth = 1,
    );

    if (buckets.length < 2) return;

    // Headroom above and below so a value that barely moves does not draw as a
    // line welded to the top of the box — and so the shape of a slow decline is
    // still visible when the range is narrow.
    final span = (peak - trough).abs() < 1 ? 1.0 : (peak - trough) * 1.15;
    final base = trough - (peak - trough) * 0.075;
    final step = size.width / (buckets.length - 1);

    double yFor(double value) {
      final fraction = ((value - base) / span).clamp(0.0, 1.0);
      return size.height - fraction * size.height;
    }

    // Recorded runs are drawn as separate paths. Joining across a gap would
    // draw a straight line through a period nobody measured and present it as
    // a smooth trend.
    var index = 0;
    while (index < buckets.length) {
      if (!buckets[index].recorded) {
        index++;
        continue;
      }

      final start = index;
      while (index < buckets.length && buckets[index].recorded) {
        index++;
      }
      final end = index - 1;
      if (end <= start) continue;

      final line = Path()..moveTo(start * step, yFor(buckets[start].primary));
      for (var i = start + 1; i <= end; i++) {
        final x = i * step;
        final target = yFor(buckets[i].primary);
        // Grows in from the baseline rather than sweeping left to right, which
        // keeps the whole shape legible the entire time it animates.
        line.lineTo(x, size.height - (size.height - target) * progress);
      }

      final area =
          Path.from(line)
            ..lineTo(end * step, size.height)
            ..lineTo(start * step, size.height)
            ..close();

      canvas.drawPath(
        area,
        Paint()
          ..style = PaintingStyle.fill
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.30),
              color.withValues(alpha: 0.02),
            ],
          ).createShader(Offset.zero & size),
      );

      canvas.drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeJoin = StrokeJoin.round
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_BucketLinePainter old) =>
      old.progress != progress ||
      old.peak != peak ||
      old.trough != trough ||
      old.color != color ||
      !identical(old.buckets, buckets);
}

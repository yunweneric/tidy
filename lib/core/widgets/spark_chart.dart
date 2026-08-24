import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';

/// Two series of readings over time, drawn as mirrored filled areas.
///
/// Lives in `core/` rather than beside the network feature because the menu bar
/// popover draws one too, and `docs/feature.md` §2 forbids a feature importing
/// from a sibling: a widget two features use moves here.
///
/// Mirrored rather than stacked or overlaid. Overlaid, the two areas hide each
/// other whenever they cross — which on a network chart is most of the time,
/// because a download's acknowledgements make the upload track it. Split about a
/// midline, both are always fully visible and the shape of the traffic is legible
/// without a legend.
class SparkChart extends StatelessWidget {
  const SparkChart({
    super.key,
    required this.down,
    required this.up,
    this.height = 120,
    this.capacity,
    this.showMidline = true,
  });

  /// A compact variant for a menu bar panel: no midline, and short enough to sit
  /// under two lines of numbers.
  const SparkChart.compact({
    super.key,
    required this.down,
    required this.up,
    this.capacity,
  }) : height = 44,
       showMidline = false;

  /// Newest last. Shorter lists draw against the right edge, so a chart that has
  /// just started filling grows leftward rather than stretching two points
  /// across the whole width.
  final List<double> down;
  final List<double> up;

  final double height;

  /// How many slots wide the chart is. Null means "as many as there are
  /// readings", which stretches. Pass the ring's capacity to keep the time axis
  /// honest while it fills.
  final int? capacity;

  final bool showMidline;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final motion = context.motion;

    final peak = _peakOf(down, up);

    return SizedBox(
      height: height,
      width: double.infinity,
      // The ceiling is eased rather than snapped. At one reading a second an
      // instant rescale makes the whole chart jump every time a new maximum
      // arrives, which reads as noise rather than as traffic.
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: peak, end: peak),
        duration: motion.slow,
        curve: motion.smooth,
        builder: (context, ceiling, _) {
          return CustomPaint(
            painter: _SparkPainter(
              down: down,
              up: up,
              ceiling: ceiling,
              slots: capacity ?? down.length,
              downColor: colors.downstream,
              upColor: colors.upstream,
              midlineColor: showMidline ? colors.border : null,
            ),
          );
        },
      ),
    );
  }

  /// Never zero: a flat chart still needs a scale to divide by, and dividing by
  /// the data's own peak is what keeps an ordinary minute from drawing as a flat
  /// line along the floor.
  static double _peakOf(List<double> down, List<double> up) {
    var peak = 0.0;
    for (final value in down) {
      if (value > peak) peak = value;
    }
    for (final value in up) {
      if (value > peak) peak = value;
    }
    return peak <= 0 ? 1 : peak;
  }
}

class _SparkPainter extends CustomPainter {
  const _SparkPainter({
    required this.down,
    required this.up,
    required this.ceiling,
    required this.slots,
    required this.downColor,
    required this.upColor,
    required this.midlineColor,
  });

  final List<double> down;
  final List<double> up;
  final double ceiling;
  final int slots;
  final Color downColor;
  final Color upColor;
  final Color? midlineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final middle = size.height / 2;

    final midlineColor = this.midlineColor;
    if (midlineColor != null) {
      canvas.drawLine(
        Offset(0, middle),
        Offset(size.width, middle),
        Paint()
          ..color = midlineColor
          ..strokeWidth = 1,
      );
    }

    _drawSeries(canvas, size, down, downColor, upward: false);
    _drawSeries(canvas, size, up, upColor, upward: true);
  }

  void _drawSeries(
    Canvas canvas,
    Size size,
    List<double> values,
    Color color, {
    required bool upward,
  }) {
    if (values.length < 2) return;

    final middle = size.height / 2;
    final half = size.height / 2;
    final slotCount = slots < values.length ? values.length : slots;
    final step = size.width / (slotCount - 1);

    // Right-aligned: the newest reading is always at the right edge, so a chart
    // that is still filling grows leftward instead of stretching.
    final offset = size.width - (values.length - 1) * step;

    double yFor(double value) {
      final fraction = (value / ceiling).clamp(0.0, 1.0);
      return upward ? middle - fraction * half : middle + fraction * half;
    }

    final line = Path()..moveTo(offset, yFor(values.first));
    for (var i = 1; i < values.length; i++) {
      line.lineTo(offset + i * step, yFor(values[i]));
    }

    final area =
        Path.from(line)
          ..lineTo(offset + (values.length - 1) * step, middle)
          ..lineTo(offset, middle)
          ..close();

    canvas.drawPath(
      area,
      Paint()
        ..style = PaintingStyle.fill
        ..shader = LinearGradient(
          begin: upward ? Alignment.topCenter : Alignment.bottomCenter,
          end: upward ? Alignment.bottomCenter : Alignment.topCenter,
          colors: [
            color.withValues(alpha: 0.34),
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

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.ceiling != ceiling ||
      old.slots != slots ||
      old.downColor != downColor ||
      old.upColor != upColor ||
      old.midlineColor != midlineColor ||
      !identical(old.down, down) ||
      !identical(old.up, up);
}

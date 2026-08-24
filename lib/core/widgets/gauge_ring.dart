import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';
import 'package:mac_uninstaller/core/widgets/ambient_background.dart';

/// The signature radial gauge.
///
/// Two modes. With a [progress] it draws a determinate arc; with null it
/// sweeps a rotating segment for work of unknown length — which is most
/// filesystem scanning, where the total is not knowable until you have already
/// walked everything.
class GaugeRing extends StatefulWidget {
  const GaugeRing({
    super.key,
    this.progress,
    this.size = 220,
    this.strokeWidth = 10,
    this.gradient,
    this.trackColor,
    this.child,
  });

  /// 0–1, or null for indeterminate.
  final double? progress;

  final double size;
  final double strokeWidth;
  final List<Color>? gradient;
  final Color? trackColor;

  /// Sits in the middle of the ring — usually the byte counter.
  final Widget? child;

  @override
  State<GaugeRing> createState() => _GaugeRingState();
}

class _GaugeRingState extends State<GaugeRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  // Theme lookups are not available in initState, and Reduce Motion can change
  // while the widget is alive, so the spinner is synced from here instead.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSpin();
  }

  @override
  void didUpdateWidget(GaugeRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSpin();
  }

  /// The spinner only runs while it is actually indeterminate — a ticker left
  /// running behind a finished scan is a silent battery cost.
  void _syncSpin() {
    final shouldSpin = widget.progress == null && !context.motion.reduced;
    if (shouldSpin && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!shouldSpin && _spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final motion = context.motion;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _spin,
            builder: (context, _) {
              return TweenAnimationBuilder<double>(
                tween: Tween(end: widget.progress ?? 0),
                duration: motion.hero,
                curve: motion.standard,
                builder: (context, animatedProgress, _) {
                  return CustomPaint(
                    size: Size.square(widget.size),
                    painter: _RingPainter(
                      progress:
                          widget.progress == null ? null : animatedProgress,
                      rotation: _spin.value,
                      strokeWidth: widget.strokeWidth,
                      gradient:
                          widget.gradient ??
                          ModuleTint.of(context)?.ramp ??
                          colors.accentGradient,
                      trackColor: widget.trackColor ?? colors.surfaceHover,
                    ),
                  );
                },
              );
            },
          ),
          if (widget.child != null)
            Padding(
              padding: EdgeInsets.all(widget.strokeWidth * 2.5),
              child: widget.child,
            ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.rotation,
    required this.strokeWidth,
    required this.gradient,
    required this.trackColor,
  });

  final double? progress;
  final double rotation;
  final double strokeWidth;
  final List<Color> gradient;
  final Color trackColor;

  /// Twelve o'clock.
  static const double _start = -math.pi / 2;

  /// How much of the circle the indeterminate segment covers.
  static const double _sweepFraction = 0.22;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final inset = rect.deflate(strokeWidth / 2);

    canvas.drawArc(
      inset,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = trackColor,
    );

    final sweep =
        progress == null
            ? math.pi * 2 * _sweepFraction
            : math.pi * 2 * progress!.clamp(0.0, 1.0);
    if (sweep <= 0) return;

    final startAngle =
        progress == null ? _start + rotation * math.pi * 2 : _start;

    canvas.drawArc(
      inset,
      startAngle,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          colors: [...gradient, gradient.first],
          startAngle: 0,
          endAngle: math.pi * 2,
          transform: GradientRotation(startAngle),
        ).createShader(inset),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.rotation != rotation ||
      old.trackColor != trackColor;
}

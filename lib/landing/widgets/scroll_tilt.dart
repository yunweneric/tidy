import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/landing/widgets/reveal.dart';

/// Leans its child away from the reader as it enters and leaves the window,
/// flattening as it reaches the middle — a laptop lid opening.
///
/// Scroll-linked rather than triggered: the angle tracks the pointer's scroll
/// position continuously, which is what separates it from an entrance
/// animation that happens to involve rotation.
class ScrollTilt extends StatefulWidget {
  const ScrollTilt({
    super.key,
    required this.child,
    this.maxTilt = 20,
    this.minScale = 0.93,
    this.perspective = 0.0011,
    this.flatAt = 0.82,
  });

  final Widget child;

  /// Degrees of lean at the extremes.
  final double maxTilt;

  /// How far the child shrinks at full lean, so it reads as receding rather
  /// than merely rotating.
  final double minScale;

  final double perspective;

  /// The fraction of its own height that has to be visible before the child is
  /// fully flat. Below 1 so it settles before it is completely on screen.
  final double flatAt;

  @override
  State<ScrollTilt> createState() => _ScrollTiltState();
}

class _ScrollTiltState extends State<ScrollTilt> {
  /// -1 fully leaning toward the reader (entering), 0 flat, 1 leaning away.
  final ValueNotifier<double> _tilt = ValueNotifier<double>(-1);

  ScrollController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = LandingScroll.maybeOf(context);
    if (controller == _controller) return;
    _controller?.removeListener(_update);
    _controller = controller?..addListener(_update);
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  @override
  void dispose() {
    // Never removed on trip, unlike Reveal: this one is scrubbable and has to
    // keep answering the scroll for as long as it is mounted.
    _controller?.removeListener(_update);
    _tilt.dispose();
    super.dispose();
  }

  void _update() {
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final viewport = MediaQuery.sizeOf(context).height;
    final height = box.size.height;
    if (viewport <= 0 || height <= 0) return;

    final top = box.localToGlobal(Offset.zero).dy;
    final visible = (math.min(top + height, viewport) - math.max(top, 0.0))
        .clamp(0.0, height);

    // Measured against whichever is smaller: a panel taller than the window can
    // never be fully visible, and would otherwise never reach flat.
    final reach = math.min(height, viewport) * widget.flatAt;
    final flat = (visible / reach).clamp(0.0, 1.0);

    // Visibility alone is symmetric — it cannot tell entering from leaving — so
    // the side of the window the child sits on decides which way the same
    // amount of lean points.
    final leaving = top + height / 2 < viewport / 2;
    _tilt.value = (1 - flat) * (leaving ? 1 : -1);
  }

  @override
  Widget build(BuildContext context) {
    if (context.motion.reduced) return widget.child;

    return AnimatedBuilder(
      animation: _tilt,
      // Built once and only re-composited: the child here is a whole app
      // window, and rebuilding it on every scroll frame would be visible.
      child: widget.child,
      builder: (context, child) {
        final lean = _tilt.value;
        final eased =
            Curves.easeInOut.transform(lean.abs()) * (lean < 0 ? -1 : 1);
        final angle = eased * widget.maxTilt * math.pi / 180;
        final scale = lerpDouble(widget.minScale, 1, 1 - eased.abs())!;

        return Transform(
          alignment: Alignment.center,
          transform:
              Matrix4.identity()
                ..setEntry(3, 2, widget.perspective)
                ..rotateX(angle)
                ..scaleByDouble(scale, scale, 1, 1),
          child: child,
        );
      },
    );
  }
}

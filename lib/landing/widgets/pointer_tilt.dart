import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';

/// Holds its child at a fixed three-quarter angle and leans it toward the
/// pointer.
///
/// Deliberately not the scroll-driven lid used further down the page. A hero is
/// the one thing on a site that is looked at before anything is scrolled, so
/// tying its only movement to the scrollbar means most visitors see it dead
/// still. This answers the pointer instead, and holds a deliberate angle when
/// there is no pointer at all — which is also what it looks like on a phone.
class PointerTilt extends StatefulWidget {
  const PointerTilt({
    super.key,
    required this.child,
    this.maxTilt = 5,
    this.rest = const Offset(-0.75, 0.35),
    this.perspective = 0.0013,
  });

  final Widget child;

  /// Degrees of lean at the far edge of the tracked area.
  final double maxTilt;

  /// Where the child sits when nothing is hovering it, in the same -1..1 space
  /// the pointer is mapped into. Off-centre on purpose: a screenshot square to
  /// the reader is a screenshot, and one turned slightly away is an object.
  final Offset rest;

  final double perspective;

  @override
  State<PointerTilt> createState() => _PointerTiltState();
}

class _PointerTiltState extends State<PointerTilt> {
  late Offset _target = widget.rest;

  void _track(PointerHoverEvent event) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final size = box.size;
    if (size.width <= 0 || size.height <= 0) return;

    final local = box.globalToLocal(event.position);
    setState(() {
      _target = Offset(
        (local.dx / size.width * 2 - 1).clamp(-1.0, 1.0),
        (local.dy / size.height * 2 - 1).clamp(-1.0, 1.0),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final motion = context.motion;
    final radians = widget.maxTilt * math.pi / 180;

    Matrix4 transformFor(Offset at) =>
        Matrix4.identity()
          ..setEntry(3, 2, widget.perspective)
          ..rotateY(-at.dx * radians)
          ..rotateX(at.dy * radians);

    if (motion.reduced) {
      return Transform(
        alignment: Alignment.center,
        transform: transformFor(widget.rest),
        child: widget.child,
      );
    }

    return MouseRegion(
      onHover: _track,
      onExit: (_) => setState(() => _target = widget.rest),
      child: TweenAnimationBuilder<Offset>(
        tween: Tween<Offset>(end: _target),
        // Slower than a hover and eased symmetrically, so following the
        // pointer reads as weight rather than as a cursor effect.
        duration: motion.slow,
        curve: motion.smooth,
        // Built once and only re-composited: the child here is a whole app
        // window, and rebuilding it on every pointer frame would be visible.
        child: widget.child,
        builder:
            (context, at, child) => Transform(
              alignment: Alignment.center,
              transform: transformFor(at),
              child: child,
            ),
      ),
    );
  }
}

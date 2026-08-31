import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// One packed circle: where it ended up, and how big it is.
class PackedCircle {
  const PackedCircle({required this.centre, required this.radius});

  final Offset centre;
  final double radius;
}

/// Packs circles of the given [radii] so that each one touches its neighbours
/// and none of them overlap.
///
/// This is the front-chain algorithm — the same one D3 packs its bubble charts
/// with, and the reason a Space Lens map looks like a map rather than a grid.
/// The idea is small: keep the circles already placed that form the outside of
/// the cluster as a ring, put each new circle in the gap between the pair of
/// them nearest the centre, and if it lands on top of something further round
/// the ring, cut the ring there and try again.
///
/// **Radii must be descending.** Placing the largest first is what keeps the
/// result compact; fed an ascending list it still produces a valid packing, but
/// a straggly one with the big circles pushed to the outside.
///
/// The result is in its own coordinate space, centred on nothing in particular
/// — [fitCircles] is what maps it onto a rectangle.
List<PackedCircle> packCircles(List<double> radii) {
  if (radii.isEmpty) return const [];
  if (radii.length == 1) {
    return [PackedCircle(centre: Offset.zero, radius: radii.first)];
  }

  final nodes = [for (final radius in radii) _Node(radius)];

  // The first three are placed by hand: one at the origin, one beside it, and
  // one in the notch they make. Everything after that has a ring to be placed
  // against, and there is no ring until three circles exist.
  var a = nodes[0]..centre = Offset.zero;
  var b = nodes[1]..centre = Offset(a.radius + nodes[1].radius, 0);

  if (nodes.length == 2) return _collect(nodes);

  var c = nodes[2];
  _place(a, b, c);

  a.next = b;
  b.previous = a;
  b.next = c;
  c.previous = b;
  c.next = a;
  a.previous = c;

  pack:
  for (var i = 3; i < nodes.length; i++) {
    c = nodes[i];
    // Placed against the pair the other way round from the opening trio above,
    // and the order is the whole difference between a packing and a heap: it
    // decides which side of the line through `a` and `b` the new circle lands
    // on, and the wrong side puts it back inside the ring on top of circles
    // already there.
    _place(b, a, c);

    // Walk outwards from the new circle in both directions along the ring,
    // taking the shorter side first, until the two walks meet. Anything the
    // new circle lands on becomes one end of the gap and the placement is
    // tried again — which is why this loop can consume a circle more than once.
    var forward = b.next!;
    var backward = a.previous!;
    var forwardSpan = b.radius;
    var backwardSpan = a.radius;

    do {
      if (forwardSpan <= backwardSpan) {
        if (_overlaps(forward, c)) {
          b = forward;
          a.next = b;
          b.previous = a;
          i--;
          continue pack;
        }
        forwardSpan += forward.radius;
        forward = forward.next!;
      } else {
        if (_overlaps(backward, c)) {
          a = backward;
          a.next = b;
          b.previous = a;
          i--;
          continue pack;
        }
        backwardSpan += backward.radius;
        backward = backward.previous!;
      }
    } while (forward != backward.next);

    // It fits. Splice it into the ring between the pair it was placed against.
    c.previous = a;
    c.next = b;
    a.next = c;
    b.previous = c;
    b = c;

    // Then take the pair closest to the cluster's middle as the next gap to
    // fill, which is what keeps the whole thing growing outwards evenly rather
    // than spiralling off in one direction.
    var best = _score(a);
    for (var node = c.next!; node != b; node = node.next!) {
      final score = _score(node);
      if (score < best) {
        best = score;
        a = node;
      }
    }
    b = a.next!;
  }

  return _collect(nodes);
}

/// Maps a packed cluster onto [area], as large as it will go.
///
/// Fitted by bounding box rather than by enclosing circle: the space a map is
/// given is a rectangle, and fitting the cluster's circle inside it would leave
/// the corners empty for the sake of a shape nobody can see.
List<PackedCircle> fitCircles(
  List<PackedCircle> circles,
  Size area, {
  double padding = 8,
}) {
  if (circles.isEmpty) return circles;

  var left = double.infinity;
  var top = double.infinity;
  var right = -double.infinity;
  var bottom = -double.infinity;

  for (final circle in circles) {
    left = math.min(left, circle.centre.dx - circle.radius);
    top = math.min(top, circle.centre.dy - circle.radius);
    right = math.max(right, circle.centre.dx + circle.radius);
    bottom = math.max(bottom, circle.centre.dy + circle.radius);
  }

  final width = math.max(right - left, 1e-9);
  final height = math.max(bottom - top, 1e-9);
  final usable = Size(
    math.max(area.width - padding * 2, 1),
    math.max(area.height - padding * 2, 1),
  );
  final scale = math.min(usable.width / width, usable.height / height);

  // Centred in whichever direction had room to spare, so a wide cluster in a
  // tall panel sits in the middle rather than against the top edge.
  final offsetX = (area.width - width * scale) / 2 - left * scale;
  final offsetY = (area.height - height * scale) / 2 - top * scale;

  return [
    for (final circle in circles)
      PackedCircle(
        centre: Offset(
          circle.centre.dx * scale + offsetX,
          circle.centre.dy * scale + offsetY,
        ),
        radius: circle.radius * scale,
      ),
  ];
}

/// Puts [c] in the notch between [a] and [b], touching both.
void _place(_Node a, _Node b, _Node c) {
  final dx = b.centre.dx - a.centre.dx;
  final dy = b.centre.dy - a.centre.dy;
  final distance = dx * dx + dy * dy;

  if (distance == 0) {
    c.centre = Offset(a.centre.dx + a.radius + c.radius, a.centre.dy);
    return;
  }

  final fromA = math.pow(a.radius + c.radius, 2).toDouble();
  final fromB = math.pow(b.radius + c.radius, 2).toDouble();

  // Measured from whichever of the two it has to reach furthest around, which
  // is the numerically steadier of the two otherwise identical constructions.
  if (fromA > fromB) {
    final x = (distance + fromB - fromA) / (2 * distance);
    final y = math.sqrt(math.max(0, fromB / distance - x * x));
    c.centre = Offset(
      b.centre.dx - x * dx - y * dy,
      b.centre.dy - x * dy + y * dx,
    );
  } else {
    final x = (distance + fromA - fromB) / (2 * distance);
    final y = math.sqrt(math.max(0, fromA / distance - x * x));
    c.centre = Offset(
      a.centre.dx + x * dx - y * dy,
      a.centre.dy + x * dy + y * dx,
    );
  }
}

/// Overlapping by more than a rounding error. The tolerance is what stops two
/// circles placed *touching* by [_place] from reading as a collision.
bool _overlaps(_Node a, _Node b) {
  final reach = a.radius + b.radius - 1e-6;
  final dx = b.centre.dx - a.centre.dx;
  final dy = b.centre.dy - a.centre.dy;
  return reach > 0 && reach * reach > dx * dx + dy * dy;
}

/// How far the gap between [node] and the one after it sits from the origin.
/// The smallest wins, which is the gap nearest the middle of the cluster.
double _score(_Node node) {
  final a = node;
  final b = node.next!;
  final span = a.radius + b.radius;
  final x = (a.centre.dx * b.radius + b.centre.dx * a.radius) / span;
  final y = (a.centre.dy * b.radius + b.centre.dy * a.radius) / span;
  return x * x + y * y;
}

List<PackedCircle> _collect(List<_Node> nodes) => [
  for (final node in nodes)
    PackedCircle(centre: node.centre, radius: node.radius),
];

/// A circle while it is being packed: its place, and its neighbours on the ring.
class _Node {
  _Node(this.radius);

  final double radius;
  Offset centre = Offset.zero;

  _Node? previous;
  _Node? next;
}

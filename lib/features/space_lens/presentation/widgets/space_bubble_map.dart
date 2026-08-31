import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/widgets/ambient_background.dart';
import 'package:tidy/features/space_lens/data/models/space_level.dart';
import 'package:tidy/features/space_lens/presentation/widgets/circle_packing.dart';

/// One folder as circles, each sized by what it actually occupies.
///
/// Area, not radius, carries the reading — a folder twice the size draws twice
/// the ink. Radius would make it look four times bigger, which is the oldest
/// way to lie with a chart and the reason `SizeBar` exists for everything that
/// can be a bar instead.
///
/// Click selects, double-click opens. That way round because a folder has to be
/// selectable to be removable, and a map where clicking a folder walked into it
/// would leave no way to point at one.
class SpaceBubbleMap extends StatefulWidget {
  const SpaceBubbleMap({
    super.key,
    required this.entries,
    required this.onSelect,
    required this.onOpen,
    this.selectedPath,
    this.onHover,
  });

  /// Biggest first — `SpaceLevel.visible` has already ordered and capped these.
  final List<SpaceEntry> entries;

  final String? selectedPath;
  final ValueChanged<SpaceEntry> onSelect;
  final ValueChanged<SpaceEntry> onOpen;
  final ValueChanged<SpaceEntry?>? onHover;

  @override
  State<SpaceBubbleMap> createState() => _SpaceBubbleMapState();
}

class _SpaceBubbleMapState extends State<SpaceBubbleMap> {
  /// The packing in its own coordinates, which depends only on the sizes. The
  /// panel is resized far more often than the folder changes, so this is kept
  /// and only [fitCircles] re-runs on a resize.
  List<PackedCircle> _packed = const [];

  /// The same circles mapped onto the panel — what is drawn, and what a click
  /// is tested against.
  List<PackedCircle> _fitted = const [];

  SpaceEntry? _hovered;

  @override
  void initState() {
    super.initState();
    _repack();
  }

  @override
  void didUpdateWidget(SpaceBubbleMap old) {
    super.didUpdateWidget(old);
    if (!identical(old.entries, widget.entries)) {
      _hovered = null;
      _repack();
    }
  }

  void _repack() {
    final entries = widget.entries;
    if (entries.isEmpty) {
      _packed = const [];
      return;
    }

    final largest = entries.first.sizeBytes;
    _packed = packCircles([
      for (final entry in entries) _radiusFor(entry.sizeBytes, largest),
    ]);
  }

  /// Area in proportion to bytes, with a floor.
  ///
  /// The floor is the one place the drawing stops being proportional, and it is
  /// the lesser of two wrongs: a folder holding a thousandth of its parent
  /// works out at a circle a third of a point across, which is not a small
  /// bubble but an invisible one — and a map that silently drops what it cannot
  /// draw is worse than one whose smallest circles are all the same size. The
  /// list beside the map carries every figure exactly.
  static double _radiusFor(int bytes, int largest) {
    if (largest <= 0) return _minRadius;
    final radius = 100 * math.sqrt(bytes / largest);
    return math.max(radius, _minRadius);
  }

  static const double _minRadius = 2.6;

  SpaceEntry? _entryAt(Offset point) {
    // Smallest first: they are drawn last and sit on top, so they win a click
    // on the hairline where two circles touch.
    for (var i = _fitted.length - 1; i >= 0; i--) {
      final circle = _fitted[i];
      if ((point - circle.centre).distance <= circle.radius) {
        return widget.entries[i];
      }
    }
    return null;
  }

  void _setHovered(SpaceEntry? entry) {
    if (entry?.path == _hovered?.path && entry?.isGroup == _hovered?.isGroup) {
      return;
    }
    setState(() => _hovered = entry);
    widget.onHover?.call(entry);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final palette = ModuleTint.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final area = Size(constraints.maxWidth, constraints.maxHeight);
        // Written during layout on purpose: these are the circles as drawn, and
        // a click has to be tested against exactly what is on screen. Nothing
        // reads it during the build itself and nothing rebuilds because of it,
        // so it is a cache of the layout rather than state feeding into one.
        _fitted = fitCircles(_packed, area);

        return MouseRegion(
          onHover: (event) => _setHovered(_entryAt(event.localPosition)),
          onExit: (_) => _setHovered(null),
          child: GestureDetector(
            onTapDown: (details) {
              final entry = _entryAt(details.localPosition);
              if (entry != null) widget.onSelect(entry);
            },
            onDoubleTapDown: (details) {
              final entry = _entryAt(details.localPosition);
              if (entry != null && entry.isDrillable) widget.onOpen(entry);
            },
            // Without this the double-tap recogniser never fires, because
            // `onDoubleTapDown` alone does not claim the gesture.
            onDoubleTap: () {},
            child: RepaintBoundary(
              child: CustomPaint(
                size: area,
                painter: _BubblePainter(
                  entries: widget.entries,
                  circles: _fitted,
                  colors: colors,
                  accent: palette?.accent ?? colors.accent,
                  hoveredPath: _hovered?.path,
                  selectedPath: widget.selectedPath,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BubblePainter extends CustomPainter {
  _BubblePainter({
    required this.entries,
    required this.circles,
    required this.colors,
    required this.accent,
    required this.hoveredPath,
    required this.selectedPath,
  });

  final List<SpaceEntry> entries;
  final List<PackedCircle> circles;
  final AppColorTokens colors;
  final Color accent;
  final String? hoveredPath;
  final String? selectedPath;

  /// Below this a label is bigger than the circle holding it.
  static const double _nameRadius = 26;

  /// And below this there is only room for one line of the two.
  static const double _sizeRadius = 40;

  @override
  void paint(Canvas canvas, Size size) {
    if (circles.isEmpty) return;

    final largest = entries.first.sizeBytes;

    for (var i = 0; i < circles.length; i++) {
      final entry = entries[i];
      final circle = circles[i];
      final share = largest <= 0 ? 0.0 : entry.sizeBytes / largest;
      final hovered = entry.path == hoveredPath;
      final selected = entry.path == selectedPath && !entry.isGroup;

      // Folders wear the module's colour and files wear the neutral veil every
      // other surface in the app is made of, so "this is somewhere I can go"
      // is legible before any label is read.
      final fill =
          entry.isDirectory
              ? accent.withValues(
                alpha:
                    _lerp(0.20, 0.52, math.sqrt(share)) + (hovered ? .12 : 0),
              )
              : colors.textPrimary.withValues(
                alpha:
                    _lerp(0.05, 0.14, math.sqrt(share)) + (hovered ? .08 : 0),
              );

      canvas.drawCircle(circle.centre, circle.radius, Paint()..color = fill);

      canvas.drawCircle(
        circle.centre,
        circle.radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2 : 1
          ..color =
              selected
                  ? accent
                  : hovered
                  ? colors.textPrimary.withValues(alpha: 0.45)
                  : colors.border,
      );

      if (circle.radius < _nameRadius) continue;

      final twoLines = circle.radius >= _sizeRadius;
      final maxWidth = circle.radius * 1.55;

      final name = _text(
        entry.name,
        maxWidth,
        colors.textPrimary,
        bold: entry.isDirectory,
      );
      final label =
          twoLines
              ? _text(
                formatBytes(entry.sizeBytes),
                maxWidth,
                colors.textSecondary,
              )
              : null;

      final height = name.height + (label == null ? 0 : label.height + 2);
      var top = circle.centre.dy - height / 2;

      name.paint(canvas, Offset(circle.centre.dx - name.width / 2, top));
      if (label != null) {
        top += name.height + 2;
        label.paint(canvas, Offset(circle.centre.dx - label.width / 2, top));
      }
    }
  }

  TextPainter _text(
    String value,
    double maxWidth,
    Color color, {
    bool bold = false,
  }) => TextPainter(
    text: TextSpan(
      text: value,
      style: TextStyle(
        fontSize: 11,
        height: 1.2,
        fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
        color: color,
      ),
    ),
    maxLines: 1,
    ellipsis: '…',
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: math.max(maxWidth, 12));

  static double _lerp(double a, double b, double t) =>
      a + (b - a) * t.clamp(0.0, 1.0);

  @override
  bool shouldRepaint(_BubblePainter old) =>
      !identical(old.entries, entries) ||
      !identical(old.circles, circles) ||
      old.hoveredPath != hoveredPath ||
      old.selectedPath != selectedPath ||
      old.accent != accent ||
      old.colors != colors;
}

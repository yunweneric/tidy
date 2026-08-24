import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Reports its child's rendered size after every layout.
///
/// The popover is a native window whose height has to be set from the outside,
/// so the panel measures itself and tells `MenuBarController` how tall to be.
class MeasureSize extends StatefulWidget {
  const MeasureSize({super.key, required this.child, required this.onChange});

  final Widget child;
  final ValueChanged<Size> onChange;

  @override
  State<MeasureSize> createState() => _MeasureSizeState();
}

class _MeasureSizeState extends State<MeasureSize> {
  final GlobalKey _key = GlobalKey();
  Size? _lastSize;

  @override
  void initState() {
    super.initState();
    _scheduleMeasurement();
  }

  @override
  void didUpdateWidget(covariant MeasureSize oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleMeasurement();
  }

  void _scheduleMeasurement() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;

      final size = box.size;
      if (_lastSize == size) return;
      _lastSize = size;
      widget.onChange(size);
    });
  }

  @override
  Widget build(BuildContext context) {
    _scheduleMeasurement();
    return SizedBox(key: _key, child: widget.child);
  }
}

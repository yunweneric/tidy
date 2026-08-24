import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';

/// A thin proportional bar, for "this row is 40% of the category".
///
/// Reading a column of byte strings and working out which matters is work;
/// a bar does it at a glance.
class SizeBar extends StatelessWidget {
  const SizeBar({
    super.key,
    required this.fraction,
    this.color,
    this.height = 4,
    this.width,
  });

  final double fraction;
  final Color? color;
  final double height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: LinearProgressIndicator(
          value: fraction.clamp(0.0, 1.0),
          minHeight: height,
          backgroundColor: colors.surfaceHover,
          valueColor: AlwaysStoppedAnimation(color ?? colors.accent),
        ),
      ),
    );
  }
}

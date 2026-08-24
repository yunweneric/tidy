import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/utils/byte_format.dart';

/// A byte count that counts up to its new value instead of snapping.
///
/// Small thing, but it is most of why a scan feels alive: the number climbing
/// while the ring sweeps is the app showing its work. Honours Reduce Motion,
/// where it lands on the final value immediately.
class AnimatedBytes extends StatelessWidget {
  const AnimatedBytes({
    super.key,
    required this.bytes,
    this.valueStyle,
    this.unitStyle,
    this.textAlign = TextAlign.center,
  });

  final int bytes;
  final TextStyle? valueStyle;
  final TextStyle? unitStyle;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final motion = context.motion;
    final value = valueStyle ?? context.text.displayXl;
    final unit = unitStyle ??
        context.text.titleM.copyWith(color: context.colors.textSecondary);

    return TweenAnimationBuilder<double>(
      tween: Tween(end: bytes.toDouble()),
      duration: motion.hero,
      curve: motion.standard,
      builder: (context, animated, _) {
        final parts = splitBytes(animated.round());
        return RichText(
          textAlign: textAlign,
          text: TextSpan(
            style: value,
            children: [
              TextSpan(text: parts.value),
              if (parts.unit.isNotEmpty) ...[
                const TextSpan(text: ' '),
                TextSpan(text: parts.unit, style: unit),
              ],
            ],
          ),
        );
      },
    );
  }
}

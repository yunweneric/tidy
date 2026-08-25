import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/utils/byte_format.dart';

/// A plain count that counts up to its new value instead of snapping.
///
/// The same idea as `AnimatedBytes`, and deliberately not the same widget: that
/// one formats with binary units, so a token count would arrive on screen as
/// `1.1 GiB`. Rather than give a shared widget a formatter parameter for one
/// caller, the forty lines live here, where the only thing they can affect is
/// this page.
class AnimatedCount extends StatelessWidget {
  const AnimatedCount({
    super.key,
    required this.count,
    this.valueStyle,
    this.unitStyle,
    this.textAlign = TextAlign.left,
  });

  final int count;
  final TextStyle? valueStyle;
  final TextStyle? unitStyle;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final motion = context.motion;
    final value = valueStyle ?? context.text.displayXl;
    final unit =
        unitStyle ??
        context.text.titleM.copyWith(color: context.colors.textSecondary);

    return TweenAnimationBuilder<double>(
      tween: Tween(end: count.toDouble()),
      duration: motion.hero,
      curve: motion.standard,
      builder: (context, animated, _) {
        final parts = splitCount(animated.round());
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

import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/utils/duration_format.dart';
import 'package:tidy/features/ai_usage/data/models/ai_usage_summary.dart';

/// One limit window in the popover: what it is, when it rolls over, how far
/// through it you are.
///
/// The right-hand figure is the honesty boundary. A window the provider
/// measures shows a percentage of its own allowance; one Tidy only infers shows
/// the tokens that went through it, because the allowance is not written down
/// anywhere on this Mac and a percentage would be invented. Both draw a bar,
/// and the bar is the only place the two look alike — see [AiUsageWindow].
class MenuBarUsageWindow extends StatelessWidget {
  const MenuBarUsageWindow({
    super.key,
    required this.window,
    required this.now,
  });

  final AiUsageWindow window;

  /// Passed in rather than read here so every row in one repaint agrees about
  /// the time — otherwise two countdowns a frame apart can disagree by a minute.
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final fraction = window.fraction;
    final remaining = window.remainingAt(now);
    final tone = _tone(colors);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md + 2,
        AppSpacing.xs,
        AppSpacing.md + 2,
        AppSpacing.xs + 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Expanded rather than a Spacer after it: the popover is 320pt,
              // and `Session (5h)` next to `Resets in 6d 23h 59m` next to
              // `2.23B tokens` does not fit. Something has to give, and the
              // label is the part the reader can still infer — the other two
              // are the reading. This way the row cannot overflow at all.
              Expanded(
                child: Text(
                  window.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.label.copyWith(color: colors.textPrimary),
                ),
              ),
              if (remaining != null) ...[
                Text(
                  'Resets in ${formatCountdown(remaining)}',
                  maxLines: 1,
                  style: text.caption,
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Text(
                window.isMeasured
                    ? '${window.usedPercent!.toStringAsFixed(1)}%'
                    : '${formatCount(window.tokens)} tokens',
                style: text.label.copyWith(
                  color: window.isMeasured ? tone : colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          _SegmentedBar(
            fraction: fraction,
            color: tone,
            // An inferred window's bar is the clock, not the allowance. Drawing
            // it in the same solid tone as a measured one would make the two
            // rows read as the same kind of fact.
            dimmed: !window.isMeasured,
          ),
        ],
      ),
    );
  }

  /// Green until a window is worth noticing, amber past two thirds, red near
  /// the end. Only ever applied to a measured window — an inferred one has no
  /// threshold to have crossed.
  Color _tone(AppColorTokens colors) {
    final percent = window.usedPercent;
    if (percent == null) return colors.accent;
    if (percent >= 90) return colors.risky;
    if (percent >= 66) return colors.review;
    return colors.safe;
  }
}

/// The track: ten segments, filled left to right.
///
/// Segmented rather than continuous because the popover is 320pt wide and a
/// solid bar at 19% and one at 30% are four points apart — close enough to read
/// as the same. Segments quantise the difference into something countable at a
/// glance, which is the only way this gets read.
class _SegmentedBar extends StatelessWidget {
  const _SegmentedBar({
    required this.fraction,
    required this.color,
    this.dimmed = false,
  });

  /// Null draws an empty track: a window with nothing to say still needs to
  /// take up its row, or the rows below it jump when a reading arrives.
  final double? fraction;
  final Color color;
  final bool dimmed;

  static const int _segments = 10;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final filled = ((fraction ?? 0) * _segments);

    return Row(
      children: [
        for (var i = 0; i < _segments; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          Expanded(
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                // Rounded, not ceiled. Ceiling lights a whole segment — a
                // tenth of the bar — for a window that is 2% used, which
                // over-reports by more than the reading itself. Rounding
                // under-draws instead, and the figure on the right is what
                // carries the precision.
                color:
                    fraction != null && i < filled.round()
                        ? (dimmed ? color.withValues(alpha: 0.45) : color)
                        : colors.surfaceHover,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

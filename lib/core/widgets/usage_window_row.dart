import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/utils/duration_format.dart';
import 'package:tidy/features/ai_usage/data/models/ai_usage_summary.dart';
import 'package:tidy/features/ai_usage/data/models/ai_window_style.dart';

/// One limit window: what it is, how far through it you are, when it rolls
/// over.
///
/// Drawn by the menu bar popover and, on sample data, by the Settings preview
/// that picks the style — which is why it lives in `core/widgets` rather than
/// beside the panel.
///
/// The right-hand figure is the honesty boundary. A window the provider
/// measures shows a percentage of its own allowance; one Tidy only infers shows
/// how far through the *clock* it is, said in those words, because the
/// allowance is not written down anywhere on this Mac and a share of it would
/// be invented. See [AiUsageWindow].
class UsageWindowRow extends StatelessWidget {
  const UsageWindowRow({
    super.key,
    required this.window,
    required this.now,
    this.style = AiWindowStyle.expanded,
  });

  final AiUsageWindow window;

  /// Passed in rather than read here so every row in one repaint agrees about
  /// the time — otherwise two countdowns a frame apart can disagree by a minute.
  final DateTime now;

  final AiWindowStyle style;

  @override
  Widget build(BuildContext context) {
    // The same padding either way. Switching style changes what a row says,
    // and it should not also move the panel's edges.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md + 2,
        AppSpacing.xs,
        AppSpacing.md + 2,
        AppSpacing.xs + 2,
      ),
      child: switch (style) {
        AiWindowStyle.expanded => _Expanded(window: window, now: now),
        AiWindowStyle.compact => _Compact(window: window, now: now),
      },
    );
  }
}

/// The default: a bar of its own, the share beside the name.
///
/// A window with nothing honest to fill a bar with — a trailing seven days has
/// no allowance and no span — draws **no bar at all** rather than an empty one.
/// At this weight an empty track reads as "none of it used", which is a claim
/// about an allowance that does not exist.
class _Expanded extends StatelessWidget {
  const _Expanded({required this.window, required this.now});

  final AiUsageWindow window;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final fraction = window.fraction;
    final tone = _toneOf(window, colors);
    final tokens = '${formatCount(window.tokens)} tokens';

    if (fraction == null) {
      return Row(
        children: [
          Expanded(
            child: Text(
              window.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.label.copyWith(color: colors.textPrimary),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(tokens, style: text.bodyM),
        ],
      );
    }

    final remaining = window.remainingAt(now);
    final footnote = [
      if (remaining != null) 'Resets in ${formatCountdown(remaining)}',
      tokens,
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                window.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.label.copyWith(color: colors.textPrimary),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              _percent(fraction * 100),
              style: text.titleM.copyWith(
                color: window.isMeasured ? tone : colors.textSecondary,
              ),
            ),
            // Only ever on an inferred window, and never abbreviated away. The
            // number beside it is a position on a clock, not a share of an
            // allowance, and this word is the whole difference.
            if (!window.isMeasured) ...[
              const SizedBox(width: AppSpacing.xs),
              Padding(
                padding: const EdgeInsets.only(bottom: 1),
                child: Text('elapsed', style: text.caption),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.xs + 2),
        _SegmentedBar(
          fraction: fraction,
          color: tone,
          // Taller than the compact style's, because here the bar is the row's
          // subject rather than a footnote under a line of text.
          height: 8,
        ),
        const SizedBox(height: AppSpacing.xs + 1),
        Text(
          footnote,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.caption,
        ),
      ],
    );
  }
}

/// One line of text over the bar.
///
/// Two lines a window instead of three, which is what it is for — a panel with
/// four windows in it and a tab strip above them.
class _Compact extends StatelessWidget {
  const _Compact({required this.window, required this.now});

  final AiUsageWindow window;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final fraction = window.fraction;
    final remaining = window.remainingAt(now);
    final tone = _toneOf(window, colors);

    return Column(
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
          // An inferred window's bar is the clock, not the allowance, and this
          // layout has no room for the word that says so — so the bar carries
          // it, a shade back from a measured one. Only a shade: the fill is the
          // reading, and a reading nobody can see is not a distinction, it is a
          // missing bar.
          dimmed: !window.isMeasured,
        ),
      ],
    );
  }
}

/// Green until a window is worth noticing, amber past two thirds, red near the
/// end. Only ever the accent for an inferred window — it has no threshold to
/// have crossed, because it has no allowance to be near the end of.
Color _toneOf(AiUsageWindow window, AppColorTokens colors) {
  final percent = window.usedPercent;
  if (percent == null) return colors.accent;
  if (percent >= 90) return colors.risky;
  if (percent >= 66) return colors.review;
  return colors.safe;
}

/// A share as text, in whole numbers, and never rounded into a lie.
///
/// `100%` says a window is spent and `0%` says it is untouched, so neither is
/// allowed to be the result of rounding towards it: the two ends are held back
/// to `99%` and `<1%` until the reading really is there.
String _percent(double value) {
  final clamped = value.clamp(0.0, 100.0);
  if (clamped > 0 && clamped < 1) return '<1%';
  if (clamped > 99 && clamped < 100) return '99%';
  return '${clamped.round()}%';
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
    this.height = 6,
    this.dimmed = false,
  });

  /// Null draws an empty track: a window with nothing to say still needs to
  /// take up its row, or the rows below it jump when a reading arrives.
  final double? fraction;
  final Color color;
  final double height;
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
              height: height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                // Rounded, not ceiled. Ceiling lights a whole segment — a
                // tenth of the bar — for a window that is 2% used, which
                // over-reports by more than the reading itself. Rounding
                // under-draws instead, and the figure on the right is what
                // carries the precision.
                color:
                    fraction != null && i < filled.round()
                        ? (dimmed ? color.withValues(alpha: 0.78) : color)
                        : colors.borderStrong,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

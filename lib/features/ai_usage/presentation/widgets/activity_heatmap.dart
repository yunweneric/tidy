import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/features/ai_usage/data/models/ai_usage_report.dart';
import 'package:tidy/features/ai_usage/presentation/widgets/usage_note.dart';

/// A contribution grid: one square per day, a column per week.
///
/// The shading runs along the module's own ramp rather than a green scale, so
/// it reads as part of this window rather than as a screenshot from a code
/// host. Days before the earliest log are drawn as an outline with no fill —
/// the same distinction the trend chart makes, because "nothing was used" and
/// "there is no log for this" are different facts and a uniform empty square
/// would say the first when it means the second.
class ActivityHeatmap extends StatelessWidget {
  const ActivityHeatmap({super.key, required this.report, this.weeks = 26});

  final AiUsageReport report;

  /// 26 weeks is what fits at the 1100pt minimum window without the squares
  /// dropping below a legible size.
  final int weeks;

  static const double _cell = 13;
  static const double _gap = 3;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final palette = ModuleTint.of(context);
    final ink = palette?.accent ?? colors.accent;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // End on the Saturday of this week so the last column is complete-shaped,
    // and start weeks - 1 Sundays before it.
    final endOfWeek = today.add(Duration(days: 6 - (today.weekday % 7)));
    final start = endOfWeek.subtract(Duration(days: weeks * 7 - 1));

    final slots = report.span(from: start, to: endOfWeek);
    final peak = slots.fold(
      0,
      (max, slot) =>
          (slot.day?.tokens.total ?? 0) > max ? slot.day!.tokens.total : max,
    );

    return TidyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SectionLabel(
                label: 'The last six months',
                padding: EdgeInsets.zero,
              ),
              const Spacer(),
              Text('Less', style: text.caption),
              const SizedBox(width: AppSpacing.xs),
              for (final step in const [0.0, 0.25, 0.5, 0.75, 1.0])
                Padding(
                  padding: const EdgeInsets.only(right: _gap),
                  child: _Cell(
                    fill: _shade(ink, colors, step),
                    outlined: false,
                  ),
                ),
              const SizedBox(width: AppSpacing.xxs),
              Text('More', style: text.caption),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var week = 0; week < weeks; week++)
                  Padding(
                    padding: const EdgeInsets.only(right: _gap),
                    child: Column(
                      children: [
                        for (var weekday = 0; weekday < 7; weekday++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: _gap),
                            child: _build(
                              context,
                              slots,
                              week * 7 + weekday,
                              peak,
                              ink,
                              colors,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          UsageNote(
            report.coversFrom == null
                ? 'No logs found yet.'
                : 'One square a day. Outlined squares are dates with no log '
                    'at all — the CLIs prune old sessions, so anything '
                    'before ${_date(report.coversFrom!)} is gone rather '
                    'than empty. Busiest day: ${formatCount(peak)} tokens.',
          ),
        ],
      ),
    );
  }

  Widget _build(
    BuildContext context,
    List<({DateTime date, DayUsage? day})> slots,
    int index,
    int peak,
    Color ink,
    AppColorTokens colors,
  ) {
    if (index >= slots.length) {
      return const SizedBox(width: _cell, height: _cell);
    }
    final slot = slots[index];
    if (slot.day == null) {
      return const _Cell(fill: null, outlined: true);
    }
    final total = slot.day!.tokens.total;
    final step = peak == 0 ? 0.0 : (total / peak).clamp(0.0, 1.0);
    return Tooltip(
      message:
          '${_date(slot.date)}\n${formatCount(total)} tokens · '
          '${formatUsd(slot.day!.cost)}',
      child: _Cell(fill: _shade(ink, colors, step), outlined: false),
    );
  }

  /// The ramp. A day with usage never lands on the empty colour, however small
  /// it is — a square that reads as blank when something happened is the same
  /// mistake as a zero standing in for a gap.
  static Color _shade(Color ink, AppColorTokens colors, double step) {
    if (step <= 0) return colors.surfaceRaised;
    final eased = 0.18 + (step * 0.82);
    return Color.lerp(colors.surfaceRaised, ink, eased)!;
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.fill, required this.outlined});

  final Color? fill;
  final bool outlined;

  @override
  Widget build(BuildContext context) => Container(
    width: ActivityHeatmap._cell,
    height: ActivityHeatmap._cell,
    decoration: BoxDecoration(
      color: fill,
      borderRadius: AppRadii.xsAll,
      border: outlined ? Border.all(color: context.colors.border) : null,
    ),
  );
}

const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _date(DateTime at) => '${at.day} ${_months[at.month - 1]} ${at.year}';

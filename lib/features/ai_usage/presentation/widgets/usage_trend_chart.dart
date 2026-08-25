import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/features/ai_usage/data/models/ai_provider.dart';
import 'package:tidy/features/ai_usage/data/models/ai_usage_report.dart';
import 'package:tidy/features/ai_usage/data/models/usage_window.dart';
import 'package:tidy/features/ai_usage/logic/ai_usage_bloc.dart';
import 'package:tidy/features/ai_usage/presentation/widgets/usage_note.dart';

/// Tokens per day, stacked by provider.
///
/// **Tokens, not cost, and that is the honest choice rather than the pretty
/// one.** Codex publishes no per-token price, so a cost chart would draw a
/// heavy Codex week as a flat line and quietly say "you did not use anything".
/// Tokens are complete for both providers, so the shape of the chart is the
/// shape of the work.
///
/// Where a day has no entry the bar is a real zero, not a gap — and that is the
/// opposite of what the network history does, for a reason worth keeping
/// straight. Tidy's own history only records while Tidy is running, so a
/// missing bucket there means "we were not looking". These logs are written by
/// the CLIs whether Tidy exists or not, so a missing day here means you did not
/// use the tool. Days before the earliest log are still gaps: there is nothing
/// to say about them either way.
class UsageTrendChart extends StatelessWidget {
  const UsageTrendChart({
    super.key,
    required this.state,
    required this.onRange,
  });

  final AiUsageState state;
  final ValueChanged<UsageRange> onRange;

  static const double _height = 190;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final days = state.chartDays;
    final claude = colors.seriesAt(0);
    final codex = colors.seriesAt(1);

    return TidyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SectionLabel(
                label: 'Tokens per day',
                padding: EdgeInsets.zero,
              ),
              const SizedBox(width: AppSpacing.lg),
              _Legend(label: AiProvider.claudeCode.label, color: claude),
              const SizedBox(width: AppSpacing.md),
              _Legend(label: AiProvider.codex.label, color: codex),
              const Spacer(),
              SegmentedTabs(
                labels: [for (final r in UsageRange.values) r.label],
                selectedIndex: UsageRange.values.indexOf(state.range),
                onChanged: (index) => onRange(UsageRange.values[index]),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          FadeThrough(
            trigger: state.range,
            child: BucketBarChart(
              buckets: [
                for (final slot in days)
                  if (slot.day case final day?)
                    ChartBucket(
                      at: slot.date,
                      primary:
                          day.byProvider[AiProvider.claudeCode]?.total
                              .toDouble() ??
                          0,
                      secondary:
                          day.byProvider[AiProvider.codex]?.total.toDouble() ??
                          0,
                    )
                  else
                    ChartBucket.missing(slot.date),
              ],
              primaryColor: claude,
              secondaryColor: codex,
              height: _height,
              animationKey: state.range,
            ),
          ),
          _footer(context, days),
        ],
      ),
    );
  }

  Widget _footer(
    BuildContext context,
    List<({DateTime date, DayUsage? day})> days,
  ) {
    final total = days.fold(0, (sum, s) => sum + (s.day?.tokens.total ?? 0));
    final cost = days.fold(0.0, (sum, s) => sum + (s.day?.cost ?? 0));
    final worked = days.where((s) => (s.day?.tokens.total ?? 0) > 0).length;

    final parts = <String>[
      '${formatCount(total)} tokens over $worked of ${days.length} days',
      '${formatUsd(cost)} at API rates',
    ];
    if (state.rangeOutrunsLogs && state.report.coversFrom != null) {
      parts.add(
        'nothing before ${_date(state.report.coversFrom!)} — those logs are '
        'gone, not empty',
      );
    }

    return UsageNote(parts.join(' · '));
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, borderRadius: AppRadii.pillAll),
      ),
      const SizedBox(width: AppSpacing.xs),
      Text(label, style: context.text.caption),
    ],
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

import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/features/ai_usage/data/models/ai_usage_report.dart';
import 'package:tidy/features/ai_usage/data/models/usage_window.dart';
import 'package:tidy/features/ai_usage/logic/ai_usage_bloc.dart';

/// Four spans at a glance. Tapping one moves the chart to it.
///
/// Tokens are the headline on every tile and cost is the detail underneath,
/// which is the other way round from the app this feature borrows its idea
/// from. The reason is on this Mac: Codex has no published per-token price, so
/// a cost-led tile would show a large Codex week as a small number. Tokens are
/// complete for every provider; money is not.
class UsageStatTiles extends StatelessWidget {
  const UsageStatTiles({super.key, required this.state, required this.onRange});

  final AiUsageState state;
  final ValueChanged<UsageRange> onRange;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final report = state.report;
    final today = report.today;

    final month = _thisMonth(report.days);
    final thirty = report.tokensOverLast(30);
    final average = thirty.total ~/ 30;

    final tiles = <Widget>[
      StatTile(
        label: 'Today',
        value: formatCount(today?.tokens.total ?? 0),
        detail: formatUsd(today?.cost ?? 0),
        icon: AppIcons.activity,
        color: colors.seriesAt(0),
        // No range of its own, so no tap and no selected state: a tile that
        // highlights alongside "Last 7 days" would suggest the chart had moved
        // to today when it had not.
      ),
      StatTile(
        label: 'Last 7 days',
        value: formatCount(report.tokensOverLast(7).total),
        detail: formatUsd(report.costOverLast(7)),
        icon: AppIcons.analytics,
        color: colors.seriesAt(1),
        selected: state.range == UsageRange.week,
        onTap: () => onRange(UsageRange.week),
      ),
      StatTile(
        label: 'This month',
        value: formatCount(month.tokens),
        detail: formatUsd(month.cost),
        icon: AppIcons.storage,
        color: colors.seriesAt(2),
        selected: state.range == UsageRange.month,
        onTap: () => onRange(UsageRange.month),
      ),
      StatTile(
        label: 'Daily average',
        value: formatCount(average),
        detail: 'over 30 days',
        icon: AppIcons.cpu,
        color: colors.seriesAt(3),
        selected: state.range == UsageRange.quarter,
        onTap: () => onRange(UsageRange.quarter),
      ),
    ];

    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.md),
          Expanded(child: tiles[i]),
        ],
      ],
    );
  }
}

({int tokens, double cost}) _thisMonth(List<DayUsage> days) {
  final now = DateTime.now();
  var tokens = 0;
  var cost = 0.0;
  for (final day in days) {
    if (day.date.year == now.year && day.date.month == now.month) {
      tokens += day.tokens.total;
      cost += day.cost;
    }
  }
  return (tokens: tokens, cost: cost);
}

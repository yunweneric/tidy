import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/widgets/spark_chart.dart';
import 'package:tidy/features/network/data/models/network_sample.dart';
import 'package:tidy/features/network/data/models/network_series.dart';
import 'package:tidy/features/network/data/models/network_units.dart';

/// The two current rates, over a chart of the last minute.
///
/// The panel's answer to the question the menu bar icon raises but cannot fit:
/// *something* is moving — what, and has it been going long?
class MenuBarNetworkNow extends StatelessWidget {
  const MenuBarNetworkNow({
    super.key,
    required this.sample,
    required this.ticks,
    required this.units,
  });

  final NetworkSample sample;
  final List<NetworkTick> ticks;
  final NetworkUnits units;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // A minute, not five: the panel is a glance, and at 320pt wide five minutes
    // of per-second readings is three pixels a reading.
    final recent = ticks.length > 60 ? ticks.sublist(ticks.length - 60) : ticks;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md + 2,
        AppSpacing.md,
        AppSpacing.md + 2,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _Rate(
                  icon: AppIcons.downstream,
                  color: colors.downstream,
                  value:
                      sample.isKnown
                          ? formatRate(sample.downBytesPerSecond, units: units)
                          : '—',
                ),
              ),
              Expanded(
                child: _Rate(
                  icon: AppIcons.upstream,
                  color: colors.upstream,
                  value:
                      sample.isKnown
                          ? formatRate(sample.upBytesPerSecond, units: units)
                          : '—',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SparkChart.compact(
            down: [for (final tick in recent) tick.down],
            up: [for (final tick in recent) tick.up],
            capacity: 60,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            sample.busiest == null
                ? 'Last minute · nothing moving'
                : 'Last minute · over ${sample.busiest!.label}',
            style: context.text.caption,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _Rate extends StatelessWidget {
  const _Rate({required this.icon, required this.color, required this.value});

  final IconData icon;
  final Color color;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: AppSpacing.xs),
        Text(value, style: context.text.titleM.copyWith(color: color)),
      ],
    );
  }
}

/// One recorded period's total, for the panel's today / this month pair.
class MenuBarNetworkTotal extends StatelessWidget {
  const MenuBarNetworkTotal({
    super.key,
    required this.label,
    required this.headline,
    required this.month,
  });

  final String label;
  final NetworkHeadline headline;

  /// False for today, true for the calendar month.
  final bool month;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final down = month ? headline.monthDownBytes : headline.todayDownBytes;
    final up = month ? headline.monthUpBytes : headline.todayUpBytes;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md + 2,
        vertical: AppSpacing.xs + 1,
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: context.text.bodyS)),
          Icon(AppIcons.downstream, size: 12, color: colors.downstream),
          const SizedBox(width: AppSpacing.xxs),
          Text(formatBytes(down), style: context.text.label),
          const SizedBox(width: AppSpacing.md),
          Icon(AppIcons.upstream, size: 12, color: colors.upstream),
          const SizedBox(width: AppSpacing.xxs),
          Text(formatBytes(up), style: context.text.label),
        ],
      ),
    );
  }
}

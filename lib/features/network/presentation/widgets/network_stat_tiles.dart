import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/features/network/data/models/network_series.dart';
import 'package:tidy/features/network/data/models/network_units.dart';
import 'package:tidy/features/network/logic/network_state.dart';

/// The four figures worth reading before the chart.
class NetworkStatTiles extends StatelessWidget {
  const NetworkStatTiles({
    super.key,
    required this.state,
    required this.units,
    required this.onRange,
  });

  final NetworkState state;
  final NetworkUnits units;

  /// Tapping a tile takes the chart to the span that tile is about.
  final ValueChanged<NetworkRange> onRange;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final headline = state.headline;
    final peak = _peakRate();

    return Row(
      children: [
        Expanded(
          child: StatTile(
            label: 'Today',
            value: formatBytes(headline.todayBytes),
            detail:
                '${formatBytes(headline.todayDownBytes)} down · '
                '${formatBytes(headline.todayUpBytes)} up',
            icon: AppIcons.activity,
            color: colors.downstream,
            onTap: () => onRange(NetworkRange.day),
            selected: state.range == NetworkRange.day,
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: StatTile(
            label: 'This month',
            value: formatBytes(headline.monthBytes),
            detail:
                '${formatBytes(headline.monthDownBytes)} down · '
                '${formatBytes(headline.monthUpBytes)} up',
            icon: AppIcons.analytics,
            color: colors.upstream,
            onTap: () => onRange(NetworkRange.month),
            selected: state.range == NetworkRange.month,
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: StatTile(
            label: 'Fastest in the last 5 minutes',
            // Not "peak ever": the sampler's ring is five minutes long, and
            // labelling a five-minute maximum as an all-time one would be a
            // number that quietly means something else.
            value: peak == null ? '—' : formatRate(peak, units: units),
            icon: AppIcons.performance,
            color: colors.info,
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: StatTile(
            label: 'Busiest day',
            value:
                headline.busiestDay == null
                    ? '—'
                    : formatBytes(headline.busiestDayBytes),
            detail:
                headline.busiestDay == null
                    ? 'Nothing recorded yet'
                    : _dateLabel(headline.busiestDay!),
            icon: AppIcons.storage,
            color: colors.accent,
            onTap:
                headline.busiestDay == null
                    ? null
                    : () => onRange(NetworkRange.all),
            selected: state.range == NetworkRange.all,
          ),
        ),
      ],
    );
  }

  double? _peakRate() {
    if (state.ticks.isEmpty) return null;
    var peak = 0.0;
    for (final tick in state.ticks) {
      final value = tick.down > tick.up ? tick.down : tick.up;
      if (value > peak) peak = value;
    }
    return peak;
  }

  static String _dateLabel(DateTime at) =>
      '${at.day} ${_months[at.month - 1]} ${at.year}';

  static const List<String> _months = [
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
}

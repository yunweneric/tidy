import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/features/network/data/models/network_units.dart';
import 'package:tidy/features/network/logic/network_state.dart';

/// What is happening right now: the two rates, and the last five minutes behind
/// them.
class NetworkNowCard extends StatelessWidget {
  const NetworkNowCard({super.key, required this.state, required this.units});

  final NetworkState state;
  final NetworkUnits units;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final sample = state.sample;
    final busiest = sample.busiest;

    return TidyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Rate(
                  icon: AppIcons.downstream,
                  label: 'Download',
                  color: colors.downstream,
                  // A rate that has not arrived is not 0 B/s. The em dash says
                  // "not read yet", which is what is true for the first second
                  // after the page opens.
                  value:
                      sample.isKnown
                          ? formatRate(sample.downBytesPerSecond, units: units)
                          : '—',
                ),
              ),
              Expanded(
                child: _Rate(
                  icon: AppIcons.upstream,
                  label: 'Upload',
                  color: colors.upstream,
                  value:
                      sample.isKnown
                          ? formatRate(sample.upBytesPerSecond, units: units)
                          : '—',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          SparkChart(
            down: state.downTicks,
            up: state.upTicks,
            capacity: NetworkState.liveCapacity,
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Text('5 minutes ago', style: context.text.overline),
              const Spacer(),
              Text(
                busiest == null
                    ? state.live
                        ? 'Nothing moving'
                        : 'Paused while you are elsewhere'
                    : 'over ${busiest.label}',
                style: context.text.caption,
              ),
              const Spacer(),
              Text('now', style: context.text.overline),
            ],
          ),
        ],
      ),
    );
  }
}

class _Rate extends StatelessWidget {
  const _Rate({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: AppSpacing.xs),
            Text(label, style: context.text.overline),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        // displayL carries tabular figures, which is the only reason a number
        // updating once a second does not shuffle the one beside it.
        Text(value, style: context.text.displayL.copyWith(color: color)),
      ],
    );
  }
}

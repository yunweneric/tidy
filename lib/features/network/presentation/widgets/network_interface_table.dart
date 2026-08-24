import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/features/network/data/models/network_sample.dart';
import 'package:tidy/features/network/data/models/network_series.dart';

/// Which link carried the traffic.
///
/// Worth its own table rather than a line of text: a laptop that moves between
/// Wi-Fi and a dock is two very different bills if one of them is tethered, and
/// "which of these was the hotspot" is the question a data cap makes people ask.
class NetworkInterfaceTable extends StatelessWidget {
  const NetworkInterfaceTable({
    super.key,
    required this.totals,
    required this.live,
  });

  /// The selected range's split, biggest first.
  final List<NetworkInterfaceTotal> totals;

  /// The current reading, for the friendly names — the store keeps BSD names,
  /// which is what stays stable, and SystemConfiguration is what knows that
  /// `en0` is called Wi-Fi.
  final List<NetworkInterfaceRate> live;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final grandTotal = totals.fold<int>(0, (sum, row) => sum + row.totalBytes);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DataTableHeader(
          columnLabels: ['Interface', 'Down', 'Up', 'Share'],
          flexValues: [3, 2, 2, 2],
        ),
        for (final row in totals)
          _Row(
            label: _labelFor(row.name),
            name: row.name,
            downBytes: row.downBytes,
            upBytes: row.upBytes,
            share: grandTotal == 0 ? 0 : row.totalBytes / grandTotal,
            color: colors.downstream,
          ),
        if (totals.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Text(
              'Nothing recorded for this period yet.',
              style: context.text.caption,
            ),
          ),
      ],
    );
  }

  String _labelFor(String name) {
    for (final rate in live) {
      if (rate.name == name) return rate.label;
    }
    return name;
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.name,
    required this.downBytes,
    required this.upBytes,
    required this.share,
    required this.color,
  });

  final String label;
  final String name;
  final int downBytes;
  final int upBytes;
  final double share;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Icon(AppIcons.ethernet, size: 15, color: colors.textMuted),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    label,
                    style: context.text.bodyM,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (label != name) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Text(name, style: context.text.caption),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(formatBytes(downBytes), style: context.text.bodyS),
          ),
          Expanded(
            flex: 2,
            child: Text(formatBytes(upBytes), style: context.text.bodyS),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Expanded(child: SizeBar(fraction: share, color: color)),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 38,
                  child: Text(
                    '${(share * 100).round()}%',
                    style: context.text.caption,
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/utils/byte_format.dart';

/// Which colour is which direction, and how much of each.
class NetworkLegend extends StatelessWidget {
  const NetworkLegend({
    super.key,
    required this.downBytes,
    required this.upBytes,
  });

  final int downBytes;
  final int upBytes;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Key(
          color: colors.downstream,
          label: 'Down',
          value: formatBytes(downBytes),
        ),
        const SizedBox(width: AppSpacing.lg),
        _Key(color: colors.upstream, label: 'Up', value: formatBytes(upBytes)),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.color, required this.label, required this.value});

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, borderRadius: AppRadii.xsAll),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(label, style: context.text.caption),
        const SizedBox(width: AppSpacing.xs),
        Text(
          value,
          style: context.text.label.copyWith(color: context.colors.textPrimary),
        ),
      ],
    );
  }
}

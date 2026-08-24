import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';
import 'package:mac_uninstaller/core/platform/system_bridge.dart';
import 'package:mac_uninstaller/core/widgets/size_bar.dart';
import 'package:mac_uninstaller/features/apps/utils/size_utils.dart';

/// Disk usage at the top of the popover: how full the volume is, and how much
/// of that this app can hand back.
class MenuBarDiskBar extends StatelessWidget {
  const MenuBarDiskBar({super.key, required this.disk, this.reclaimable = 0});

  final DiskUsage disk;
  final int reclaimable;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final unknown = disk.totalBytes == 0;

    final barColor = switch (disk.usedFraction) {
      >= 0.95 => colors.risky,
      >= 0.85 => colors.review,
      _ => colors.accent,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              unknown ? 'Reading disk…' : '${formatBytes(disk.usedBytes)} used',
              style: context.text.titleS,
            ),
            const Spacer(),
            Text(
              unknown ? '' : '${formatBytes(disk.freeBytes)} free',
              style: context.text.caption,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        SizeBar(
          fraction: unknown ? 0 : disk.usedFraction,
          color: barColor,
          height: 5,
        ),
      ],
    );
  }
}

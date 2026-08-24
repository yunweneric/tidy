import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/platform/system_bridge.dart';
import 'package:mac_uninstaller/core/theme/app_theme.dart';
import 'package:mac_uninstaller/features/apps/utils/size_utils.dart';

/// Disk usage summary at the top of the popover: how full the volume is, and
/// how much of that this app can hand back.
class MenuBarDiskBar extends StatelessWidget {
  const MenuBarDiskBar({super.key, required this.disk, this.reclaimable = 0});

  final DiskUsage disk;
  final int reclaimable;

  @override
  Widget build(BuildContext context) {
    final unknown = disk.totalBytes == 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              unknown ? 'Reading disk…' : '${formatBytes(disk.usedBytes)} used',
              style: AppTheme.bodyPrimary.copyWith(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Text(
              unknown ? '' : '${formatBytes(disk.freeBytes)} free',
              style: AppTheme.labelSmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: unknown ? 0 : disk.usedFraction,
            backgroundColor: AppTheme.borderSubtle,
            valueColor: AlwaysStoppedAnimation<Color>(
              disk.usedFraction > 0.9 ? AppTheme.accentRed : AppTheme.accentBlue,
            ),
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/theme/app_theme.dart';
import 'package:mac_uninstaller/core/widgets/widgets.dart';
import 'package:mac_uninstaller/features/apps/utils/size_utils.dart';

/// Row of four summary cards, all driven by the live scan.
class AppSummaryCards extends StatelessWidget {
  const AppSummaryCards({
    super.key,
    required this.totalApps,
    required this.appsSpaceBytes,
    required this.reclaimableBytes,
    required this.unusedCount,
    this.isScanningJunk = false,
    this.onReclaimablePressed,
  });

  final int totalApps;
  final int appsSpaceBytes;
  final int reclaimableBytes;

  /// Apps not launched in the last 90 days.
  final int unusedCount;

  final bool isScanningJunk;
  final VoidCallback? onReclaimablePressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SummaryCard(
          label: 'Total Apps',
          value: '$totalApps',
          icon: Icons.apps,
          accentColor: AppTheme.accentBlue,
        ),
        const SizedBox(width: 16),
        SummaryCard(
          label: 'Apps Space',
          value: formatBytes(appsSpaceBytes),
          icon: Icons.folder_outlined,
          accentColor: AppTheme.accentGreen,
        ),
        const SizedBox(width: 16),
        SummaryCard(
          label: 'Reclaimable',
          value: isScanningJunk && reclaimableBytes == 0
              ? '…'
              : formatBytes(reclaimableBytes),
          icon: Icons.delete_outline,
          accentColor: AppTheme.accentOrange,
          onTap: onReclaimablePressed,
        ),
        const SizedBox(width: 16),
        SummaryCard(
          label: 'Unused (90d+)',
          value: '$unusedCount',
          icon: Icons.warning_amber_rounded,
          accentColor: AppTheme.accentRed,
        ),
      ],
    );
  }
}

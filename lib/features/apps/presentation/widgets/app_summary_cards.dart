import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/theme/app_theme.dart';
import 'package:mac_uninstaller/core/widgets/widgets.dart';

/// Row of four summary cards: Total Apps, Apps Space, System Junk, Unused (30d+).
class AppSummaryCards extends StatelessWidget {
  const AppSummaryCards({
    super.key,
    required this.totalApps,
    required this.appsSpace,
    this.systemJunk = '1.8 GB',
    this.unusedCount = '12',
  });

  final int totalApps;
  final String appsSpace;
  final String systemJunk;
  final String unusedCount;

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
          value: appsSpace,
          icon: Icons.folder_outlined,
          accentColor: AppTheme.accentGreen,
        ),
        const SizedBox(width: 16),
        SummaryCard(
          label: 'System Junk',
          value: systemJunk,
          icon: Icons.delete_outline,
          accentColor: AppTheme.accentOrange,
        ),
        const SizedBox(width: 16),
        SummaryCard(
          label: 'Unused (30d+)',
          value: unusedCount,
          icon: Icons.warning_amber_rounded,
          accentColor: AppTheme.accentRed,
        ),
      ],
    );
  }
}

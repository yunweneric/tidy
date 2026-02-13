import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/theme/app_theme.dart';
import 'package:mac_uninstaller/core/widgets/widgets.dart';

/// Application sidebar with logo, navigation, and storage card.
class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    this.currentRoute = 'Applications',
    this.onNavTap,
    this.storageUsed = 342,
    this.storageTotal = 512,
    this.onUpgradeStorage,
  });

  final String currentRoute;
  final ValueChanged<String>? onNavTap;
  final int storageUsed;
  final int storageTotal;
  final VoidCallback? onUpgradeStorage;

  static const List<({String label, IconData icon})> _mainNav = [
    (label: 'Dashboard', icon: Icons.dashboard_outlined),
    (label: 'Applications', icon: Icons.apps),
    (label: 'System Junk', icon: Icons.delete_outline),
    (label: 'Cleanup History', icon: Icons.history),
  ];

  static const List<({String label, IconData icon})> _managementNav = [
    (label: 'Unused Apps', icon: Icons.download_outlined),
    (label: 'Settings', icon: Icons.settings_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      decoration: const BoxDecoration(
        color: AppTheme.backgroundSidebar,
        border: Border(right: BorderSide(color: AppTheme.borderSubtle)),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            _buildLogo(),
            const SizedBox(height: 32),
            ..._mainNav.map((e) => NavItem(
                  icon: e.icon,
                  label: e.label,
                  active: e.label == currentRoute,
                  onTap: () => onNavTap?.call(e.label),
                )),
            const SizedBox(height: 16),
            const SectionLabel(label: 'MANAGEMENT'),
            const SizedBox(height: 8),
            ..._managementNav.map((e) => NavItem(
                  icon: e.icon,
                  label: e.label,
                  active: e.label == currentRoute,
                  onTap: () => onNavTap?.call(e.label),
                )),
            const Spacer(),
            StorageCard(
              usedLabel: '$storageUsed GB of $storageTotal GB used',
              progress: storageTotal > 0 ? storageUsed / storageTotal : 0,
              buttonLabel: 'Upgrade Storage',
              onButtonPressed: onUpgradeStorage,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.accentBlue.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.cleaning_services,
              color: AppTheme.accentBlue,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'MacUninstaller',
                  style: AppTheme.bodyPrimary.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                Text('PRO EDITION', style: AppTheme.labelSmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/platform/system_bridge.dart';
import 'package:mac_uninstaller/core/theme/app_theme.dart';
import 'package:mac_uninstaller/core/widgets/widgets.dart';
import 'package:mac_uninstaller/features/apps/presentation/widgets/app_list_toolbar.dart';
import 'package:mac_uninstaller/features/apps/utils/size_utils.dart';

/// Sidebar with logo, navigation, and live storage status.
///
/// Every entry maps to a view that actually exists — there are no decorative
/// destinations.
class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.filter,
    required this.onFilterChanged,
    required this.disk,
    required this.reclaimableBytes,
    this.onCleanupPressed,
  });

  final AppFilter filter;
  final ValueChanged<AppFilter> onFilterChanged;
  final DiskUsage disk;
  final int reclaimableBytes;
  final VoidCallback? onCleanupPressed;

  static const Map<AppFilter, IconData> _navIcons = {
    AppFilter.all: Icons.apps,
    AppFilter.large: Icons.folder_outlined,
    AppFilter.unused: Icons.hourglass_empty,
  };

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
            const SectionLabel(label: 'APPLICATIONS'),
            const SizedBox(height: 8),
            for (final entry in _navIcons.entries)
              NavItem(
                icon: entry.value,
                label: entry.key.label,
                active: filter == entry.key,
                onTap: () => onFilterChanged(entry.key),
              ),
            const SizedBox(height: 16),
            const SectionLabel(label: 'STORAGE'),
            const SizedBox(height: 8),
            NavItem(
              icon: Icons.delete_outline,
              label: 'Reclaimable Space',
              onTap: onCleanupPressed,
            ),
            const Spacer(),
            _buildFullDiskAccessHint(),
            const SizedBox(height: 12),
            StorageCard(
              usedLabel: disk.totalBytes == 0
                  ? 'Reading disk usage…'
                  : '${formatBytes(disk.usedBytes)} of ${formatBytes(disk.totalBytes)} used',
              progress: disk.usedFraction,
              buttonLabel: reclaimableBytes > 0
                  ? 'Free up ${formatBytes(reclaimableBytes)}'
                  : 'Free up space',
              onButtonPressed: onCleanupPressed,
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
                Text('Menu bar + full app', style: AppTheme.labelSmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Some leftovers live in TCC-protected folders; this is the only way to
  /// reach them, so surface it rather than silently under-reporting.
  Widget _buildFullDiskAccessHint() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: TextButton.icon(
        onPressed: SystemBridge.openFullDiskAccessSettings,
        icon: const Icon(Icons.lock_open_outlined, size: 15),
        label: const Text('Full Disk Access', style: TextStyle(fontSize: 12)),
        style: TextButton.styleFrom(
          foregroundColor: AppTheme.textSecondary,
          padding: EdgeInsets.zero,
          alignment: Alignment.centerLeft,
        ),
      ),
    );
  }
}

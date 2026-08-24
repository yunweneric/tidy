import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';
import 'package:mac_uninstaller/core/platform/system_bridge.dart';
import 'package:mac_uninstaller/core/widgets/permission_banner.dart';
import 'package:mac_uninstaller/features/shell/domain/app_destination.dart';
import 'package:mac_uninstaller/features/shell/presentation/widgets/sidebar_nav_item.dart';
import 'package:mac_uninstaller/features/shell/presentation/widgets/storage_summary.dart';

/// The app's permanent left rail.
class NavSidebar extends StatelessWidget {
  const NavSidebar({
    super.key,
    required this.current,
    required this.onSelect,
    required this.disk,
    this.badges = const {},
    this.reclaimableBytes = 0,
    this.fullDiskAccessGranted,
    this.onGrantAccess,
    this.onReclaim,
  });

  static const double width = 236;

  final AppDestination current;
  final ValueChanged<AppDestination> onSelect;
  final DiskUsage disk;

  /// Per-destination trailing text, e.g. reclaimable size on Cleanup.
  final Map<AppDestination, String> badges;

  final int reclaimableBytes;

  /// Null while the probe is still running.
  final bool? fullDiskAccessGranted;

  final VoidCallback? onGrantAccess;
  final VoidCallback? onReclaim;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: width,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors.sidebarGradient,
        ),
        border: Border(right: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _BrandBlock(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              children: [
                ..._group(context, NavGroup.primary),
                const SizedBox(height: AppSpacing.lg),
                _SectionLabel(label: 'MORE'),
                ..._group(context, NavGroup.secondary),
              ],
            ),
          ),
          if (fullDiskAccessGranted == false && onGrantAccess != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: PermissionBanner(
                compact: true,
                onOpenSettings: onGrantAccess!,
              ),
            ),
          StorageSummary(
            disk: disk,
            reclaimableBytes: reclaimableBytes,
            onPressed: onReclaim,
          ),
          const SizedBox(height: AppSpacing.md),
          Divider(height: 1, color: colors.border),
          const SizedBox(height: AppSpacing.sm),
          ..._group(context, NavGroup.footer),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }

  List<Widget> _group(BuildContext context, NavGroup group) => [
    for (final destination in AppDestination.of(group))
      SidebarNavItem(
        icon: destination.icon,
        label: destination.label,
        active: destination == current,
        badge: badges[destination],
        badgeColor: context.colors.safe,
        onTap: () => onSelect(destination),
      ),
  ];
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl + AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.sm,
      ),
      child: Text(label, style: context.text.overline),
    );
  }
}

class _BrandBlock extends StatelessWidget {
  const _BrandBlock();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.titleBar + AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xxl,
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors.accentGradient,
              ),
              borderRadius: AppRadii.mdAll,
              boxShadow: [
                BoxShadow(
                  color: colors.accentGradient.last.withValues(alpha: 0.30),
                  blurRadius: 14,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(Brand.mark, size: 17, color: colors.textOnAccent),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  Brand.name,
                  style: context.text.titleM.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(Brand.subtitle, style: context.text.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

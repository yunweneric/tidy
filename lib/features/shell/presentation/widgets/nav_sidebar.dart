import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/platform/system_bridge.dart';
import 'package:tidy/core/widgets/brand_mark.dart';
import 'package:tidy/core/widgets/permission_banner.dart';
import 'package:tidy/features/shell/domain/app_destination.dart';
import 'package:tidy/features/shell/presentation/widgets/sidebar_nav_item.dart';
import 'package:tidy/features/shell/presentation/widgets/storage_summary.dart';

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
                const _SectionLabel(label: 'MORE'),
                ..._group(context, NavGroup.secondary),
                const SizedBox(height: AppSpacing.lg),
                // Everything below this heading opens onto a roadmap rather
                // than a working page, which is worth saying once here instead
                // of six times after the click.
                const _SectionLabel(label: 'ON THE WAY', badge: 'SOON'),
                ..._group(context, NavGroup.soon),
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
  const _SectionLabel({required this.label, this.badge});

  final String label;

  /// An optional pill beside the heading, for a group whose rows all share
  /// something the rows themselves do not say — currently only SOON.
  ///
  /// On the heading rather than on every row: six identical badges down the
  /// rail is noise, and the thing being labelled is the group.
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl + AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: context.text.overline,
            ),
          ),
          if (badge != null) ...[
            const SizedBox(width: AppSpacing.sm),
            _SoonBadge(label: badge!),
          ],
        ],
      ),
    );
  }
}

/// The SOON pill.
///
/// Not [AppPill]: that one is sized for body text in a page, and at the rail's
/// overline size it would be taller than the heading it sits beside. Muted
/// accent rather than a warning colour — unbuilt is a statement of fact, not a
/// problem the user has to deal with.
class _SoonBadge extends StatelessWidget {
  const _SoonBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: colors.accentMuted,
        borderRadius: AppRadii.pillAll,
      ),
      child: Text(
        label,
        style: context.text.overline.copyWith(
          color: colors.accent,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _BrandBlock extends StatelessWidget {
  const _BrandBlock();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.titleBar + AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xxl,
      ),
      child: Row(
        children: [
          // The app icon itself, not a stand-in for it. This used to be a
          // sparkles glyph on the accent ramp, which was a different drawing
          // from the one in the Dock — the rail now shows the same mark the
          // user clicked to get here.
          const BrandMark(size: 30),
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

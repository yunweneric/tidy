import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/features/shell/domain/app_destination.dart';
import 'package:tidy/features/shell/presentation/widgets/sidebar_nav_item.dart';
import 'package:tidy/landing/preview/preview_mac.dart';

/// macOS window chrome, drawn rather than captured.
///
/// A capture is frozen in whatever appearance it was taken in and cannot be
/// poked at. This repaints with the site's theme and answers the pointer, which
/// is the entire reason the preview exists.
class PreviewTitleBar extends StatelessWidget {
  const PreviewTitleBar({super.key, required this.title});

  final String title;

  /// The system colours. Literal by nature — these are Apple's, not ours, and
  /// they do not change with the app's palette.
  static const List<Color> _lights = [
    Color(0xFFFF5F57),
    Color(0xFFFEBC2E),
    Color(0xFF28C840),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: double.infinity,
      height: 38,
      decoration: BoxDecoration(
        color: colors.sidebar,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            '${Brand.name} — $title',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: colors.textMuted,
            ),
          ),
          Positioned(
            left: 14,
            child: Row(
              children: [
                for (final light in _lights)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: light,
                        shape: BoxShape.circle,
                      ),
                      child: const SizedBox.square(dimension: 11),
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

/// The preview's navigation rail — the app's own, minus the parts that need a
/// real disk underneath them.
///
/// Rows are built from [AppDestination] rather than a list of its own, so the
/// modules, their order, their glyphs and their grouping are whatever the app
/// says they are. The ones that are not built yet render as real rows carrying
/// a "Soon" badge and go nowhere, which is exactly what they do in the app: a
/// cleaner reporting "0 threats found" from a scanner that does not exist is
/// lying, and neither the product nor its marketing page does that.
class PreviewSidebar extends StatelessWidget {
  const PreviewSidebar({
    super.key,
    required this.mac,
    required this.screen,
    this.onNavigate,
  });

  static const double width = 236;

  final PreviewMac mac;
  final PreviewScreen screen;
  final ValueChanged<PreviewScreen>? onNavigate;

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
              physics: const NeverScrollableScrollPhysics(),
              children: [
                ..._group(context, NavGroup.primary),
                const SizedBox(height: AppSpacing.lg),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl + AppSpacing.xs,
                    AppSpacing.sm,
                    AppSpacing.xl,
                    AppSpacing.sm,
                  ),
                  child: Text('MORE', style: context.text.overline),
                ),
                ..._group(context, NavGroup.secondary),
              ],
            ),
          ),
          _PreviewStorage(
            mac: mac,
            onReclaim: () => onNavigate?.call(PreviewScreen.smartCare),
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
      _row(context, destination),
  ];

  Widget _row(BuildContext context, AppDestination destination) {
    final target = PreviewScreen.forDestination(destination);
    final reclaimable = mac.reclaimableBytes;

    return SidebarNavItem(
      icon: destination.icon,
      label: destination.label,
      active: target == screen,
      badge: switch (destination) {
        AppDestination.smartCare when reclaimable > 0 => formatBytes(
          reclaimable,
        ),
        _ when kPlannedDestinations.contains(destination) => 'Soon',
        _ => null,
      },
      badgeColor:
          destination == AppDestination.smartCare
              ? context.colors.safe
              : context.colors.textMuted,
      // A destination with no pane still draws a real row and still does
      // nothing, which is what it does in the app too.
      onTap: target == null ? () {} : () => onNavigate?.call(target),
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
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xxl,
      ),
      child: Row(
        children: [
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

/// Disk usage at the foot of the rail.
///
/// A copy of the app's `StorageSummary` rather than the widget itself: that one
/// takes a `DiskUsage` from `core/platform/system_bridge.dart`, which reaches
/// `dart:io` through the trash ledger and does not compile for web.
class _PreviewStorage extends StatelessWidget {
  const _PreviewStorage({required this.mac, this.onReclaim});

  final PreviewMac mac;
  final VoidCallback? onReclaim;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fraction = mac.usedFraction;

    // Past 85% free space is the actual problem, and the bar should say so
    // without being asked.
    final barColor = switch (fraction) {
      >= 0.95 => colors.risky,
      >= 0.85 => colors.review,
      _ => colors.accent,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors.surfaceGradient,
          ),
          borderRadius: AppRadii.mdAll,
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('STORAGE', style: context.text.overline),
                const Spacer(),
                Text(
                  '${(fraction * 100).round()}%',
                  style: context.text.caption.copyWith(
                    color: barColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            SizeBar(fraction: fraction, color: barColor, height: 5),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${formatBytes(mac.freeBytes)} free of '
              '${formatBytes(PreviewMac.diskTotalBytes)}',
              style: context.text.caption,
            ),
            if (mac.reclaimableBytes > 0) ...[
              const SizedBox(height: AppSpacing.md),
              GradientButton(
                label: 'Reclaim ${formatBytes(mac.reclaimableBytes)}',
                onPressed: onReclaim,
                size: GradientButtonSize.compact,
                expand: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A table header row, sized by flex weights.
class PreviewTableHeader extends StatelessWidget {
  const PreviewTableHeader({super.key, required this.cells});

  /// `(flex weight, label)` per column.
  final List<(int, String)> cells;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          for (final (flex, label) in cells)
            Expanded(
              flex: flex,
              child: Text(label.toUpperCase(), style: context.text.overline),
            ),
        ],
      ),
    );
  }
}

/// One row of a preview table, with the app's hover wash.
class PreviewRow extends StatefulWidget {
  const PreviewRow({
    super.key,
    required this.child,
    this.onTap,
    this.last = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool last;

  @override
  State<PreviewRow> createState() => _PreviewRowState();
}

class _PreviewRowState extends State<PreviewRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return MouseRegion(
      cursor:
          widget.onTap == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: context.motion.fast,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: _hovered ? colors.surfaceHover : Colors.transparent,
            border:
                widget.last
                    ? null
                    : Border(bottom: BorderSide(color: colors.border)),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// A bordered frame around a header and its rows.
class PreviewTable extends StatelessWidget {
  const PreviewTable({super.key, required this.header, required this.rows});

  final Widget header;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors.surfaceGradient,
        ),
        borderRadius: AppRadii.lgAll,
        border: Border.all(color: colors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.lg - 1),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [header, ...rows],
        ),
      ),
    );
  }
}

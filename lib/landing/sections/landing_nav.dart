import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/landing/data/tidy_repo.dart';
import 'package:tidy/landing/state/landing_controller.dart';
import 'package:tidy/landing/widgets/glass_panel.dart';
import 'package:tidy/landing/widgets/landing_button.dart';
import 'package:tidy/landing/widgets/landing_layout.dart';

/// One entry in the navigation bar.
@immutable
class NavTarget {
  const NavTarget({required this.id, required this.label, required this.onTap});

  final String id;
  final String label;
  final VoidCallback onTap;
}

const double _kControlHeight = 40;
const double _kRestWidth = kLandingMaxWidth;
const double _kShrunkWidth = 940;
const double _kRestHeight = 68;
const double _kShrunkHeight = 58;
const double _kRestTop = 18;
const double _kShrunkTop = 10;

/// The floating bar. Draws in as the page scrolls under it, so it takes less
/// room once the visitor is reading rather than arriving.
class LandingNav extends StatelessWidget {
  const LandingNav({
    super.key,
    required this.controller,
    required this.targets,
    required this.menuTargets,
    required this.scrolled,
    required this.onDownload,
  });

  final LandingController controller;

  /// The three links the bar has room for.
  final List<NavTarget> targets;

  /// Every link, for the sheet the bar collapses into. Below `large` there is
  /// no width to lose, so the narrow layout gets the fuller menu rather than
  /// the shorter one.
  final List<NavTarget> menuTargets;

  final bool scrolled;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final motion = context.motion;
    final size = context.windowSize;
    final collapsed = size.isBelow(WindowSizeClass.large);
    final gutter = size.resolve<double>(compact: 12, medium: 20, expanded: 28);

    final height = scrolled ? _kShrunkHeight : _kRestHeight;

    // Clamped to the window, not just given a target. The bar is `Positioned`
    // across the top of a `Stack` whose other child is the page, so a fixed
    // 1180 on a phone does not get clipped — it makes the whole page 1180 wide
    // and the site scrolls sideways.
    final available = MediaQuery.sizeOf(context).width - gutter * 2;
    final width = math.min(scrolled ? _kShrunkWidth : _kRestWidth, available);

    return Align(
      alignment: Alignment.topCenter,
      child: AnimatedContainer(
        duration: motion.slow,
        curve: motion.standard,
        margin: EdgeInsets.only(
          top: scrolled ? _kShrunkTop : _kRestTop,
          left: gutter,
          right: gutter,
        ),
        width: width,
        height: height,
        child: GlassPanel(
          borderRadius: BorderRadius.circular(height / 2),
          blur: scrolled ? 26 : 16,
          opacity: scrolled ? 1 : 0.72,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child:
                collapsed
                    ? _CollapsedBar(
                      controller: controller,
                      targets: menuTargets,
                      onDownload: onDownload,
                    )
                    : _FullBar(
                      controller: controller,
                      targets: targets,
                      onDownload: onDownload,
                    ),
          ),
        ),
      ),
    );
  }
}

class _FullBar extends StatelessWidget {
  const _FullBar({
    required this.controller,
    required this.targets,
    required this.onDownload,
  });

  final LandingController controller;
  final List<NavTarget> targets;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    // Both flanks are Expanded so the centred links stay centred when the star
    // count arrives and the right-hand cluster grows.
    return Row(
      children: [
        const Expanded(
          child: Align(alignment: Alignment.centerLeft, child: _Mark()),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final target in targets)
              _NavLink(
                target: target,
                active: target.id == controller.activeAnchor,
              ),
          ],
        ),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: _Controls(controller: controller, onDownload: onDownload),
          ),
        ),
      ],
    );
  }
}

class _CollapsedBar extends StatelessWidget {
  const _CollapsedBar({
    required this.controller,
    required this.targets,
    required this.onDownload,
  });

  final LandingController controller;
  final List<NavTarget> targets;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _Mark(),
        const Spacer(),
        _ThemeToggle(controller: controller),
        const SizedBox(width: AppSpacing.sm),
        LandingButton(
          label: 'Download',
          icon: AppIcons.downloads,
          height: _kControlHeight,
          onPressed: onDownload,
        ),
        const SizedBox(width: AppSpacing.sm),
        LandingButton(
          label: 'Menu',
          icon: AppIcons.allTools,
          kind: LandingButtonKind.ghost,
          height: _kControlHeight,
          iconOnly: true,
          onPressed: () => _openSheet(context),
        ),
      ],
    );
  }

  void _openSheet(BuildContext context) {
    final colors = context.colors;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surfaceOpaque,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
      ),
      builder:
          (sheetContext) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: AppSpacing.md),
                for (final target in targets)
                  ListTile(
                    title: Text(target.label, style: context.text.titleM),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      target.onTap();
                    },
                  ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const BrandMark(size: 26),
        const SizedBox(width: AppSpacing.sm + 2),
        Text(
          Brand.name,
          style: context.text.titleM.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.controller, required this.onDownload});

  final LandingController controller;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final stars = controller.stars;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ThemeToggle(controller: controller),
        const SizedBox(width: AppSpacing.sm),
        // Hidden until GitHub answers. A star chip reading "—" says the page is
        // broken; no chip says nothing at all, which is correct.
        if (stars != null) ...[
          _StarChip(count: stars),
          const SizedBox(width: AppSpacing.sm),
        ],
        LandingButton(
          label: 'Download for macOS',
          icon: AppIcons.downloads,
          height: _kControlHeight,
          onPressed: onDownload,
        ),
      ],
    );
  }
}

class _ThemeToggle extends StatelessWidget {
  const _ThemeToggle({required this.controller});

  final LandingController controller;

  @override
  Widget build(BuildContext context) {
    return LandingButton(
      label: controller.isDark ? 'Switch to light' : 'Switch to dark',
      icon: controller.isDark ? AppIcons.light : AppIcons.dark,
      kind: LandingButtonKind.ghost,
      height: _kControlHeight,
      iconOnly: true,
      onPressed: controller.toggleBrightness,
    );
  }
}

class _StarChip extends StatelessWidget {
  const _StarChip({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => openExternalUrl(TidyRepo.url),
        child: Container(
          height: _kControlHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: colors.surfaceHover,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(AppIcons.brand, size: 15, color: colors.review),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '$count',
                style: context.text.label.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavLink extends StatefulWidget {
  const _NavLink({required this.target, required this.active});

  final NavTarget target;
  final bool active;

  @override
  State<_NavLink> createState() => _NavLinkState();
}

class _NavLinkState extends State<_NavLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final lit = widget.active || _hovered;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.target.onTap,
        child: AnimatedContainer(
          duration: context.motion.fast,
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: widget.active ? colors.surfaceHover : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: Text(
            widget.target.label,
            style: context.text.label.copyWith(
              color: lit ? colors.textPrimary : colors.textSecondary,
              fontWeight: widget.active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

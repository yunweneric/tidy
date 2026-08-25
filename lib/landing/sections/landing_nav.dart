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

/// Taller on a phone, where the control is a thumb rather than a pointer. 44 is
/// the smallest target Apple's HIG will vouch for, and the bar grows to hold it
/// rather than the control shrinking to fit the bar.
const double _kTouchControlHeight = 44;

const double _kRestWidth = kLandingMaxWidth;
const double _kShrunkWidth = 940;
const double _kRestHeight = 68;
const double _kShrunkHeight = 58;

/// The touch bar barely draws in. There is no width to reclaim on a phone, and
/// a bar that shed 10 points of height on the first scroll would be motion for
/// its own sake.
const double _kTouchRestHeight = 60;
const double _kTouchShrunkHeight = 56;

const double _kRestTop = 18;
const double _kShrunkTop = 10;

/// The floating bar. Draws in as the page scrolls under it, so it takes less
/// room once the visitor is reading rather than arriving.
///
/// **Three layouts, not two.** From `large` up the links sit in the bar. Between
/// `medium` and `large` they move into a sheet and every control stays. Below
/// `medium` the bar keeps only what a thumb needs — the wordmark, the download
/// and the menu — and the theme toggle and the repository chip move into the
/// sheet with the links. That last band is the one that used to overflow: four
/// controls and a labelled download button beside a wordmark is more than 320
/// points of phone has ever had room for.
class LandingNav extends StatelessWidget {
  const LandingNav({
    super.key,
    required this.controller,
    required this.targets,
    required this.menuTargets,
    required this.scrolled,
    required this.activeId,
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

  /// The section under the reading line. Passed in rather than read off
  /// [LandingController]: it changes several times per scroll, and a rebuild
  /// of the whole page for a bold nav link is not a trade worth making.
  ///
  /// Reaches the sheet as well as the bar — once the links are behind a button
  /// the sheet is the only place left that can say where you are.
  final String? activeId;

  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final motion = context.motion;
    final size = context.windowSize;
    final collapsed = size.isBelow(WindowSizeClass.large);
    final touch = size.isBelow(WindowSizeClass.medium);
    final gutter = size.resolve<double>(compact: 12, medium: 20, expanded: 28);

    final height =
        touch
            ? (scrolled ? _kTouchShrunkHeight : _kTouchRestHeight)
            : (scrolled ? _kShrunkHeight : _kRestHeight);

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
          top: scrolled || touch ? _kShrunkTop : _kRestTop,
          left: gutter,
          right: gutter,
        ),
        width: width,
        height: height,
        child: GlassPanel(
          borderRadius: BorderRadius.circular(height / 2),
          blur: scrolled ? 18 : 12,
          opacity: scrolled ? 1 : 0.72,
          child: Padding(
            // A pill's ends curve away from its contents, so the tighter the
            // bar the less of that padding is real. Ten is what keeps a 44pt
            // control off the curve at this radius.
            padding: EdgeInsets.symmetric(
              horizontal: touch ? AppSpacing.sm + 2 : AppSpacing.md,
            ),
            child:
                collapsed
                    ? _CollapsedBar(
                      controller: controller,
                      targets: menuTargets,
                      activeId: activeId,
                      onDownload: onDownload,
                      touch: touch,
                    )
                    : _FullBar(
                      controller: controller,
                      targets: targets,
                      activeId: activeId,
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
    required this.activeId,
    required this.onDownload,
  });

  final LandingController controller;
  final List<NavTarget> targets;
  final String? activeId;
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
              _NavLink(target: target, active: target.id == activeId),
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

/// Everything below `large`. What is left in the bar depends on [touch].
class _CollapsedBar extends StatelessWidget {
  const _CollapsedBar({
    required this.controller,
    required this.targets,
    required this.activeId,
    required this.onDownload,
    required this.touch,
  });

  final LandingController controller;
  final List<NavTarget> targets;
  final String? activeId;
  final VoidCallback onDownload;

  /// Below `medium`. Sheds the theme toggle and the repository chip into the
  /// sheet, and squares the download button off — the one thing that stays
  /// visible, because it is what the page is for.
  final bool touch;

  @override
  Widget build(BuildContext context) {
    final height = touch ? _kTouchControlHeight : _kControlHeight;

    return Row(
      children: [
        _Mark(compact: touch),
        const Spacer(),
        if (!touch) ...[
          _ThemeToggle(controller: controller),
          const SizedBox(width: AppSpacing.sm),
          _GithubChip(count: controller.stars),
          const SizedBox(width: AppSpacing.sm),
        ],
        LandingButton(
          label: 'Download',
          icon: AppIcons.downloads,
          height: height,
          iconOnly: touch,
          onPressed: onDownload,
        ),
        SizedBox(width: touch ? AppSpacing.xs + 2 : AppSpacing.sm),
        LandingButton(
          label: 'Menu',
          icon: AppIcons.menu,
          kind: LandingButtonKind.ghost,
          height: height,
          iconOnly: true,
          onPressed:
              () => _openNavSheet(
                context,
                controller: controller,
                targets: targets,
                activeId: activeId,
                onDownload: onDownload,
              ),
        ),
      ],
    );
  }
}

/// The links, plus whatever the narrow bar had to drop.
///
/// Scroll-controlled rather than the default half-height sheet: eight links and
/// a footer is taller than half a phone in landscape, and a sheet that clips
/// its last row hides the download button.
Future<void> _openNavSheet(
  BuildContext context, {
  required LandingController controller,
  required List<NavTarget> targets,
  required String? activeId,
  required VoidCallback onDownload,
}) {
  final colors = context.colors;

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: colors.surfaceOpaque,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
    ),
    builder:
        (sheetContext) => _NavSheet(
          controller: controller,
          targets: targets,
          activeId: activeId,
          onDownload: onDownload,
        ),
  );
}

class _NavSheet extends StatelessWidget {
  const _NavSheet({
    required this.controller,
    required this.targets,
    required this.activeId,
    required this.onDownload,
  });

  final LandingController controller;
  final List<NavTarget> targets;
  final String? activeId;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final target in targets)
                _SheetLink(target: target, active: target.id == activeId),
              const SizedBox(height: AppSpacing.sm),
              Divider(height: 1, thickness: 1, color: colors.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _ThemeToggle(
                          controller: controller,
                          height: _kTouchControlHeight,
                          kind: LandingButtonKind.secondary,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        _GithubChip(
                          count: controller.stars,
                          height: _kTouchControlHeight,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    // Full width and labelled, where the bar's copy is a 44pt
                    // square. The sheet has the room to say what the button
                    // does, and this is the one place on a phone that does.
                    SizedBox(
                      width: double.infinity,
                      child: LandingButton(
                        label: 'Download for macOS',
                        icon: AppIcons.downloads,
                        height: _kTouchControlHeight,
                        onPressed: () {
                          Navigator.of(context).pop();
                          onDownload();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetLink extends StatelessWidget {
  const _SheetLink({required this.target, required this.active});

  final NavTarget target;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ListTile(
      title: Text(
        target.label,
        style: context.text.titleM.copyWith(
          color: active ? colors.accent : colors.textPrimary,
          fontWeight: active ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
      onTap: () {
        Navigator.of(context).pop();
        target.onTap();
      },
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark({this.compact = false});

  /// Two points off the tile and the gap. The wordmark stays either way — four
  /// characters is not what makes a phone bar overflow.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandMark(size: compact ? 24 : 26),
        SizedBox(width: compact ? AppSpacing.sm : AppSpacing.sm + 2),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ThemeToggle(controller: controller),
        const SizedBox(width: AppSpacing.sm),
        _GithubChip(count: controller.stars),
        const SizedBox(width: AppSpacing.sm),
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
  const _ThemeToggle({
    required this.controller,
    this.height = _kControlHeight,
    this.kind = LandingButtonKind.ghost,
  });

  final LandingController controller;
  final double height;

  /// Ghost in the bar, where hover does the explaining. The sheet asks for
  /// [LandingButtonKind.secondary] instead: a touch screen has no hover, so a
  /// control with no chrome until it is pressed has no chrome at all — and a
  /// bare glyph beside the bordered repository chip reads as a decoration
  /// rather than as the other half of a pair.
  final LandingButtonKind kind;

  @override
  Widget build(BuildContext context) {
    return LandingButton(
      label: controller.isDark ? 'Switch to light' : 'Switch to dark',
      icon: controller.isDark ? AppIcons.light : AppIcons.dark,
      kind: kind,
      height: height,
      iconOnly: true,
      onPressed: controller.toggleBrightness,
    );
  }
}

/// The repository, and its star count once GitHub has answered.
///
/// The mark is GitHub's rather than the brand sparkle this used to wear in the
/// amber "worth a look" tone. A sparkle beside a number reads as a rating the
/// page has awarded itself; GitHub's mark says where the number came from
/// without a word of label.
///
/// The count is *added* when it arrives rather than the chip appearing with it.
/// A chip reading "—" says the page is broken, but the bare mark is a link to
/// the source, which is true whether or not the API answered.
class _GithubChip extends StatelessWidget {
  const _GithubChip({required this.count, this.height = _kControlHeight});

  final int? count;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final message =
        count == null
            ? 'Tidy on GitHub'
            : 'Tidy on GitHub — ${_formatStars(count!)} stars';

    return Tooltip(
      message: message,
      child: Semantics(
        button: true,
        label: message,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => openExternalUrl(TidyRepo.url),
            child: Container(
              height: height,
              // Square when it is only a mark, and a chip once it has a number
              // to hold — so a count arriving grows it rather than making a
              // lopsided box that was always the wrong shape.
              width: count == null ? height : null,
              alignment: Alignment.center,
              padding:
                  count == null
                      ? EdgeInsets.zero
                      : const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              decoration: BoxDecoration(
                color: colors.surfaceHover,
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(AppIcons.github, size: 16, color: colors.textPrimary),
                  if (count != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      _formatStars(count!),
                      style: context.text.label.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 1240 → "1.2k". Four digits is width the narrow bar does not have, and the
/// last two of a star count are not what anyone reads it for.
String _formatStars(int count) {
  if (count < 1000) return '$count';
  final thousands = count / 1000;
  return '${thousands.toStringAsFixed(thousands < 10 ? 1 : 0)}k';
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

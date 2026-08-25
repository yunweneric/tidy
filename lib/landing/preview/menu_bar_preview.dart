import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/features/menubar/presentation/widgets/menu_bar_button.dart';
import 'package:tidy/features/menubar/presentation/widgets/menu_bar_section.dart';
import 'package:tidy/landing/preview/preview_mac.dart';

/// Which status item the popover belongs to.
///
/// One Flutter view, several panels. The icons mean different things and each
/// panel shows what its icon promised — a clipboard glyph that opened a disk
/// report would be a worse lie than having no clipboard glyph at all.
///
/// Deliberately **not** `MenuBarSurface` from the app, even though the two
/// overlap. These are hand-drawn mockups for the marketing page, and folding
/// them together would mean every surface the app gains has to be drawn twice
/// before it can ship. Three of them is a gallery, not an inventory.
enum MenuBarPanelKind {
  dashboard('Dashboard', AppIcons.brand, 460),
  clipboard('Clipboard', AppIcons.clipboard, 320),
  network('Network', AppIcons.network, 320);

  const MenuBarPanelKind(this.label, this.icon, this.width);

  final String label;
  final IconData icon;

  /// The popover's real width in points, from `MenuBarController.swift`. The
  /// dashboard is a table and needs the room; the other two are a column of
  /// one-line rows, and dashboard width would be a lot of empty gutter.
  final double width;
}

/// Tidy's corner of the menu bar, enlarged, with one of its popovers open
/// under it.
///
/// Drawn rather than captured — a capture of a menu bar is frozen at one
/// appearance, one screen scale and one set of neighbouring status items — and
/// deliberately *cropped* rather than shown as a whole desktop. At the width a
/// page can give it, a real-proportion menu bar is a 3px sliver of the picture
/// with the subject of the section inside it. This shows the last few inches
/// of the bar at about twice size, the way a detail figure would.
class MenuBarPreview extends StatelessWidget {
  const MenuBarPreview({
    super.key,
    required this.mac,
    required this.panel,
    this.onSelect,
  });

  /// Composed at a fixed size and scaled to whatever room the page has, for the
  /// same reason the app window is. Sized to the content rather than to a
  /// screen: the frame ends just past the popover, so there is no empty
  /// wallpaper to look at.
  static const double width = 620;

  /// Deep enough for the dashboard panel — the tallest of the three — with the
  /// bar's own margin above it and a comparable margin below. Fixed rather
  /// than per-panel so switching tabs does not resize the section under the
  /// reader's cursor.
  static const double height = 772;

  // ─── The enlarged bar ────────────────────────────────────────────────────

  static const double _barWidth = 552;
  static const double _barHeight = 42;
  static const double _barTop = 40;
  static const double _barPad = 14;
  static const double _gap = 8;

  /// Item widths, right to left, in the order macOS lays a menu bar out.
  static const double _clockWidth = 74;
  static const double _wifiWidth = 28;
  static const double _networkWidth = 82;
  static const double _itemWidth = 38;

  static double get _barLeft => (width - _barWidth) / 2;
  static double get _barRight => _barLeft + _barWidth;

  /// Where each status item's centre sits, measured from the bar's right edge.
  ///
  /// Arithmetic rather than a `GlobalKey` measurement: the popover has to be
  /// positioned in the same frame the bar is laid out in, and one pass of
  /// addition is cheaper and more predictable than a post-frame read.
  static double _anchorFromRight(MenuBarPanelKind kind) {
    final network = _barPad + _clockWidth + _gap + _wifiWidth + _gap;
    return switch (kind) {
      MenuBarPanelKind.network => network + _networkWidth / 2,
      MenuBarPanelKind.clipboard =>
        network + _networkWidth + _gap + _itemWidth / 2,
      MenuBarPanelKind.dashboard =>
        network + _networkWidth + _gap + _itemWidth + _gap + _itemWidth / 2,
    };
  }

  static double _centreOf(MenuBarPanelKind kind) =>
      _barRight - _anchorFromRight(kind);

  final PreviewMac mac;
  final MenuBarPanelKind panel;
  final ValueChanged<MenuBarPanelKind>? onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final centre = _centreOf(panel);

    // Kept inside the frame: the network item sits close enough to the right
    // edge that a 320pt panel centred under it would hang off.
    final left = (centre - panel.width / 2).clamp(
      16.0,
      width - panel.width - 16,
    );

    return AspectRatio(
      aspectRatio: width / height,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            children: [
              Positioned.fill(child: _Ground(colors: colors)),
              Positioned(
                top: _barTop,
                left: _barLeft,
                child: _Bar(mac: mac, active: panel, onSelect: onSelect),
              ),
              Positioned(
                top: _barTop + _barHeight - 1,
                left: left,
                width: panel.width,
                child: _Popover(
                  mac: mac,
                  panel: panel,
                  // The pointer leaves the popover's own box and lands under
                  // the status item, wherever the panel had to be clamped to.
                  pointerAt: centre - left,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the bar and the popover float over.
///
/// Not a wallpaper photograph and not a flat panel: the app's own backdrop
/// colours, with the light pooled behind the bar so the crop reads as lit from
/// above rather than pasted on.
class _Ground extends StatelessWidget {
  const _Ground({required this.colors});

  final AppColorTokens colors;

  @override
  Widget build(BuildContext context) {
    final palette = colors.modulePalette(ModuleTone.brand);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.xl),
        border: Border.all(color: colors.border),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(palette.base, palette.lift, 0.12)!, palette.base],
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.xl),
          gradient: RadialGradient(
            center: const Alignment(0.25, -0.95),
            radius: 1.1,
            colors: [
              palette.lift.withValues(alpha: 0.30 * colors.glowStrength),
              palette.lift.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.mac, required this.active, this.onSelect});

  final PreviewMac mac;
  final MenuBarPanelKind active;
  final ValueChanged<MenuBarPanelKind>? onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: MenuBarPreview._barWidth,
      height: MenuBarPreview._barHeight,
      padding: const EdgeInsets.symmetric(horizontal: MenuBarPreview._barPad),
      decoration: BoxDecoration(
        // The bar is a crop, so it gets a rounded edge and a shadow. Squared
        // off against the frame it would read as the top of a window.
        color: Color.alphaBlend(colors.sidebar, const Color(0xFF0B0918)),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            blurRadius: 24,
            spreadRadius: -8,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          // The bar carries on to the left, out of frame. Three dots fading
          // out say so without inventing menus nobody is being shown.
          for (final alpha in const [0.10, 0.18, 0.28])
            Padding(
              padding: const EdgeInsets.only(right: 7),
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: colors.textPrimary.withValues(alpha: alpha),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          const Spacer(),
          // Tidy's three status items, in the order the app installs them.
          _StatusItem(
            kind: MenuBarPanelKind.dashboard,
            active: active,
            onSelect: onSelect,
            child: const BrandMark(size: 20, tile: false),
          ),
          const SizedBox(width: MenuBarPreview._gap),
          _StatusItem(
            kind: MenuBarPanelKind.clipboard,
            active: active,
            onSelect: onSelect,
            child: Icon(
              AppIcons.clipboard,
              size: 19,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(width: MenuBarPreview._gap),
          _StatusItem(
            kind: MenuBarPanelKind.network,
            active: active,
            onSelect: onSelect,
            width: MenuBarPreview._networkWidth,
            // The "two lines" readout: download above upload. One of three
            // styles — the others are a live graph beside the rates, and a
            // single compact line for a crowded bar.
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _Rate(
                  icon: AppIcons.downstream,
                  color: colors.textPrimary,
                  label: formatBytes(mac.downNowBytes),
                ),
                _Rate(
                  icon: AppIcons.upstream,
                  color: colors.textSecondary,
                  label: formatBytes(mac.upNowBytes),
                ),
              ],
            ),
          ),
          const SizedBox(width: MenuBarPreview._gap),
          SizedBox(
            width: MenuBarPreview._wifiWidth,
            child: Icon(
              AppIcons.network,
              size: 17,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(width: MenuBarPreview._gap),
          SizedBox(
            width: MenuBarPreview._clockWidth,
            child: Text(
              'Mon 09:41',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Rate extends StatelessWidget {
  const _Rate({required this.icon, required this.color, required this.label});

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            height: 1.2,
            fontWeight: FontWeight.w600,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _StatusItem extends StatelessWidget {
  const _StatusItem({
    required this.kind,
    required this.active,
    required this.child,
    this.width = MenuBarPreview._itemWidth,
    this.onSelect,
  });

  final MenuBarPanelKind kind;
  final MenuBarPanelKind active;
  final Widget child;
  final double width;
  final ValueChanged<MenuBarPanelKind>? onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final selected = kind == active;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onSelect == null ? null : () => onSelect!(kind),
        child: AnimatedContainer(
          duration: context.motion.fast,
          width: width,
          height: MenuBarPreview._barHeight - 10,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            // macOS highlights the status item whose popover is open.
            color: selected ? colors.surfaceHover : Colors.transparent,
            borderRadius: AppRadii.smAll,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The popover itself: a solid panel with a pointer, floating over everything.
class _Popover extends StatelessWidget {
  const _Popover({
    required this.mac,
    required this.panel,
    required this.pointerAt,
  });

  final PreviewMac mac;
  final MenuBarPanelKind panel;

  /// Where the pointer sits along the popover's own width. Passed in rather
  /// than centred, because the panel is clamped to stay inside the frame and
  /// the pointer has to keep aiming at the status item regardless.
  final double pointerAt;

  static const double _pointerWidth = 20;
  static const double _pointerHeight = 10;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The pointer. A popover floating free of its status item is a dialog,
        // and reads as one.
        Padding(
          padding: EdgeInsets.only(
            left: (pointerAt - _pointerWidth / 2).clamp(
              AppRadii.lg,
              panel.width - AppRadii.lg - _pointerWidth,
            ),
          ),
          child: CustomPaint(
            size: const Size(_pointerWidth, _pointerHeight),
            painter: _PointerPainter(
              fill: colors.surfaceOpaque,
              stroke: colors.border,
            ),
          ),
        ),
        Container(
          width: panel.width,
          decoration: BoxDecoration(
            // The one surface in the app that has to be opaque: a sheer panel
            // over a desktop is unreadable.
            color: colors.surfaceOpaque,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: colors.border),
            boxShadow: [
              BoxShadow(
                color: colors.shadow,
                blurRadius: 44,
                spreadRadius: -6,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.lg - 1),
            child: switch (panel) {
              MenuBarPanelKind.dashboard => _DashboardPanel(mac: mac),
              MenuBarPanelKind.clipboard => _ClipboardPanel(mac: mac),
              // The one panel with a live figure in it, so the one panel that
              // subscribes.
              MenuBarPanelKind.network => AnimatedBuilder(
                animation: mac,
                builder: (context, _) => _NetworkPanel(mac: mac),
              ),
            },
          ),
        ),
      ],
    );
  }
}

class _PointerPainter extends CustomPainter {
  const _PointerPainter({required this.fill, required this.stroke});

  final Color fill;
  final Color stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final path =
        Path()
          ..moveTo(size.width / 2, 0)
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close();
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_PointerPainter old) =>
      old.fill != fill || old.stroke != stroke;
}

// ─── Dashboard panel ───────────────────────────────────────────────────────

class _DashboardPanel extends StatelessWidget {
  const _DashboardPanel({required this.mac});

  final PreviewMac mac;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            0,
          ),
          child: Row(
            children: [
              Expanded(
                child: _Vital(
                  icon: AppIcons.cpu,
                  label: 'CPU',
                  value: '31%',
                  fraction: 0.31,
                  color: colors.info,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _Vital(
                  icon: AppIcons.memory,
                  label: 'MEMORY',
                  value: '70%',
                  fraction: 0.70,
                  color: colors.review,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _Vital(
                  icon: AppIcons.storage,
                  label: 'DISK',
                  value: '${(mac.usedFraction * 100).round()}%',
                  fraction: mac.usedFraction,
                  color: colors.accent,
                ),
              ),
            ],
          ),
        ),
        const MenuBarSection(title: 'Worth doing'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: TidyCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            tint: colors.safe,
            child: Row(
              children: [
                Icon(AppIcons.cleanup, size: 17, color: colors.safe),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    '${formatBytes(mac.reclaimableBytes)} of caches and logs '
                    'can go',
                    style: context.text.titleS,
                  ),
                ),
                MenuBarButton(
                  label: 'Clean',
                  tone: MenuBarButtonTone.filled,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
        const MenuBarSection(title: 'Reclaimable'),
        _Row(
          icon: AppIcons.cleanup,
          title: 'Caches, logs, saved state',
          subtitle: 'Regenerated automatically',
          trailing: formatBytes(mac.reclaimableBytes),
          tone: colors.safe,
        ),
        _Row(
          icon: AppIcons.recycleBin,
          title: 'In the Trash',
          subtitle:
              '${mac.trash.length} items · '
              '${mac.staleTrashCount} older than a month',
          trailing: formatBytes(mac.trashBytes),
          tone: colors.review,
        ),
        MenuBarSection(title: 'Using the most CPU', trailing: 'Top 3'),
        for (final process in PreviewMac.processes.take(3))
          _Row(
            icon: AppIcons.cpu,
            title: process.name,
            subtitle: formatBytes(process.memoryBytes),
            trailing: '${process.cpu}%',
            tone: process.cpu > 30 ? colors.risky : colors.textMuted,
          ),
        const MenuBarSection(title: 'Recently copied'),
        for (final clip in mac.clips.take(3))
          _Row(
            icon: AppIcons.clipboard,
            title: clip.body,
            subtitle: clip.source,
            trailing: clip.age,
            tone: colors.accent,
          ),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }
}

class _Vital extends StatelessWidget {
  const _Vital({
    required this.icon,
    required this.label,
    required this.value,
    required this.fraction,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TidyCard(
      padding: const EdgeInsets.all(AppSpacing.sm + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: AppSpacing.xs + 1),
              Text(label, style: context.text.overline),
            ],
          ),
          const SizedBox(height: AppSpacing.xs + 1),
          Text(value, style: context.text.titleM),
          const SizedBox(height: AppSpacing.xs + 1),
          SizeBar(fraction: fraction, color: color, height: 3),
        ],
      ),
    );
  }
}

/// One line in a popover: a glyph, a title, a note, and a figure.
class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.tone,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String trailing;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md + 2,
        vertical: AppSpacing.xs + 2,
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: tone),
          const SizedBox(width: AppSpacing.md - 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleS,
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            trailing,
            style: context.text.caption.copyWith(
              fontWeight: FontWeight.w700,
              color: context.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Clipboard panel ───────────────────────────────────────────────────────

class _ClipboardPanel extends StatelessWidget {
  const _ClipboardPanel({required this.mac});

  final PreviewMac mac;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MenuBarSection(
          title: 'Clipboard',
          trailing: '${mac.clips.length} kept · ⌘⇧V',
        ),
        for (final clip in mac.clips.take(7))
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md + 2,
              vertical: AppSpacing.xs + 1,
            ),
            child: Row(
              children: [
                Icon(
                  clip.pinned ? AppIcons.pin : _glyph(clip.kind),
                  size: 13,
                  color: clip.pinned ? colors.accent : colors.textMuted,
                ),
                const SizedBox(width: AppSpacing.sm + 2),
                Expanded(
                  child: Text(
                    clip.body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        clip.masked
                            ? context.text.mono.copyWith(color: colors.risky)
                            : context.text.bodyM.copyWith(
                              color: colors.textPrimary,
                            ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(clip.source, style: context.text.caption),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        Divider(height: 1, color: colors.border),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Text(
            'Password-manager copies are skipped. Card- and key-shaped text is '
            'masked before it is stored.',
            style: context.text.caption,
          ),
        ),
      ],
    );
  }

  static IconData _glyph(PreviewClipKind kind) => switch (kind) {
    PreviewClipKind.link => AppIcons.link,
    PreviewClipKind.image => AppIcons.image,
    PreviewClipKind.file => AppIcons.folder,
    PreviewClipKind.text => AppIcons.plainText,
  };
}

// ─── Network panel ─────────────────────────────────────────────────────────

class _NetworkPanel extends StatelessWidget {
  const _NetworkPanel({required this.mac});

  final PreviewMac mac;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MenuBarSection(title: 'Right now'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md + 2),
          child: Row(
            children: [
              Expanded(
                child: _Big(
                  icon: AppIcons.downstream,
                  color: colors.downstream,
                  value: '${formatBytes(mac.downNowBytes)}/s',
                  label: 'Down',
                ),
              ),
              Expanded(
                child: _Big(
                  icon: AppIcons.upstream,
                  color: colors.upstream,
                  value: '${formatBytes(mac.upNowBytes)}/s',
                  label: 'Up',
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            0,
          ),
          child: SparkChart.compact(down: mac.down, up: mac.up, capacity: 60),
        ),
        const MenuBarSection(title: 'Today'),
        _Row(
          icon: AppIcons.downstream,
          title: 'Downloaded',
          subtitle: 'Across every interface',
          trailing: formatBytes(mac.todayDownBytes),
          tone: colors.downstream,
        ),
        _Row(
          icon: AppIcons.upstream,
          title: 'Uploaded',
          subtitle: 'Across every interface',
          trailing: formatBytes(mac.todayUpBytes),
          tone: colors.upstream,
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }
}

class _Big extends StatelessWidget {
  const _Big({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: AppSpacing.xs + 1),
            Text(label.toUpperCase(), style: context.text.overline),
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(value, style: context.text.titleL.copyWith(color: color)),
      ],
    );
  }
}

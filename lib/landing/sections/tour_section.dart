import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/landing/widgets/app_preview.dart';
import 'package:tidy/landing/widgets/landing_layout.dart';
import 'package:tidy/landing/widgets/landing_pill.dart';
import 'package:tidy/landing/widgets/reveal.dart';

/// The real thing, running in the page.
///
/// The [PreviewMac] is owned here rather than by the window, so a scan run on
/// the Cleanup tab is still there when the visitor comes back from Applications
/// — and the bytes reclaimed on one tab show up in the Trash on another. A demo
/// whose screens forget each other is a slideshow with extra steps.
class TourSection extends StatefulWidget {
  const TourSection({super.key, this.anchor});

  final GlobalKey? anchor;

  @override
  State<TourSection> createState() => _TourSectionState();
}

class _TourSectionState extends State<TourSection> {
  final PreviewMac _mac = PreviewMac();

  PreviewScreen _screen = PreviewScreen.dashboard;

  /// Advances the tabs on its own until the visitor touches something, then
  /// stops for good. An auto-advance that keeps yanking the screen away from
  /// someone who has started reading is worse than no auto-advance.
  Timer? _autoAdvance;
  bool _touched = false;

  /// Drives the live network chart.
  ///
  /// Runs only while the Network pane is the one on screen. A tick notifies
  /// [PreviewMac], which rebuilds the whole app window — sidebar, tables and
  /// all — and doing that once a second behind six panes that show no live
  /// data was a dropped frame every second, which is exactly what scroll
  /// stutter feels like.
  Timer? _networkTicker;

  @override
  void initState() {
    super.initState();
    _autoAdvance = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_touched || !mounted) return;
      final next = (_screen.index + 1) % PreviewScreen.values.length;
      _show(PreviewScreen.values[next]);
    });
  }

  void _show(PreviewScreen screen) {
    setState(() => _screen = screen);
    _syncTicker();
  }

  void _syncTicker() {
    final live = _screen == PreviewScreen.network;
    if (live == (_networkTicker != null)) return;

    if (live) {
      _networkTicker = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _mac.tickNetwork(),
      );
    } else {
      _networkTicker?.cancel();
      _networkTicker = null;
    }
  }

  @override
  void dispose() {
    _autoAdvance?.cancel();
    _networkTicker?.cancel();
    _mac.dispose();
    super.dispose();
  }

  void _go(PreviewScreen screen) {
    _touched = true;
    _autoAdvance?.cancel();
    _show(screen);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final narrow = context.windowSize.isBelow(WindowSizeClass.expanded);

    return LandingSection(
      anchor: widget.anchor,
      tinted: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeading(
            eyebrow: 'The app',
            title: 'This is not a screenshot',
            lead:
                'It is Tidy, running here, on an invented Mac. Run a scan, '
                'untick a category, uninstall something, put it back out of '
                'the Trash. Every number answers to every other one.',
          ),
          const SizedBox(height: AppSpacing.xl),
          Reveal(
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final screen in PreviewScreen.values)
                        _TourTab(
                          label: screen.label,
                          icon: screen.destination.icon,
                          tone:
                              colors
                                  .modulePalette(screen.destination.tone)
                                  .accent,
                          active: screen == _screen,
                          onTap: () => _go(screen),
                        ),
                    ],
                  ),
                ),
                // Beside the tabs rather than floating over the window: laid
                // on top it reads as part of the app's own chrome, which is
                // the one thing a label about the page must not do.
                if (!narrow) ...[
                  const SizedBox(width: AppSpacing.lg),
                  const LandingPill(
                    label: 'Live — go on, click it',
                    emphasis: true,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Reveal(
            child: LandingAppPreview(
              screen: _screen,
              mac: _mac,
              // Below `expanded` the window is scaled down far enough that a
              // 13px table row is unreadable and a tap lands on the wrong
              // thing. It stays on the page as an illustration.
              interactive: !narrow,
              onNavigate: _go,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AnimatedSwitcher(
            duration: context.motion.normal,
            child: Row(
              key: ValueKey(_screen),
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _screen.destination.icon,
                  size: 15,
                  color: colors.modulePalette(_screen.destination.tone).accent,
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    _screen.blurb,
                    textAlign: TextAlign.center,
                    style: context.text.bodyM,
                  ),
                ),
              ],
            ),
          ),
          if (narrow) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'The demo takes clicks on a wider screen.',
              textAlign: TextAlign.center,
              style: context.text.caption,
            ),
          ],
        ],
      ),
    );
  }
}

class _TourTab extends StatefulWidget {
  const _TourTab({
    required this.label,
    required this.icon,
    required this.tone,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color tone;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_TourTab> createState() => _TourTabState();
}

class _TourTabState extends State<_TourTab> {
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
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: context.motion.fast,
          curve: context.motion.standard,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md - 1,
          ),
          decoration: BoxDecoration(
            color:
                widget.active
                    ? widget.tone.withValues(alpha: 0.16)
                    : colors.surface,
            borderRadius: AppRadii.pillAll,
            border: Border.all(
              color:
                  widget.active
                      ? widget.tone.withValues(alpha: 0.5)
                      : colors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 15,
                color: lit ? widget.tone : colors.textMuted,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                widget.label,
                style: context.text.label.copyWith(
                  color: lit ? colors.textPrimary : colors.textSecondary,
                  fontWeight: widget.active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

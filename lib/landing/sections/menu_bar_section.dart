import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/landing/preview/menu_bar_preview.dart';
import 'package:tidy/landing/preview/preview_mac.dart';
import 'package:tidy/landing/widgets/landing_layout.dart';
import 'package:tidy/landing/widgets/reveal.dart';

/// The part of Tidy you see most, and the part a screenshot of the main window
/// never shows.
class MenuBarSection extends StatefulWidget {
  const MenuBarSection({super.key, this.anchor});

  final GlobalKey? anchor;

  @override
  State<MenuBarSection> createState() => _MenuBarSectionState();
}

class _MenuBarSectionState extends State<MenuBarSection> {
  final PreviewMac _mac = PreviewMac();

  MenuBarPanelKind _panel = MenuBarPanelKind.dashboard;

  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // The bar's network readout is a live figure in the real app; a frozen one
    // here would be the one detail giving the drawing away.
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _mac.tickNetwork(),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _mac.dispose();
    super.dispose();
  }

  static const Map<MenuBarPanelKind, String> _captions = {
    MenuBarPanelKind.dashboard:
        'Live vitals, the one thing worth doing, what is using the most CPU, '
        'and what you copied last. Most of it is actionable from here.',
    MenuBarPanelKind.clipboard:
        'The last few things you copied, one keystroke away — ⌘⇧V opens it '
        'from anywhere, with no Accessibility permission.',
    MenuBarPanelKind.network:
        'Out and in, right now and today. The bar itself carries the readout, '
        'in whichever of three styles fits your menu bar.',
  };

  @override
  Widget build(BuildContext context) {
    final split = context.windowSize.atLeast(WindowSizeClass.large);

    final preview = Reveal(
      child: AnimatedBuilder(
        animation: _mac,
        builder:
            (context, _) => MenuBarPreview(
              mac: _mac,
              panel: _panel,
              onSelect: split ? (kind) => setState(() => _panel = kind) : null,
            ),
      ),
    );

    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeading(
          eyebrow: 'The menu bar',
          title: 'Most of it never needs the window',
          lead:
              'Three status items, three popovers. They run a second Flutter '
              'engine, so they keep working with the main window closed — '
              'closing it does not quit Tidy.',
        ),
        const SizedBox(height: AppSpacing.xxl),
        // The choices carry their own explanation and sit in a column, so the
        // panel on the right never needs a caption underneath it — and the
        // reader is choosing between three described things rather than three
        // words.
        for (final kind in MenuBarPanelKind.values) ...[
          _PanelTab(
            kind: kind,
            caption: _captions[kind]!,
            active: kind == _panel,
            onTap: () => setState(() => _panel = kind),
          ),
          if (kind != MenuBarPanelKind.values.last)
            const SizedBox(height: AppSpacing.md),
        ],
        const SizedBox(height: AppSpacing.xl),
        Row(
          children: [
            Icon(AppIcons.info, size: 15, color: context.colors.textMuted),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Drawn here, not captured — so it repaints with the theme, '
                'and the network readout in the bar is live.',
                style: context.text.caption,
              ),
            ),
          ],
        ),
      ],
    );

    return LandingSection(
      anchor: widget.anchor,
      child:
          split
              ? Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(flex: 42, child: copy),
                  const SizedBox(width: AppSpacing.xxxl),
                  Expanded(flex: 58, child: preview),
                ],
              )
              : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  copy,
                  const SizedBox(height: AppSpacing.xxl),
                  preview,
                ],
              ),
    );
  }
}

class _PanelTab extends StatefulWidget {
  const _PanelTab({
    required this.kind,
    required this.caption,
    required this.active,
    required this.onTap,
  });

  final MenuBarPanelKind kind;
  final String caption;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_PanelTab> createState() => _PanelTabState();
}

class _PanelTabState extends State<_PanelTab> {
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
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: widget.active ? colors.surface : Colors.transparent,
            borderRadius: AppRadii.lgAll,
            border: Border.all(
              color: widget.active ? colors.borderStrong : colors.border,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color:
                      widget.active ? colors.accentMuted : colors.surfaceRaised,
                  borderRadius: AppRadii.mdAll,
                ),
                child: Icon(
                  widget.kind.icon,
                  size: 17,
                  color: lit ? colors.accent : colors.textMuted,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.kind.label,
                      style: context.text.titleS.copyWith(
                        color: lit ? colors.textPrimary : colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(widget.caption, style: context.text.bodyS),
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

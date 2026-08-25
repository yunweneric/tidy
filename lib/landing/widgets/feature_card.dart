import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/landing/widgets/landing_layout.dart';
import 'package:tidy/landing/widgets/reveal.dart';

/// A responsive grid of equal-width cards.
///
/// `Wrap` over a computed width rather than `GridView`: the page is one long
/// scroll view, and a nested scrollable that has to be told not to scroll is a
/// worse thing to maintain than four lines of arithmetic.
class LandingGrid extends StatelessWidget {
  const LandingGrid({
    super.key,
    required this.columns,
    required this.children,
    this.gap = AppSpacing.xl,
  });

  final int columns;
  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;

        // Chunked into rows under an IntrinsicHeight rather than left to a
        // single Wrap. Wrap sizes each child to its own content, so a row of
        // cards with two lines of body next to one with four ends with three
        // different bottom edges — which reads as unfinished rather than as
        // deliberate.
        final rows = <Widget>[];
        for (var start = 0; start < children.length; start += columns) {
          final end = (start + columns).clamp(0, children.length);
          rows.add(
            // One `Reveal` around the row rather than one per card. Each
            // instance keeps a scroll listener that measures its own position
            // on every frame until it trips, and a page of three- and
            // four-across grids had about thirty of them doing that at once.
            // The per-card stagger is kept — it just no longer costs a
            // listener each.
            Reveal(
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = start; i < end; i++) ...[
                      if (i > start) SizedBox(width: gap),
                      SizedBox(
                        width: width,
                        child: StaggeredFade(
                          index: i - start,
                          child: children[i],
                        ),
                      ),
                    ],
                    // Keeps a short final row left-aligned instead of
                    // stretching its cards across the width the full rows use.
                    if (end - start < columns)
                      SizedBox(
                        width: (columns - (end - start)) * (width + gap),
                      ),
                  ],
                ),
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) SizedBox(height: gap),
              rows[i],
            ],
          ],
        );
      },
    );
  }

  /// The column count for the current width, for the common three-across case.
  static int columnsFor(BuildContext context, {int wide = 3}) =>
      context.windowSize.resolve<int>(compact: 1, medium: 2, large: wide);
}

/// One card in a grid: a tinted glyph tile, a title, a body.
class FeatureCard extends StatefulWidget {
  const FeatureCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.tone,
    this.badge,
    this.footer,
  });

  final IconData icon;
  final String title;
  final String body;

  /// The module's own colour, where the card stands for a module. Null falls
  /// back to the brand accent.
  final Color? tone;

  final Widget? badge;
  final Widget? footer;

  @override
  State<FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<FeatureCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final motion = context.motion;
    final tone = widget.tone ?? colors.accent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: motion.fast,
        curve: motion.standard,
        transform: Matrix4.translationValues(0, _hovered ? -3 : 0, 0),
        padding: const EdgeInsets.all(AppSpacing.xxl - 2),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: AppRadii.lgAll,
          border: Border.all(
            color: _hovered ? tone.withValues(alpha: 0.45) : colors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  // Tight constraints would otherwise override the icon's own
                  // size and leave it filling the tile.
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.16),
                    borderRadius: AppRadii.mdAll,
                  ),
                  child: Icon(widget.icon, size: 20, color: tone),
                ),
                const Spacer(),
                if (widget.badge != null) widget.badge!,
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(widget.title, style: context.text.titleM),
            const SizedBox(height: AppSpacing.sm),
            Text(
              widget.body,
              style: TextStyle(
                fontSize: 14.5,
                height: 1.55,
                color: colors.textSecondary,
              ),
            ),
            if (widget.footer != null) ...[
              const SizedBox(height: AppSpacing.lg),
              widget.footer!,
            ],
          ],
        ),
      ),
    );
  }
}

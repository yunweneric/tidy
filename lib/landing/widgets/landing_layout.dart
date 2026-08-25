import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/landing/widgets/reveal.dart';

/// The width bands the page is laid out against — Material 3's window size
/// classes.
///
/// This lives in `lib/landing/` rather than `lib/core/` on purpose. The macOS
/// app is a fixed-size desktop window and has never needed a breakpoint
/// system; adding one to `core/` for the sake of the marketing site would be a
/// change to the product in service of something that is not the product.
enum WindowSizeClass {
  /// < 600 — phones in portrait.
  compact(0),

  /// 600–839 — phones in landscape, small tablets.
  medium(600),

  /// 840–1199 — tablets in landscape, small desktop windows.
  expanded(840),

  /// 1200–1599 — desktop.
  large(1200),

  /// >= 1600 — wide desktop.
  extraLarge(1600);

  const WindowSizeClass(this.minWidth);

  final double minWidth;

  static WindowSizeClass fromWidth(double width) {
    if (width >= extraLarge.minWidth) return extraLarge;
    if (width >= large.minWidth) return large;
    if (width >= expanded.minWidth) return expanded;
    if (width >= medium.minWidth) return medium;
    return compact;
  }

  /// True from [other] upwards, so `atLeast(expanded)` reads the way the
  /// comparison is spoken.
  bool atLeast(WindowSizeClass other) => index >= other.index;

  bool isBelow(WindowSizeClass other) => index < other.index;

  /// Picks the value for this class, falling back *down* the scale when a band
  /// is left unspecified: [large] with only [compact] and [expanded] given
  /// resolves to the [expanded] value. Most call sites only care about two or
  /// three of the five bands, and this is what lets them say so.
  T resolve<T>({
    required T compact,
    T? medium,
    T? expanded,
    T? large,
    T? extraLarge,
  }) => switch (this) {
    WindowSizeClass.extraLarge =>
      extraLarge ?? large ?? expanded ?? medium ?? compact,
    WindowSizeClass.large => large ?? expanded ?? medium ?? compact,
    WindowSizeClass.expanded => expanded ?? medium ?? compact,
    WindowSizeClass.medium => medium ?? compact,
    WindowSizeClass.compact => compact,
  };
}

extension WindowSizeContext on BuildContext {
  WindowSizeClass get windowSize =>
      WindowSizeClass.fromWidth(MediaQuery.sizeOf(this).width);
}

/// The widest the page's content ever gets. Past this the gutters grow instead,
/// so a 4K window reads as a well-set page rather than a wall of text.
const double kLandingMaxWidth = 1180;

/// Vertical room the floating navigation bar takes out of the top of the
/// window: its own height plus the margin it rides on, plus a little air.
///
/// Used to keep the hero clear of it and to offset in-page anchor scrolling so
/// a heading never lands underneath it. Measured against the *scrolled* bar,
/// which is the state an anchor jump ends in.
const double kLandingNavHeight = 80;

/// Centres content at [kLandingMaxWidth] and applies the gutter for the
/// current width class.
class LandingContainer extends StatelessWidget {
  const LandingContainer({
    super.key,
    required this.child,
    this.maxWidth = kLandingMaxWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final gutter = context.windowSize.resolve<double>(
      compact: 20,
      medium: 28,
      expanded: 40,
      large: 48,
    );
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth + gutter * 2),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          child: child,
        ),
      ),
    );
  }
}

/// One band of the page: vertical rhythm, an optional tinted ground, and a
/// scroll anchor so the navigation bar can jump to it.
class LandingSection extends StatelessWidget {
  const LandingSection({
    super.key,
    required this.child,
    this.anchor,
    this.tinted = false,
    this.topPadding,
    this.bottomPadding,
  });

  final Widget child;

  /// Attached to this section's outermost box so `LandingPage` can measure and
  /// scroll to it.
  final GlobalKey? anchor;

  /// Paints the band on the sidebar veil, which is a step deeper than the page
  /// in dark and a step lighter in light. Alternating tinted and plain bands is
  /// what gives the page its rhythm without introducing a second palette.
  final bool tinted;

  final double? topPadding;
  final double? bottomPadding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final vertical = context.windowSize.resolve<double>(
      compact: 64,
      medium: 80,
      expanded: 104,
      large: 120,
    );

    return Container(
      key: anchor,
      width: double.infinity,
      // `sidebar` is a translucent veil, so it needs the canvas underneath it
      // rather than being painted straight onto whatever is behind the page.
      decoration: BoxDecoration(
        color: colors.canvas,
        gradient:
            tinted
                ? null
                : LinearGradient(
                  colors: colors.canvasGradient,
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
      ),
      foregroundDecoration:
          tinted ? BoxDecoration(color: colors.sidebar) : null,
      child: Padding(
        padding: EdgeInsets.only(
          top: topPadding ?? vertical,
          bottom: bottomPadding ?? vertical,
        ),
        child: LandingContainer(child: child),
      ),
    );
  }
}

/// Eyebrow, title and an optional lead paragraph — the top of every band.
class SectionHeading extends StatelessWidget {
  const SectionHeading({
    super.key,
    required this.eyebrow,
    required this.title,
    this.lead,
    this.align = CrossAxisAlignment.start,
  });

  final String eyebrow;
  final String title;
  final String? lead;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final centred = align == CrossAxisAlignment.center;
    final size = context.windowSize.resolve<double>(
      compact: 30,
      medium: 34,
      expanded: 40,
    );

    return Reveal(
      child: Column(
        crossAxisAlignment: align,
        children: [
          Text(
            eyebrow.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: colors.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            textAlign: centred ? TextAlign.center : TextAlign.start,
            style: TextStyle(
              fontSize: size,
              height: 1.1,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
              color: colors.textPrimary,
            ),
          ),
          if (lead != null) ...[
            const SizedBox(height: AppSpacing.lg),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 660),
              child: Text(
                lead!,
                textAlign: centred ? TextAlign.center : TextAlign.start,
                style: TextStyle(
                  fontSize: 17,
                  height: 1.6,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The page's card. Flat: a hairline and a veil, no shadow.
///
/// [docs/ui.md] allows a gradient in exactly two places — the backdrop and a
/// primary action — so everything else on this page is a neutral surface, the
/// same as everything else in the app.
class LandingCard extends StatelessWidget {
  const LandingCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.radius = AppRadii.lg,
    this.color,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? colors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? colors.border),
      ),
      child: child,
    );
  }
}

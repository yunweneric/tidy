import 'package:flutter/material.dart';

/// The modules that own a backdrop colour.
///
/// Each top-level module paints the whole window in its own hue — Cleanup is
/// green, Protection magenta, Performance amber — so the app says where you
/// are before you have read the page title. The colours live in
/// [AppColorTokens.modulePalettes]; nothing outside this layer names one.
///
/// [brand] is the fallback: a view that is not one of the modules keeps the
/// signature violet rather than inventing another hue.
enum ModuleTone {
  brand,

  /// Smart Care. It used to wear the brand violet, which stopped working the
  /// moment the Dashboard sat directly above it wearing the same one — two
  /// adjacent rows opening into an identical window is the one thing the tone
  /// exists to prevent.
  ///
  /// A citrine gold at ~58°, sat in the middle of the widest unused arc on the
  /// wheel — 37° from Performance's burnt orange and 44° from Cleanup's green.
  ///
  /// Placed by maximising distance from the other *module* tones rather than
  /// from the status ones, because no new hue can clear all four of those: the
  /// status hues (amber 39°, green 143°, azure 198°, red 355°) are spread right
  /// across the wheel and the modules fill what is left. What keeps that safe is
  /// the rule in ui.md §3 — a module's colour appears in the backdrop and the
  /// CTA and nowhere else — so an amber "worth a look" chip still reads as a
  /// warning on this window and not as a location. Deliberately yellower than
  /// that amber all the same: 19° of separation, where Performance has 18°.
  smartCare,
  cleanup,
  protection,
  performance,
  applications,
  clutter,
  spaceLens,

  /// Network. Toned for the same reason Space Lens is — it is somewhere you go
  /// to *watch*, and the window saying so before you have read the title is the
  /// whole point of the tone. An azure kept clear of Applications' indigo and My
  /// Clutter's teal, which are its two nearest neighbours.
  network,
}

/// One module's two backdrop colours.
///
/// [base] is the window's darkest corner; [lift] is the pool of light the
/// backdrop brightens toward, and the ramp a primary button wears on that
/// module. Two colours rather than a full gradient because everything else —
/// the corner falloff, the glow placement — is the same on every module, and
/// only the hue changes.
@immutable
class ModulePalette {
  const ModulePalette({
    required this.base,
    required this.lift,
    required this.accent,
  });

  final Color base;
  final Color lift;

  /// The saturated version of the hue, for controls — a toggle, a checkbox, a
  /// progress bar, the current page in a pagination bar. [lift] is a backdrop
  /// colour and is far too pale in light mode to carry a switch.
  ///
  /// `AmbientBackground` swaps this in for `AppColorTokens.accent` inside a
  /// module, so Material's own widgets follow the module without a single
  /// call site knowing about it.
  final Color accent;

  /// The gradient a primary action wears on this module, so a call to action
  /// never sits on the page in a colour the page is not.
  List<Color> get ramp => [lift, Color.lerp(lift, base, 0.35)!];

  static ModulePalette lerp(ModulePalette a, ModulePalette b, double t) =>
      ModulePalette(
        base: Color.lerp(a.base, b.base, t)!,
        lift: Color.lerp(a.lift, b.lift, t)!,
        accent: Color.lerp(a.accent, b.accent, t)!,
      );
}

/// Every colour in the app, resolved for the active brightness.
///
/// Widgets read these through `context.colors` rather than importing statics,
/// which is what makes a runtime light/dark switch possible at all.
///
/// **Surfaces here are neutral veils, not colours.** A card is white at 8% in
/// dark and white at 72% in light — it has no hue of its own, so it takes
/// whatever the module behind it is and blends into it. That is the whole
/// reason a green module and a magenta one can share one set of components.
@immutable
class AppColorTokens extends ThemeExtension<AppColorTokens> {
  const AppColorTokens({
    required this.brightness,
    required this.canvas,
    required this.canvasGradient,
    required this.modulePalettes,
    required this.sidebar,
    required this.sidebarGradient,
    required this.surface,
    required this.surfaceOpaque,
    required this.surfaceGradient,
    required this.surfaceRaised,
    required this.surfaceHover,
    required this.overlay,
    required this.glowStrength,
    required this.pattern,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textOnAccent,
    required this.accent,
    required this.accentMuted,
    required this.accentGradient,
    required this.safe,
    required this.review,
    required this.risky,
    required this.info,
    required this.downstream,
    required this.upstream,
    required this.chartSeries,
    required this.chartOther,
    required this.shadow,
  });

  final Brightness brightness;

  // ─── Backdrop ────────────────────────────────────────────────────────────
  /// Flat fallback behind everything, for the places that cannot take a
  /// gradient (Material's `scaffoldBackgroundColor`).
  final Color canvas;

  /// The backdrop when no module owns the view — the brand tone's ramp.
  final List<Color> canvasGradient;

  /// Every module's backdrop colours. Read through [modulePalette], which falls
  /// back to the brand tone rather than throwing on a missing key.
  final Map<ModuleTone, ModulePalette> modulePalettes;

  /// How strongly `AmbientBackground` pools the module's [ModulePalette.lift]
  /// into the backdrop. Light mode wants less: the same pool that reads as
  /// depth on a deep green reads as a stain on a pale one.
  final double glowStrength;

  /// The ink for the backdrop's ring outlines and dot grid. Carries its own
  /// alpha, and is near-invisible on purpose — if a pattern is legible enough
  /// to count, it is too strong.
  final Color pattern;

  // ─── Surfaces ────────────────────────────────────────────────────────────
  /// Darkens (dark) or lightens (light) the rail against the module colour.
  /// Neutral, so the rail is the same hue as the page it sits beside.
  final Color sidebar;

  /// The rail's vertical veil, top to bottom.
  final List<Color> sidebarGradient;

  /// Default card / tile / table background. A neutral veil — it has no colour
  /// of its own and blends into whatever module is behind it.
  final Color surface;

  /// The one solid surface, for what floats *over* the window: dialogs, popup
  /// menus, tooltips, snackbars, the menu-bar popover. Those have to hide what
  /// is behind them, and a sheer dialog over a table is unreadable.
  final Color surfaceOpaque;

  /// The card veil, lit slightly from the top-left and thinning toward the
  /// bottom so a card settles into the backdrop instead of ending on an edge.
  final List<Color> surfaceGradient;

  /// A surface on top of [surface] — inputs, nested rows, the segmented track.
  final Color surfaceRaised;

  /// Hover / pressed wash, and the selected sidebar row.
  final Color surfaceHover;

  /// Scrim behind dialogs.
  final Color overlay;

  // ─── Lines ───────────────────────────────────────────────────────────────
  /// Default 1px separator and card outline. Neutral, like the surfaces.
  final Color border;

  /// A deliberately visible edge (focused input, selected row).
  final Color borderStrong;

  // ─── Text ────────────────────────────────────────────────────────────────
  /// Text sits on module colour as often as on a card, so the secondary and
  /// muted tiers are the primary colour at reduced alpha rather than their own
  /// grey — a cool grey turns muddy the moment the backdrop is green or amber.
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  /// Text drawn on top of [accent] or a status fill.
  final Color textOnAccent;

  // ─── Brand ───────────────────────────────────────────────────────────────
  final Color accent;

  /// A low-opacity accent wash. For brand moments only — a selected row on a
  /// module page uses [surfaceHover], because a blue wash on a green page is
  /// just a mistake with extra steps.
  final Color accentMuted;

  /// The brand ramp: the mark, the onboarding panel, and any primary action on
  /// a view no module owns. Inside a module, a primary action wears that
  /// module's [ModulePalette.ramp] instead.
  final List<Color> accentGradient;

  // ─── Semantic status ─────────────────────────────────────────────────────
  /// Regenerated automatically; safe to remove without thinking.
  final Color safe;

  /// Worth a look before removing.
  final Color review;

  /// Destructive, or user data. Never pre-selected.
  final Color risky;

  final Color info;

  // ─── Traffic ─────────────────────────────────────────────────────────────
  /// Bytes coming in, and bytes going out.
  ///
  /// Their own pair rather than borrowed status colours: `safe` / `review` /
  /// `risky` mean the same thing on every module in the app, and a green
  /// "download" against an amber "upload" would quietly teach the user that one
  /// direction is fine and the other needs looking at. They also cannot be the
  /// module ramp, because a chart with two series needs two colours and a ramp
  /// is one.
  final Color downstream;
  final Color upstream;

  // ─── Charts ──────────────────────────────────────────────────────────────
  /// Eight hues in a fixed order, for anything that plots.
  ///
  /// **Its own palette, not the status colours.** `safe` / `review` / `risky`
  /// mean one thing everywhere in the app — regenerated automatically, worth a
  /// look, destructive — and a chart that spends green on "Removed by category"
  /// teaches the reader that the category is *safe*, which is not what the bar
  /// is saying. Reserved meanings have to stay reserved to keep meaning
  /// anything, so charts draw from here instead.
  ///
  /// **The order is fixed and never cycled.** It is the mechanism that keeps
  /// neighbouring hues apart under protanopia and deuteranopia, so assigning
  /// out of order — or generating a ninth — silently gives up the guarantee.
  /// Anything past what these can carry folds into [chartOther].
  ///
  /// Both columns are stepped for their own surface rather than one being a
  /// flip of the other, and both were validated against this app's card
  /// colours: worst adjacent pair ΔE 9.1 light / 8.4 dark under simulated CVD,
  /// 19.6 / 19.3 under normal vision. Several slots sit under 3:1 against the
  /// card, which is legal only because every mark in this app is labelled with
  /// its name and its value — colour is never the only thing carrying identity.
  final List<Color> chartSeries;

  /// The fill for a remainder — the part of a whole nobody has measured, or
  /// what is left after the hues run out.
  ///
  /// Deliberately colourless. A hue here would claim the remainder is a
  /// category like the others, when what it actually says is "not one of the
  /// above". Distinct from [surfaceRaised], which is the *unfilled* track: one
  /// is space that holds something we have not named, the other is space that
  /// holds nothing.
  final Color chartOther;

  final Color shadow;

  bool get isDark => brightness == Brightness.dark;

  /// The hue for the nth mark in a chart, counting from zero.
  ///
  /// Past the end of [chartSeries] it hands back [chartOther] rather than
  /// wrapping. A ninth hue would have to be invented, and an invented hue is
  /// one the fixed order was never checked against — it can land on top of a
  /// neighbour under colour-blindness and nothing would catch it. A row that
  /// reads "one of the rest" is honest; a row that reads as a category it is
  /// not is not.
  Color seriesAt(int index) =>
      index >= 0 && index < chartSeries.length
          ? chartSeries[index]
          : chartOther;

  /// The colour a [SafetyLevel]-style tier should use.
  Color statusFor(int tierIndex) => switch (tierIndex) {
    0 => safe,
    1 => review,
    _ => risky,
  };

  /// The backdrop palette for [tone], falling back to the brand tone.
  ModulePalette modulePalette(ModuleTone tone) =>
      modulePalettes[tone] ?? modulePalettes[ModuleTone.brand]!;

  /// The opaque surface for something floating over a module's window —
  /// a dialog, a toast — carrying that module's own colour.
  ///
  /// This is the one exception to "never give a surface a hue", and it is not
  /// really an exception: a floating panel *has* to be solid, and a solid
  /// neutral panel dropped onto an amber window reads as a screenshot from a
  /// different app. Everything sheer still blends by being sheer; this blends
  /// by being made of the module.
  ///
  /// Null palette — Settings, onboarding, the menu-bar popover — falls back to
  /// [surfaceOpaque].
  Color floatingSurface(ModulePalette? palette) {
    if (palette == null) return surfaceOpaque;

    if (isDark) {
      // The module's darkest corner, warmed a little toward its light so the
      // panel does not go muddy, then the neutral veil on top so it separates
      // from the window behind it.
      return Color.alphaBlend(
        const Color(0x14FFFFFF),
        Color.lerp(palette.base, palette.lift, 0.10)!,
      );
    }

    // Light mode starts from the module's *light* instead. Its base is already
    // pale, and a white veil over a pale tint leaves nothing of the hue behind
    // — the panel would come out white and the module would vanish. The veil is
    // heavy enough that the panel still reads as paper: in light mode a raised
    // thing is whiter than the page, not more saturated than it.
    return Color.alphaBlend(const Color(0xDBFFFFFF), palette.lift);
  }

  /// A two-stop veil tinted toward [tint], for a card whose colour *is* the
  /// information — amber for apps gone unopened, green for a clean result.
  ///
  /// The tint is layered onto the neutral veil rather than replacing it, so a
  /// tinted card still blends into the module behind it.
  List<Color> tintedSurface(Color tint, {double strength = 1}) => [
    Color.alphaBlend(
      tint.withValues(alpha: 0.20 * strength),
      surfaceGradient.first,
    ),
    Color.alphaBlend(
      tint.withValues(alpha: 0.06 * strength),
      surfaceGradient.last,
    ),
  ];

  /// Deep, saturated module colour with white laid over it. The signature look.
  factory AppColorTokens.dark() => const AppColorTokens(
    brightness: Brightness.dark,
    canvas: Color(0xFF15112E),
    canvasGradient: [Color(0xFF1B1440), Color(0xFF13102B)],
    modulePalettes: {
      ModuleTone.brand: ModulePalette(
        base: Color(0xFF17123A),
        lift: Color(0xFF5B45E0),
        accent: Color(0xFF8B79FF),
      ),
      ModuleTone.smartCare: ModulePalette(
        base: Color(0xFF2E2C09),
        lift: Color(0xFFBAB41E),
        accent: Color(0xFFE4DC55),
      ),
      ModuleTone.cleanup: ModulePalette(
        base: Color(0xFF0A2A12),
        lift: Color(0xFF3F961B),
        accent: Color(0xFF6BC93F),
      ),
      ModuleTone.protection: ModulePalette(
        base: Color(0xFF350A2B),
        lift: Color(0xFFC2229B),
        accent: Color(0xFFE45CBE),
      ),
      ModuleTone.performance: ModulePalette(
        base: Color(0xFF361206),
        lift: Color(0xFFC4551B),
        accent: Color(0xFFE8823F),
      ),
      ModuleTone.applications: ModulePalette(
        base: Color(0xFF0C1A4A),
        lift: Color(0xFF4632C8),
        accent: Color(0xFF7C6BF0),
      ),
      ModuleTone.clutter: ModulePalette(
        base: Color(0xFF062B2B),
        lift: Color(0xFF12837B),
        accent: Color(0xFF3FC7B8),
      ),
      ModuleTone.spaceLens: ModulePalette(
        base: Color(0xFF220848),
        lift: Color(0xFF7B27D6),
        accent: Color(0xFFA96BF5),
      ),
      ModuleTone.network: ModulePalette(
        base: Color(0xFF04243D),
        lift: Color(0xFF0F6FA8),
        accent: Color(0xFF35B4E8),
      ),
    },
    glowStrength: 1,
    pattern: Color(0x1FFFFFFF),
    sidebar: Color(0x1A000000),
    sidebarGradient: [Color(0x0D000000), Color(0x2E000000)],
    surface: Color(0x14FFFFFF),
    surfaceOpaque: Color(0xFF1B1832),
    surfaceGradient: [Color(0x1AFFFFFF), Color(0x0DFFFFFF)],
    surfaceRaised: Color(0x1FFFFFFF),
    surfaceHover: Color(0x2EFFFFFF),
    overlay: Color(0xB3000000),
    border: Color(0x24FFFFFF),
    borderStrong: Color(0x52FFFFFF),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xC4FFFFFF),
    textMuted: Color(0x8AFFFFFF),
    textOnAccent: Color(0xFFFFFFFF),
    accent: Color(0xFFA593FF),
    accentMuted: Color(0x33A593FF),
    accentGradient: [Color(0xFF6E5BFF), Color(0xFF4C8DFF), Color(0xFF3DD5C8)],
    safe: Color(0xFF5BE08F),
    review: Color(0xFFFFC24D),
    risky: Color(0xFFFF7A85),
    info: Color(0xFF7FD8FF),
    downstream: Color(0xFF4FC3F7),
    upstream: Color(0xFFB388FF),
    chartSeries: [
      Color(0xFF3987E5), // 1 blue
      Color(0xFFD95926), // 2 orange
      Color(0xFF199E70), // 3 aqua
      Color(0xFFC98500), // 4 yellow
      Color(0xFFD55181), // 5 magenta
      Color(0xFF008300), // 6 green
      Color(0xFF9085E9), // 7 violet
      Color(0xFFE66767), // 8 red
    ],
    chartOther: Color(0x80FFFFFF),
    shadow: Color(0x66000000),
  );

  factory AppColorTokens.light() => const AppColorTokens(
    brightness: Brightness.light,
    canvas: Color(0xFFF3F1FD),
    canvasGradient: [Color(0xFFF2EFFF), Color(0xFFF6F5FC)],
    modulePalettes: {
      ModuleTone.brand: ModulePalette(
        base: Color(0xFFE8E2FF),
        lift: Color(0xFFBCA8FF),
        accent: Color(0xFF5B45E0),
      ),
      ModuleTone.smartCare: ModulePalette(
        base: Color(0xFFF7F2C6),
        lift: Color(0xFFE2D97F),
        accent: Color(0xFF7E7409),
      ),
      ModuleTone.cleanup: ModulePalette(
        base: Color(0xFFDFF0DA),
        lift: Color(0xFF9FD190),
        accent: Color(0xFF3F8B1E),
      ),
      ModuleTone.protection: ModulePalette(
        base: Color(0xFFFBE0EF),
        lift: Color(0xFFEBA6D2),
        accent: Color(0xFFB51E88),
      ),
      ModuleTone.performance: ModulePalette(
        base: Color(0xFFFDE6CF),
        lift: Color(0xFFF4BC8A),
        accent: Color(0xFFB85218),
      ),
      ModuleTone.applications: ModulePalette(
        base: Color(0xFFDFE8FC),
        lift: Color(0xFFA5BDF3),
        accent: Color(0xFF3E45C8),
      ),
      ModuleTone.clutter: ModulePalette(
        base: Color(0xFFD7EDE9),
        lift: Color(0xFF93D2C7),
        accent: Color(0xFF0E7A72),
      ),
      ModuleTone.spaceLens: ModulePalette(
        base: Color(0xFFE7DAFB),
        lift: Color(0xFFBE9FF2),
        accent: Color(0xFF6D28C4),
      ),
      ModuleTone.network: ModulePalette(
        base: Color(0xFFD9EBF7),
        lift: Color(0xFF8FC4E6),
        accent: Color(0xFF0A6C9E),
      ),
    },
    // A pale backdrop has less room before a pool of light reads as a stain,
    // so light mode uses a softer glow than dark.
    glowStrength: 0.7,
    pattern: Color(0x1A101319),
    sidebar: Color(0x33FFFFFF),
    sidebarGradient: [Color(0x4DFFFFFF), Color(0x1AFFFFFF)],
    // Light mode does NOT blend its cards, and that is deliberate. A white
    // veil over a dark base separates hard, which is why dark works; the same
    // veil over a pale tint gives two near-identical values and the whole
    // window turns to mud. So here the backdrop carries the colour and the
    // cards are near-white and definite, with a real border under them.
    surface: Color(0xF2FFFFFF),
    surfaceOpaque: Color(0xFFFFFFFF),
    surfaceGradient: [Color(0xFAFFFFFF), Color(0xE8FFFFFF)],
    surfaceRaised: Color(0xE0FFFFFF),
    // Black, not white: on a near-white card a lighter hover is invisible.
    // Doubles as the neutral button pill, which comes out a light grey.
    surfaceHover: Color(0x14101319),
    overlay: Color(0x59101319),
    border: Color(0x24101319),
    borderStrong: Color(0x52101319),
    textPrimary: Color(0xFF12151C),
    textSecondary: Color(0xB0101319),
    textMuted: Color(0x75101319),
    textOnAccent: Color(0xFFFFFFFF),
    accent: Color(0xFF5B45E0),
    accentMuted: Color(0x1F5B45E0),
    accentGradient: [Color(0xFF5B45E0), Color(0xFF2E6FE8), Color(0xFF15B8AC)],
    safe: Color(0xFF15964F),
    review: Color(0xFFB8720A),
    risky: Color(0xFFD32F3D),
    info: Color(0xFF0B84D6),
    downstream: Color(0xFF0277BD),
    upstream: Color(0xFF6A3FC0),
    chartSeries: [
      Color(0xFF2A78D6), // 1 blue
      Color(0xFFEB6834), // 2 orange
      Color(0xFF1BAF7A), // 3 aqua
      Color(0xFFEDA100), // 4 yellow
      Color(0xFFE87BA4), // 5 magenta
      Color(0xFF008300), // 6 green
      Color(0xFF4A3AA7), // 7 violet
      Color(0xFFE34948), // 8 red
    ],
    chartOther: Color(0x66101319),
    shadow: Color(0x1A101319),
  );

  @override
  AppColorTokens copyWith({
    Brightness? brightness,
    Color? canvas,
    List<Color>? canvasGradient,
    Map<ModuleTone, ModulePalette>? modulePalettes,
    double? glowStrength,
    Color? pattern,
    Color? sidebar,
    List<Color>? sidebarGradient,
    Color? surface,
    Color? surfaceOpaque,
    List<Color>? surfaceGradient,
    Color? surfaceRaised,
    Color? surfaceHover,
    Color? overlay,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? textOnAccent,
    Color? accent,
    Color? accentMuted,
    List<Color>? accentGradient,
    Color? safe,
    Color? review,
    Color? risky,
    Color? info,
    Color? downstream,
    Color? upstream,
    List<Color>? chartSeries,
    Color? chartOther,
    Color? shadow,
  }) {
    return AppColorTokens(
      brightness: brightness ?? this.brightness,
      canvas: canvas ?? this.canvas,
      canvasGradient: canvasGradient ?? this.canvasGradient,
      modulePalettes: modulePalettes ?? this.modulePalettes,
      glowStrength: glowStrength ?? this.glowStrength,
      pattern: pattern ?? this.pattern,
      sidebar: sidebar ?? this.sidebar,
      sidebarGradient: sidebarGradient ?? this.sidebarGradient,
      surface: surface ?? this.surface,
      surfaceOpaque: surfaceOpaque ?? this.surfaceOpaque,
      surfaceGradient: surfaceGradient ?? this.surfaceGradient,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceHover: surfaceHover ?? this.surfaceHover,
      overlay: overlay ?? this.overlay,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      textOnAccent: textOnAccent ?? this.textOnAccent,
      accent: accent ?? this.accent,
      accentMuted: accentMuted ?? this.accentMuted,
      accentGradient: accentGradient ?? this.accentGradient,
      safe: safe ?? this.safe,
      review: review ?? this.review,
      risky: risky ?? this.risky,
      info: info ?? this.info,
      downstream: downstream ?? this.downstream,
      upstream: upstream ?? this.upstream,
      chartSeries: chartSeries ?? this.chartSeries,
      chartOther: chartOther ?? this.chartOther,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  AppColorTokens lerp(ThemeExtension<AppColorTokens>? other, double t) {
    if (other is! AppColorTokens) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    // Stop counts match across themes by construction, but a mismatch would
    // otherwise crash mid-transition rather than just looking wrong.
    List<Color> g(List<Color> a, List<Color> b) =>
        a.length == b.length
            ? [for (var i = 0; i < a.length; i++) c(a[i], b[i])]
            : (t < 0.5 ? a : b);
    return AppColorTokens(
      brightness: t < 0.5 ? brightness : other.brightness,
      canvas: c(canvas, other.canvas),
      canvasGradient: g(canvasGradient, other.canvasGradient),
      modulePalettes: {
        for (final tone in ModuleTone.values)
          if (modulePalettes[tone] != null &&
              other.modulePalettes[tone] != null)
            tone: ModulePalette.lerp(
              modulePalettes[tone]!,
              other.modulePalettes[tone]!,
              t,
            ),
      },
      glowStrength: glowStrength + (other.glowStrength - glowStrength) * t,
      pattern: c(pattern, other.pattern),
      sidebar: c(sidebar, other.sidebar),
      sidebarGradient: g(sidebarGradient, other.sidebarGradient),
      surface: c(surface, other.surface),
      surfaceOpaque: c(surfaceOpaque, other.surfaceOpaque),
      surfaceGradient: g(surfaceGradient, other.surfaceGradient),
      surfaceRaised: c(surfaceRaised, other.surfaceRaised),
      surfaceHover: c(surfaceHover, other.surfaceHover),
      overlay: c(overlay, other.overlay),
      border: c(border, other.border),
      borderStrong: c(borderStrong, other.borderStrong),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textMuted: c(textMuted, other.textMuted),
      textOnAccent: c(textOnAccent, other.textOnAccent),
      accent: c(accent, other.accent),
      accentMuted: c(accentMuted, other.accentMuted),
      accentGradient: g(accentGradient, other.accentGradient),
      safe: c(safe, other.safe),
      review: c(review, other.review),
      risky: c(risky, other.risky),
      info: c(info, other.info),
      downstream: c(downstream, other.downstream),
      upstream: c(upstream, other.upstream),
      chartSeries: g(chartSeries, other.chartSeries),
      chartOther: c(chartOther, other.chartOther),
      shadow: c(shadow, other.shadow),
    );
  }
}

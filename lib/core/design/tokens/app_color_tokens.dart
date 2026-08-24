import 'package:flutter/material.dart';

/// The modules that own a backdrop hue.
///
/// Each top-level module gets its own colour of light in the window, so the
/// app tells you where you are before you have read the page title — the same
/// way a well-signed building does. `AppDestination` declares which tone it
/// wears; the colours themselves live in [AppColorTokens.moduleTints], because
/// nothing outside this layer is allowed to name a colour.
///
/// [brand] is the fallback: a view that is not one of the six modules keeps the
/// signature violet rather than inventing a seventh hue.
enum ModuleTone {
  brand,
  cleanup,
  protection,
  performance,
  applications,
  clutter,
  spaceLens,
}

/// Every colour in the app, resolved for the active brightness.
///
/// Widgets read these through `context.colors` rather than importing statics,
/// which is what makes a runtime light/dark switch possible at all.
@immutable
class AppColorTokens extends ThemeExtension<AppColorTokens> {
  const AppColorTokens({
    required this.brightness,
    required this.canvas,
    required this.canvasGradient,
    required this.sidebar,
    required this.sidebarGradient,
    required this.surface,
    required this.surfaceOpaque,
    required this.surfaceGradient,
    required this.surfaceRaised,
    required this.surfaceHover,
    required this.overlay,
    required this.glowPrimary,
    required this.glowSecondary,
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
    required this.moduleTints,
    required this.safe,
    required this.review,
    required this.risky,
    required this.info,
    required this.shadow,
  });

  final Brightness brightness;

  // ─── Surfaces ────────────────────────────────────────────────────────────
  /// The window background behind everything. The flat fallback for anywhere
  /// that cannot take a gradient (Material's `scaffoldBackgroundColor`).
  final Color canvas;

  /// The window backdrop wash, painted top-left to bottom-right by
  /// `AmbientBackground`. Two neighbouring tints of [canvas] — wide enough to
  /// stop a 1100pt-wide window reading as one flat slab, narrow enough that no
  /// single screenful looks tinted.
  final List<Color> canvasGradient;

  /// Sidebar veil. Translucent, like every other in-window surface: the rail
  /// is a tint over the backdrop, not a panel cut out of it.
  final Color sidebar;

  /// The rail's vertical wash — lighter at the brand mark, settling at the
  /// storage summary. Translucent, so the window's glows carry straight
  /// through the sidebar and the backdrop reads as one continuous surface.
  final List<Color> sidebarGradient;

  /// Default card / tile / table background. **Translucent** — the backdrop
  /// shows through every in-window surface, which is what stops a screen of
  /// cards reading as slabs pasted onto a picture.
  final Color surface;

  /// The one solid surface, for anything that floats *over* the window rather
  /// than sitting in it: dialogs, popup menus, tooltips, snackbars, the
  /// menu-bar popover. Those need to hide what is behind them, and a sheer
  /// dialog over a table is unreadable.
  final Color surfaceOpaque;

  /// The card sheen: [surface] lit very slightly from the top-left, and
  /// slightly more transparent at the bottom so the card settles into the
  /// backdrop instead of ending on a hard edge.
  final List<Color> surfaceGradient;

  /// A surface that sits on top of [surface] (inputs, nested rows). Sheer for
  /// the same reason [surface] is; inside a dialog it composites over
  /// [surfaceOpaque] and comes out solid anyway.
  final Color surfaceRaised;

  /// Hover / pressed wash for interactive surfaces.
  final Color surfaceHover;

  /// Scrim behind dialogs.
  final Color overlay;

  // ─── Ambient light ───────────────────────────────────────────────────────
  /// The warm glow in the top-left of the window. Already carries its own
  /// alpha — it is composited over [canvasGradient], never used as a fill.
  final Color glowPrimary;

  /// The cooler counterweight in the bottom-right. Same rules as
  /// [glowPrimary]: ambience only, never a surface, never behind body text at
  /// full strength.
  final Color glowSecondary;

  /// The ink for the backdrop's shapes and dot grid. Already carries its own
  /// alpha, and it is deliberately near-invisible: the pattern is meant to be
  /// noticed only when you look for it, never while reading a size column.
  final Color pattern;

  // ─── Lines ───────────────────────────────────────────────────────────────
  /// Default 1px separator and card outline.
  final Color border;

  /// A deliberately visible edge (focused input, selected row).
  final Color borderStrong;

  // ─── Text ────────────────────────────────────────────────────────────────
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  /// Text drawn on top of [accent] or a status fill.
  final Color textOnAccent;

  // ─── Brand ───────────────────────────────────────────────────────────────
  final Color accent;

  /// A low-opacity accent wash for selected nav items and icon tiles.
  final Color accentMuted;

  /// The signature gradient. The brand mark, the scan ring, and every primary
  /// call to action (`GradientButton`) — the things the user is meant to press
  /// or watch. Not tables, not rows, not chrome.
  final List<Color> accentGradient;

  /// The backdrop hue each module owns. Read it through [moduleTint], which
  /// falls back to the brand tone rather than throwing on a missing key.
  ///
  /// These are *light*, not paint: they replace the primary glow in
  /// `AmbientBackground` and tint the canvas wash a few percent. A module's
  /// buttons, chips and status colours stay exactly as they are everywhere
  /// else — the tone says where you are, it does not restyle the controls.
  final Map<ModuleTone, Color> moduleTints;

  // ─── Semantic status ─────────────────────────────────────────────────────
  /// Regenerated automatically; safe to remove without thinking.
  final Color safe;

  /// Worth a look before removing.
  final Color review;

  /// Destructive, or user data. Never pre-selected.
  final Color risky;

  final Color info;

  final Color shadow;

  bool get isDark => brightness == Brightness.dark;

  /// The colour a [SafetyLevel]-style tier should use.
  Color statusFor(int tierIndex) => switch (tierIndex) {
    0 => safe,
    1 => review,
    _ => risky,
  };

  /// The backdrop hue for [tone], falling back to the brand violet.
  Color moduleTint(ModuleTone tone) =>
      moduleTints[tone] ?? moduleTints[ModuleTone.brand] ?? glowPrimary;

  /// A two-stop wash of [tint] over [surface], for a card that should glow in
  /// its own semantic colour. Blended rather than layered so the result is an
  /// opaque fill — a translucent card over the ambient glows picks up whatever
  /// happens to be behind it, which is different on every screen.
  List<Color> tintedSurface(Color tint, {double strength = 1}) => [
    Color.alphaBlend(
      tint.withValues(alpha: 0.11 * strength),
      surfaceGradient.first,
    ),
    Color.alphaBlend(
      tint.withValues(alpha: 0.02 * strength),
      surfaceGradient.last,
    ),
  ];

  /// Deep neutral-navy, lifted by a violet glow at the top and a teal one at
  /// the foot. The signature look.
  factory AppColorTokens.dark() => const AppColorTokens(
    brightness: Brightness.dark,
    canvas: Color(0xFF0F1219),
    canvasGradient: [Color(0xFF181E33), Color(0xFF0F1219), Color(0xFF0C1823)],
    sidebar: Color(0x4D0B0F1A),
    sidebarGradient: [Color(0x400F1526), Color(0x73070910)],
    surface: Color(0x9E1C2130),
    surfaceOpaque: Color(0xFF171B24),
    surfaceGradient: [Color(0xA3212739), Color(0x8A161B27)],
    surfaceRaised: Color(0x8F252C3C),
    surfaceHover: Color(0xB22E3648),
    overlay: Color(0xCC05070B),
    glowPrimary: Color(0x596E5BFF),
    glowSecondary: Color(0x403DD5C8),
    pattern: Color(0x1FA9B6D6),
    border: Color(0xFF262C38),
    borderStrong: Color(0xFF39414F),
    textPrimary: Color(0xFFEDEFF3),
    textSecondary: Color(0xFF98A1B2),
    textMuted: Color(0xFF69707E),
    textOnAccent: Color(0xFFFFFFFF),
    accent: Color(0xFF4C8DFF),
    accentMuted: Color(0x264C8DFF),
    accentGradient: [Color(0xFF6E5BFF), Color(0xFF4C8DFF), Color(0xFF3DD5C8)],
    moduleTints: {
      ModuleTone.brand: Color(0x596E5BFF),
      ModuleTone.cleanup: Color(0x594C8DFF),
      ModuleTone.protection: Color(0x4DF05BC8),
      ModuleTone.performance: Color(0x4DFF8A3D),
      ModuleTone.applications: Color(0x5935B6F5),
      ModuleTone.clutter: Color(0x4D3DD5C8),
      ModuleTone.spaceLens: Color(0x598B5CF6),
    },
    safe: Color(0xFF34C77B),
    review: Color(0xFFF5A524),
    risky: Color(0xFFF04A5E),
    info: Color(0xFF5AC8FA),
    shadow: Color(0x66000000),
  );

  factory AppColorTokens.light() => const AppColorTokens(
    brightness: Brightness.light,
    canvas: Color(0xFFF4F6F9),
    canvasGradient: [Color(0xFFF4F1FE), Color(0xFFF4F6F9), Color(0xFFEBF6F8)],
    sidebar: Color(0x59FFFFFF),
    sidebarGradient: [Color(0x59FFFFFF), Color(0x8CEDEFF5)],
    surface: Color(0xD9FFFFFF),
    surfaceOpaque: Color(0xFFFFFFFF),
    surfaceGradient: [Color(0xE6FFFFFF), Color(0xC7F8FAFE)],
    surfaceRaised: Color(0xCCF7F8FB),
    surfaceHover: Color(0xE0EDF0F5),
    overlay: Color(0x66101319),
    glowPrimary: Color(0x406E5BFF),
    glowSecondary: Color(0x3315B8AC),
    pattern: Color(0x1A283452),
    border: Color(0xFFE1E5EC),
    borderStrong: Color(0xFFC7CDD8),
    textPrimary: Color(0xFF12151C),
    textSecondary: Color(0xFF576073),
    textMuted: Color(0xFF848C9B),
    textOnAccent: Color(0xFFFFFFFF),
    accent: Color(0xFF2E6FE8),
    accentMuted: Color(0x1F2E6FE8),
    accentGradient: [Color(0xFF5B45E0), Color(0xFF2E6FE8), Color(0xFF15B8AC)],
    moduleTints: {
      ModuleTone.brand: Color(0x406E5BFF),
      ModuleTone.cleanup: Color(0x402E6FE8),
      ModuleTone.protection: Color(0x38C4359E),
      ModuleTone.performance: Color(0x38E06A12),
      ModuleTone.applications: Color(0x400E8FD0),
      ModuleTone.clutter: Color(0x3815B8AC),
      ModuleTone.spaceLens: Color(0x406D3FE0),
    },
    safe: Color(0xFF15964F),
    review: Color(0xFFB8720A),
    risky: Color(0xFFD32F3D),
    info: Color(0xFF0B84D6),
    shadow: Color(0x1A101319),
  );

  @override
  AppColorTokens copyWith({
    Brightness? brightness,
    Color? canvas,
    List<Color>? canvasGradient,
    Color? sidebar,
    List<Color>? sidebarGradient,
    Color? surface,
    Color? surfaceOpaque,
    List<Color>? surfaceGradient,
    Color? surfaceRaised,
    Color? surfaceHover,
    Color? overlay,
    Color? glowPrimary,
    Color? glowSecondary,
    Color? pattern,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? textOnAccent,
    Color? accent,
    Color? accentMuted,
    List<Color>? accentGradient,
    Map<ModuleTone, Color>? moduleTints,
    Color? safe,
    Color? review,
    Color? risky,
    Color? info,
    Color? shadow,
  }) {
    return AppColorTokens(
      brightness: brightness ?? this.brightness,
      canvas: canvas ?? this.canvas,
      canvasGradient: canvasGradient ?? this.canvasGradient,
      sidebar: sidebar ?? this.sidebar,
      sidebarGradient: sidebarGradient ?? this.sidebarGradient,
      surface: surface ?? this.surface,
      surfaceOpaque: surfaceOpaque ?? this.surfaceOpaque,
      surfaceGradient: surfaceGradient ?? this.surfaceGradient,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceHover: surfaceHover ?? this.surfaceHover,
      overlay: overlay ?? this.overlay,
      glowPrimary: glowPrimary ?? this.glowPrimary,
      glowSecondary: glowSecondary ?? this.glowSecondary,
      pattern: pattern ?? this.pattern,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      textOnAccent: textOnAccent ?? this.textOnAccent,
      accent: accent ?? this.accent,
      accentMuted: accentMuted ?? this.accentMuted,
      accentGradient: accentGradient ?? this.accentGradient,
      moduleTints: moduleTints ?? this.moduleTints,
      safe: safe ?? this.safe,
      review: review ?? this.review,
      risky: risky ?? this.risky,
      info: info ?? this.info,
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
      sidebar: c(sidebar, other.sidebar),
      sidebarGradient: g(sidebarGradient, other.sidebarGradient),
      surface: c(surface, other.surface),
      surfaceOpaque: c(surfaceOpaque, other.surfaceOpaque),
      surfaceGradient: g(surfaceGradient, other.surfaceGradient),
      surfaceRaised: c(surfaceRaised, other.surfaceRaised),
      surfaceHover: c(surfaceHover, other.surfaceHover),
      overlay: c(overlay, other.overlay),
      glowPrimary: c(glowPrimary, other.glowPrimary),
      glowSecondary: c(glowSecondary, other.glowSecondary),
      pattern: c(pattern, other.pattern),
      border: c(border, other.border),
      borderStrong: c(borderStrong, other.borderStrong),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textMuted: c(textMuted, other.textMuted),
      textOnAccent: c(textOnAccent, other.textOnAccent),
      accent: c(accent, other.accent),
      accentMuted: c(accentMuted, other.accentMuted),
      accentGradient: g(accentGradient, other.accentGradient),
      moduleTints: {
        for (final tone in ModuleTone.values)
          if (moduleTints[tone] != null && other.moduleTints[tone] != null)
            tone: c(moduleTints[tone]!, other.moduleTints[tone]!),
      },
      safe: c(safe, other.safe),
      review: c(review, other.review),
      risky: c(risky, other.risky),
      info: c(info, other.info),
      shadow: c(shadow, other.shadow),
    );
  }
}

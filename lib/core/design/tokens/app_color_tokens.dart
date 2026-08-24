import 'package:flutter/material.dart';

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
    required this.surfaceGradient,
    required this.surfaceRaised,
    required this.surfaceHover,
    required this.overlay,
    required this.glowPrimary,
    required this.glowSecondary,
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

  /// Sidebar background. Sits behind the vibrancy layer when it is available.
  final Color sidebar;

  /// The rail's vertical wash — lighter at the brand mark, settling at the
  /// storage summary, so the sidebar reads as its own plane against the canvas.
  final List<Color> sidebarGradient;

  /// Default card / tile background.
  final Color surface;

  /// The card sheen: [surface] lit very slightly from the top-left. Subtle by
  /// design — a card should read as one surface catching light, not as two.
  final List<Color> surfaceGradient;

  /// A surface that sits on top of [surface] (inputs, nested rows).
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
    canvasGradient: [Color(0xFF151A2A), Color(0xFF0F1219), Color(0xFF0E1620)],
    sidebar: Color(0xFF0A0D13),
    sidebarGradient: [Color(0xFF0E1220), Color(0xFF080A10)],
    surface: Color(0xFF171B24),
    surfaceGradient: [Color(0xFF1B2029), Color(0xFF15181F)],
    surfaceRaised: Color(0xFF1F2430),
    surfaceHover: Color(0xFF262C3A),
    overlay: Color(0xCC05070B),
    glowPrimary: Color(0x3D6E5BFF),
    glowSecondary: Color(0x2E3DD5C8),
    border: Color(0xFF262C38),
    borderStrong: Color(0xFF39414F),
    textPrimary: Color(0xFFEDEFF3),
    textSecondary: Color(0xFF98A1B2),
    textMuted: Color(0xFF69707E),
    textOnAccent: Color(0xFFFFFFFF),
    accent: Color(0xFF4C8DFF),
    accentMuted: Color(0x264C8DFF),
    accentGradient: [Color(0xFF6E5BFF), Color(0xFF4C8DFF), Color(0xFF3DD5C8)],
    safe: Color(0xFF34C77B),
    review: Color(0xFFF5A524),
    risky: Color(0xFFF04A5E),
    info: Color(0xFF5AC8FA),
    shadow: Color(0x66000000),
  );

  factory AppColorTokens.light() => const AppColorTokens(
    brightness: Brightness.light,
    canvas: Color(0xFFF4F6F9),
    canvasGradient: [Color(0xFFF6F4FE), Color(0xFFF4F6F9), Color(0xFFEFF7F8)],
    sidebar: Color(0xFFEAEDF2),
    sidebarGradient: [Color(0xFFEDEBF7), Color(0xFFE6EBF1)],
    surface: Color(0xFFFFFFFF),
    surfaceGradient: [Color(0xFFFFFFFF), Color(0xFFFAFBFE)],
    surfaceRaised: Color(0xFFF7F8FB),
    surfaceHover: Color(0xFFEDF0F5),
    overlay: Color(0x66101319),
    glowPrimary: Color(0x2E6E5BFF),
    glowSecondary: Color(0x2415B8AC),
    border: Color(0xFFE1E5EC),
    borderStrong: Color(0xFFC7CDD8),
    textPrimary: Color(0xFF12151C),
    textSecondary: Color(0xFF576073),
    textMuted: Color(0xFF848C9B),
    textOnAccent: Color(0xFFFFFFFF),
    accent: Color(0xFF2E6FE8),
    accentMuted: Color(0x1F2E6FE8),
    accentGradient: [Color(0xFF5B45E0), Color(0xFF2E6FE8), Color(0xFF15B8AC)],
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
    List<Color>? surfaceGradient,
    Color? surfaceRaised,
    Color? surfaceHover,
    Color? overlay,
    Color? glowPrimary,
    Color? glowSecondary,
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
    Color? shadow,
  }) {
    return AppColorTokens(
      brightness: brightness ?? this.brightness,
      canvas: canvas ?? this.canvas,
      canvasGradient: canvasGradient ?? this.canvasGradient,
      sidebar: sidebar ?? this.sidebar,
      sidebarGradient: sidebarGradient ?? this.sidebarGradient,
      surface: surface ?? this.surface,
      surfaceGradient: surfaceGradient ?? this.surfaceGradient,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceHover: surfaceHover ?? this.surfaceHover,
      overlay: overlay ?? this.overlay,
      glowPrimary: glowPrimary ?? this.glowPrimary,
      glowSecondary: glowSecondary ?? this.glowSecondary,
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
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  AppColorTokens lerp(ThemeExtension<AppColorTokens>? other, double t) {
    if (other is! AppColorTokens) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    // Stop counts match across themes by construction, but a mismatch would
    // otherwise crash mid-transition rather than just looking wrong.
    List<Color> g(List<Color> a, List<Color> b) => a.length == b.length
        ? [for (var i = 0; i < a.length; i++) c(a[i], b[i])]
        : (t < 0.5 ? a : b);
    return AppColorTokens(
      brightness: t < 0.5 ? brightness : other.brightness,
      canvas: c(canvas, other.canvas),
      canvasGradient: g(canvasGradient, other.canvasGradient),
      sidebar: c(sidebar, other.sidebar),
      sidebarGradient: g(sidebarGradient, other.sidebarGradient),
      surface: c(surface, other.surface),
      surfaceGradient: g(surfaceGradient, other.surfaceGradient),
      surfaceRaised: c(surfaceRaised, other.surfaceRaised),
      surfaceHover: c(surfaceHover, other.surfaceHover),
      overlay: c(overlay, other.overlay),
      glowPrimary: c(glowPrimary, other.glowPrimary),
      glowSecondary: c(glowSecondary, other.glowSecondary),
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
      shadow: c(shadow, other.shadow),
    );
  }
}

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
    required this.sidebar,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceHover,
    required this.overlay,
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
  /// The window background behind everything.
  final Color canvas;

  /// Sidebar background. Sits behind the vibrancy layer when it is available.
  final Color sidebar;

  /// Default card / tile background.
  final Color surface;

  /// A surface that sits on top of [surface] (inputs, nested rows).
  final Color surfaceRaised;

  /// Hover / pressed wash for interactive surfaces.
  final Color surfaceHover;

  /// Scrim behind dialogs.
  final Color overlay;

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

  /// The signature gradient. Used for the scan ring and hero surfaces only —
  /// gradients everywhere is what makes an app look cheap.
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

  /// Deep neutral-navy. The signature look.
  factory AppColorTokens.dark() => const AppColorTokens(
    brightness: Brightness.dark,
    canvas: Color(0xFF0F1219),
    sidebar: Color(0xFF0A0D13),
    surface: Color(0xFF171B24),
    surfaceRaised: Color(0xFF1F2430),
    surfaceHover: Color(0xFF262C3A),
    overlay: Color(0xCC05070B),
    border: Color(0xFF262C38),
    borderStrong: Color(0xFF39414F),
    textPrimary: Color(0xFFEDEFF3),
    textSecondary: Color(0xFF98A1B2),
    textMuted: Color(0xFF69707E),
    textOnAccent: Color(0xFFFFFFFF),
    accent: Color(0xFF4C8DFF),
    accentMuted: Color(0x264C8DFF),
    accentGradient: [Color(0xFF4C8DFF), Color(0xFF3DD5C8)],
    safe: Color(0xFF34C77B),
    review: Color(0xFFF5A524),
    risky: Color(0xFFF04A5E),
    info: Color(0xFF5AC8FA),
    shadow: Color(0x66000000),
  );

  factory AppColorTokens.light() => const AppColorTokens(
    brightness: Brightness.light,
    canvas: Color(0xFFF4F6F9),
    sidebar: Color(0xFFEAEDF2),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFF7F8FB),
    surfaceHover: Color(0xFFEDF0F5),
    overlay: Color(0x66101319),
    border: Color(0xFFE1E5EC),
    borderStrong: Color(0xFFC7CDD8),
    textPrimary: Color(0xFF12151C),
    textSecondary: Color(0xFF576073),
    textMuted: Color(0xFF848C9B),
    textOnAccent: Color(0xFFFFFFFF),
    accent: Color(0xFF2E6FE8),
    accentMuted: Color(0x1F2E6FE8),
    accentGradient: [Color(0xFF2E6FE8), Color(0xFF15B8AC)],
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
    Color? sidebar,
    Color? surface,
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
    Color? shadow,
  }) {
    return AppColorTokens(
      brightness: brightness ?? this.brightness,
      canvas: canvas ?? this.canvas,
      sidebar: sidebar ?? this.sidebar,
      surface: surface ?? this.surface,
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
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  AppColorTokens lerp(ThemeExtension<AppColorTokens>? other, double t) {
    if (other is! AppColorTokens) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColorTokens(
      brightness: t < 0.5 ? brightness : other.brightness,
      canvas: c(canvas, other.canvas),
      sidebar: c(sidebar, other.sidebar),
      surface: c(surface, other.surface),
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
      accentGradient: [
        for (var i = 0; i < accentGradient.length; i++)
          c(accentGradient[i], other.accentGradient[i]),
      ],
      safe: c(safe, other.safe),
      review: c(review, other.review),
      risky: c(risky, other.risky),
      info: c(info, other.info),
      shadow: c(shadow, other.shadow),
    );
  }
}

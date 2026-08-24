import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';

/// Compatibility shim over the token layer in `lib/core/design/`.
///
/// The constants below are the dark [AppColorTokens] values repeated as
/// compile-time constants, because callers use them inside `const` widget
/// constructors. They exist so the app keeps compiling while widgets migrate to
/// `context.colors` one at a time — a widget reading these can never respond to
/// a light/dark switch, so every one of them is a migration TODO.
@Deprecated('Use context.colors / context.text from core/design instead.')
class AppTheme {
  AppTheme._();

  // ─── Backgrounds ─────────────────────────────────────────────────────────
  static const Color backgroundPrimary = Color(0xFF0F1219);
  static const Color backgroundSidebar = Color(0xFF0A0D13);
  static const Color surfaceCard = Color(0xFF171B24);
  static const Color surfaceElevated = Color(0xFF1F2430);

  // ─── Accents ─────────────────────────────────────────────────────────────
  static const Color accentBlue = Color(0xFF4C8DFF);
  static const Color accentGreen = Color(0xFF34C77B);
  static const Color accentOrange = Color(0xFFF5A524);
  static const Color accentRed = Color(0xFFF04A5E);

  // ─── Text ────────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFEDEFF3);
  static const Color textSecondary = Color(0xFF98A1B2);
  static const Color textMuted = Color(0xFF69707E);

  // ─── Borders & dividers ──────────────────────────────────────────────────
  static const Color borderSubtle = Color(0xFF262C38);
  static const Color borderLight = Color(0xFF39414F);

  static ThemeData get dark => TidyTheme.dark();

  static TextStyle get titleLarge => const TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    letterSpacing: -0.5,
  );

  static TextStyle get sectionHeader => const TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: textMuted,
    letterSpacing: 0.7,
  );

  static TextStyle summaryValue(Color color) =>
      TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: color);

  static const TextStyle bodyPrimary = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: textPrimary,
  );

  static const TextStyle bodySecondary = TextStyle(
    fontSize: 13,
    color: textSecondary,
  );

  static const TextStyle tableHeader = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: textMuted,
    letterSpacing: 0.7,
  );

  static const TextStyle labelSmall = TextStyle(
    fontSize: 11,
    color: textSecondary,
  );

  static const TextStyle versionBadge = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: accentBlue,
  );
}

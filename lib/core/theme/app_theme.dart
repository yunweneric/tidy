import 'package:flutter/material.dart';

/// MacUninstaller PRO theme — dark blue-grey base with accent colors.
class AppTheme {
  AppTheme._();

  // ─── Backgrounds ─────────────────────────────────────────────────────────
  static const Color backgroundPrimary = Color(0xFF1A1E29);
  static const Color backgroundSidebar = Color(0xFF141822);
  static const Color surfaceCard = Color(0xFF232936);
  static const Color surfaceElevated = Color(0xFF2A3040);

  // ─── Accents ─────────────────────────────────────────────────────────────
  static const Color accentBlue = Color(0xFF007AFF);
  static const Color accentGreen = Color(0xFF2ECC71);
  static const Color accentOrange = Color(0xFFE67E22);
  static const Color accentRed = Color(0xFFE74C3C);

  // ─── Text ────────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFF0F2F5);
  static const Color textSecondary = Color(0xFF9CA3B4);
  static const Color textMuted = Color(0xFF6B7280);

  // ─── Borders & dividers ──────────────────────────────────────────────────
  static const Color borderSubtle = Color(0xFF3B4254);
  static const Color borderLight = Color(0xFF4B5563);

  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: backgroundPrimary,
      colorScheme: ColorScheme.dark(
        primary: accentBlue,
        secondary: accentGreen,
        surface: backgroundPrimary,
        error: accentRed,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimary,
        onError: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: backgroundPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: surfaceCard,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceElevated,
        hintStyle: const TextStyle(color: textMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: accentBlue, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentBlue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accentBlue),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accentBlue;
          return Colors.transparent;
        }),
        side: const BorderSide(color: borderLight),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      dividerTheme: const DividerThemeData(color: borderSubtle, thickness: 1),
    );
  }

  /// Large title (e.g. "Application Manager")
  static TextStyle get titleLarge => const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: textPrimary,
        letterSpacing: -0.5,
      );

  /// Section headers (e.g. "Total Apps", nav section "MANAGEMENT")
  static TextStyle get sectionHeader => const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: textMuted,
        letterSpacing: 0.8,
      );

  /// Summary card value (e.g. "142", "84.2 GB")
  static TextStyle summaryValue(Color color) => TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: color,
      );

  /// Body / list primary
  static const TextStyle bodyPrimary = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: textPrimary,
  );

  /// Body secondary
  static const TextStyle bodySecondary = TextStyle(
    fontSize: 13,
    color: textSecondary,
  );

  /// Table header (APPLICATION, DEVELOPER, etc.)
  static const TextStyle tableHeader = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: textMuted,
    letterSpacing: 0.6,
  );

  /// Small label (e.g. "PRO EDITION", "Selected: 0")
  static const TextStyle labelSmall = TextStyle(
    fontSize: 11,
    color: textSecondary,
  );

  /// Version pill / badge
  static const TextStyle versionBadge = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: accentBlue,
  );
}

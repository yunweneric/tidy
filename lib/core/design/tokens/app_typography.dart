import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/tokens/app_color_tokens.dart';

/// The type ramp, already resolved against the active [AppColorTokens].
///
/// Styles carry their colour so call sites never pair the wrong text colour
/// with a surface — the single most common way a dark theme springs a leak.
@immutable
class AppTypography extends ThemeExtension<AppTypography> {
  const AppTypography({
    required this.displayXl,
    required this.displayL,
    required this.titleL,
    required this.titleM,
    required this.titleS,
    required this.bodyL,
    required this.bodyM,
    required this.bodyS,
    required this.label,
    required this.caption,
    required this.overline,
    required this.mono,
  });

  /// The reclaimable-bytes number on a scan hero. Nothing else.
  final TextStyle displayXl;

  /// Tile headline numbers ("3.2 GB").
  final TextStyle displayL;

  /// Page title ("Cleanup").
  final TextStyle titleL;

  /// Card / section title.
  final TextStyle titleM;

  /// Row title, emphasised body.
  final TextStyle titleS;

  final TextStyle bodyL;

  /// Default body text.
  final TextStyle bodyM;

  final TextStyle bodyS;

  /// Buttons, nav items, chips.
  final TextStyle label;

  /// Secondary metadata under a row.
  final TextStyle caption;

  /// Uppercase section label and table headers.
  final TextStyle overline;

  /// Filesystem paths. Monospace so components line up when scanning a list.
  final TextStyle mono;

  /// Tabular figures, so a column of sizes doesn't jitter as digits change.
  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  factory AppTypography.from(AppColorTokens colors) {
    return AppTypography(
      displayXl: TextStyle(
        fontSize: 56,
        height: 1.05,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.6,
        color: colors.textPrimary,
        fontFeatures: _tabular,
      ),
      displayL: TextStyle(
        fontSize: 30,
        height: 1.15,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.7,
        color: colors.textPrimary,
        fontFeatures: _tabular,
      ),
      titleL: TextStyle(
        fontSize: 24,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: colors.textPrimary,
      ),
      titleM: TextStyle(
        fontSize: 17,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: colors.textPrimary,
      ),
      titleS: TextStyle(
        fontSize: 14,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: colors.textPrimary,
      ),
      bodyL: TextStyle(
        fontSize: 15,
        height: 1.45,
        fontWeight: FontWeight.w400,
        color: colors.textPrimary,
      ),
      bodyM: TextStyle(
        fontSize: 13,
        height: 1.45,
        fontWeight: FontWeight.w400,
        color: colors.textSecondary,
      ),
      bodyS: TextStyle(
        fontSize: 12,
        height: 1.4,
        fontWeight: FontWeight.w400,
        color: colors.textSecondary,
      ),
      label: TextStyle(
        fontSize: 13,
        height: 1.2,
        fontWeight: FontWeight.w500,
        color: colors.textPrimary,
      ),
      caption: TextStyle(
        fontSize: 11,
        height: 1.35,
        fontWeight: FontWeight.w400,
        color: colors.textMuted,
      ),
      overline: TextStyle(
        fontSize: 11,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.7,
        color: colors.textMuted,
      ),
      mono: TextStyle(
        fontSize: 12,
        height: 1.4,
        fontWeight: FontWeight.w400,
        fontFamily: 'SF Mono',
        fontFamilyFallback: const ['Menlo', 'Monaco', 'monospace'],
        color: colors.textMuted,
      ),
    );
  }

  /// A [TextTheme] for the Material widgets we don't own.
  TextTheme toTextTheme() => TextTheme(
    displayLarge: displayXl,
    displayMedium: displayL,
    headlineSmall: titleL,
    titleLarge: titleL,
    titleMedium: titleM,
    titleSmall: titleS,
    bodyLarge: bodyL,
    bodyMedium: bodyM,
    bodySmall: bodyS,
    labelLarge: label,
    labelMedium: label,
    labelSmall: caption,
  );

  @override
  AppTypography copyWith({
    TextStyle? displayXl,
    TextStyle? displayL,
    TextStyle? titleL,
    TextStyle? titleM,
    TextStyle? titleS,
    TextStyle? bodyL,
    TextStyle? bodyM,
    TextStyle? bodyS,
    TextStyle? label,
    TextStyle? caption,
    TextStyle? overline,
    TextStyle? mono,
  }) {
    return AppTypography(
      displayXl: displayXl ?? this.displayXl,
      displayL: displayL ?? this.displayL,
      titleL: titleL ?? this.titleL,
      titleM: titleM ?? this.titleM,
      titleS: titleS ?? this.titleS,
      bodyL: bodyL ?? this.bodyL,
      bodyM: bodyM ?? this.bodyM,
      bodyS: bodyS ?? this.bodyS,
      label: label ?? this.label,
      caption: caption ?? this.caption,
      overline: overline ?? this.overline,
      mono: mono ?? this.mono,
    );
  }

  @override
  AppTypography lerp(ThemeExtension<AppTypography>? other, double t) {
    if (other is! AppTypography) return this;
    TextStyle s(TextStyle a, TextStyle b) => TextStyle.lerp(a, b, t)!;
    return AppTypography(
      displayXl: s(displayXl, other.displayXl),
      displayL: s(displayL, other.displayL),
      titleL: s(titleL, other.titleL),
      titleM: s(titleM, other.titleM),
      titleS: s(titleS, other.titleS),
      bodyL: s(bodyL, other.bodyL),
      bodyM: s(bodyM, other.bodyM),
      bodyS: s(bodyS, other.bodyS),
      label: s(label, other.label),
      caption: s(caption, other.caption),
      overline: s(overline, other.overline),
      mono: s(mono, other.mono),
    );
  }
}

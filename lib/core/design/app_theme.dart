import 'package:flutter/material.dart';
import 'package:tidy/core/design/tokens/app_color_tokens.dart';
import 'package:tidy/core/design/tokens/app_motion.dart';
import 'package:tidy/core/design/tokens/app_radii.dart';
import 'package:tidy/core/design/tokens/app_spacing.dart';
import 'package:tidy/core/design/tokens/app_typography.dart';

/// Builds the [ThemeData] and installs the token extensions on it.
///
/// Material's own theming is configured only so the widgets we don't own
/// (dialogs, checkboxes, scrollbars) match. Our widgets read tokens directly.
class TidyTheme {
  const TidyTheme._();

  static ThemeData dark({bool reduceMotion = false}) =>
      _build(AppColorTokens.dark(), reduceMotion: reduceMotion);

  static ThemeData light({bool reduceMotion = false}) =>
      _build(AppColorTokens.light(), reduceMotion: reduceMotion);

  static ThemeData _build(AppColorTokens c, {required bool reduceMotion}) {
    final type = AppTypography.from(c);

    return ThemeData(
      useMaterial3: true,
      brightness: c.brightness,
      scaffoldBackgroundColor: c.canvas,
      canvasColor: c.canvas,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.compact,
      extensions: [c, type, AppMotion(reduced: reduceMotion)],
      colorScheme: ColorScheme(
        brightness: c.brightness,
        primary: c.accent,
        onPrimary: c.textOnAccent,
        secondary: c.safe,
        onSecondary: c.textOnAccent,
        error: c.risky,
        onError: c.textOnAccent,
        surface: c.surfaceOpaque,
        onSurface: c.textPrimary,
        surfaceContainerHighest: c.surfaceRaised,
        outline: c.border,
        outlineVariant: c.borderStrong,
        shadow: c.shadow,
      ),
      textTheme: type.toTextTheme(),
      iconTheme: IconThemeData(color: c.textSecondary, size: 18),
      dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
      cardTheme: CardThemeData(
        color: c.surfaceOpaque,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.lgAll),
      ),
      dialogTheme: DialogThemeData(
        // Floats over the window, so it is the one solid surface — a sheer
        // dialog sitting on a table of file paths is unreadable.
        backgroundColor: c.surfaceOpaque,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.xlAll),
        titleTextStyle: type.titleM,
        contentTextStyle: type.bodyM,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceRaised,
        hintStyle: type.bodyM.copyWith(color: c.textMuted),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadii.mdAll,
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.mdAll,
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.mdAll,
          borderSide: BorderSide(color: c.accent, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          // A neutral veil, not the accent. Every ordinary button sits on a
          // saturated module colour, and the one action that gets to wear a
          // colour is GradientButton — which wears the module's own.
          backgroundColor: c.surfaceHover,
          foregroundColor: c.textPrimary,
          disabledBackgroundColor: c.surface,
          disabledForegroundColor: c.textMuted,
          elevation: 0,
          textStyle: type.label.copyWith(fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.md,
          ),
          shape: const RoundedRectangleBorder(borderRadius: AppRadii.mdAll),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.textSecondary,
          textStyle: type.label,
          side: BorderSide(color: c.border),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          shape: const RoundedRectangleBorder(borderRadius: AppRadii.mdAll),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.textSecondary,
          textStyle: type.label,
          shape: const RoundedRectangleBorder(borderRadius: AppRadii.smAll),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.selected) ? c.accent : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(c.textOnAccent),
        side: BorderSide(color: c.borderStrong, width: 1.5),
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.xsAll),
        visualDensity: VisualDensity.compact,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          // Material defaults a selected segment to colorScheme.secondary,
          // which is our "safe" green — a theme picker is not a status.
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) =>
                s.contains(WidgetState.selected)
                    ? c.accent
                    : Colors.transparent,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) =>
                s.contains(WidgetState.selected)
                    ? c.textOnAccent
                    : c.textSecondary,
          ),
          side: WidgetStatePropertyAll(BorderSide(color: c.border)),
          textStyle: WidgetStatePropertyAll(type.label),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: AppRadii.mdAll),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStatePropertyAll(c.textOnAccent),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.accent : c.surfaceHover,
        ),
        trackOutlineColor: WidgetStatePropertyAll(Colors.transparent),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accent,
        linearTrackColor: c.surfaceHover,
        circularTrackColor: c.surfaceHover,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(c.borderStrong),
        radius: const Radius.circular(AppRadii.sm),
        thickness: const WidgetStatePropertyAll(8),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: c.surfaceOpaque,
          borderRadius: AppRadii.smAll,
          border: Border.all(color: c.border),
        ),
        textStyle: type.bodyS.copyWith(color: c.textPrimary),
        waitDuration: const Duration(milliseconds: 400),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.surfaceOpaque,
        contentTextStyle: type.bodyL.copyWith(color: c.textPrimary),
        actionTextColor: c.accent,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.mdAll),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surfaceOpaque,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.mdAll,
          side: BorderSide(color: c.border),
        ),
        textStyle: type.bodyL,
      ),
    );
  }
}

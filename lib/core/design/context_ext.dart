import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/tokens/app_color_tokens.dart';
import 'package:mac_uninstaller/core/design/tokens/app_motion.dart';
import 'package:mac_uninstaller/core/design/tokens/app_typography.dart';

/// Token accessors. `context.colors.surface` instead of importing statics.
extension AppThemeContext on BuildContext {
  AppColorTokens get colors =>
      Theme.of(this).extension<AppColorTokens>() ?? AppColorTokens.dark();

  AppTypography get text =>
      Theme.of(this).extension<AppTypography>() ??
      AppTypography.from(AppColorTokens.dark());

  AppMotion get motion =>
      Theme.of(this).extension<AppMotion>() ?? const AppMotion(reduced: false);

  bool get isDarkTheme => Theme.of(this).brightness == Brightness.dark;
}

import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/theme/app_theme.dart';
import 'package:mac_uninstaller/features/apps/data/models/mac_app_model.dart';

/// 40x40 app icon from [MacApp] (file or placeholder).
class AppIcon extends StatelessWidget {
  const AppIcon({super.key, required this.app, this.size = 40});

  final MacApp app;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: AppTheme.surfaceElevated,
      ),
      child:
          app.iconBytes != null
              ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  app.iconBytes!,
                  fit: BoxFit.cover,
                  errorBuilder:
                      (_, __, ___) => const Icon(Icons.apps, color: AppTheme.textMuted),
                ),
              )
              : const Icon(Icons.apps, color: AppTheme.textMuted),
    );
  }
}

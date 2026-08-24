import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/features/apps/data/models/mac_app_model.dart';

/// App icon, falling back to a placeholder while icons stream in.
class AppIcon extends StatelessWidget {
  const AppIcon({super.key, required this.app, this.size = 36});

  final MacApp app;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final placeholder = Icon(
      AppIcons.appPlaceholder,
      size: size * 0.5,
      color: colors.textMuted,
    );

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: AppRadii.smAll,
        color: colors.surfaceRaised,
      ),
      child:
          app.iconBytes == null
              ? placeholder
              : ClipRRect(
                borderRadius: AppRadii.smAll,
                child: Image.memory(
                  app.iconBytes!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => placeholder,
                ),
              ),
    );
  }
}

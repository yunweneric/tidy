import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/theme/app_theme.dart';

/// Circular avatar placeholder (e.g. user profile in header).
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    this.radius = 18,
    this.icon = Icons.person_outline,
  });

  final double radius;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppTheme.surfaceElevated,
      child: Icon(icon, color: AppTheme.textSecondary),
    );
  }
}

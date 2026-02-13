import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/theme/app_theme.dart';

/// Small pill showing a version string (e.g. "25.3.1").
class VersionBadge extends StatelessWidget {
  const VersionBadge({
    super.key,
    required this.version,
  });

  final String version;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        version,
        style: AppTheme.versionBadge,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

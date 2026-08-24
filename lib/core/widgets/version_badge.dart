import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';

/// Small pill showing a version string.
class VersionBadge extends StatelessWidget {
  const VersionBadge({super.key, required this.version});

  final String version;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: context.colors.surfaceRaised,
        borderRadius: AppRadii.smAll,
      ),
      child: Text(
        version,
        style: context.text.caption.copyWith(
          color: context.colors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

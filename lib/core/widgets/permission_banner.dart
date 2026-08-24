import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';
import 'package:mac_uninstaller/core/widgets/tidy_card.dart';

/// Explains why Full Disk Access is needed and links to the right settings pane.
///
/// A cleaner that demands Full Disk Access with no explanation is
/// indistinguishable from malware, so this always says what it unlocks — and it
/// says the app must be relaunched afterwards, because TCC caches the decision
/// per process and a granted-but-not-relaunched app looks like a broken one.
class PermissionBanner extends StatelessWidget {
  const PermissionBanner({
    super.key,
    required this.onOpenSettings,
    this.message,
    this.compact = false,
  });

  final VoidCallback onOpenSettings;

  /// Overrides the default copy with something module-specific, e.g. "Mail
  /// attachments are behind Full Disk Access."
  final String? message;

  /// A single line, for use inside a sidebar rather than above a page.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (compact) {
      return TextButton.icon(
        onPressed: onOpenSettings,
        icon: Icon(AppIcons.locked, size: 14, color: colors.review),
        label: Text(
          'Grant Full Disk Access',
          style: context.text.caption.copyWith(color: colors.review),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          alignment: Alignment.centerLeft,
          minimumSize: const Size(0, 30),
        ),
      );
    }

    return TidyCard(
      accent: colors.review,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: colors.review.withValues(alpha: 0.14),
              borderRadius: AppRadii.mdAll,
            ),
            child: Icon(AppIcons.locked, size: 18, color: colors.review),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Some results are hidden', style: context.text.titleS),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  message ??
                      'macOS keeps other apps’ data behind Full Disk Access. '
                          'Without it this scan can only see part of your disk — '
                          'grant access, then reopen ${Brand.name}.',
                  style: context.text.bodyM,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          OutlinedButton(
            onPressed: onOpenSettings,
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}

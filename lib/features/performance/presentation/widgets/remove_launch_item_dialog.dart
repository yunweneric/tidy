import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';
import 'package:mac_uninstaller/core/utils/byte_format.dart';
import 'package:mac_uninstaller/core/utils/home_dir.dart';
import 'package:mac_uninstaller/features/performance/data/models/launch_item.dart';

/// Confirms removing one launch item, and says what removal actually means.
///
/// Disabling and removing are not the same decision. Disabling is reversible
/// from this page; removing puts the file in the Trash and, if the owning app
/// is still installed, it may well write the file back the next time it runs.
/// Saying so up front is cheaper than a confused bug report afterwards.
Future<bool> showRemoveLaunchItemDialog(BuildContext context, LaunchItem item) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => _RemoveLaunchItemDialog(item: item),
  );
  return confirmed ?? false;
}

class _RemoveLaunchItemDialog extends StatelessWidget {
  const _RemoveLaunchItemDialog({required this.item});

  final LaunchItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final broken = item.health == LaunchItemHealth.broken;

    // Background, radius and the title style all come from `dialogTheme`.
    return AlertDialog(
      title: Text('Remove ${item.name}?'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              broken
                  ? 'This cannot start anything — the program it points at is gone, '
                        'or the file is empty. Removing it changes nothing except '
                        'tidying up after whatever left it here.'
                  : 'This stops the item and moves its settings file to the Trash. '
                        'If the app it belongs to is still installed, it may put the '
                        'file back the next time it runs — turning it off instead is '
                        'the change that sticks.',
              style: context.text.bodyM,
            ),
            const SizedBox(height: AppSpacing.lg),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: colors.surfaceRaised,
                borderRadius: AppRadii.mdAll,
                border: Border.all(color: colors.border),
              ),
              child: Text(
                collapseHome(item.path, kHomeDir),
                style: context.text.mono,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.risky,
            foregroundColor: colors.textOnAccent,
          ),
          child: const Text('Move to Trash'),
        ),
      ],
    );
  }
}

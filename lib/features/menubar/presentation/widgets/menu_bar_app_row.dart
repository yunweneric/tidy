import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/theme/app_theme.dart';
import 'package:mac_uninstaller/features/apps/data/models/mac_app_model.dart';
import 'package:mac_uninstaller/features/apps/presentation/widgets/app_icon.dart';
import 'package:mac_uninstaller/features/apps/utils/size_utils.dart';

/// One app in the popover list.
///
/// Removal confirms inline rather than in a dialog — a modal inside a 380pt
/// popover is worse than expanding the row, and the inline state is where the
/// leftover count and freed space are shown before anything is touched.
class MenuBarAppRow extends StatelessWidget {
  const MenuBarAppRow({
    super.key,
    required this.app,
    required this.confirming,
    required this.onRemovePressed,
    required this.onCancel,
    this.onConfirm,
    this.pendingLabel,
    this.enabled = true,
  });

  final MacApp app;
  final bool confirming;
  final VoidCallback onRemovePressed;
  final VoidCallback onCancel;
  final VoidCallback? onConfirm;
  final String? pendingLabel;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      color: confirming ? AppTheme.surfaceCard : Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              AppIcon(app: app, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      app.name,
                      style: AppTheme.bodyPrimary.copyWith(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      app.lastUsedLabel,
                      style: AppTheme.labelSmall.copyWith(
                        fontSize: 10,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatBytes(app.sizeBytes),
                style: AppTheme.bodySecondary.copyWith(fontSize: 12),
              ),
              if (!confirming)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 15),
                  color: AppTheme.accentRed,
                  tooltip: 'Uninstall ${app.name}',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  padding: EdgeInsets.zero,
                  onPressed: enabled ? onRemovePressed : null,
                )
              else
                const SizedBox(width: 28),
            ],
          ),
          if (confirming) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    pendingLabel ?? '',
                    style: AppTheme.labelSmall.copyWith(
                      fontSize: 11,
                      color: AppTheme.accentOrange,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: onCancel,
                  style: _compactButtonStyle(AppTheme.textSecondary),
                  child: const Text('Cancel', style: TextStyle(fontSize: 11)),
                ),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: onConfirm,
                  style: _compactButtonStyle(AppTheme.accentRed),
                  child: const Text('Move to Trash', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static ButtonStyle _compactButtonStyle(Color color) {
    return TextButton.styleFrom(
      foregroundColor: color,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      minimumSize: const Size(0, 26),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

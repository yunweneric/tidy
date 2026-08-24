import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';
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
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md + 2,
        vertical: AppSpacing.xs + 2,
      ),
      color: confirming ? colors.surface : Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              AppIcon(app: app, size: 24),
              const SizedBox(width: AppSpacing.sm + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      app.name,
                      style: context.text.label,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(app.lastUsedLabel, style: context.text.caption),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(formatBytes(app.sizeBytes), style: context.text.bodyS),
              if (!confirming)
                IconButton(
                  icon: const Icon(AppIcons.delete, size: 15),
                  color: colors.risky,
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
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: Text(
                    pendingLabel ?? '',
                    style: context.text.caption.copyWith(color: colors.review),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: onCancel,
                  style: _compactButtonStyle(colors.textSecondary),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: AppSpacing.xs),
                TextButton(
                  onPressed: onConfirm,
                  style: _compactButtonStyle(colors.risky),
                  child: const Text('Move to Trash'),
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
      textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      minimumSize: const Size(0, 26),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

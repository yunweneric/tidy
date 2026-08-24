import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';
import 'package:mac_uninstaller/core/utils/byte_format.dart';
import 'package:mac_uninstaller/features/menubar/presentation/widgets/menu_bar_button.dart';

/// One pool of space that can be handed back: junk, or the Trash.
///
/// Deliberately not a list of individual files. Everything here is either safe
/// to clear wholesale or belongs in the main window, and a popover offering
/// per-file deletion is a file manager in a 460pt box.
class MenuBarReclaimRow extends StatelessWidget {
  const MenuBarReclaimRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.bytes,
    this.actionLabel,
    this.onAction,
    this.scanning = false,
    this.note,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final int bytes;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// The size is still being worked out, so show that rather than a confident
  /// zero — an empty Trash and an unscanned one are not the same answer.
  final bool scanning;

  /// Stands in for the size when there is no honest number to give, such as a
  /// Trash macOS will not let the app read.
  final String? note;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md + 2,
        AppSpacing.xs + 2,
        AppSpacing.md + 2,
        AppSpacing.xs + 2,
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: colors.textSecondary),
          const SizedBox(width: AppSpacing.md - 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: context.text.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: context.text.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            note ?? (scanning ? 'scanning…' : formatBytes(bytes)),
            style:
                note == null
                    ? context.text.bodyS
                    : context.text.caption.copyWith(color: colors.review),
          ),
          if (actionLabel != null) ...[
            const SizedBox(width: AppSpacing.xs),
            MenuBarButton(label: actionLabel!, onPressed: onAction),
          ] else
            const SizedBox(width: AppSpacing.sm),
        ],
      ),
    );
  }
}

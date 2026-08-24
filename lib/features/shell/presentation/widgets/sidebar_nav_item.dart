import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';

/// One sidebar row: glyph, label, optional trailing badge.
class SidebarNavItem extends StatefulWidget {
  const SidebarNavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.badge,
    this.badgeColor,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  /// Usually a reclaimable size, so the sidebar answers "where is the space?"
  /// before anything is clicked.
  final String? badge;

  final Color? badgeColor;

  @override
  State<SidebarNavItem> createState() => _SidebarNavItemState();
}

class _SidebarNavItemState extends State<SidebarNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final foreground =
        widget.active
            ? colors.accent
            : (_hovered ? colors.textPrimary : colors.textSecondary);

    // The active row fades its wash out to the right rather than filling the
    // pill evenly: the eye lands on the glyph and label, which is where the
    // information is, instead of on a solid block of accent.
    final background =
        widget.active
            ? null
            : (_hovered ? colors.surfaceHover : Colors.transparent);

    final backgroundGradient =
        widget.active
            ? LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                colors.accentMuted,
                colors.accentMuted.withValues(alpha: 0),
              ],
            )
            : null;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 1,
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: context.motion.fast,
            curve: context.motion.standard,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm + 1,
            ),
            decoration: BoxDecoration(
              color: background,
              gradient: backgroundGradient,
              borderRadius: AppRadii.mdAll,
            ),
            child: Row(
              children: [
                Icon(widget.icon, size: 17, color: foreground),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    widget.label,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.label.copyWith(
                      color: foreground,
                      fontWeight:
                          widget.active ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (widget.badge != null)
                  Text(
                    widget.badge!,
                    style: context.text.caption.copyWith(
                      color: widget.badgeColor ?? colors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

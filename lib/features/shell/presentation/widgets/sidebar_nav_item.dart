import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';

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
        widget.active || _hovered ? colors.textPrimary : colors.textSecondary;

    // Neutral, never accent-coloured. The rail sits on whatever colour the
    // module is, and a blue wash on a green page is a mistake with extra
    // steps — the selected row is a lighter patch of the module's own colour.
    final background =
        widget.active
            ? colors.surfaceHover
            : (_hovered ? colors.surface : Colors.transparent);

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

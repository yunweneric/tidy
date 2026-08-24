import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/features/settings/domain/settings_section.dart';

/// The Settings page's own tab column.
///
/// Deliberately quieter than the app's nav rail two hundred pixels to its
/// left: no gradient panel, no border, just pills on the page. Two rails that
/// looked alike would read as one confused navigation.
class SettingsRail extends StatelessWidget {
  const SettingsRail({
    super.key,
    required this.current,
    required this.onSelect,
  });

  static const double width = 176;

  final SettingsSection current;
  final ValueChanged<SettingsSection> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final section in SettingsSection.values)
            _RailItem(
              section: section,
              active: section == current,
              onTap: () => onSelect(section),
            ),
        ],
      ),
    );
  }
}

class _RailItem extends StatefulWidget {
  const _RailItem({
    required this.section,
    required this.active,
    required this.onTap,
  });

  final SettingsSection section;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final foreground =
        widget.active || _hovered ? colors.textPrimary : colors.textSecondary;

    // Same neutral treatment as the app rail: the selected row is a lighter
    // patch of the page's own colour, never an accent wash.
    final background =
        widget.active
            ? colors.surfaceHover
            : (_hovered ? colors.surface : Colors.transparent);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
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
                Icon(widget.section.icon, size: 16, color: foreground),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    widget.section.label,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.label.copyWith(
                      color: foreground,
                      fontWeight:
                          widget.active ? FontWeight.w600 : FontWeight.w500,
                    ),
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

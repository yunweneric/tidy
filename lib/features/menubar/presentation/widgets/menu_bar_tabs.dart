import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/features/menubar/domain/menu_bar_surface.dart';

/// The consolidated layout's section switcher.
///
/// Not `SegmentedTabs` from `core/widgets/`. That one is sized for a window —
/// a 36pt-tall track with `label` type in it — and in a 460pt popover next to
/// 11pt captions it reads as a control borrowed from somewhere else. This is
/// the pill the process sort toggle already uses two hundred lines below,
/// widened to fit an icon.
class MenuBarTabs extends StatelessWidget {
  const MenuBarTabs({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final MenuBarSurface selected;
  final ValueChanged<MenuBarSurface> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          for (final surface in MenuBarSurface.values)
            Expanded(
              child: _Tab(
                surface: surface,
                selected: surface == selected,
                onTap: () => onChanged(surface),
              ),
            ),
        ],
      ),
    );
  }
}

class _Tab extends StatefulWidget {
  const _Tab({
    required this.surface,
    required this.selected,
    required this.onTap,
  });

  final MenuBarSurface surface;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final selected = widget.selected;

    final background =
        selected
            ? colors.surfaceRaised
            : _hovered
            ? colors.surfaceHover
            : Colors.transparent;
    final ink = selected ? colors.textPrimary : colors.textMuted;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: context.motion.fast,
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          decoration: BoxDecoration(
            color: background,
            borderRadius: AppRadii.smAll,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.surface.icon, size: 13, color: ink),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  widget.surface.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.caption.copyWith(
                    color: ink,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

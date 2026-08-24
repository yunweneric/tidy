import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';

/// A macOS-style segmented control.
///
/// A recessed track with one raised segment, rather than a filled accent tab.
/// At this size a saturated block reads as a call to action, and a filter is
/// not one — the emphasis belongs on the primary button next to it.
class SegmentedTabs extends StatelessWidget {
  const SegmentedTabs({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
    this.counts = const <int?>[],
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  /// Optional per-segment count, shown after the label. A null entry means
  /// that segment has no meaningful count — a "0" there reads as "none found",
  /// which is a different and usually wrong statement.
  final List<int?> counts;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: AppRadii.mdAll,
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < labels.length; i++)
            _Segment(
              label: labels[i],
              count: i < counts.length ? counts[i] : null,
              active: i == selectedIndex,
              onTap: () => onChanged(i),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatefulWidget {
  const _Segment({
    required this.label,
    required this.active,
    required this.onTap,
    this.count,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final int? count;

  @override
  State<_Segment> createState() => _SegmentState();
}

class _SegmentState extends State<_Segment> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final foreground =
        widget.active
            ? colors.textPrimary
            : (_hovered ? colors.textPrimary : colors.textSecondary);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: context.motion.fast,
          curve: context.motion.standard,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color:
                widget.active
                    ? colors.surface
                    : (_hovered ? colors.surfaceHover : Colors.transparent),
            borderRadius: AppRadii.smAll,
            border: Border.all(
              color: widget.active ? colors.border : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                style: context.text.label.copyWith(
                  color: foreground,
                  fontWeight: widget.active ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              if (widget.count != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '${widget.count}',
                  style: context.text.caption.copyWith(
                    color: widget.active ? colors.accent : colors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

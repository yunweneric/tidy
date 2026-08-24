import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';
import 'package:mac_uninstaller/features/clipboard/data/models/clipboard_entry.dart';

/// One recent clip in the popover.
///
/// Deliberately thinner than the row on the Clipboard page: the popover is a
/// glance and a click, so this is the preview, where it came from, and nothing
/// else. Everything the page offers — pinning, removing, the full text — is a
/// click away through "Open".
class MenuBarClipRow extends StatefulWidget {
  const MenuBarClipRow({
    super.key,
    required this.entry,
    required this.onCopy,
    this.onHover,
  });

  final ClipboardEntry entry;
  final VoidCallback onCopy;

  /// Called with this row's distance from the top of the panel when the
  /// pointer enters it, and with null when it leaves. The whole content is
  /// previewed in a native window beside the panel, which needs to know which
  /// row to line up with.
  final ValueChanged<double?>? onHover;

  @override
  State<MenuBarClipRow> createState() => _MenuBarClipRowState();
}

class _MenuBarClipRowState extends State<MenuBarClipRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final entry = widget.entry;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() => _hovered = true);
        _reportHover();
      },
      onExit: (_) {
        setState(() => _hovered = false);
        widget.onHover?.call(null);
      },
      child: GestureDetector(
        onTap: entry.isEmptied ? null : widget.onCopy,
        child: AnimatedContainer(
          duration: context.motion.fast,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md + 2,
            vertical: AppSpacing.sm,
          ),
          color: _hovered ? colors.surfaceHover : Colors.transparent,
          child: Row(
            children: [
              Icon(
                entry.sensitive ? AppIcons.locked : entry.kind.icon,
                size: 15,
                color: entry.sensitive ? colors.review : colors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: _preview(context)),
              const SizedBox(width: AppSpacing.sm),
              // The affordance only when the pointer is on the row: four
              // "Copy" labels stacked down a popover reads as a toolbar.
              if (_hovered && !entry.isEmptied)
                Icon(AppIcons.copy, size: 14, color: colors.accent)
              else
                Text(
                  entry.pinned ? 'Pinned' : (entry.sourceAppName ?? ''),
                  style: context.text.caption,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Where this row sits inside the panel, in points from its top.
  void _reportHover() {
    final onHover = widget.onHover;
    if (onHover == null) return;

    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    // Against the root, which is the Flutter view — and the Flutter view fills
    // the popover, so its coordinates are the popover's.
    onHover(box.localToGlobal(Offset.zero).dy);
  }

  Widget _preview(BuildContext context) {
    final entry = widget.entry;
    final text = Text(
      entry.preview,
      style: entry.prefersMono ? context.text.mono : context.text.bodyM,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    // The guard applies here too. A popover is the most likely place for
    // someone else to be looking over a shoulder.
    if (!entry.sensitive) return text;
    return ClipRect(
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: text,
      ),
    );
  }
}

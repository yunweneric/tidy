import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';
import 'package:mac_uninstaller/core/utils/byte_format.dart';
import 'package:mac_uninstaller/core/utils/home_dir.dart';
import 'package:mac_uninstaller/features/recycle_bin/data/models/trash_item.dart';

/// Column geometry, shared by the header and every row.
///
/// One spec used by both, for the reason `AppTableLayout` exists: a header that
/// declares its own flex values ends up with labels that do not sit above their
/// data.
@immutable
class TrashTableLayout {
  const TrashTableLayout._();

  static const double checkbox = 40;
  static const double actions = 108;

  /// Fixed: dates and sizes are short and predictable, and letting them flex
  /// shifts the columns every time the list is filtered.
  static const double deleted = 120;
  static const double size = 96;

  static const int itemFlex = 4;
  static const int originFlex = 3;

  static const double rowHeight = 54;
  static const EdgeInsets rowPadding = EdgeInsets.symmetric(
    horizontal: AppSpacing.xl,
  );
}

/// One selectable row in the bin.
class TrashTableRow extends StatefulWidget {
  const TrashTableRow({
    super.key,
    required this.item,
    required this.selected,
    required this.onSelectionChanged,
    required this.onRestore,
    required this.onReveal,
    required this.onDelete,
    this.enabled = true,
    this.isLast = false,
  });

  final TrashItem item;
  final bool selected;
  final ValueChanged<bool> onSelectionChanged;
  final VoidCallback onRestore;
  final VoidCallback onReveal;
  final VoidCallback onDelete;

  /// False while an action is in flight, so a second click cannot address an
  /// item the first one is halfway through moving.
  final bool enabled;

  /// Suppresses the divider so the table meets its rounded bottom edge cleanly.
  final bool isLast;

  @override
  State<TrashTableRow> createState() => _TrashTableRowState();
}

class _TrashTableRowState extends State<TrashTableRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final item = widget.item;

    final background =
        widget.selected
            ? colors.accentMuted
            : (_hovered ? colors.surfaceHover : Colors.transparent);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => widget.onSelectionChanged(!widget.selected),
        child: AnimatedContainer(
          duration: context.motion.fast,
          height: TrashTableLayout.rowHeight,
          padding: TrashTableLayout.rowPadding,
          decoration: BoxDecoration(
            color: background,
            border:
                widget.isLast
                    ? null
                    : Border(bottom: BorderSide(color: colors.border)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: TrashTableLayout.checkbox,
                child: Checkbox(
                  value: widget.selected,
                  onChanged: (_) => widget.onSelectionChanged(!widget.selected),
                ),
              ),
              Expanded(
                flex: TrashTableLayout.itemFlex,
                child: _identity(context),
              ),
              Expanded(
                flex: TrashTableLayout.originFlex,
                child: _origin(context),
              ),
              SizedBox(
                width: TrashTableLayout.deleted,
                child: Text(
                  _deletedLabel(item),
                  style: context.text.bodyM.copyWith(
                    color:
                        item.deletedAt == null
                            ? colors.textMuted
                            : colors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                width: TrashTableLayout.size,
                child: Text(
                  formatBytes(item.sizeBytes),
                  textAlign: TextAlign.right,
                  style: context.text.bodyM.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(
                width: TrashTableLayout.actions,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _actions(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _identity(BuildContext context) {
    final colors = context.colors;
    final item = widget.item;

    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: colors.surfaceRaised,
            borderRadius: AppRadii.mdAll,
          ),
          child: Icon(_glyph(item.kind), size: 16, color: colors.textSecondary),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.name,
                style: context.text.titleS,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 1),
              Text(
                item.kindLabel.isEmpty
                    ? (item.isDirectory ? 'Folder' : 'File')
                    : item.kindLabel,
                style: context.text.caption,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Where it came from, when anything knows.
  ///
  /// "Tidy does not know" rather than a blank: an empty cell reads as a bug,
  /// and the reason — macOS keeps Finder's put-back index somewhere no other
  /// app can read — is not the user's fault or ours.
  Widget _origin(BuildContext context) {
    final colors = context.colors;
    final origin = widget.item.origin;

    if (origin == null) {
      return Text(
        'Not known',
        style: context.text.bodyM.copyWith(color: colors.textMuted),
        overflow: TextOverflow.ellipsis,
      );
    }

    return Tooltip(
      message: origin.originalPath,
      child: Text(
        collapseHome(origin.originalParent, kHomeDir),
        style: context.text.bodyM,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// Restore and reveal are always available; the permanent delete appears on
  /// hover only, so a table of your own files is not a wall of red.
  Widget _actions(BuildContext context) {
    final colors = context.colors;
    final canPutBack = widget.item.canPutBack;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _IconAction(
          icon: canPutBack ? AppIcons.putBack : AppIcons.restore,
          tooltip:
              canPutBack
                  ? 'Put back where it came from'
                  : 'Restore to a folder you choose…',
          color: colors.textSecondary,
          onPressed: widget.enabled ? widget.onRestore : null,
        ),
        _IconAction(
          icon: AppIcons.revealInFinder,
          tooltip: 'Show in Finder',
          color: colors.textSecondary,
          onPressed: widget.onReveal,
        ),
        if (_hovered)
          _IconAction(
            icon: AppIcons.delete,
            tooltip: 'Delete permanently',
            color: colors.risky,
            onPressed: widget.enabled ? widget.onDelete : null,
          )
        else
          const SizedBox(width: 30),
      ],
    );
  }

  static IconData _glyph(TrashItemKind kind) => switch (kind) {
    TrashItemKind.folder => AppIcons.folder,
    TrashItemKind.app => AppIcons.applications,
    TrashItemKind.image => AppIcons.image,
    TrashItemKind.video => AppIcons.video,
    TrashItemKind.audio => AppIcons.audio,
    TrashItemKind.archive => AppIcons.archive,
    TrashItemKind.document => AppIcons.document,
    TrashItemKind.other => AppIcons.document,
  };

  /// Plain language over a date stamp: how long it has been sitting there is
  /// the thing that helps someone decide, and nobody reads "12/03/2026" as
  /// "long enough to let go of".
  static String _deletedLabel(TrashItem item) {
    final days = item.daysInBin;
    if (days == null) return 'Unknown';
    if (days <= 0) return 'Today';
    if (days == 1) return 'Yesterday';
    if (days < 30) return '$days days ago';
    if (days < 60) return 'Last month';
    if (days < 365) return '${(days / 30).floor()} months ago';
    return days < 730 ? 'Over a year ago' : '${(days / 365).floor()} years ago';
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.color,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 17),
      color: color,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
    );
  }
}

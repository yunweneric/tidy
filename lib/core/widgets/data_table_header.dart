import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';

/// How a column is currently sorted.
enum SortDirection { none, ascending, descending }

/// One column in a [DataTableHeader].
class TableColumn {
  const TableColumn(
    this.label, {
    this.flex = 1,
    this.width,
    this.align = TextAlign.left,
    this.onTap,
    this.sort = SortDirection.none,
  });

  final String label;
  final int flex;

  /// Fixed width. Wins over [flex] — use it for short, predictable values so
  /// the columns stop shifting as the list filters.
  final double? width;

  final TextAlign align;

  /// When set the header becomes clickable and shows a sort caret.
  final VoidCallback? onTap;
  final SortDirection sort;
}

/// Table header row with an optional leading tri-state checkbox.
class DataTableHeader extends StatelessWidget {
  const DataTableHeader({
    super.key,
    required this.columnLabels,
    this.flexValues,
    this.columns,
    this.showSelectAll = false,
    this.onSelectAll,
    this.selectAllValue = false,
    this.trailingWidth = 0,
  });

  /// Simple form: labels only.
  final List<String> columnLabels;
  final List<int>? flexValues;

  /// Rich form: per-column sort state and tap handling. Wins over
  /// [columnLabels] when supplied.
  final List<TableColumn>? columns;

  final bool showSelectAll;
  final ValueChanged<bool?>? onSelectAll;

  /// Tri-state: true = all, false = none, null = some.
  final bool? selectAllValue;

  /// Reserves room for a trailing action column so the header labels line up
  /// with the data rather than drifting right by the width of a button.
  final double trailingWidth;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final resolved = columns ??
        [
          for (var i = 0; i < columnLabels.length; i++)
            TableColumn(
              columnLabels[i],
              flex: flexValues != null && i < flexValues!.length
                  ? flexValues![i]
                  : 1,
            ),
        ];

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          if (showSelectAll)
            SizedBox(
              width: 40,
              child: Checkbox(
                value: selectAllValue,
                tristate: true,
                onChanged: onSelectAll,
              ),
            ),
          for (final column in resolved)
            if (column.width != null)
              SizedBox(
                width: column.width,
                child: _HeaderCell(column: column),
              )
            else
              Expanded(
                flex: column.flex,
                child: _HeaderCell(column: column),
              ),
          if (trailingWidth > 0) SizedBox(width: trailingWidth),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({required this.column});

  final TableColumn column;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final active = column.sort != SortDirection.none;

    final label = Row(
      mainAxisAlignment: column.align == TextAlign.right
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: [
        Flexible(
          child: Text(
            column.label,
            textAlign: column.align,
            overflow: TextOverflow.ellipsis,
            style: context.text.overline.copyWith(
              color: active ? colors.accent : colors.textMuted,
            ),
          ),
        ),
        if (active) ...[
          const SizedBox(width: 2),
          Icon(
            column.sort == SortDirection.ascending
                ? AppIcons.sortAscending
                : AppIcons.sortDescending,
            size: 11,
            color: colors.accent,
          ),
        ],
      ],
    );

    if (column.onTap == null) return label;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: column.onTap, child: label),
    );
  }
}

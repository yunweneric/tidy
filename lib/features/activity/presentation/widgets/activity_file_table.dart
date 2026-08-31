import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/store/models/store_models.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/features/activity/logic/activity_state.dart';
import 'package:tidy/features/activity/presentation/widgets/activity_operation_row.dart';

/// The audit list: every removal in the range, newest first.
///
/// Flat rather than grouped, and searchable, because this is the view for a
/// question about one file — "did Tidy take that, and when" — where the run it
/// belonged to is the answer rather than the way in.
class ActivityFileTable extends StatefulWidget {
  const ActivityFileTable({super.key, required this.state});

  final ActivityState state;

  @override
  State<ActivityFileTable> createState() => _ActivityFileTableState();
}

class _ActivityFileTableState extends State<ActivityFileTable> {
  static const int _pageSize = 50;

  int _page = 1;

  @override
  void didUpdateWidget(ActivityFileTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A filter that leaves fewer pages than the one you are on strands the
    // table on an empty page. Back to the top whenever the list underneath
    // changes shape.
    if (oldWidget.state.visibleItems.length !=
        widget.state.visibleItems.length) {
      _page = 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final items = widget.state.visibleItems;

    if (items.isEmpty) {
      return EmptyState(
        icon: AppIcons.search,
        title: 'Nothing matches',
        message:
            widget.state.query.isEmpty
                ? 'No removals in this category for the range.'
                : 'No removed file matches “${widget.state.query}”.',
      );
    }

    final totalPages = (items.length / _pageSize).ceil();
    final page = _page.clamp(1, totalPages);
    final start = (page - 1) * _pageSize;
    final visible = items.skip(start).take(_pageSize).toList();

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors.surfaceGradient,
        ),
        borderRadius: AppRadii.lgAll,
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DataTableHeader(
            columnLabels: [],
            columns: [
              TableColumn('FILE', flex: 5),
              TableColumn('CATEGORY', width: 110),
              TableColumn('WHAT HAPPENED', width: 96),
              TableColumn('WHEN', width: 104),
              TableColumn('SIZE', width: 84, align: TextAlign.right),
            ],
          ),
          Expanded(
            child: ListView.separated(
              itemCount: visible.length,
              separatorBuilder:
                  (_, _) => Divider(height: 1, color: colors.border),
              itemBuilder:
                  (context, index) =>
                      ActivityFileRow(item: visible[index], showWhen: true),
            ),
          ),
          TableFooter(
            divider: true,
            currentPage: page,
            totalPages: totalPages,
            onPageChanged: (value) => setState(() => _page = value),
            summary: TableSummary(
              count: items.length,
              countNoun: 'removed',
              total: _bytesOf(items),
              totalNoun: 'in total',
            ),
          ),
        ],
      ),
    );
  }

  /// What the filtered list comes to.
  ///
  /// Restored files are left out: they were put back, so counting their bytes
  /// as removed would overstate the total by exactly the amount the user
  /// recovered.
  static String _bytesOf(List<RemovedItemRecord> items) {
    var total = 0;
    for (final item in items) {
      if (!item.restored) total += item.sizeBytes;
    }
    return formatBytes(total);
  }
}

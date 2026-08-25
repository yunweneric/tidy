import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/features/ai_usage/data/models/model_pricing.dart';
import 'package:tidy/features/ai_usage/data/models/usage_totals.dart';

/// Column geometry, declared once and used by both the header and the rows.
///
/// The reason `AppTableLayout` exists over in Applications, for the same
/// reason: a header that declares its own flex values is how a table ends up
/// with labels that do not sit above their data.
@immutable
class UsageTableLayout {
  const UsageTableLayout._();

  static const double replies = 72;
  static const double input = 84;
  static const double output = 84;
  static const double cache = 96;
  static const double cost = 92;
  static const double share = 84;

  /// Everything else is fixed, so the name takes what is left. At the 1100pt
  /// minimum window that is about 280pt, which fits a model id and an elided
  /// project path.
  static const int nameFlex = 1;

  static const double rowHeight = 44;

  /// Matches `DataTableHeader`'s own horizontal padding. Four points out and
  /// the labels stop sitting above their data.
  static const EdgeInsets rowPadding = EdgeInsets.symmetric(
    horizontal: AppSpacing.xl,
  );
}

/// One line of a breakdown — a model, or a project.
class BreakdownRow {
  const BreakdownRow({
    required this.name,
    required this.tokens,
    this.subtitle,
    this.mono = false,
    this.priced = true,
  });

  final String name;
  final String? subtitle;
  final TokenTotals tokens;

  /// Renders the name in the monospace face. On for paths, off for model ids.
  final bool mono;

  /// False when nobody publishes a rate for this row, so the cost cell shows a
  /// dash rather than a zero. A zero would say "this was free".
  final bool priced;

  double get cost {
    final rate = ModelPricing.of(name);
    return rate == null ? 0 : tokens.costAt(rate);
  }
}

/// A model or project breakdown: name, tokens by kind, cost, and a share bar.
class BreakdownTable extends StatelessWidget {
  const BreakdownTable({
    super.key,
    required this.title,
    required this.nameHeading,
    required this.rows,
    this.footer,
  });

  final String title;
  final String nameHeading;
  final List<BreakdownRow> rows;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final biggest =
        rows.isEmpty
            ? 0
            : rows
                .map((row) => row.tokens.total)
                .reduce((a, b) => a > b ? a : b);

    return TidyCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: SectionLabel(label: title, padding: EdgeInsets.zero),
          ),
          DataTableHeader(
            columnLabels: const [],
            columns: [
              TableColumn(nameHeading, flex: UsageTableLayout.nameFlex),
              const TableColumn(
                'Replies',
                width: UsageTableLayout.replies,
                align: TextAlign.right,
              ),
              const TableColumn(
                'Input',
                width: UsageTableLayout.input,
                align: TextAlign.right,
              ),
              const TableColumn(
                'Output',
                width: UsageTableLayout.output,
                align: TextAlign.right,
              ),
              const TableColumn(
                'Cache',
                width: UsageTableLayout.cache,
                align: TextAlign.right,
              ),
              const TableColumn(
                'Cost',
                width: UsageTableLayout.cost,
                align: TextAlign.right,
              ),
              // Right-aligned so its label cannot butt against the
              // right-aligned "Cost" above the previous column.
              const TableColumn(
                'Share',
                width: UsageTableLayout.share,
                align: TextAlign.right,
              ),
            ],
          ),
          for (var i = 0; i < rows.length; i++)
            _Row(
              row: rows[i],
              fraction: biggest == 0 ? 0 : rows[i].tokens.total / biggest,
              isLast: i == rows.length - 1 && footer == null,
            ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: footer,
            ),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Text('Nothing recorded yet.', style: context.text.bodyM),
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.row, required this.fraction, required this.isLast});

  final BreakdownRow row;
  final double fraction;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final tint = ModuleTint.of(context);

    return Container(
      height: UsageTableLayout.rowHeight,
      padding: UsageTableLayout.rowPadding,
      decoration: BoxDecoration(
        border:
            isLast ? null : Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: UsageTableLayout.nameFlex,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.name,
                  style: row.mono ? text.mono : text.titleS,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (row.subtitle case final subtitle?)
                  Text(
                    subtitle,
                    style: text.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          _cell(context, '${row.tokens.messages}', UsageTableLayout.replies),
          _cell(context, formatCount(row.tokens.input), UsageTableLayout.input),
          _cell(
            context,
            formatCount(row.tokens.output),
            UsageTableLayout.output,
          ),
          _cell(
            context,
            formatCount(row.tokens.cacheRead + row.tokens.cacheWrite),
            UsageTableLayout.cache,
          ),
          SizedBox(
            width: UsageTableLayout.cost,
            child: Text(
              row.priced ? formatUsd(row.cost) : '—',
              textAlign: TextAlign.right,
              style:
                  row.priced
                      ? text.bodyM.copyWith(color: colors.textPrimary)
                      : text.bodyM.copyWith(color: colors.textMuted),
            ),
          ),
          SizedBox(
            width: UsageTableLayout.share,
            child: Padding(
              padding: const EdgeInsets.only(left: AppSpacing.md),
              child: SizeBar(
                fraction: fraction,
                color: tint?.accent ?? colors.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, String value, double width) => SizedBox(
    width: width,
    child: Text(value, textAlign: TextAlign.right, style: context.text.bodyM),
  );
}

import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/features/dashboard/logic/dashboard_state.dart';

/// The history charts — the part of the page that needs the store behind it.
class DashboardTrends extends StatelessWidget {
  const DashboardTrends({
    super.key,
    required this.state,
    required this.onRange,
  });

  final DashboardState state;
  final ValueChanged<TrendRange> onRange;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return TidyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // One flex child, not a Flexible beside a Spacer: those split the
              // free width between them, which left the tabs floating near the
              // middle rather than sitting against the right edge.
              Expanded(
                child: Text(
                  'OVER TIME',
                  style: context.text.overline,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SegmentedTabs(
                labels: [for (final r in TrendRange.values) r.label],
                selectedIndex: TrendRange.values.indexOf(state.range),
                onChanged: (index) => onRange(TrendRange.values[index]),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (!state.hasHistory)
            _NoHistoryYet(state: state)
          else ...[
            _ReclaimChart(state: state),
            const SizedBox(height: AppSpacing.xl),
            _FreeSpaceChart(state: state),
          ],
          const SizedBox(height: AppSpacing.md),
          Text(_recordingNote(state), style: context.text.caption),
          if (state.reclaimTotals.trashedBytes > 0) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${formatBytes(state.reclaimTotals.trashedBytes)} of that is in '
              'the Trash, so it is recoverable — and not free until the Trash '
              'is emptied.',
              style: context.text.caption.copyWith(color: colors.review),
            ),
          ],
        ],
      ),
    );
  }

  /// Always says when recording began. Without it a short bar chart looks like
  /// a quiet month rather than a young database.
  static String _recordingNote(DashboardState state) {
    final since = state.recordingSince;
    if (since == null) return 'No history has been recorded yet.';

    final days = DateTime.now().difference(since).inDays;
    final when = switch (days) {
      <= 0 => 'today',
      1 => 'yesterday',
      < 31 => '$days days ago',
      < 365 => '${days ~/ 30} months ago',
      _ => '${(days / 365).toStringAsFixed(1)} years ago',
    };
    return 'Tidy has been keeping records since $when. Periods it was not '
        'running are drawn as gaps, not as zeroes.';
  }
}

class _ReclaimChart extends StatelessWidget {
  const _ReclaimChart({required this.state});

  final DashboardState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final totals = state.reclaimTotals;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Wraps rather than overflows: at the 1100px minimum window, the
        // sidebar and gutters leave this row about 800px, and a title plus two
        // legends plus a total is close enough to that to matter.
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Removed', style: context.text.titleS),
            _Legend(color: colors.safe, label: 'Deleted for good'),
            _Legend(color: colors.review, label: 'Moved to Trash'),
            Text(
              '${formatBytes(totals.deletedBytes)} freed',
              style: context.text.caption.copyWith(color: colors.textPrimary),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        BucketBarChart(
          buckets: [
            for (final bucket in state.reclaimBuckets)
              ChartBucket(
                at: bucket.at,
                // Deleted sits on the axis because it is the figure that
                // actually means space back; trashed stacks above it.
                primary: bucket.deletedBytes.toDouble(),
                secondary: bucket.trashedBytes.toDouble(),
              ),
          ],
          primaryColor: colors.safe,
          secondaryColor: colors.review,
          animationKey: state.range,
          height: 120,
        ),
        const SizedBox(height: AppSpacing.sm),
        _AxisLabels(
          first: state.reclaimBuckets.firstOrNull?.at,
          last: state.reclaimBuckets.lastOrNull?.at,
          middle:
              '${totals.itemCount} items in '
              '${totals.operationCount} clean-ups',
        ),
      ],
    );
  }
}

class _FreeSpaceChart extends StatelessWidget {
  const _FreeSpaceChart({required this.state});

  final DashboardState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final buckets = state.diskFreeBuckets;
    final recorded = buckets.where((b) => b.recorded).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Free space', style: context.text.titleS),
            const Spacer(),
            if (recorded.isNotEmpty)
              Flexible(
                child: Text(
                  'Low as ${formatBytes(recorded.map((b) => b.min).reduce(_min).round())}',
                  style: context.text.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        BucketLineChart(
          buckets: [
            for (final bucket in buckets)
              bucket.recorded
                  ? ChartBucket(at: bucket.at, primary: bucket.average)
                  : ChartBucket.missing(bucket.at),
          ],
          color: colors.info,
          animationKey: state.range,
          height: 110,
        ),
        const SizedBox(height: AppSpacing.sm),
        _AxisLabels(
          first: buckets.firstOrNull?.at,
          last: buckets.lastOrNull?.at,
          middle:
              recorded.isEmpty
                  ? ''
                  : 'Now ${formatBytes(recorded.last.average.round())}',
        ),
      ],
    );
  }

  static double _min(double a, double b) => a < b ? a : b;
}

class _NoHistoryYet extends StatelessWidget {
  const _NoHistoryYet({required this.state});

  final DashboardState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: [
          Icon(AppIcons.analytics, size: 30, color: context.colors.textMuted),
          const SizedBox(height: AppSpacing.md),
          Text('Nothing to plot yet', style: context.text.titleM),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            width: 420,
            child: Text(
              'Tidy started keeping records when you updated it. Clean '
              'something up, and this fills in from there.',
              style: context.text.bodyM,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: AppRadii.pillAll,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(label, style: context.text.caption),
      ],
    );
  }
}

class _AxisLabels extends StatelessWidget {
  const _AxisLabels({this.first, this.last, this.middle = ''});

  final DateTime? first;
  final DateTime? last;
  final String middle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(_label(first), style: context.text.overline),
        const Spacer(),
        Flexible(
          child: Text(
            middle,
            style: context.text.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const Spacer(),
        Text(_label(last), style: context.text.overline),
      ],
    );
  }

  static String _label(DateTime? at) =>
      at == null ? '' : '${at.day} ${_months[at.month - 1]}';

  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
}

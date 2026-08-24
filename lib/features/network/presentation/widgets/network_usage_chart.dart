import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/models/network_series.dart';

/// One range's traffic, as stacked bars.
///
/// **A gap is not a zero.** Tidy records only while it is running, so a period
/// with no bucket is one the app was quit for. Those are drawn as a faint
/// hatched slot rather than a zero-height bar — telling someone they used no
/// data overnight is a claim this feature is in no position to make.
class NetworkUsageChart extends StatelessWidget {
  const NetworkUsageChart({super.key, required this.series});

  final NetworkSeries series;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final slots = _slots();

    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                // Keyed on the range so switching tabs replays the grow-in
                // rather than cross-fading two static charts.
                key: ValueKey(series.range),
                duration: context.motion.hero,
                curve: context.motion.standard,
                builder: (context, progress, _) {
                  return CustomPaint(
                    painter: _BarsPainter(
                      slots: slots,
                      peak: series.peakBytes.toDouble(),
                      progress: progress,
                      downColor: colors.downstream,
                      upColor: colors.upstream,
                      gapColor: colors.border,
                      gridColor: colors.border,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Text(_axisLabel(slots.firstOrNull), style: context.text.overline),
                const Spacer(),
                Text(
                  formatBytes(series.totalBytes),
                  style: context.text.caption,
                ),
                const Spacer(),
                Text(_axisLabel(slots.lastOrNull), style: context.text.overline),
              ],
            ),
          ],
        );
      },
    );
  }

  /// Fills in the periods the store has no row for, so the chart's x axis is
  /// time rather than "however many buckets happened to exist".
  List<_Slot> _slots() {
    if (series.buckets.isEmpty) return const [];

    final step = switch (series.granularity) {
      NetworkGranularity.minute => const Duration(minutes: 1),
      NetworkGranularity.hour => const Duration(hours: 1),
      NetworkGranularity.day => const Duration(days: 1),
      NetworkGranularity.week => const Duration(days: 7),
      // Months are not a fixed length, so they are never synthesised — the
      // store already groups them and a missing month is vanishingly unlikely
      // to matter at that zoom.
      NetworkGranularity.month => null,
    };

    if (step == null) {
      return [
        for (final bucket in series.buckets)
          _Slot(at: bucket.at, bucket: bucket),
      ];
    }

    final byStart = {
      for (final bucket in series.buckets)
        bucket.at.millisecondsSinceEpoch: bucket,
    };

    final slots = <_Slot>[];
    var cursor = series.buckets.first.at;
    final end = series.buckets.last.at;
    // Bounded so a corrupt row with a nonsense date cannot spin here.
    while (!cursor.isAfter(end) && slots.length < 2000) {
      slots.add(
        _Slot(at: cursor, bucket: byStart[cursor.millisecondsSinceEpoch]),
      );
      cursor = cursor.add(step);
    }
    return slots;
  }

  String _axisLabel(_Slot? slot) {
    if (slot == null) return '';
    final at = slot.at;
    return switch (series.granularity) {
      NetworkGranularity.minute ||
      NetworkGranularity.hour =>
        '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}',
      NetworkGranularity.day ||
      NetworkGranularity.week =>
        '${at.day} ${_months[at.month - 1]}',
      NetworkGranularity.month => '${_months[at.month - 1]} ${at.year}',
    };
  }

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

class _Slot {
  const _Slot({required this.at, this.bucket});

  final DateTime at;

  /// Null when nothing was recorded for this period — the app was not running.
  final NetworkBucket? bucket;
}

class _BarsPainter extends CustomPainter {
  const _BarsPainter({
    required this.slots,
    required this.peak,
    required this.progress,
    required this.downColor,
    required this.upColor,
    required this.gapColor,
    required this.gridColor,
  });

  final List<_Slot> slots;
  final double peak;
  final double progress;
  final Color downColor;
  final Color upColor;
  final Color gapColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      Paint()
        ..color = gridColor
        ..strokeWidth = 1,
    );

    if (slots.isEmpty || peak <= 0) return;

    final slotWidth = size.width / slots.length;
    // A hairline of breathing room, but never so much that a year of daily bars
    // disappears into gaps.
    final barWidth = (slotWidth - 2).clamp(1.0, 28.0);
    final radius = Radius.circular(barWidth < 4 ? 0 : 2);

    for (var i = 0; i < slots.length; i++) {
      final left = i * slotWidth + (slotWidth - barWidth) / 2;
      final bucket = slots[i].bucket;

      if (bucket == null) {
        // Not recorded. A faint stub on the baseline: visibly a slot with no
        // answer, rather than a bar of height zero.
        canvas.drawRect(
          Rect.fromLTWH(left, size.height - 2, barWidth, 2),
          Paint()..color = gapColor,
        );
        continue;
      }

      final total = bucket.totalBytes * progress;
      if (total <= 0) continue;

      final height = (total / peak).clamp(0.0, 1.0) * size.height;
      final downHeight = height * (bucket.downBytes / bucket.totalBytes.clamp(1, 1 << 62));
      final upHeight = height - downHeight;

      // Upload stacked on top of download, so the taller half is the one
      // sitting on the axis and the eye reads total height first.
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(left, size.height - height, barWidth, upHeight),
          topLeft: radius,
          topRight: radius,
        ),
        Paint()..color = upColor,
      );
      canvas.drawRect(
        Rect.fromLTWH(left, size.height - downHeight, barWidth, downHeight),
        Paint()..color = downColor,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.progress != progress ||
      old.peak != peak ||
      old.downColor != downColor ||
      old.upColor != upColor ||
      !identical(old.slots, slots);
}

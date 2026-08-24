import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/features/dashboard/logic/dashboard_state.dart';

/// What is on the startup disk, as far as Tidy has actually measured it.
class StorageBreakdown extends StatelessWidget {
  const StorageBreakdown({super.key, required this.state});

  final DashboardState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final disk = state.disk;

    if (disk == null || disk.totalBytes == 0) {
      return TidyCard(
        child: Text('Reading your disk…', style: context.text.bodyM),
      );
    }

    final apps = state.apps.isKnown ? state.apps.totalBytes : 0;
    final junk = state.junkBytes ?? 0;
    final trash = state.trash?.totalBytes ?? 0;

    // Whatever is used but not accounted for by the three things we have
    // measured. Named "Everything else" rather than guessed at: Tidy has not
    // looked at documents, photos or system files, and a chart that labelled
    // this remainder would be inventing a category out of a subtraction.
    final measured = apps + junk + trash;
    final other = (disk.usedBytes - measured).clamp(0, disk.usedBytes);

    final slices =
        [
          BarSlice(label: 'Applications', bytes: apps, color: colors.info),
          BarSlice(label: 'Junk', bytes: junk, color: colors.safe),
          BarSlice(label: 'Trash', bytes: trash, color: colors.review),
          BarSlice(
            label: 'Everything else',
            bytes: other,
            color: colors.textMuted,
          ),
        ].where((slice) => slice.bytes > 0).toList();

    return TidyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('STARTUP DISK', style: context.text.overline),
              const Spacer(),
              Flexible(
                child: Text(
                  '${formatBytes(disk.freeBytes)} free of '
                  '${formatBytes(disk.totalBytes)}',
                  style: context.text.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          StackedBar(slices: slices, total: disk.totalBytes, height: 12),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              for (final slice in slices)
                _LegendDot(
                  color: slice.color,
                  label: slice.label,
                  value: formatBytes(slice.bytes),
                ),
              _LegendDot(
                color: colors.surfaceRaised,
                label: 'Free',
                value: formatBytes(disk.freeBytes),
              ),
            ],
          ),
          if (state.junkBytes == null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'Junk is not included until a scan has run, so “Everything else” '
              'is larger than it will be.',
              style: context.text.caption,
            ),
          ],
          if (state.apps.isKnown && state.apps.largest.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xl),
            Text('LARGEST APPLICATIONS', style: context.text.overline),
            const SizedBox(height: AppSpacing.md),
            for (final app in state.apps.largest)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _AppRow(
                  name: app.name,
                  bytes: app.bytes,
                  fraction:
                      state.apps.largest.first.bytes == 0
                          ? 0
                          : app.bytes / state.apps.largest.first.bytes,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

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
        const SizedBox(width: AppSpacing.xs),
        Text(
          value,
          style: context.text.caption.copyWith(
            color: context.colors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({
    required this.name,
    required this.bytes,
    required this.fraction,
  });

  final String name;
  final int bytes;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 160,
          child: Text(
            name,
            style: context.text.bodyM.copyWith(
              color: context.colors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: SizeBar(
            fraction: fraction.clamp(0.0, 1.0),
            color: context.colors.info,
            height: 5,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        SizedBox(
          width: 72,
          child: Text(
            formatBytes(bytes),
            style: context.text.caption,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

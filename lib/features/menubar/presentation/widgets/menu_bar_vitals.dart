import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/platform/system_bridge.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/widgets/size_bar.dart';
import 'package:tidy/core/widgets/tidy_card.dart';
import 'package:tidy/core/insights/health_insight.dart';
import 'package:tidy/core/vitals/system_vitals.dart';

/// The colour a [VitalLevel] wears, everywhere in the panel.
Color colorForLevel(BuildContext context, VitalLevel level) => switch (level) {
  VitalLevel.good => context.colors.accent,
  VitalLevel.watch => context.colors.review,
  VitalLevel.urgent => context.colors.risky,
};

/// The three numbers worth having in a menu bar: how busy the machine is, how
/// much memory is left, and how much disk is left.
///
/// Three tiles rather than a row of text because the *shape* is the reading —
/// a full bar says "act now" before any of the numbers have been parsed.
class MenuBarVitals extends StatelessWidget {
  const MenuBarVitals({super.key, required this.vitals, required this.disk});

  final SystemVitals vitals;
  final DiskUsage disk;

  @override
  Widget build(BuildContext context) {
    final cpu = vitals.cpuPercent;
    final diskKnown = disk.totalBytes > 0;

    // IntrinsicHeight, not a stretched Row: the panel lives in a scroll view,
    // so its height is unbounded, and stretching into that hands the tiles an
    // infinite constraint and throws in layout. This measures the tallest tile
    // and matches the other two to it.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _VitalTile(
              icon: AppIcons.cpu,
              label: 'CPU',
              value: cpu == null ? '—' : '${cpu.round()}%',
              fraction: vitals.cpuFraction,
              level: levelForFraction(
                vitals.cpuFraction,
                watch: 0.6,
                urgent: 0.85,
              ),
              caption: _cpuCaption(),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _VitalTile(
              icon: AppIcons.memory,
              label: 'Memory',
              value:
                  vitals.isKnown
                      ? '${(vitals.memoryUsedFraction * 100).round()}%'
                      : '—',
              fraction: vitals.memoryUsedFraction,
              // Coloured by pressure, not by how full it looks: macOS runs
              // memory near full on purpose, and the number that hurts is how
              // much of it cannot be handed back.
              level: levelForFraction(
                vitals.pressureFraction,
                watch: 0.70,
                urgent: 0.85,
              ),
              caption: _memoryCaption(),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _VitalTile(
              icon: AppIcons.storage,
              label: 'Disk',
              value: diskKnown ? '${(disk.usedFraction * 100).round()}%' : '—',
              fraction: diskKnown ? disk.usedFraction : 0,
              level: levelForFraction(
                diskKnown ? disk.usedFraction : 0,
                watch: 0.88,
                urgent: 0.95,
              ),
              caption:
                  diskKnown
                      ? '${formatBytes(disk.freeBytes)} free'
                      : 'Reading…',
            ),
          ),
        ],
      ),
    );
  }

  String _cpuCaption() {
    if (vitals.coreCount == 0) return 'Reading…';
    final load = vitals.loadAverage;
    final cores = '${vitals.coreCount} cores';
    return load == null ? cores : '$cores · load ${load.toStringAsFixed(2)}';
  }

  String _memoryCaption() {
    if (!vitals.isKnown) return 'Reading…';
    // Deliberately not "swapping X": macOS keeps swap in use on almost every
    // machine, so leading with it would raise an alarm on a healthy Mac. Heavy
    // swap is the insight card's job, where it is judged against pressure.
    return '${formatBytes(vitals.memoryUsedBytes)} of '
        '${formatBytes(vitals.memoryTotalBytes)}';
  }
}

class _VitalTile extends StatelessWidget {
  const _VitalTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.fraction,
    required this.level,
    required this.caption,
  });

  final IconData icon;
  final String label;
  final String value;
  final double fraction;
  final VitalLevel level;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final color = colorForLevel(context, level);

    return TidyCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md - 2,
      ),
      // Only a tile with something to say wears its colour; three tinted tiles
      // is three tiles with no signal left.
      tint: level == VitalLevel.good ? null : color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: context.colors.textSecondary),
              const SizedBox(width: AppSpacing.xs + 1),
              // Flexible, because a third of the panel is not a fixed width.
              // The popover engine lays this out once before macOS has told it
              // how wide the panel is, and `MEMORY` at 11pt is five points
              // wider than the tile gets in that first pass — which is a
              // console full of overflow before anything is on screen.
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.overline,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs + 2),
          Text(
            value,
            style: context.text.titleM.copyWith(
              color: level == VitalLevel.good ? null : color,
            ),
          ),
          const SizedBox(height: AppSpacing.sm - 1),
          SizeBar(fraction: fraction, color: color, height: 4),
          const SizedBox(height: AppSpacing.xs + 1),
          Text(
            caption,
            style: context.text.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

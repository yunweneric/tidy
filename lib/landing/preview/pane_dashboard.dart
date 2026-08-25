import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/insights/health_score.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/landing/preview/preview_mac.dart';

/// Where the app opens: how the Mac is doing, and what Tidy has done about it.
class PreviewDashboardPane extends StatelessWidget {
  const PreviewDashboardPane({super.key, required this.mac, this.onNavigate});

  final PreviewMac mac;
  final ValueChanged<PreviewScreen>? onNavigate;

  @override
  Widget build(BuildContext context) {
    return ModuleScaffold(
      title: PreviewScreen.dashboard.label,
      subtitle: PreviewScreen.dashboard.blurb,
      actions: [
        OutlineActionButton(
          label: 'Refresh',
          icon: AppIcons.refresh,
          onPressed: () {},
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HealthHero(mac: mac, onNavigate: onNavigate),
          const SizedBox(height: AppSpacing.lg),
          _VitalsRow(mac: mac),
          const SizedBox(height: AppSpacing.xl),
          _Counters(mac: mac, onNavigate: onNavigate),
          const SizedBox(height: AppSpacing.xl),
          _StorageBreakdown(mac: mac),
          const SizedBox(height: AppSpacing.xl),
          _RecentActivity(mac: mac),
        ],
      ),
    );
  }
}

class _HealthHero extends StatelessWidget {
  const _HealthHero({required this.mac, this.onNavigate});

  final PreviewMac mac;
  final ValueChanged<PreviewScreen>? onNavigate;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final score = mac.healthScore;
    final tier = HealthTier.of(score);

    final tone = switch (tier) {
      HealthTier.excellent || HealthTier.good => colors.safe,
      HealthTier.fair => colors.review,
      HealthTier.needsAttention || HealthTier.critical => colors.risky,
    };

    return TidyCard(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Row(
        children: [
          GaugeRing(
            progress: score / 100,
            size: 108,
            strokeWidth: 9,
            gradient: [tone, Color.lerp(tone, colors.accent, 0.45)!],
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$score',
                  style: context.text.displayL.copyWith(height: 1),
                ),
                Text('of 100', style: context.text.caption),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xxl),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tier.label, style: context.text.titleL),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  mac.reclaimableBytes > 0
                      ? '${formatBytes(mac.reclaimableBytes)} of caches, logs '
                          'and saved state is waiting to be cleared.'
                      : 'Nothing is waiting. Everything Tidy checks is clear.',
                  style: context.text.bodyM,
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    GradientButton(
                      label:
                          mac.reclaimableBytes > 0
                              ? 'Clean up ${formatBytes(mac.reclaimableBytes)}'
                              : 'Run Smart Care',
                      icon: AppIcons.cleanup,
                      onPressed: () => onNavigate?.call(PreviewScreen.cleanup),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    // The score is honest about what it could not measure. A
                    // signal that was never read is excluded, not scored as
                    // perfect.
                    Text('From 6 of 8 checks', style: context.text.caption),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VitalsRow extends StatelessWidget {
  const _VitalsRow({required this.mac});

  final PreviewMac mac;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      children: [
        Expanded(
          child: _Vital(
            label: 'CPU',
            value: '31%',
            fraction: 0.31,
            color: colors.info,
            icon: AppIcons.cpu,
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: _Vital(
            label: 'Memory',
            value: '11.2 / 16 GB',
            fraction: 0.70,
            color: colors.review,
            icon: AppIcons.memory,
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: _Vital(
            label: 'Storage',
            value: '${formatBytes(mac.freeBytes)} free',
            fraction: mac.usedFraction,
            color: colors.accent,
            icon: AppIcons.storage,
          ),
        ),
      ],
    );
  }
}

class _Vital extends StatelessWidget {
  const _Vital({
    required this.label,
    required this.value,
    required this.fraction,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final double fraction;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return TidyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: AppSpacing.sm),
              Text(label.toUpperCase(), style: context.text.overline),
              const Spacer(),
              Text(
                value,
                style: context.text.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SizeBar(fraction: fraction, color: color, height: 5),
        ],
      ),
    );
  }
}

class _Counters extends StatelessWidget {
  const _Counters({required this.mac, this.onNavigate});

  final PreviewMac mac;
  final ValueChanged<PreviewScreen>? onNavigate;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // Every tile is a link as well as a number. A dashboard that shows you a
    // problem and then makes you find the screen that fixes it has done half a
    // job.
    final tiles = <Widget>[
      StatTile(
        label: 'Applications',
        value: '${mac.appCount}',
        detail:
            '${formatBytes(mac.appBytes)} · '
            '${mac.unusedAppCount} unused for 6 months',
        icon: AppIcons.applications,
        color: colors.info,
        onTap: () => onNavigate?.call(PreviewScreen.applications),
      ),
      StatTile(
        label: 'Reclaimable junk',
        value: formatBytes(mac.reclaimableBytes),
        detail: 'Caches, logs and saved app state',
        icon: AppIcons.cleanup,
        color: colors.safe,
        onTap: () => onNavigate?.call(PreviewScreen.cleanup),
      ),
      StatTile(
        label: 'In the Trash',
        value: formatBytes(mac.trashBytes),
        detail:
            '${mac.trash.length} items · '
            '${mac.staleTrashCount} older than a month',
        icon: AppIcons.recycleBin,
        color: colors.review,
        onTap: () => onNavigate?.call(PreviewScreen.recycleBin),
      ),
      StatTile(
        label: 'Clipboard',
        value: '${mac.clips.length}',
        detail: '${mac.pinnedClipCount} pinned',
        icon: AppIcons.clipboard,
        color: colors.accent,
        onTap: () => onNavigate?.call(PreviewScreen.clipboard),
      ),
      StatTile(
        label: 'Network today',
        value: formatBytes(mac.todayDownBytes + mac.todayUpBytes),
        detail:
            '${formatBytes(mac.todayDownBytes)} down · '
            '${formatBytes(mac.todayUpBytes)} up',
        icon: AppIcons.network,
        color: colors.downstream,
        onTap: () => onNavigate?.call(PreviewScreen.network),
      ),
    ];

    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.lg),
          Expanded(child: tiles[i]),
        ],
      ],
    );
  }
}

class _StorageBreakdown extends StatelessWidget {
  const _StorageBreakdown({required this.mac});

  final PreviewMac mac;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final series = colors.chartSeries;

    final slices = [
      BarSlice(label: 'Applications', bytes: mac.appBytes, color: series[0]),
      BarSlice(
        label: 'Developer',
        bytes: 64 * 1024 * 1024 * 1024,
        color: series[1],
      ),
      BarSlice(
        label: 'Photos & media',
        bytes: 118 * 1024 * 1024 * 1024,
        color: series[2],
      ),
      BarSlice(
        label: 'Documents',
        bytes: 46 * 1024 * 1024 * 1024,
        color: series[3],
      ),
      BarSlice(
        label: 'Reclaimable',
        bytes: mac.reclaimableBytes,
        color: colors.safe,
      ),
    ];

    return TidyCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('What is on this disk', style: context.text.titleM),
              const Spacer(),
              Text(
                '${formatBytes(mac.usedBytes)} of '
                '${formatBytes(PreviewMac.diskTotalBytes)} used',
                style: context.text.caption,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          StackedBar(
            slices: slices,
            total: PreviewMac.diskTotalBytes,
            height: 14,
            remainderLabel: 'Free',
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.xl,
            runSpacing: AppSpacing.sm,
            children: [
              for (final slice in slices)
                _LegendDot(
                  label: slice.label,
                  value: formatBytes(slice.bytes),
                  color: slice.color,
                ),
              _LegendDot(
                label: 'Free',
                value: formatBytes(mac.freeBytes),
                color: colors.chartOther,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(label, style: context.text.caption),
        const SizedBox(width: AppSpacing.xs + 2),
        Text(
          value,
          style: context.text.caption.copyWith(
            color: context.colors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _RecentActivity extends StatelessWidget {
  const _RecentActivity({required this.mac});

  final PreviewMac mac;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final entries =
        <({String title, String detail, IconData icon, Color tone})>[
          if (mac.reclaimedBytes > 0)
            (
              title: 'Emptied the Trash',
              detail: '${formatBytes(mac.reclaimedBytes)} reclaimed · just now',
              icon: AppIcons.recycleBin,
              tone: colors.safe,
            ),
          (
            title: 'Cleared user caches',
            detail: '4.1 GB moved to Trash · 2 days ago',
            icon: AppIcons.cleanup,
            tone: colors.safe,
          ),
          (
            title: 'Uninstalled Evernote',
            detail: '18 leftovers removed · 5 days ago',
            icon: AppIcons.applications,
            tone: colors.info,
          ),
          (
            title: 'Disabled 2 login items',
            detail: 'Startup ~11s faster · 1 week ago',
            icon: AppIcons.loginItems,
            tone: colors.review,
          ),
        ];

    return TidyCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('What Tidy has done', style: context.text.titleM),
          const SizedBox(height: AppSpacing.lg),
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                StatIconTile(icon: entries[i].icon, color: entries[i].tone),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entries[i].title, style: context.text.titleS),
                      Text(entries[i].detail, style: context.text.caption),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

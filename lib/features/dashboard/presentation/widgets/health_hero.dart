import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/insights/health_score.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/features/dashboard/logic/dashboard_state.dart';

/// The reading at the top of the page: one score, one sentence, one action.
class HealthHero extends StatelessWidget {
  const HealthHero({
    super.key,
    required this.state,
    required this.onAction,
  });

  final DashboardState state;

  /// What the insight's button does. Null when it offers none.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final health = state.health;
    final insight = state.insight;

    return TidyCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _Gauge(health: health),
          const SizedBox(width: AppSpacing.xl),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  health.isKnown ? health.tier.label : 'Reading your Mac…',
                  style: context.text.titleL,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  insight?.headline ??
                      'Gathering what is worth telling you about.',
                  style: context.text.bodyL,
                ),
                if (insight != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(insight.detail, style: context.text.bodyM),
                ],
                const SizedBox(height: AppSpacing.md),
                _Coverage(health: health),
                if (health.dragging.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final signal in health.dragging.take(3))
                        StatusChip(
                          label: signal.detail,
                          color:
                              signal.goodness < 0.35
                                  ? colors.risky
                                  : colors.review,
                        ),
                    ],
                  ),
                ],
                if (insight?.action != null && onAction != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  GradientButton(
                    label: insight!.actionLabel ?? 'Open',
                    onPressed: onAction,
                    size: GradientButtonSize.compact,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Gauge extends StatelessWidget {
  const _Gauge({required this.health});

  final HealthScore health;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final known = health.isKnown;

    return GaugeRing(
      // Indeterminate until at least one check has answered — a ring resting
      // at zero would read as a score of nought rather than as "still looking".
      progress: known ? health.score / 100 : null,
      size: 132,
      strokeWidth: 9,
      gradient: known ? _rampFor(health, colors) : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            known ? '${health.score}' : '—',
            style: context.text.displayL,
          ),
          Text('out of 100', style: context.text.caption),
        ],
      ),
    );
  }

  /// Green through amber to red, from the same status tokens every other
  /// severity in the app uses — so a red ring means what a red chip means.
  static List<Color> _rampFor(HealthScore health, AppColorTokens colors) {
    final color = switch (health.tier) {
      HealthTier.excellent || HealthTier.good => colors.safe,
      HealthTier.fair => colors.review,
      HealthTier.needsAttention || HealthTier.critical => colors.risky,
    };
    return [color, Color.lerp(color, colors.canvas, 0.35)!];
  }
}

/// Says how much of the score is actually measured.
///
/// Without this the number is a confident claim built on however many checks
/// happened to have data — which on a fresh install is five of eight. Saying so
/// is the difference between a score and a guess.
class _Coverage extends StatelessWidget {
  const _Coverage({required this.health});

  final HealthScore health;

  @override
  Widget build(BuildContext context) {
    if (!health.isKnown) {
      return Text(
        'Nothing has answered yet.',
        style: context.text.caption,
      );
    }

    if (health.isComplete) {
      return Text(
        'From all ${health.signalsTotal} checks.',
        style: context.text.caption,
      );
    }

    return Text(
      'From ${health.signalsUsed} of ${health.signalsTotal} checks — '
      'the rest need a scan or a permission Tidy does not have yet.',
      style: context.text.caption,
    );
  }
}

/// The four live meters under the hero.
class VitalsRow extends StatelessWidget {
  const VitalsRow({super.key, required this.state});

  final DashboardState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final vitals = state.vitals;
    final disk = state.disk;

    final cpu = vitals?.cpuPercent;
    final memory = vitals == null || vitals.memoryTotalBytes == 0
        ? null
        : vitals.memoryUsedFraction;
    final diskFraction = disk == null || disk.totalBytes == 0
        ? null
        : disk.usedFraction;

    return Row(
      children: [
        Expanded(
          child: _Meter(
            label: 'CPU',
            fraction: cpu == null ? null : cpu / 100,
            value: cpu == null ? '—' : '${cpu.round()}%',
            detail: vitals == null ? null : '${vitals.coreCount} cores',
            icon: AppIcons.performance,
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: _Meter(
            label: 'Memory',
            fraction: memory,
            value: memory == null ? '—' : '${(memory * 100).round()}%',
            detail: vitals == null
                ? null
                : '${formatBytes(vitals.memoryUsedBytes)} of '
                    '${formatBytes(vitals.memoryTotalBytes)}',
            icon: AppIcons.storage,
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: _Meter(
            label: 'Startup disk',
            fraction: diskFraction,
            value: diskFraction == null
                ? '—'
                : '${(diskFraction * 100).round()}%',
            detail: disk == null ? null : '${formatBytes(disk.freeBytes)} free',
            icon: AppIcons.storage,
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: _Meter(
            label: 'Temperature',
            // A thermal state is a category, not a proportion, so it gets no
            // bar — a filled meter would invent a scale macOS never reports.
            fraction: null,
            value: vitals?.thermal.label ?? '—',
            detail: vitals == null ? null : 'Up ${vitals.uptimeLabel}',
            icon: AppIcons.activity,
            tone: vitals == null
                ? null
                : (vitals.thermal.isNotable ? colors.review : colors.safe),
          ),
        ),
      ],
    );
  }
}

class _Meter extends StatelessWidget {
  const _Meter({
    required this.label,
    required this.value,
    required this.icon,
    this.fraction,
    this.detail,
    this.tone,
  });

  final String label;
  final String value;
  final IconData icon;

  /// Null when there is no reading, or when the value is not a proportion.
  final double? fraction;

  final String? detail;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fraction = this.fraction;
    final color = tone ??
        switch (fraction) {
          null => colors.textMuted,
          >= 0.90 => colors.risky,
          >= 0.75 => colors.review,
          _ => colors.safe,
        };

    return TidyCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: colors.textMuted),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: Text(label, style: context.text.overline)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            style: context.text.titleM.copyWith(color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (fraction != null) ...[
            const SizedBox(height: AppSpacing.sm),
            SizeBar(fraction: fraction, color: color, height: 4),
          ],
          if (detail != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              detail!,
              style: context.text.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

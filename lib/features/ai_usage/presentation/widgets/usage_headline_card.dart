import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/features/ai_usage/data/models/ai_usage_report.dart';
import 'package:tidy/features/ai_usage/data/models/usage_totals.dart';
import 'package:tidy/features/ai_usage/data/models/usage_window.dart';
import 'package:tidy/features/ai_usage/logic/ai_usage_bloc.dart';
import 'package:tidy/features/ai_usage/presentation/widgets/animated_count.dart';
import 'package:tidy/features/ai_usage/presentation/widgets/usage_note.dart';

/// Today, the block you are in, and — for Codex only — a real plan limit.
///
/// The two right-hand panels look alike and mean different things, which is the
/// whole reason they are labelled as carefully as they are. The block is
/// **inferred** from where activity clusters, because Claude Code writes no
/// limit into its logs; Codex's bar is **read**, because Codex writes its own
/// `used_percent` and reset time down. One gets a time bar, the other gets a
/// usage bar, and neither is allowed to look like the other.
class UsageHeadlineCard extends StatelessWidget {
  const UsageHeadlineCard({super.key, required this.state});

  final AiUsageState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final today = state.report.today;

    return TidyCard(
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 5, child: _Today(state: state, today: today)),
            const SizedBox(width: AppSpacing.xl),
            VerticalDivider(width: 1, thickness: 1, color: colors.border),
            const SizedBox(width: AppSpacing.xl),
            Expanded(
              flex: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _BlockPanel(block: state.currentBlock),
                  const SizedBox(height: AppSpacing.lg),
                  _CodexPanel(limit: state.liveCodexLimit),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Today extends StatelessWidget {
  const _Today({required this.state, required this.today});

  final AiUsageState state;
  final DayUsage? today;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final tokens = today?.tokens ?? TokenTotals.empty;
    final cost = today?.cost ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('TODAY', style: text.overline.copyWith(color: colors.textMuted)),
        const SizedBox(height: AppSpacing.sm),
        AnimatedCount(count: tokens.total),
        const SizedBox(height: AppSpacing.xxs),
        Text('tokens', style: text.bodyM),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Text(
              formatUsd(cost),
              style: text.titleM.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                'at API rates',
                style: text.bodyS.copyWith(color: colors.textMuted),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          today == null
              ? 'Nothing yet today.'
              : '${tokens.messages} replies across '
                  '${today!.sessions} ${today!.sessions == 1 ? "session" : "sessions"}',
          style: text.bodyS.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

class _BlockPanel extends StatelessWidget {
  const _BlockPanel({required this.block});

  final UsageBlock? block;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final tint = ModuleTint.of(context);
    final accent = tint?.accent ?? colors.accent;

    if (block == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CURRENT SESSION BLOCK',
            style: text.overline.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('Not in one right now.', style: text.bodyM),
          const UsageNote(
            'A block opens at the top of the hour you start work and runs for '
            'five. This is worked out from when the replies landed — neither '
            'CLI writes its own limit down.',
          ),
        ],
      );
    }

    final now = DateTime.now();
    final elapsed = now.difference(block!.startsAt);
    final fraction = (elapsed.inSeconds / kBlockLength.inSeconds).clamp(
      0.0,
      1.0,
    );
    final left = block!.remainingAt(now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'CURRENT SESSION BLOCK',
              style: text.overline.copyWith(color: colors.textMuted),
            ),
            const Spacer(),
            Text(
              '${_clock(block!.startsAt)} – ${_clock(block!.endsAt)}',
              style: text.caption.copyWith(color: colors.textMuted),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              formatCount(block!.tokens.total),
              style: text.displayL.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text('tokens', style: text.bodyM),
            const Spacer(),
            Text(formatUsd(block!.cost), style: text.titleS),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        // A *time* bar, not a usage bar. It says how far into the five hours
        // you are, which is a fact; how far into an allowance you are is not
        // one this Mac holds.
        SizeBar(fraction: fraction, color: accent, height: 6),
        const SizedBox(height: AppSpacing.xs),
        Text(
          left == Duration.zero
              ? 'This block has closed.'
              : '${_span(left)} left in the block',
          style: text.caption.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

class _CodexPanel extends StatelessWidget {
  const _CodexPanel({required this.limit});

  final ProviderRateLimit? limit;

  @override
  Widget build(BuildContext context) {
    if (limit == null) return const SizedBox.shrink();

    final colors = context.colors;
    final text = context.text;
    final used = (limit!.usedPercent / 100).clamp(0.0, 1.0);
    final tone = switch (limit!.usedPercent) {
      >= 90 => colors.risky,
      >= 70 => colors.review,
      _ => colors.safe,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'CODEX ${_window(limit!.window)} LIMIT',
              style: text.overline.copyWith(color: colors.textMuted),
            ),
            const Spacer(),
            if (limit!.planType case final plan?)
              Text(
                plan.toUpperCase(),
                style: text.caption.copyWith(color: colors.textMuted),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Text(
              '${limit!.usedPercent.toStringAsFixed(0)}%',
              style: text.titleM.copyWith(color: tone),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: SizeBar(fraction: used, color: tone, height: 6)),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Codex reports this itself. Resets ${_when(limit!.resetsAt)}.',
          style: text.caption.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

String _clock(DateTime at) =>
    '${at.hour.toString().padLeft(2, '0')}:'
    '${at.minute.toString().padLeft(2, '0')}';

String _span(Duration left) {
  final hours = left.inHours;
  final minutes = left.inMinutes % 60;
  if (hours == 0) return '${minutes}m';
  return '${hours}h ${minutes}m';
}

String _window(Duration window) {
  if (window.inDays >= 1) return '${window.inDays}-DAY';
  return '${window.inHours}-HOUR';
}

String _when(DateTime at) {
  final now = DateTime.now();
  final days =
      DateTime(
        at.year,
        at.month,
        at.day,
      ).difference(DateTime(now.year, now.month, now.day)).inDays;
  final clock = _clock(at);
  return switch (days) {
    0 => 'today at $clock',
    1 => 'tomorrow at $clock',
    _ => 'in $days days, at $clock',
  };
}

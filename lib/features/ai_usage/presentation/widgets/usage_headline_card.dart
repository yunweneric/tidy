import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/utils/duration_format.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/features/ai_usage/data/models/ai_provider.dart';
import 'package:tidy/features/ai_usage/data/models/ai_usage_report.dart';
import 'package:tidy/features/ai_usage/data/models/ai_usage_summary.dart';
import 'package:tidy/features/ai_usage/data/models/claude_plan_usage.dart';
import 'package:tidy/features/ai_usage/data/models/usage_totals.dart';
import 'package:tidy/features/ai_usage/logic/ai_usage_bloc.dart';
import 'package:tidy/features/ai_usage/presentation/widgets/animated_count.dart';
import 'package:tidy/features/ai_usage/presentation/widgets/usage_note.dart';
import 'package:tidy/features/shell/domain/app_destination.dart';

/// Today on the left, and every limit window on the right.
///
/// The right-hand column draws the same [AiUsageWindow] rows the menu bar
/// popover draws, from the same builder — the page used to assemble its own
/// version and ended up showing a session block and nothing else, so the one
/// window people actually run out of, the week, was visible in the popover and
/// missing here.
///
/// Rows are not interchangeable and are not allowed to look it. A **measured**
/// row draws the provider's own percentage; an **inferred** row draws how far
/// through the window the clock is, because that is all this Mac can prove. The
/// row says which it is in its own footnote rather than leaving the bar to
/// imply it.
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
            Expanded(flex: 6, child: _WindowsPanel(state: state)),
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

/// Every window with a bar, in the popover's order: session before week,
/// Claude before Codex.
class _WindowsPanel extends StatelessWidget {
  const _WindowsPanel({required this.state});

  final AiUsageState state;

  @override
  Widget build(BuildContext context) {
    final windows = state.windows;

    // Nothing has been used inside any window worth drawing. An empty column
    // rather than a row of zeroes: a 0% bar is a claim about an allowance, and
    // there is no allowance in play.
    if (windows.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'LIMIT WINDOWS',
            style: context.text.overline.copyWith(
              color: context.colors.textMuted,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('Nothing in flight right now.', style: context.text.bodyM),
        ],
      );
    }

    // Claude's weekly row carries no percentage until the plan reading is
    // switched on, and a bare token count next to two bars reads as a bar that
    // failed to draw. Say what would fill it instead — and say which nothing
    // it is, which is what the status carries.
    final promptForClaude =
        state.claudePlan?.week == null &&
        windows.any((w) => w.provider == AiProvider.claudeCode);

    // Per-model weeks are unbounded — the API adds and removes metered models
    // whenever it likes — and this column sits inside an IntrinsicHeight row
    // beside a fixed block of text. Four is enough for every shape seen so far
    // and keeps the card from growing taller than the chart below it.
    final shown = _capped(windows);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final (index, window) in shown.indexed) ...[
          if (index > 0) const SizedBox(height: AppSpacing.lg),
          _WindowRow(window: window),
        ],
        if (shown.length < windows.length) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            '+${windows.length - shown.length} more in the menu bar',
            style: context.text.caption.copyWith(
              color: context.colors.textMuted,
            ),
          ),
        ],
        if (promptForClaude)
          _ClaudeLimitsPrompt(status: state.report.claudePlanStatus),
      ],
    );
  }

  /// Keeps every unscoped window and trims the per-model tail, because the
  /// session and the week are the two anybody opened the page for.
  static List<AiUsageWindow> _capped(List<AiUsageWindow> windows) {
    const limit = 4;
    if (windows.length <= limit) return windows;

    final primary = [
      for (final w in windows)
        if (!w.label.contains('·')) w,
    ];
    if (primary.length >= limit) return primary.take(limit).toList();

    return [
      ...primary,
      ...windows
          .where((w) => w.label.contains('·'))
          .take(limit - primary.length),
    ];
  }
}

/// One window: what it is called, what has gone through it, and a bar.
class _WindowRow extends StatelessWidget {
  const _WindowRow({required this.window});

  final AiUsageWindow window;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final tint = ModuleTint.of(context);
    final now = DateTime.now();
    final percent = window.usedPercent;
    final fraction = window.fraction;

    // Measured rows are colour-coded by how much is left, because there is a
    // "left" to speak of. An inferred row wears the module's own accent: it is
    // a clock, and a clock at 90% is not a warning about anything.
    final tone =
        percent == null
            ? (tint?.accent ?? colors.accent)
            : _toneFor(context, percent);

    final left = window.remainingAt(now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                _title(window),
                overflow: TextOverflow.ellipsis,
                style: text.overline.copyWith(color: colors.textMuted),
              ),
            ),
            const Spacer(),
            if (window.tokens > 0)
              Text(
                '${formatCount(window.tokens)} tokens · '
                '${formatUsd(window.cost)}',
                style: text.caption.copyWith(color: colors.textMuted),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            if (percent != null) ...[
              Text(
                '${percent.toStringAsFixed(0)}%',
                style: text.titleM.copyWith(color: tone),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            Expanded(
              child:
                  fraction == null
                      // No denominator anywhere: a trailing week with no
                      // published allowance. A bar here would have to invent
                      // the number it was a fraction of.
                      ? Text(
                        window.tokens == 0
                            ? 'Nothing yet.'
                            : 'No published allowance to measure against.',
                        style: text.bodyS.copyWith(color: colors.textSecondary),
                      )
                      : SizeBar(fraction: fraction, color: tone, height: 6),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          _footnote(window, left),
          style: text.caption.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }

  static String _title(AiUsageWindow window) {
    final provider = switch (window.provider) {
      AiProvider.claudeCode => 'CLAUDE',
      AiProvider.codex => 'CODEX',
    };
    return '$provider ${window.label.toUpperCase()}';
  }

  /// Where the number came from, and when it goes back to zero. Both matter:
  /// the first is whether to trust the bar, the second is how long to wait.
  static String _footnote(AiUsageWindow window, Duration? left) {
    final source =
        window.isMeasured
            ? 'Reported by the provider.'
            : 'Worked out from when replies landed.';

    if (left == null) {
      return window.isMeasured
          ? '$source Nothing scheduled to reset.'
          : '$source Rolls with the clock.';
    }
    if (left == Duration.zero) return '$source This window has closed.';
    return '$source ${formatCountdown(left)} left.';
  }
}

/// The one switch that turns Claude's bare token counts into real bars.
///
/// A blank space where the weekly percentage should be reads as "you have no
/// weekly limit", which is the opposite of true. Naming the switch is the
/// difference between a missing feature and an unmade choice.
class _ClaudeLimitsPrompt extends StatelessWidget {
  const _ClaudeLimitsPrompt({required this.status});

  final ClaudePlanStatus status;

  @override
  Widget build(BuildContext context) {
    final enabled = status != ClaudePlanStatus.off;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // One sentence per outcome. This used to be a single "sign in or check
        // your connection", which named the wrong cause for anyone who was
        // merely offline and named a fix that does not exist for an account
        // that meters nothing.
        UsageNote(switch (status) {
          ClaudePlanStatus.off =>
            'Your session and weekly allowances live on your Claude account, '
                'not in the logs on this Mac. Turn on Claude plan limits to '
                'draw them as real percentages.',
          ClaudePlanStatus.notSignedIn =>
            'Claude Code is not signed in on this Mac, so there is no account '
                'to read the allowances from. Run `claude` and sign in, and '
                '${Brand.name} will pick them up.',
          ClaudePlanStatus.unreachable =>
            'Could not reach Anthropic for the plan limits. The token counts '
                'below are read locally and are unaffected — ${Brand.name} '
                'tries again on the next refresh.',
          ClaudePlanStatus.rateLimited =>
            'Anthropic is rate-limiting the limits request. ${Brand.name} '
                'backs off and tries again shortly.',
          ClaudePlanStatus.noLimits =>
            'This Claude account has no metered session or weekly allowance — '
                'usually an API or Console account, which is billed rather '
                'than capped. The token counts below still apply.',
          ClaudePlanStatus.ready =>
            'No weekly window published for this account.',
        }),
        if (!enabled)
          TextButton(
            onPressed:
                () => context.go(
                  '${AppDestination.settings.path}?section=aiUsage',
                ),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Open Settings'),
          ),
      ],
    );
  }
}

/// Green until it is worth knowing, amber when it is, red when it is nearly
/// gone. One scale for "how much is left", whoever published the number.
Color _toneFor(BuildContext context, double percent) {
  final colors = context.colors;
  return switch (percent) {
    >= 90 => colors.risky,
    >= 70 => colors.review,
    _ => colors.safe,
  };
}

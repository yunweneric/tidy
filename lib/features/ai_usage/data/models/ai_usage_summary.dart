import 'package:tidy/features/ai_usage/data/models/ai_provider.dart';
import 'package:tidy/features/ai_usage/data/models/ai_usage_report.dart';
import 'package:tidy/features/ai_usage/data/models/claude_plan_usage.dart';
import 'package:tidy/features/ai_usage/data/models/model_pricing.dart';
import 'package:tidy/features/ai_usage/data/models/usage_totals.dart';
import 'package:tidy/features/ai_usage/data/models/usage_window.dart';

/// The small part of an [AiUsageReport] that the menu bar needs.
///
/// A separate type because of who reads it. The popover runs in a second
/// Flutter engine with `includeUi: false`, which has no `AiUsageService` and no
/// `AppSettings` to build one with — and must never run the sweep, which is 16
/// seconds over 1.5 GB on a cold start. The native side has neither Dart nor a
/// parser at all.
///
/// So the main engine computes this, writes it where both can reach it, and
/// pushes it over a channel — the same road the network units already travel,
/// and for the same reason.
class AiUsageSummary {
  const AiUsageSummary({
    required this.generatedAt,
    this.tokensToday = 0,
    this.costToday = 0,
    this.repliesToday = 0,
    this.sessionsToday = 0,
    this.blockStartsAt,
    this.blockTokens = 0,
    this.blockCost = 0,
    this.costLastSevenDays = 0,
    this.topModels = const [],
    this.hasUnpricedModels = false,
    this.windows = const [],
    this.providers = const [],
  });

  /// 3 added `providers`, the per-provider slice the bar's readout scope needs.
  static const int version = 3;

  final DateTime generatedAt;

  final int tokensToday;

  /// USD at published API rates. **Not a bill** — both CLIs run on flat-fee
  /// subscriptions, which the page says out loud and the menu bar says in the
  /// item's tooltip, there being no room for it in the bar itself.
  final double costToday;

  final int repliesToday;
  final int sessionsToday;

  /// When the current five-hour block opened, or null if not inside one.
  ///
  /// Inferred from where activity clusters — neither CLI writes its limit down.
  /// Enough to answer "how much have I got through since I sat down", and not
  /// enough to draw a percentage, which is why the readout's block style is a
  /// *time* bar. See [UsageBlock].
  final DateTime? blockStartsAt;

  final int blockTokens;
  final double blockCost;
  final double costLastSevenDays;

  /// Heaviest first, at most three. Name and tokens only.
  final List<AiUsageSummaryModel> topModels;

  /// Some of the tokens above have no published per-token rate, so the cost is
  /// a floor rather than a total. The panel says which models; the bar cannot,
  /// so it does not pretend otherwise.
  final bool hasUnpricedModels;

  /// The limit windows the popover draws, provider order, session before week.
  ///
  /// Empty when neither CLI has been used inside a window worth drawing, which
  /// the panel renders as nothing rather than as a row of zeroes.
  final List<AiUsageWindow> windows;

  /// One entry per provider whose logs were found, in bar order.
  ///
  /// The bar can be pointed at one provider or at both, and the totals above
  /// are every provider added together — so a scoped readout needs the parts,
  /// not the sum. Native reads these; the panel goes on drawing [windows].
  final List<AiProviderReadout> providers;

  /// What one provider contributes, or null when its logs were not found.
  AiProviderReadout? readoutFor(AiProvider provider) {
    for (final entry in providers) {
      if (entry.provider == provider) return entry;
    }
    return null;
  }

  /// The windows belonging to one provider, in the order they should be drawn.
  List<AiUsageWindow> windowsFor(AiProvider provider) => [
    for (final window in windows)
      if (window.provider == provider) window,
  ];

  /// Providers with at least one window, in enum order.
  List<AiProvider> get providersWithWindows => [
    for (final provider in AiProvider.values)
      if (windows.any((window) => window.provider == provider)) provider,
  ];

  bool get isEmpty => tokensToday == 0 && topModels.isEmpty;

  DateTime? get blockEndsAt => blockStartsAt?.add(kBlockLength);

  /// How far into the current block, 0–1, or null when not inside one.
  double? blockElapsedAt(DateTime now) {
    final start = blockStartsAt;
    if (start == null) return null;
    final elapsed = now.difference(start).inSeconds / kBlockLength.inSeconds;
    return elapsed.clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    // UTC on the wire, with the `Z` that implies. A local `DateTime`'s
    // `toIso8601String` carries no offset at all, and Swift's
    // `ISO8601DateFormatter` rejects a stamp with no zone — which threw the
    // whole summary away and left the menu bar showing a glyph.
    'generated_at': generatedAt.toUtc().toIso8601String(),
    'tokens_today': tokensToday,
    'cost_today': costToday,
    'replies_today': repliesToday,
    'sessions_today': sessionsToday,
    if (blockStartsAt != null)
      'block_starts_at': blockStartsAt!.toUtc().toIso8601String(),
    'block_tokens': blockTokens,
    'block_cost': blockCost,
    'cost_last_seven_days': costLastSevenDays,
    'top_models': [for (final model in topModels) model.toJson()],
    'has_unpriced_models': hasUnpricedModels,
    'windows': [for (final window in windows) window.toJson()],
    'providers': [for (final entry in providers) entry.toJson()],
  };

  static AiUsageSummary? fromJson(Object? raw) {
    if (raw is! Map) return null;
    if (raw['version'] != version) return null;
    // Back to local on the way in: everything downstream formats a clock face
    // with it, and a block that opened at 06:00 must not read as 05:00 because
    // it crossed the boundary as UTC.
    final generatedAt = DateTime.tryParse('${raw['generated_at']}')?.toLocal();
    if (generatedAt == null) return null;

    return AiUsageSummary(
      generatedAt: generatedAt,
      tokensToday: _int(raw['tokens_today']),
      costToday: _double(raw['cost_today']),
      repliesToday: _int(raw['replies_today']),
      sessionsToday: _int(raw['sessions_today']),
      blockStartsAt: DateTime.tryParse('${raw['block_starts_at']}')?.toLocal(),
      blockTokens: _int(raw['block_tokens']),
      blockCost: _double(raw['block_cost']),
      costLastSevenDays: _double(raw['cost_last_seven_days']),
      topModels: [
        if (raw['top_models'] is List)
          for (final model in raw['top_models'] as List)
            if (AiUsageSummaryModel.fromJson(model) case final parsed?) parsed,
      ],
      hasUnpricedModels: raw['has_unpriced_models'] == true,
      windows: [
        if (raw['windows'] is List)
          for (final window in raw['windows'] as List)
            if (AiUsageWindow.fromJson(window) case final parsed?) parsed,
      ],
      providers: [
        if (raw['providers'] is List)
          for (final entry in raw['providers'] as List)
            if (AiProviderReadout.fromJson(entry) case final parsed?) parsed,
      ],
    );
  }
}

/// What one provider contributes to the menu bar's readout.
///
/// Deliberately not a second copy of [AiUsageWindow]: that type is the panel's
/// row, and carries a label and a token count it draws. This is the bar's, and
/// carries only what fits in it — today's figures, and the one share the bar
/// can fill a five-pixel track with.
class AiProviderReadout {
  const AiProviderReadout({
    required this.provider,
    this.tokensToday = 0,
    this.costToday = 0,
    this.usedPercent,
    this.blockStartsAt,
    this.windowMinutes,
  });

  final AiProvider provider;
  final int tokensToday;
  final double costToday;

  /// The provider's own published reading, 0–100, or null where there is none.
  ///
  /// Only Codex writes one. Where it is null the share is the clock's — see
  /// [blockStartsAt] — and the two are not the same claim.
  final double? usedPercent;

  /// When the window the share is measured against opened, for the provider
  /// that publishes no reading of its own.
  ///
  /// Sent as an instant rather than as a fraction because the native side
  /// redraws between publishes: a fraction computed here would be up to a
  /// minute stale every time, and the bar would tick in jumps.
  final DateTime? blockStartsAt;

  /// How long that window runs. Null with [blockStartsAt].
  final int? windowMinutes;

  /// How full this provider's bar would be, or null when there is nothing
  /// honest to fill it with.
  ///
  /// Mirrors `AiProviderReadout.share(at:)` in `AiUsageChannel.swift`, which is
  /// what the menu bar actually draws — the settings preview reads this so it
  /// promises a bar only where the bar will really appear. A published reading
  /// wins; failing that the clock through an open window; failing both there is
  /// no share, and a style that needs one falls back to the cost.
  double? shareAt(DateTime now) {
    final measured = usedPercent;
    if (measured != null) return (measured / 100).clamp(0.0, 1.0);

    final start = blockStartsAt;
    final minutes = windowMinutes;
    if (start == null || minutes == null || minutes <= 0) return null;

    final elapsed =
        now.difference(start).inSeconds / Duration(minutes: minutes).inSeconds;
    return elapsed.clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
    'provider': provider.name,
    'tokens_today': tokensToday,
    'cost_today': costToday,
    if (usedPercent != null) 'used_percent': usedPercent,
    if (blockStartsAt != null)
      'block_starts_at': blockStartsAt!.toUtc().toIso8601String(),
    if (windowMinutes != null) 'window_minutes': windowMinutes,
  };

  static AiProviderReadout? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final provider = AiProvider.tryParse('${raw['provider']}');
    if (provider == null) return null;
    return AiProviderReadout(
      provider: provider,
      tokensToday: _int(raw['tokens_today']),
      costToday: _double(raw['cost_today']),
      usedPercent:
          raw['used_percent'] is num
              ? (raw['used_percent'] as num).toDouble()
              : null,
      blockStartsAt: DateTime.tryParse('${raw['block_starts_at']}')?.toLocal(),
      windowMinutes:
          raw['window_minutes'] is num
              ? (raw['window_minutes'] as num).toInt()
              : null,
    );
  }
}

/// One row of the summary's model breakdown.
class AiUsageSummaryModel {
  const AiUsageSummaryModel({
    required this.model,
    required this.tokens,
    required this.cost,
    required this.priced,
  });

  final String model;
  final int tokens;
  final double cost;

  /// False where nobody publishes a rate. The panel shows a dash rather than a
  /// zero — a zero says the tokens were free, which is a different claim.
  final bool priced;

  Map<String, dynamic> toJson() => {
    'model': model,
    'tokens': tokens,
    'cost': cost,
    'priced': priced,
  };

  static AiUsageSummaryModel? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final model = raw['model'];
    if (model is! String) return null;
    return AiUsageSummaryModel(
      model: model,
      tokens: _int(raw['tokens']),
      cost: _double(raw['cost']),
      priced: raw['priced'] == true,
    );
  }
}

/// One limit window, as the popover draws it.
///
/// Two kinds, and the difference between them is the whole point of the type:
///
///  * **Measured.** Codex writes `used_percent` and a reset time into its own
///    rollout logs, so its row is a real share of a real allowance and gets a
///    percentage.
///  * **Inferred.** Claude Code writes neither. Its five-hour block is
///    reconstructed from where activity clusters, so the row can say how far
///    through the window the clock is and what has gone through it — and must
///    not say what share of an allowance that is, because the allowance is not
///    written down anywhere on this Mac.
///
/// Both draw the same row. Only the measured one draws a percentage, and
/// [isMeasured] is what the panel switches on rather than guessing from nulls.
class AiUsageWindow {
  const AiUsageWindow({
    required this.provider,
    required this.label,
    this.tokens = 0,
    this.cost = 0,
    this.resetsAt,
    this.usedPercent,
    this.elapsed,
  });

  final AiProvider provider;

  /// What the row is called: `Session (5h)`, `Weekly`.
  final String label;

  final int tokens;
  final double cost;

  /// When this window rolls over, or null for a rolling window that never
  /// resets on a clock — a trailing seven days has no reset time, and a row
  /// that invented one would be the most believable kind of wrong.
  final DateTime? resetsAt;

  /// The provider's own reading, 0–100, or null where none is published.
  final double? usedPercent;

  /// How far through the window the clock is, 0–1. Set only where the window
  /// has a known span but no known allowance.
  final double? elapsed;

  bool get isMeasured => usedPercent != null;

  /// What the bar fills to, or null when there is nothing honest to fill it to.
  double? get fraction {
    final percent = usedPercent;
    if (percent != null) return (percent / 100).clamp(0.0, 1.0);
    return elapsed?.clamp(0.0, 1.0);
  }

  /// Time until the reset, or null when there is no reset to count down to.
  /// Zero once the window has rolled over — the caller redraws rather than
  /// showing a negative countdown.
  Duration? remainingAt(DateTime now) {
    final at = resetsAt;
    if (at == null) return null;
    final left = at.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  Map<String, dynamic> toJson() => {
    'provider': provider.name,
    'label': label,
    'tokens': tokens,
    'cost': cost,
    if (resetsAt != null) 'resets_at': resetsAt!.toUtc().toIso8601String(),
    if (usedPercent != null) 'used_percent': usedPercent,
    if (elapsed != null) 'elapsed': elapsed,
  };

  static AiUsageWindow? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final provider = AiProvider.tryParse('${raw['provider']}');
    final label = raw['label'];
    if (provider == null || label is! String) return null;
    return AiUsageWindow(
      provider: provider,
      label: label,
      tokens: _int(raw['tokens']),
      cost: _double(raw['cost']),
      resetsAt: DateTime.tryParse('${raw['resets_at']}')?.toLocal(),
      usedPercent:
          raw['used_percent'] is num
              ? (raw['used_percent'] as num).toDouble()
              : null,
      elapsed:
          raw['elapsed'] is num ? (raw['elapsed'] as num).toDouble() : null,
    );
  }
}

/// The menu bar's slice of a full report.
extension AiUsageReportSummary on AiUsageReport {
  AiUsageSummary summarise({DateTime? now}) {
    final at = now ?? DateTime.now();
    final day = today;
    final block = activeBlock(recentHours, now: at);

    final models = modelBreakdown.take(3).toList();

    return AiUsageSummary(
      generatedAt: at,
      tokensToday: day?.tokens.total ?? 0,
      costToday: day?.cost ?? 0,
      repliesToday: day?.tokens.messages ?? 0,
      sessionsToday: day?.sessions ?? 0,
      blockStartsAt: block?.startsAt,
      blockTokens: block?.tokens.total ?? 0,
      blockCost: block?.cost ?? 0,
      costLastSevenDays: costOverLast(7),
      topModels: [
        for (final entry in models)
          AiUsageSummaryModel(
            model: entry.key,
            tokens: entry.value.total,
            cost: _costOf(entry.key, entry.value),
            priced: ModelPricing.of(entry.key) != null,
          ),
      ],
      hasUnpricedModels: unpricedModels.isNotEmpty,
      windows: _windows(at, block),
      providers: _readouts(at, block),
    );
  }

  /// The per-provider slice the bar's readout scope needs.
  ///
  /// A provider that was not found contributes nothing at all, for the reason
  /// [_windows] gives: zeroes for a CLI that is not installed read as a fact
  /// about how little you used it.
  List<AiProviderReadout> _readouts(DateTime at, UsageBlock? block) {
    final day = today;
    final readouts = <AiProviderReadout>[];

    for (final provider in AiProvider.values) {
      if (!providersFound.contains(provider)) continue;

      // The provider's own reading, and only while it still describes the
      // window we are in — the same test the windows apply. Past its reset it
      // is a percentage of a window that has already rolled over.
      final limit = rateLimits[provider];
      var measured =
          limit != null && !limit.isStaleAt(at) ? limit.usedPercent : null;

      // Claude publishes no limit into its logs, but it does publish one to the
      // account. Where that reading is in hand the bar shows the session share
      // like Codex's, rather than the clock it had to settle for before.
      if (provider == AiProvider.claudeCode) {
        measured ??= claudePlanAt(at)?.session?.utilization;
      }

      // Where nobody publishes a reading, the clock is the only share there is,
      // and the five-hour block is the only window this Mac can reconstruct.
      final inferred = measured == null && provider == AiProvider.claudeCode;

      readouts.add(
        AiProviderReadout(
          provider: provider,
          tokensToday: day?.byProvider[provider]?.total ?? 0,
          costToday: day?.costFor(provider) ?? 0,
          usedPercent: measured,
          blockStartsAt: inferred ? block?.startsAt : null,
          windowMinutes:
              inferred && block != null ? kBlockLength.inMinutes : null,
        ),
      );
    }

    return readouts;
  }

  /// The limit windows, provider order, session before week.
  ///
  /// A provider contributes nothing unless its logs were actually found — a row
  /// of zeroes for a CLI that is not installed reads as "you have used none of
  /// your allowance", which is a claim about an allowance that does not exist.
  List<AiUsageWindow> _windows(DateTime at, UsageBlock? block) {
    final windows = <AiUsageWindow>[];

    if (providersFound.contains(AiProvider.claudeCode)) {
      windows.addAll(_claudeWindows(at, block));
    }

    if (providersFound.contains(AiProvider.codex)) {
      final limit = rateLimits[AiProvider.codex];
      final week = _week(AiProvider.codex, at);
      // Codex's own reading, but only while it still describes the window we
      // are in. Past its reset it is a fact about a window that has rolled
      // over, and the row falls back to the tokens it can still stand behind.
      windows.add(
        limit == null || limit.isStaleAt(at)
            ? week
            : AiUsageWindow(
              provider: AiProvider.codex,
              label: _windowLabel(limit.windowMinutes),
              tokens: week.tokens,
              cost: week.cost,
              resetsAt: limit.resetsAt,
              usedPercent: limit.usedPercent,
            ),
      );
    }

    return windows;
  }

  /// Claude's rows: the session, the week, and any per-model week.
  ///
  /// Two sources, and which one is in play decides what a row is allowed to
  /// claim. When the plan reading is present these are *measured* — the
  /// percentage and the reset are Anthropic's own, so the week finally has a
  /// bar instead of a bare token count. Without it they fall back to what this
  /// Mac can prove on its own: a session row that is a clock, and a week that
  /// is a total. The tokens are local either way; only the denominator is
  /// remote, so a failed fetch costs the bar and never the count.
  List<AiUsageWindow> _claudeWindows(DateTime at, UsageBlock? block) {
    const provider = AiProvider.claudeCode;
    final plan = claudePlanAt(at);
    final week = _week(provider, at);
    final windows = <AiUsageWindow>[];

    final session = plan?.session;
    if (session != null) {
      windows.add(
        AiUsageWindow(
          provider: provider,
          label: 'Session (5h)',
          tokens: block?.tokens.total ?? 0,
          cost: block?.cost ?? 0,
          // The published reset, not the inferred block end. They disagree
          // whenever the block was inferred from a gap in activity, and only
          // one of them is when the allowance actually comes back.
          resetsAt: session.resetsAt ?? block?.endsAt,
          usedPercent: session.utilization,
        ),
      );
    } else if (block != null) {
      // Inferred, and only while inside one. Between blocks there is no window
      // to be a fraction of, so the row is absent rather than empty.
      windows.add(
        AiUsageWindow(
          provider: provider,
          label: 'Session (5h)',
          tokens: block.tokens.total,
          cost: block.cost,
          resetsAt: block.endsAt,
          elapsed:
              at.difference(block.startsAt).inSeconds / kBlockLength.inSeconds,
        ),
      );
    }

    final published = plan?.week;
    windows.add(
      published == null
          ? week
          : AiUsageWindow(
            provider: provider,
            label: 'Weekly',
            tokens: week.tokens,
            cost: week.cost,
            resetsAt: published.resetsAt,
            usedPercent: published.utilization,
          ),
    );

    // Per-model weeks last, and only where they are metered separately. These
    // carry no token count of their own: the logs record which model answered,
    // but the allowance these percentages are drawn against is not the same
    // denominator as the overall week, so pairing them would be arithmetic
    // across two different scales.
    for (final model in plan?.modelWeeks ?? const <ClaudeModelLimit>[]) {
      windows.add(
        AiUsageWindow(
          provider: provider,
          label: 'Weekly · ${model.model}',
          resetsAt: model.window.resetsAt,
          usedPercent: model.window.utilization,
        ),
      );
    }

    return windows;
  }

  /// A trailing seven days for one provider. No reset time: the window rolls
  /// with the clock rather than expiring on it.
  ///
  /// Takes [at] rather than reading the clock itself. Every other path through
  /// `summarise` threads one instant, and this one used to call `DateTime.now()`
  /// three times of its own — so `summarise(now: fixed)` did not actually fix
  /// the clock, and the week could land on a different day from the session
  /// drawn beside it when a sweep straddled midnight.
  AiUsageWindow _week(AiProvider provider, DateTime at) {
    final cutoff = DateTime(
      at.year,
      at.month,
      at.day,
    ).subtract(const Duration(days: 6));

    var tokens = 0;
    var cost = 0.0;
    for (final day in days) {
      if (day.date.isBefore(cutoff)) continue;
      tokens += day.byProvider[provider]?.total ?? 0;
      cost += day.costFor(provider);
    }
    return AiUsageWindow(
      provider: provider,
      label: 'Weekly',
      tokens: tokens,
      cost: cost,
    );
  }
}

/// `10080` is a week, `300` five hours. Anything else is named in hours rather
/// than guessed at, so a window Codex adds later still reads correctly.
String _windowLabel(int minutes) {
  if (minutes >= 10080) return 'Weekly';
  if (minutes >= 1440) return '${minutes ~/ 1440}-day';
  if (minutes == 300) return 'Session (5h)';
  return '${minutes ~/ 60}h window';
}

double _costOf(String model, TokenTotals tokens) {
  final rate = ModelPricing.of(model);
  return rate == null ? 0 : tokens.costAt(rate);
}

int _int(Object? value) => value is num ? value.toInt() : 0;
double _double(Object? value) => value is num ? value.toDouble() : 0;

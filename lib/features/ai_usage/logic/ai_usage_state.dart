import 'package:equatable/equatable.dart';
import 'package:tidy/features/ai_usage/data/models/ai_provider.dart';
import 'package:tidy/features/ai_usage/data/models/ai_usage_report.dart';
import 'package:tidy/features/ai_usage/data/models/ai_usage_summary.dart';
import 'package:tidy/features/ai_usage/data/models/claude_plan_usage.dart';
import 'package:tidy/features/ai_usage/data/models/usage_window.dart';

enum AiUsageStatus { initial, loading, ready }

enum AiUsageTab { overview, analytics }

class AiUsageState extends Equatable {
  const AiUsageState({
    this.status = AiUsageStatus.initial,
    this.report = AiUsageReport.empty,
    this.tab = AiUsageTab.overview,
    this.range = UsageRange.month,
    this.filesDone = 0,
    this.filesTotal = 0,
    this.tickedAt,
    this.windows = const [],
    this.claudePlan,
    this.currentBlock,
    this.liveCodexLimit,
  });

  final AiUsageStatus status;
  final AiUsageReport report;
  final AiUsageTab tab;
  final UsageRange range;

  /// Sweep progress. Both zero before one starts.
  final int filesDone;
  final int filesTotal;

  // ─── Derived, once ───────────────────────────────────────────────────────
  //
  // Everything below is worked out from [report] at [tickedAt] when the state
  // is built, rather than by a getter when the widget draws.
  //
  // They were getters, and getters were the wrong shape twice over. `windows`
  // ran `summarise()`, which folds every day and every recent hour in the
  // report — so a rebuild re-derived a year of logs, and the headline card
  // rebuilds on every emission. And each one called `DateTime.now()` itself,
  // which made the state impure: two equal states could draw differently, and
  // no two rows on the page agreed on what "now" meant. One clock, one pass.

  /// The instant every derived view below was computed at. Null before the
  /// first derivation.
  final DateTime? tickedAt;

  /// The limit windows, exactly as the menu bar's popover draws them — same
  /// builder, so the page and the popover cannot disagree about your session
  /// and your week.
  final List<AiUsageWindow> windows;

  /// Claude's published plan reading, while it still described [tickedAt].
  ///
  /// Null when the setting is off, when Claude Code is not signed in on this
  /// Mac, or when the last fetch did not answer. The panel says which.
  final ClaudePlanUsage? claudePlan;

  /// The five-hour block the user was inside at [tickedAt], if any.
  final UsageBlock? currentBlock;

  /// Codex's own plan reading, but only while it still describes the window we
  /// are in. Once its reset time has passed it is a fact about a window that
  /// has since rolled over, and drawing a bar from it would be inventing a
  /// number rather than reporting one.
  final ProviderRateLimit? liveCodexLimit;

  bool get isLoading => status == AiUsageStatus.loading;
  bool get hasLoaded => status == AiUsageStatus.ready;

  double get progress => filesTotal == 0 ? 0 : filesDone / filesTotal;

  /// Loaded, and there is genuinely nothing in any log.
  bool get hasNothing => hasLoaded && report.isEmpty;

  /// The days the chart draws, oldest first. A null `day` is a date before any
  /// log covers — a gap, not a zero.
  List<({DateTime date, DayUsage? day})> get chartDays {
    final now = tickedAt ?? DateTime.now();
    final to = DateTime(now.year, now.month, now.day);
    return report.span(
      from: to.subtract(Duration(days: range.days - 1)),
      to: to,
    );
  }

  /// The selected range reaches back past the earliest log, so part of the
  /// chart is empty because there is nothing to say rather than because
  /// nothing was used.
  bool get rangeOutrunsLogs {
    final covers = report.coversFrom;
    if (covers == null) return false;
    final now = tickedAt ?? DateTime.now();
    final from = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: range.days - 1));
    return from.isBefore(covers);
  }

  /// Re-derives every view above from [report] at [at].
  ///
  /// The one place `summarise()` is called for the page, so the cost is paid
  /// once per sweep and once per tick rather than once per frame. Pass a
  /// [report] when a sweep has landed; omit it to re-read the clock against
  /// the report already held, which is what the countdown ticker does.
  AiUsageState derive({
    AiUsageReport? report,
    DateTime? at,
    AiUsageStatus? status,
  }) {
    final source = report ?? this.report;
    final now = at ?? DateTime.now();
    final codex = source.rateLimits[AiProvider.codex];

    return AiUsageState(
      status: status ?? this.status,
      report: source,
      tab: tab,
      range: range,
      filesDone: filesDone,
      filesTotal: filesTotal,
      tickedAt: now,
      windows: source.summarise(now: now).windows,
      claudePlan: source.claudePlanAt(now),
      currentBlock: activeBlock(source.recentHours, now: now),
      liveCodexLimit: codex != null && !codex.isStaleAt(now) ? codex : null,
    );
  }

  AiUsageState copyWith({
    AiUsageStatus? status,
    AiUsageTab? tab,
    UsageRange? range,
    int? filesDone,
    int? filesTotal,
  }) => AiUsageState(
    status: status ?? this.status,
    report: report,
    tab: tab ?? this.tab,
    range: range ?? this.range,
    filesDone: filesDone ?? this.filesDone,
    filesTotal: filesTotal ?? this.filesTotal,
    tickedAt: tickedAt,
    windows: windows,
    claudePlan: claudePlan,
    currentBlock: currentBlock,
    liveCodexLimit: liveCodexLimit,
  );

  @override
  List<Object?> get props => [
    status,
    report.scannedAt,
    report.days.length,
    report.tokens.total,
    tab,
    range,
    filesDone,
    filesTotal,
    // The tick is part of identity, or a countdown that has moved on by a
    // minute is equal to the one before it and never redraws.
    tickedAt,
  ];
}

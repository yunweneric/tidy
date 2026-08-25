import 'package:equatable/equatable.dart';
import 'package:tidy/features/ai_usage/data/models/ai_provider.dart';
import 'package:tidy/features/ai_usage/data/models/ai_usage_report.dart';
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
  });

  final AiUsageStatus status;
  final AiUsageReport report;
  final AiUsageTab tab;
  final UsageRange range;

  /// Sweep progress. Both zero before one starts.
  final int filesDone;
  final int filesTotal;

  bool get isLoading => status == AiUsageStatus.loading;
  bool get hasLoaded => status == AiUsageStatus.ready;

  double get progress => filesTotal == 0 ? 0 : filesDone / filesTotal;

  /// Loaded, and there is genuinely nothing in any log.
  bool get hasNothing => hasLoaded && report.isEmpty;

  /// The block the user is inside right now, if any.
  UsageBlock? get currentBlock => activeBlock(report.recentHours);

  /// Codex's own plan reading, but only while it still describes the window we
  /// are in. Once its reset time has passed it is a fact about a window that
  /// has since rolled over, and drawing a bar from it would be inventing a
  /// number rather than reporting one.
  ProviderRateLimit? get liveCodexLimit {
    final limit = report.rateLimits[AiProvider.codex];
    if (limit == null || limit.isStaleAt(DateTime.now())) return null;
    return limit;
  }

  /// The days the chart draws, oldest first. A null `day` is a date before any
  /// log covers — a gap, not a zero.
  List<({DateTime date, DayUsage? day})> get chartDays {
    final now = DateTime.now();
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
    final now = DateTime.now();
    final from = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: range.days - 1));
    return from.isBefore(covers);
  }

  AiUsageState copyWith({
    AiUsageStatus? status,
    AiUsageReport? report,
    AiUsageTab? tab,
    UsageRange? range,
    int? filesDone,
    int? filesTotal,
  }) => AiUsageState(
    status: status ?? this.status,
    report: report ?? this.report,
    tab: tab ?? this.tab,
    range: range ?? this.range,
    filesDone: filesDone ?? this.filesDone,
    filesTotal: filesTotal ?? this.filesTotal,
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
  ];
}

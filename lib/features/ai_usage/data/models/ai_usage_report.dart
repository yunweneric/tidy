import 'package:tidy/features/ai_usage/data/models/ai_provider.dart';
import 'package:tidy/features/ai_usage/data/models/claude_plan_usage.dart';
import 'package:tidy/features/ai_usage/data/models/model_pricing.dart';
import 'package:tidy/features/ai_usage/data/models/usage_totals.dart';

/// One day's usage, split every way the page needs to slice it.
class DayUsage {
  const DayUsage({
    required this.date,
    this.byModel = const {},
    this.byProvider = const {},
    this.byProject = const {},
    this.sessions = 0,
  });

  /// Local midnight.
  final DateTime date;

  /// Normalised model id → tokens.
  final Map<String, TokenTotals> byModel;
  final Map<AiProvider, TokenTotals> byProvider;

  /// Absolute working-directory path → tokens.
  final Map<String, TokenTotals> byProject;

  final int sessions;

  TokenTotals get tokens =>
      byModel.values.fold(TokenTotals.empty, (sum, t) => sum + t);

  /// USD at published rates, counting only models that have one.
  double get cost => costOf(byModel);

  /// USD for one provider's share of the day.
  double costFor(AiProvider provider) => costOf({
    for (final entry in byModel.entries)
      if (_providerOf(entry.key) == provider) entry.key: entry.value,
  });

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'by_model': byModel.map((k, v) => MapEntry(k, v.toJson())),
    'by_provider': byProvider.map((k, v) => MapEntry(k.name, v.toJson())),
    'by_project': byProject.map((k, v) => MapEntry(k, v.toJson())),
    'sessions': sessions,
  };

  factory DayUsage.fromJson(Map<dynamic, dynamic> json) => DayUsage(
    date: DateTime.parse(json['date'] as String),
    byModel: _totalsMap(json['by_model']),
    byProvider: {
      for (final entry in _totalsMap(json['by_provider']).entries)
        if (AiProvider.tryParse(entry.key) case final provider?)
          provider: entry.value,
    },
    byProject: _totalsMap(json['by_project']),
    sessions: json['sessions'] as int? ?? 0,
  );
}

/// One hour's usage, kept only for the recent window the 5-hour block needs.
class HourUsage {
  const HourUsage({
    required this.at,
    this.tokens = TokenTotals.empty,
    this.cost = 0,
  });

  /// Local top of the hour.
  final DateTime at;
  final TokenTotals tokens;
  final double cost;

  Map<String, dynamic> toJson() => {
    'at': at.toIso8601String(),
    'tokens': tokens.toJson(),
    'cost': cost,
  };

  factory HourUsage.fromJson(Map<dynamic, dynamic> json) => HourUsage(
    at: DateTime.parse(json['at'] as String),
    tokens: TokenTotals.fromJson(json['tokens'] as Map),
    cost: (json['cost'] as num?)?.toDouble() ?? 0,
  );
}

/// Codex's own reading of the user's plan window.
///
/// The one piece of authoritative limit data either CLI writes down. Claude
/// Code records no limit at all, so the Claude side of the page shows totals
/// and no percentage — a bar needs a denominator, and inferring one would be
/// the same class of lie as a scanner reporting "0 threats found".
class ProviderRateLimit {
  const ProviderRateLimit({
    required this.usedPercent,
    required this.windowMinutes,
    required this.resetsAt,
    required this.observedAt,
    this.planType,
  });

  final double usedPercent;
  final int windowMinutes;
  final DateTime resetsAt;

  /// When the CLI wrote this reading down.
  ///
  /// The reason a figure is trusted is that it is recent, not that its reset
  /// time is the furthest away — a session left running overnight can carry an
  /// older percentage with a later reset than the session you used this
  /// morning. Picking the freshest reading needs this; picking by [resetsAt]
  /// quietly picks the wrong one.
  final DateTime observedAt;

  final String? planType;

  Duration get window => Duration(minutes: windowMinutes);

  /// The window this reading describes has already rolled over.
  ///
  /// A percentage of a window that has since reset is not a small number, it is
  /// no number at all — the page says when it was last read instead of drawing
  /// a bar that means nothing.
  bool isStaleAt(DateTime now) => !resetsAt.isAfter(now);

  Map<String, dynamic> toJson() => {
    'used_percent': usedPercent,
    'window_minutes': windowMinutes,
    'resets_at': resetsAt.toIso8601String(),
    'observed_at': observedAt.toIso8601String(),
    'plan_type': planType,
  };

  static ProviderRateLimit? fromJson(Map<dynamic, dynamic> json) {
    final used = json['used_percent'];
    final window = json['window_minutes'];
    final resets = json['resets_at'];
    final observed = json['observed_at'];
    if (used is! num || window is! int) return null;
    final resetsAt = DateTime.tryParse('$resets');
    final observedAt = DateTime.tryParse('$observed');
    if (resetsAt == null || observedAt == null) return null;
    return ProviderRateLimit(
      usedPercent: used.toDouble(),
      windowMinutes: window,
      resetsAt: resetsAt,
      observedAt: observedAt,
      planType: json['plan_type'] as String?,
    );
  }
}

/// Everything the page draws, and everything it has to be honest about.
class AiUsageReport {
  const AiUsageReport({
    this.days = const [],
    this.recentHours = const [],
    this.providersFound = const {},
    this.missingRoots = const [],
    this.unpricedModels = const [],
    this.rateLimits = const {},
    this.claudePlan,
    this.claudePlanStatus = ClaudePlanStatus.off,
    this.unreadableFiles = 0,
    this.filesScanned = 0,
    this.scannedAt,
  });

  static const AiUsageReport empty = AiUsageReport();

  /// Days that carry usage, ascending. A day inside the covered span with no
  /// entry is genuinely a day with no usage and is simply absent here — see
  /// [coversFrom] for why that is a zero rather than a gap.
  final List<DayUsage> days;

  /// Hourly buckets for the recent window, ascending. Bounded to a little over
  /// a week, which is all the 5-hour block and the rolling week need.
  final List<HourUsage> recentHours;

  final Set<AiProvider> providersFound;

  /// Provider roots that are not on this Mac. Named on screen, because "Codex:
  /// not found" and "Codex: nothing used" are different facts.
  final List<String> missingRoots;

  /// Models whose tokens were counted but whose cost could not be, because
  /// nobody publishes a per-token rate for them. Named on screen for the same
  /// reason.
  final List<String> unpricedModels;

  final Map<AiProvider, ProviderRateLimit> rateLimits;

  /// Claude's published plan usage, when the reading was switched on and the
  /// fetch succeeded.
  ///
  /// Not a [ProviderRateLimit]: that type describes one window Codex wrote into
  /// its own log, and this is several windows fetched from a service — a
  /// session, a week, and one per metered model. Squeezing it into the same
  /// shape would mean throwing away every window but one, and the week is the
  /// one people actually run out of.
  final ClaudePlanUsage? claudePlan;

  /// Why there is, or is not, a [claudePlan].
  ///
  /// Carried beside the reading rather than inferred from its absence, because
  /// the panel says different things for "not switched on", "not signed in to
  /// Claude Code", "could not reach it" and "this account meters nothing" — and
  /// a null cannot tell them apart. It used to guess, and it guessed "not
  /// signed in" at anyone who was merely offline.
  final ClaudePlanStatus claudePlanStatus;

  /// The plan reading, but only while it still describes now.
  ClaudePlanUsage? claudePlanAt(DateTime now) => claudePlan?.freshAt(now);

  /// The same report with Claude's published limits attached.
  ///
  /// A separate step because the two come from different places at different
  /// speeds: the sweep is local and slow, the fetch is remote and may not
  /// answer at all. Folding the fetch into `buildReport` would put a network
  /// call inside an isolate whose whole job is reading files, and would make a
  /// flaky connection look like a failed sweep.
  AiUsageReport withClaudePlan(ClaudePlanReading reading) => AiUsageReport(
    days: days,
    recentHours: recentHours,
    providersFound: providersFound,
    missingRoots: missingRoots,
    unpricedModels: unpricedModels,
    rateLimits: rateLimits,
    claudePlan: reading.usage,
    claudePlanStatus: reading.status,
    unreadableFiles: unreadableFiles,
    filesScanned: filesScanned,
    scannedAt: scannedAt,
  );

  /// Files that could not be read. Counted rather than swallowed: a silent
  /// undercount reads as "you used less than you did".
  final int unreadableFiles;

  final int filesScanned;
  final DateTime? scannedAt;

  bool get isEmpty => days.isEmpty;

  /// The first day any log covers.
  ///
  /// The honesty boundary. Inside it, a day with no usage is a real zero — the
  /// CLIs write their logs whether or not Tidy is running, unlike the network
  /// history, so an empty day means you did not use the tool. Before it, there
  /// is nothing to say, and the chart draws a gap.
  DateTime? get coversFrom => days.isEmpty ? null : days.first.date;

  DateTime? get coversTo => days.isEmpty ? null : days.last.date;

  TokenTotals get tokens =>
      days.fold(TokenTotals.empty, (sum, day) => sum + day.tokens);

  double get cost => days.fold(0.0, (sum, day) => sum + day.cost);

  /// Every date from [from] to [to] inclusive, each carrying its day or null.
  ///
  /// The null is the honest part. A date inside the covered span with no entry
  /// comes back as an empty [DayUsage] — a real zero, because the CLIs write
  /// their logs whether or not Tidy is running, so "no rows" means "you did not
  /// use it". A date *before* the earliest log comes back null, and the chart
  /// draws a gap: there is nothing to say about it in either direction.
  ///
  /// The date rides along rather than being recovered from the day, so a gap
  /// still knows where it sits on the axis.
  List<({DateTime date, DayUsage? day})> span({
    required DateTime from,
    required DateTime to,
  }) {
    final byDate = {for (final day in days) _key(day.date): day};
    final covers = coversFrom;
    final out = <({DateTime date, DayUsage? day})>[];
    var cursor = DateTime(from.year, from.month, from.day);
    final last = DateTime(to.year, to.month, to.day);
    while (!cursor.isAfter(last)) {
      final found = byDate[_key(cursor)];
      final inRange = covers != null && !cursor.isBefore(covers);
      out.add((
        date: cursor,
        day: found ?? (inRange ? DayUsage(date: cursor) : null),
      ));
      cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
    }
    return out;
  }

  /// Totals over the last [days] days, today included.
  TokenTotals tokensOverLast(int dayCount) {
    final cutoff = _startOfToday().subtract(Duration(days: dayCount - 1));
    return days
        .where((day) => !day.date.isBefore(cutoff))
        .fold(TokenTotals.empty, (sum, day) => sum + day.tokens);
  }

  double costOverLast(int dayCount) {
    final cutoff = _startOfToday().subtract(Duration(days: dayCount - 1));
    return days
        .where((day) => !day.date.isBefore(cutoff))
        .fold(0.0, (sum, day) => sum + day.cost);
  }

  DayUsage? get today {
    final start = _startOfToday();
    for (final day in days.reversed) {
      if (day.date == start) return day;
      if (day.date.isBefore(start)) break;
    }
    return null;
  }

  /// Tokens per model across the whole report, heaviest first.
  List<MapEntry<String, TokenTotals>> get modelBreakdown {
    final merged = <String, TokenTotals>{};
    for (final day in days) {
      day.byModel.forEach((model, totals) {
        merged[model] = (merged[model] ?? TokenTotals.empty) + totals;
      });
    }
    final entries =
        merged.entries.toList()
          ..sort((a, b) => b.value.total.compareTo(a.value.total));
    return entries;
  }

  /// Tokens per project across the whole report, heaviest first.
  List<MapEntry<String, TokenTotals>> get projectBreakdown {
    final merged = <String, TokenTotals>{};
    for (final day in days) {
      day.byProject.forEach((project, totals) {
        merged[project] = (merged[project] ?? TokenTotals.empty) + totals;
      });
    }
    final entries =
        merged.entries.toList()
          ..sort((a, b) => b.value.total.compareTo(a.value.total));
    return entries;
  }

  Map<AiProvider, TokenTotals> get providerBreakdown {
    final merged = <AiProvider, TokenTotals>{};
    for (final day in days) {
      day.byProvider.forEach((provider, totals) {
        merged[provider] = (merged[provider] ?? TokenTotals.empty) + totals;
      });
    }
    return merged;
  }
}

/// USD for a model→tokens map, skipping models with no published rate.
double costOf(Map<String, TokenTotals> byModel) {
  var total = 0.0;
  byModel.forEach((model, tokens) {
    final rate = ModelPricing.of(model);
    if (rate != null) total += tokens.costAt(rate);
  });
  return total;
}

/// Which provider a normalised model id belongs to.
///
/// A crude split, and a safe one: Claude Code only ever writes `claude-…`, and
/// nothing else does.
AiProvider _providerOf(String model) =>
    model.startsWith('claude-') ? AiProvider.claudeCode : AiProvider.codex;

Map<String, TokenTotals> _totalsMap(Object? raw) {
  if (raw is! Map) return const {};
  return {
    for (final entry in raw.entries)
      if (entry.value is Map)
        '${entry.key}': TokenTotals.fromJson(entry.value as Map),
  };
}

String _key(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

DateTime _startOfToday() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

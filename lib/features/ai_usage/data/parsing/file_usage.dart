import 'package:tidy/features/ai_usage/data/models/ai_provider.dart';
import 'package:tidy/features/ai_usage/data/models/ai_usage_report.dart';
import 'package:tidy/features/ai_usage/data/models/usage_entry.dart';
import 'package:tidy/features/ai_usage/data/models/usage_totals.dart';

/// Everything one session log contributed, and the stamp that says whether it
/// still needs reading.
///
/// The unit of caching. A rollup per file rather than per month is what makes
/// the cache exact rather than approximate: a deleted log takes its own
/// contribution with it, where a month rollup would have to be rebuilt from
/// scratch because there is no way to subtract one file from a merged total.
///
/// There is no byte offset here, and that is deliberate. Resuming a part-read
/// file would be wrong: 43% of the usage rows in a real Claude Code log are
/// repeats of an earlier row in the *same* file, so the deduplication set has
/// to see the whole file to do its job. Re-reading a changed file from the
/// start is the only correct option — and it costs nothing in practice, since
/// the only files that change are the sessions being used right now.
class FileUsage {
  FileUsage({
    required this.path,
    required this.modifiedMs,
    required this.size,
    required this.provider,
    this.sessionId = '',
    Map<String, DayBucket>? days,
    Map<int, Map<String, TokenTotals>>? hours,
    this.rateLimit,
  }) : days = days ?? {},
       hours = hours ?? {};

  final String path;

  /// `(modifiedMs, size)` together are the cache key. Either one alone misses a
  /// same-second rewrite that happens to land on the same length.
  final int modifiedMs;
  final int size;

  final AiProvider provider;
  final String sessionId;

  /// `YYYY-MM-DD` in local time → that day's slice of this file.
  final Map<String, DayBucket> days;

  /// Local top-of-hour epoch milliseconds → model → tokens.
  ///
  /// Kept per model rather than merged so the 5-hour block can be priced
  /// exactly, the same way a day is, instead of at the day's blended rate. Only
  /// the recent end is ever read, but a session file spans a handful of hours,
  /// so pruning it would cost more code than it saves bytes.
  final Map<int, Map<String, TokenTotals>> hours;

  /// Codex only, and only from the most recent event in the file.
  final ProviderRateLimit? rateLimit;

  bool matches({required int modifiedMs, required int size}) =>
      this.modifiedMs == modifiedMs && this.size == size;

  Map<String, dynamic> toJson() => {
    'm': modifiedMs,
    's': size,
    'p': provider.name,
    'sid': sessionId,
    'd': days.map((key, value) => MapEntry(key, value.toJson())),
    'h': {
      for (final e in hours.entries)
        '${e.key}': e.value.map((k, v) => MapEntry(k, v.toArray())),
    },
    if (rateLimit != null) 'rl': rateLimit!.toJson(),
  };

  static FileUsage? fromJson(String path, Object? raw) {
    if (raw is! Map) return null;
    final provider = AiProvider.tryParse('${raw['p']}');
    if (provider == null) return null;
    final modified = raw['m'];
    final size = raw['s'];
    if (modified is! int || size is! int) return null;

    return FileUsage(
      path: path,
      modifiedMs: modified,
      size: size,
      provider: provider,
      sessionId: '${raw['sid'] ?? ''}',
      days: {
        if (raw['d'] is Map)
          for (final entry in (raw['d'] as Map).entries)
            '${entry.key}': DayBucket.fromJson(entry.value),
      },
      hours: {
        if (raw['h'] is Map)
          for (final entry in (raw['h'] as Map).entries)
            if (int.tryParse('${entry.key}') case final at?)
              at: _arrays(entry.value),
      },
      rateLimit:
          raw['rl'] is Map
              ? ProviderRateLimit.fromJson(raw['rl'] as Map)
              : null,
    );
  }

  /// Folds one parsed turn in.
  void add(UsageEntry entry) {
    final day = days.putIfAbsent(_dayKey(entry.at), DayBucket.new);
    day.addModel(entry.model, entry.tokens);
    if (entry.project case final project? when project.isNotEmpty) {
      day.addProject(project, entry.tokens);
    }

    final hour =
        DateTime(
          entry.at.year,
          entry.at.month,
          entry.at.day,
          entry.at.hour,
        ).millisecondsSinceEpoch;
    final models = hours.putIfAbsent(hour, () => {});
    models[entry.model] =
        (models[entry.model] ?? TokenTotals.empty) + entry.tokens;
  }

  FileUsage withRateLimit(ProviderRateLimit? limit) => FileUsage(
    path: path,
    modifiedMs: modifiedMs,
    size: size,
    provider: provider,
    sessionId: sessionId,
    days: days,
    hours: hours,
    rateLimit: limit,
  );
}

/// One file's contribution to one local day.
class DayBucket {
  DayBucket({
    Map<String, TokenTotals>? models,
    Map<String, TokenTotals>? projects,
  }) : models = models ?? {},
       projects = projects ?? {};

  final Map<String, TokenTotals> models;
  final Map<String, TokenTotals> projects;

  void addModel(String model, TokenTotals tokens) {
    models[model] = (models[model] ?? TokenTotals.empty) + tokens;
  }

  void addProject(String project, TokenTotals tokens) {
    projects[project] = (projects[project] ?? TokenTotals.empty) + tokens;
  }

  Map<String, dynamic> toJson() => {
    'm': models.map((k, v) => MapEntry(k, v.toArray())),
    if (projects.isNotEmpty)
      'p': projects.map((k, v) => MapEntry(k, v.toArray())),
  };

  factory DayBucket.fromJson(Object? raw) {
    if (raw is! Map) return DayBucket();
    return DayBucket(models: _arrays(raw['m']), projects: _arrays(raw['p']));
  }
}

Map<String, TokenTotals> _arrays(Object? raw) {
  if (raw is! Map) return {};
  return {
    for (final entry in raw.entries)
      if (entry.value is List)
        '${entry.key}': TokenTotals.fromArray(entry.value as List),
  };
}

String _dayKey(DateTime at) =>
    '${at.year}-${at.month.toString().padLeft(2, '0')}-'
    '${at.day.toString().padLeft(2, '0')}';

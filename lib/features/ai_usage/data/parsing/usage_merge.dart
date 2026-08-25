import 'package:tidy/features/ai_usage/data/models/ai_provider.dart';
import 'package:tidy/features/ai_usage/data/models/ai_usage_report.dart';
import 'package:tidy/features/ai_usage/data/models/model_pricing.dart';
import 'package:tidy/features/ai_usage/data/models/usage_totals.dart';
import 'package:tidy/features/ai_usage/data/parsing/usage_scan.dart';

/// How far back hourly detail is kept.
///
/// Eight days covers the rolling week and every 5-hour block inside it, which
/// is everything drawn at finer than daily resolution. Keeping a year of hours
/// would be 8,760 buckets nobody reads.
const Duration kRecentHourWindow = Duration(days: 8);

/// Folds every file's rollup into the one object the page reads.
AiUsageReport buildReport(UsageScanResult scan, {DateTime? now}) {
  final at = now ?? DateTime.now();

  final byDate = <String, _DayBuilder>{};
  final hours = <int, Map<String, TokenTotals>>{};
  final providers = <AiProvider>{};
  final limits = <AiProvider, ProviderRateLimit>{};
  final hourFloor =
      DateTime(
        at.year,
        at.month,
        at.day,
        at.hour,
      ).subtract(kRecentHourWindow).millisecondsSinceEpoch;

  for (final file in scan.files.values) {
    if (file.days.isNotEmpty) providers.add(file.provider);

    if (file.rateLimit case final limit?) {
      // The most recently *observed* reading wins: a limit is a statement about
      // now, and an older file's copy of it is simply out of date.
      final held = limits[file.provider];
      if (held == null || limit.observedAt.isAfter(held.observedAt)) {
        limits[file.provider] = limit;
      }
    }

    file.days.forEach((dateKey, bucket) {
      final day = byDate.putIfAbsent(dateKey, () => _DayBuilder(dateKey));
      if (day.date == null) return;
      bucket.models.forEach(
        (model, tokens) => day.addModel(file.provider, model, tokens),
      );
      bucket.projects.forEach(day.addProject);
      if (file.sessionId.isNotEmpty) day.sessions.add(file.sessionId);
    });

    file.hours.forEach((epoch, models) {
      if (epoch < hourFloor) return;
      final bucket = hours.putIfAbsent(epoch, () => {});
      models.forEach((model, tokens) {
        bucket[model] = (bucket[model] ?? TokenTotals.empty) + tokens;
      });
    });
  }

  final days =
      byDate.values.where((day) => day.date != null).toList()
        ..sort((a, b) => a.date!.compareTo(b.date!));

  final unpriced = <String>{};
  for (final day in days) {
    for (final model in day.models.keys) {
      if (ModelPricing.of(model) == null) unpriced.add(model);
    }
  }

  final recentHours =
      hours.entries
          .map(
            (entry) => HourUsage(
              at: DateTime.fromMillisecondsSinceEpoch(entry.key),
              tokens: entry.value.values.fold(
                TokenTotals.empty,
                (sum, tokens) => sum + tokens,
              ),
              cost: costOf(entry.value),
            ),
          )
          .toList()
        ..sort((a, b) => a.at.compareTo(b.at));

  return AiUsageReport(
    days: [for (final day in days) day.build()],
    recentHours: recentHours,
    providersFound: providers,
    missingRoots: scan.missingRoots,
    unpricedModels: unpriced.toList()..sort(),
    rateLimits: limits,
    unreadableFiles: scan.unreadableFiles,
    filesScanned: scan.filesScanned,
    scannedAt: at,
  );
}

class _DayBuilder {
  _DayBuilder(this.key) : date = _parseDay(key);

  final String key;
  final DateTime? date;

  final Map<String, TokenTotals> models = {};
  final Map<AiProvider, TokenTotals> providers = {};
  final Map<String, TokenTotals> projects = {};
  final Set<String> sessions = {};

  void addModel(AiProvider provider, String model, TokenTotals tokens) {
    models[model] = (models[model] ?? TokenTotals.empty) + tokens;
    providers[provider] = (providers[provider] ?? TokenTotals.empty) + tokens;
  }

  void addProject(String project, TokenTotals tokens) {
    projects[project] = (projects[project] ?? TokenTotals.empty) + tokens;
  }

  DayUsage build() => DayUsage(
    date: date!,
    byModel: models,
    byProvider: providers,
    byProject: projects,
    sessions: sessions.length,
  );
}

DateTime? _parseDay(String key) {
  final parts = key.split('-');
  if (parts.length != 3) return null;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) return null;
  return DateTime(year, month, day);
}

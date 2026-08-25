import 'package:tidy/features/ai_usage/data/models/ai_provider.dart';
import 'package:tidy/features/ai_usage/data/models/usage_totals.dart';

/// One metered assistant turn, as a parser hands it to the aggregator.
///
/// Deliberately not part of the report. A busy year is a few hundred thousand
/// of these, which is fine to walk inside the isolate and far too much to send
/// back across the port — the isolate folds them into day and hour buckets and
/// returns only those.
class UsageEntry {
  const UsageEntry({
    required this.provider,
    required this.at,
    required this.model,
    required this.tokens,
    required this.sessionId,
    this.project,
  });

  final AiProvider provider;

  /// Local time. Everything downstream buckets by local day, matching the rule
  /// `TidyStore` already follows — bucketing on UTC boundaries splits a day's
  /// bar in two for anyone who is not on UTC.
  final DateTime at;

  /// Normalised model id.
  final String model;

  final TokenTotals tokens;
  final String sessionId;

  /// The working directory the turn ran in, for the per-project table. Null
  /// where the log does not record one.
  final String? project;
}

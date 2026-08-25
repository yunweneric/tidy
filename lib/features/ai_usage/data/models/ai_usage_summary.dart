import 'package:tidy/features/ai_usage/data/models/ai_usage_report.dart';
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
  });

  static const int version = 1;

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
    );
  }
}

double _costOf(String model, TokenTotals tokens) {
  final rate = ModelPricing.of(model);
  return rate == null ? 0 : tokens.costAt(rate);
}

int _int(Object? value) => value is num ? value.toInt() : 0;
double _double(Object? value) => value is num ? value.toDouble() : 0;

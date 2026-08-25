import 'package:tidy/features/ai_usage/data/models/ai_usage_report.dart';
import 'package:tidy/features/ai_usage/data/models/usage_totals.dart';

/// How long a Claude Code usage block runs.
const Duration kBlockLength = Duration(hours: 5);

/// One inferred five-hour block of activity.
///
/// **Inferred, and the page says so.** Claude Code writes no limit and no reset
/// time into its logs, so the only thing that can be reconstructed offline is
/// where the activity clusters: a block opens at the top of the hour containing
/// the first turn after a gap of five hours or more, and runs for five.
///
/// That is enough to answer "how much have I got through since I sat down",
/// which is what the block readout claims. It is *not* enough to draw a
/// percentage bar, because the denominator — the plan's actual ceiling — is not
/// in any file on this Mac. Codex publishes its own `used_percent` and gets a
/// real bar; Claude Code gets a total and no bar. The asymmetry is honest and
/// the two are labelled differently on screen.
class UsageBlock {
  const UsageBlock({
    required this.startsAt,
    required this.tokens,
    required this.cost,
  });

  final DateTime startsAt;
  final TokenTotals tokens;
  final double cost;

  DateTime get endsAt => startsAt.add(kBlockLength);

  bool isActiveAt(DateTime now) =>
      !now.isBefore(startsAt) && now.isBefore(endsAt);

  Duration remainingAt(DateTime now) {
    final left = endsAt.difference(now);
    return left.isNegative ? Duration.zero : left;
  }
}

/// Groups hourly buckets into blocks, oldest first.
List<UsageBlock> blocksFrom(List<HourUsage> hours) {
  final used =
      hours.where((hour) => !hour.tokens.isEmpty).toList()
        ..sort((a, b) => a.at.compareTo(b.at));
  if (used.isEmpty) return const [];

  final blocks = <UsageBlock>[];
  var start = used.first.at;
  var tokens = TokenTotals.empty;
  var cost = 0.0;

  void close() =>
      blocks.add(UsageBlock(startsAt: start, tokens: tokens, cost: cost));

  for (final hour in used) {
    if (!hour.at.isBefore(start.add(kBlockLength))) {
      close();
      start = hour.at;
      tokens = TokenTotals.empty;
      cost = 0;
    }
    tokens += hour.tokens;
    cost += hour.cost;
  }
  close();
  return blocks;
}

/// The block covering [now], or null when nothing has been used inside one.
UsageBlock? activeBlock(List<HourUsage> hours, {DateTime? now}) {
  final at = now ?? DateTime.now();
  for (final block in blocksFrom(hours).reversed) {
    if (block.isActiveAt(at)) return block;
    if (block.endsAt.isBefore(at)) return null;
  }
  return null;
}

/// How far back the trend chart looks.
enum UsageRange {
  week('7 days', 7),
  month('30 days', 30),
  quarter('90 days', 90);

  const UsageRange(this.label, this.days);

  final String label;
  final int days;
}

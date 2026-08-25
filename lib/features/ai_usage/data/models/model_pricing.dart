/// Published API rates, in USD per million tokens.
///
/// **These are not what you were billed.** Claude Code and Codex both run on
/// flat-fee subscriptions, so every figure this feature shows is what the same
/// tokens *would* have cost through the API. `docs/ui.md` §9 forbids
/// overclaiming, and quoting an API total as a bill is exactly that, so the
/// distinction is on screen and not in a tooltip.
///
/// Rates come from platform.claude.com/docs/en/about-claude/pricing. Cache
/// multipliers over the base input rate are fixed by that page and identical on
/// every model: **read ×0.1, 5-minute write ×1.25, 1-hour write ×2.0**. They
/// are applied rather than tabulated, so a new model is one row.
library;

/// When the rates below were last checked against the pricing page.
///
/// Printed under the tables. A cost figure with no date on it is a claim about
/// today that quietly ages into a claim about nothing.
const String kPricesCheckedOn = '25 August 2026';

/// Base rates for one model, in USD per million tokens.
class ModelRate {
  const ModelRate({required this.input, required this.output});

  final double input;
  final double output;

  double get cacheRead => input * 0.1;
  double get cacheWrite5m => input * 1.25;
  double get cacheWrite1h => input * 2.0;
}

/// Every model with a published per-token rate.
///
/// Keys are the normalised ids `ModelPricing.normalise` produces, which is what
/// Claude Code writes into `message.model`.
const Map<String, ModelRate> _rates = {
  // Fable tier.
  'claude-fable-5': ModelRate(input: 10, output: 50),
  'claude-mythos-5': ModelRate(input: 10, output: 50),
  'claude-mythos-preview': ModelRate(input: 10, output: 50),

  // Opus tier. 4.1 and 4.0 were three times the price of everything after
  // them, which is worth keeping accurate — an old month priced at today's
  // Opus rate would understate itself by two thirds.
  'claude-opus-5': ModelRate(input: 5, output: 25),
  'claude-opus-4-8': ModelRate(input: 5, output: 25),
  'claude-opus-4-7': ModelRate(input: 5, output: 25),
  'claude-opus-4-6': ModelRate(input: 5, output: 25),
  'claude-opus-4-5': ModelRate(input: 5, output: 25),
  'claude-opus-4-1': ModelRate(input: 15, output: 75),
  'claude-opus-4-0': ModelRate(input: 15, output: 75),

  // Sonnet tier. Sonnet 5's $2/$10 launched as introductory pricing through
  // 31 August 2026; Anthropic has since made it the standard rate and
  // cancelled the rise to $3/$15, so there is no date to switch on.
  'claude-sonnet-5': ModelRate(input: 2, output: 10),
  'claude-sonnet-4-6': ModelRate(input: 3, output: 15),
  'claude-sonnet-4-5': ModelRate(input: 3, output: 15),
  'claude-sonnet-4-0': ModelRate(input: 3, output: 15),

  // Haiku tier.
  'claude-haiku-4-5': ModelRate(input: 1, output: 5),
  'claude-haiku-3-5': ModelRate(input: 0.8, output: 4),
};

/// Rate lookup, and the model-id tidying that has to happen first.
abstract final class ModelPricing {
  /// The rate for [model], or null when there is no published per-token price.
  ///
  /// Null is a real answer, not a failure. Codex reaches here for every one of
  /// its models: OpenAI meters Codex in credits rather than dollars per token,
  /// and there is no published conversion, so its tokens are counted and its
  /// cost is left blank. Inventing a plausible number would be worse than the
  /// blank — a blank is visibly missing, and a wrong number is not.
  static ModelRate? of(String model) => _rates[normalise(model)];

  /// Collapses the spellings the same model arrives under.
  ///
  /// Gateways and older CLI builds write `claude-opus-4.8`, and the API returns
  /// dated snapshots like `claude-haiku-4-5-20251001`. Both are the same rate
  /// as the plain alias, and leaving them distinct splits one model into three
  /// rows in the breakdown table.
  static String normalise(String model) {
    var id = model.trim().toLowerCase();
    if (id.isEmpty) return id;

    // `claude-opus-4.8` → `claude-opus-4-8`.
    id = id.replaceAll('.', '-');

    // Strip a trailing 8-digit date snapshot. By hand rather than with a
    // pattern: `RegExp` is deprecated in this SDK and the analyzer flags it.
    final dash = id.lastIndexOf('-');
    if (dash > 0 && id.length - dash - 1 == 8) {
      final tail = id.substring(dash + 1);
      if (tail.codeUnits.every((c) => c >= 0x30 && c <= 0x39)) {
        id = id.substring(0, dash);
      }
    }

    // Some gateways prefix the vendor: `anthropic.claude-opus-5`.
    final dot = id.indexOf('claude-');
    if (dot > 0) id = id.substring(dot);

    return id;
  }

  /// True for the placeholder turns Claude Code writes when no model ran.
  ///
  /// `<synthetic>` and friends carry a usage block of zeroes and would
  /// otherwise appear in the breakdown as a model the user has never heard of.
  static bool isSynthetic(String model) {
    final id = model.trim();
    return id.isEmpty || id.startsWith('<') || id.toLowerCase() == 'synthetic';
  }
}

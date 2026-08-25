import 'package:tidy/features/ai_usage/data/models/model_pricing.dart';

/// Tokens for one model, split the way the price list splits them.
///
/// The four categories are separate fields rather than one total because they
/// bill at four different rates — a cache read costs a tenth of fresh input,
/// and a one-hour cache write costs twice it. Folding them together before
/// pricing loses a factor of twenty between the cheapest and dearest token in
/// the same request.
class TokenTotals {
  const TokenTotals({
    this.input = 0,
    this.output = 0,
    this.cacheRead = 0,
    this.cacheWrite5m = 0,
    this.cacheWrite1h = 0,
    this.thinking = 0,
    this.messages = 0,
  });

  /// Fresh input, with cache reads excluded. Codex reports the two combined,
  /// so its parser subtracts before it gets here.
  final int input;
  final int output;
  final int cacheRead;

  /// Cache writes, split by TTL. Claude Code writes almost everything at the
  /// one-hour TTL, which bills at 2x input against the 5-minute TTL's 1.25x —
  /// pricing the two together understates a heavy month by around 7%.
  final int cacheWrite5m;
  final int cacheWrite1h;

  /// Reasoning tokens. A **subset** of [output], reported for interest and
  /// never added — Claude nests it under `output_tokens_details`, Codex reports
  /// it as `reasoning_output_tokens`, and both are already counted.
  final int thinking;

  /// Assistant turns behind these numbers.
  final int messages;

  static const TokenTotals empty = TokenTotals();

  int get cacheWrite => cacheWrite5m + cacheWrite1h;

  /// Everything the API metered, which is what "tokens" means on screen.
  int get total => input + output + cacheRead + cacheWrite;

  bool get isEmpty => total == 0 && messages == 0;

  TokenTotals operator +(TokenTotals other) => TokenTotals(
    input: input + other.input,
    output: output + other.output,
    cacheRead: cacheRead + other.cacheRead,
    cacheWrite5m: cacheWrite5m + other.cacheWrite5m,
    cacheWrite1h: cacheWrite1h + other.cacheWrite1h,
    thinking: thinking + other.thinking,
    messages: messages + other.messages,
  );

  /// What these tokens would have cost at [rate], in USD.
  double costAt(ModelRate rate) =>
      (input * rate.input +
          output * rate.output +
          cacheRead * rate.cacheRead +
          cacheWrite5m * rate.cacheWrite5m +
          cacheWrite1h * rate.cacheWrite1h) /
      1000000;

  /// What the cached input would have cost had it been sent fresh every time.
  ///
  /// The other half of the cache-efficiency line: reads bill at a tenth of
  /// input, so the difference between this and the read's real cost is the
  /// saving, and it is arithmetic on numbers we have rather than an estimate.
  double uncachedCostAt(ModelRate rate) => (cacheRead * rate.input) / 1000000;

  /// Compact form for the cache file.
  ///
  /// Seven named keys per model per day per file runs to megabytes of JSON on a
  /// working Mac; the positional form is a fifth of that and the cache is never
  /// read by anything but this class.
  List<int> toArray() => [
    input,
    output,
    cacheRead,
    cacheWrite5m,
    cacheWrite1h,
    thinking,
    messages,
  ];

  factory TokenTotals.fromArray(List<dynamic> a) => TokenTotals(
    input: _at(a, 0),
    output: _at(a, 1),
    cacheRead: _at(a, 2),
    cacheWrite5m: _at(a, 3),
    cacheWrite1h: _at(a, 4),
    thinking: _at(a, 5),
    messages: _at(a, 6),
  );

  Map<String, dynamic> toJson() => {
    'input': input,
    'output': output,
    'cache_read': cacheRead,
    'cache_write_5m': cacheWrite5m,
    'cache_write_1h': cacheWrite1h,
    'thinking': thinking,
    'messages': messages,
  };

  factory TokenTotals.fromJson(Map<dynamic, dynamic> json) => TokenTotals(
    input: _int(json['input']),
    output: _int(json['output']),
    cacheRead: _int(json['cache_read']),
    cacheWrite5m: _int(json['cache_write_5m']),
    cacheWrite1h: _int(json['cache_write_1h']),
    thinking: _int(json['thinking']),
    messages: _int(json['messages']),
  );

  @override
  String toString() =>
      'TokenTotals(in: $input, out: $output, read: $cacheRead, '
      'write: $cacheWrite5m/5m + $cacheWrite1h/1h, msgs: $messages)';
}

int _int(Object? value) => value is num ? value.toInt() : 0;

int _at(List<dynamic> a, int i) =>
    i < a.length && a[i] is num ? (a[i] as num).toInt() : 0;

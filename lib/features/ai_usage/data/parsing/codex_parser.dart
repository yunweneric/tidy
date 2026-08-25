import 'dart:convert';

import 'package:tidy/features/ai_usage/data/models/ai_provider.dart';
import 'package:tidy/features/ai_usage/data/models/ai_usage_report.dart';
import 'package:tidy/features/ai_usage/data/models/usage_entry.dart';
import 'package:tidy/features/ai_usage/data/models/usage_totals.dart';

/// Reads the rollout logs Codex writes to `~/.codex/sessions/YYYY/MM/DD`.
///
/// A different shape from Claude Code's in every respect that matters:
///
/// ```jsonc
/// { "type": "turn_context", "payload": { "model": "gpt-5.6-sol", … } }
/// { "type": "event_msg", "timestamp": "2026-08-17T19:30:12.390Z",
///   "payload": { "type": "token_count",
///     "info": {
///       "total_token_usage": { … },                 // cumulative — never sum
///       "last_token_usage": { "input_tokens": 19943,
///                             "cached_input_tokens": 11008,
///                             "cache_write_input_tokens": 0,
///                             "output_tokens": 67,
///                             "reasoning_output_tokens": 0 } },
///     "rate_limits": { "primary": { "used_percent": 18.0,
///                                   "window_minutes": 10080,
///                                   "resets_at": 1787201946 },
///                      "plan_type": "plus" } } }
/// ```
///
/// Stateful across the file, so an instance per file rather than a static
/// method: the model belongs to the most recent `turn_context`, not to the
/// usage event, and a session can change model part-way through.
///
/// No Flutter imports — this runs inside an isolate.
class CodexParser {
  CodexParser({required this.sessionId});

  final String sessionId;

  String _model = 'unknown';
  String? _project;

  /// The last plan-limit reading seen in this file. Codex is the only source
  /// either CLI gives us that states a real limit rather than implying one.
  ProviderRateLimit? rateLimit;

  static bool couldMatter(String line) =>
      line.contains('"token_count"') || line.contains('"turn_context"');

  /// The one turn on this line, or null.
  ///
  /// No dedup set: rollout files are one per session and are never rewritten,
  /// so nothing here is written twice. The double-counting risk on this side is
  /// `~/.codex/archived_sessions`, which holds copies — the file walk skips it
  /// rather than the parser.
  UsageEntry? parseLine(String line) {
    if (!couldMatter(line)) return null;

    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;

    final payload = decoded['payload'];
    if (payload is! Map) return null;

    if (decoded['type'] == 'turn_context') {
      final model = payload['model'];
      if (model is String && model.isNotEmpty) _model = model;
      final cwd = payload['cwd'];
      if (cwd is String && cwd.isNotEmpty) _project = cwd;
      return null;
    }

    if (payload['type'] != 'token_count') return null;

    final at = DateTime.tryParse('${decoded['timestamp']}');
    if (at == null) return null;

    final limits = payload['rate_limits'];
    if (limits is Map) {
      rateLimit = _readRateLimit(limits, at.toLocal()) ?? rateLimit;
    }

    final info = payload['info'];
    if (info is! Map) return null;

    // `last_token_usage` is the delta for this turn. `total_token_usage` is the
    // running total for the session — summing that across a session's events
    // would over-count by roughly the square of the turn count.
    final last = info['last_token_usage'];
    if (last is! Map) return null;

    // OpenAI's `input_tokens` is the whole input, with `cached_input_tokens` a
    // subset of it. Anthropic reports the two as disjoint. Subtracting here is
    // what lets one `TokenTotals` mean the same thing on both sides.
    final input = _int(last['input_tokens']);
    final cached = _int(last['cached_input_tokens']);
    final fresh = input - cached;

    final tokens = TokenTotals(
      input: fresh < 0 ? 0 : fresh,
      output: _int(last['output_tokens']),
      cacheRead: cached,
      // Codex reports one cache-write figure with no TTL. The five-minute
      // bucket is the conservative home for it; nothing prices Codex anyway.
      cacheWrite5m: _int(last['cache_write_input_tokens']),
      // A subset of `output_tokens`, never added.
      thinking: _int(last['reasoning_output_tokens']),
      messages: 1,
    );
    if (tokens.isEmpty) return null;

    return UsageEntry(
      provider: AiProvider.codex,
      at: at.toLocal(),
      model: _model,
      sessionId: sessionId,
      project: _project,
      tokens: tokens,
    );
  }

  static ProviderRateLimit? _readRateLimit(
    Map<dynamic, dynamic> limits,
    DateTime observedAt,
  ) {
    final primary = limits['primary'];
    if (primary is! Map) return null;

    final used = primary['used_percent'];
    final window = primary['window_minutes'];
    final resets = primary['resets_at'];
    if (used is! num || window is! num || resets is! num) return null;

    return ProviderRateLimit(
      usedPercent: used.toDouble(),
      windowMinutes: window.toInt(),
      resetsAt:
          DateTime.fromMillisecondsSinceEpoch(resets.toInt() * 1000).toLocal(),
      observedAt: observedAt,
      planType:
          limits['plan_type'] is String ? limits['plan_type'] as String : null,
    );
  }
}

int _int(Object? value) => value is num ? value.toInt() : 0;

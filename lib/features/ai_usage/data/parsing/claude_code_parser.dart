import 'dart:convert';

import 'package:tidy/features/ai_usage/data/models/ai_provider.dart';
import 'package:tidy/features/ai_usage/data/models/model_pricing.dart';
import 'package:tidy/features/ai_usage/data/models/usage_entry.dart';
import 'package:tidy/features/ai_usage/data/models/usage_totals.dart';

/// Reads the session logs Claude Code writes to `~/.claude/projects`.
///
/// One JSONL file per session, appended to as the session runs. A metered turn
/// looks like this, with the parts that matter kept:
///
/// ```jsonc
/// { "type": "assistant", "timestamp": "2026-08-20T18:26:25.880Z",
///   "requestId": "req_…", "sessionId": "80b6d6c9-…",
///   "cwd": "/Users/you/code/thing",
///   "message": { "id": "msg_…", "model": "claude-opus-5",
///     "usage": { "input_tokens": 2, "output_tokens": 485,
///       "cache_read_input_tokens": 25447,
///       "cache_creation_input_tokens": 12437,
///       "cache_creation": { "ephemeral_1h_input_tokens": 12437,
///                           "ephemeral_5m_input_tokens": 0 },
///       "output_tokens_details": { "thinking_tokens": 121 },
///       "iterations": [ /* repeats the numbers above */ ] } } }
/// ```
///
/// No Flutter imports anywhere in this file — it runs inside an isolate.
abstract final class ClaudeCodeParser {
  /// Cheap reject before the expensive one.
  ///
  /// A session file is roughly 40% assistant turns; the rest is user messages,
  /// attachments, and file-history snapshots. Those snapshots are why this
  /// matters — the largest file on a working Mac runs to 40 MB and decoding
  /// every line of it to find out it was not a usage row costs more than the
  /// whole rest of the sweep.
  static bool couldBeUsage(String line) =>
      line.contains('"type":"assistant"') && line.contains('"usage"');

  /// The one turn on this line, or null if it carries no billable usage.
  ///
  /// [dedup] collects `messageId:requestId` across the whole sweep. Resuming a
  /// session replays its history into a fresh file, so without this a
  /// long-running project is counted once per resume.
  static UsageEntry? parseLine(String line, {required Set<String> dedup}) {
    if (!couldBeUsage(line)) return null;

    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      // A half-written trailing line while Claude Code is mid-flush. The next
      // sweep sees it complete.
      return null;
    }
    if (decoded is! Map) return null;
    if (decoded['type'] != 'assistant') return null;

    final message = decoded['message'];
    if (message is! Map) return null;

    final usage = message['usage'];
    if (usage is! Map) return null;

    final rawModel = message['model'];
    if (rawModel is! String || ModelPricing.isSynthetic(rawModel)) return null;

    final messageId = message['id'];
    final requestId = decoded['requestId'];
    if (messageId is String && requestId is String) {
      if (!dedup.add('$messageId:$requestId')) return null;
    }

    final at = DateTime.tryParse('${decoded['timestamp']}');
    if (at == null) return null;

    // `cache_creation` splits the write by TTL. Claude Code writes at the
    // one-hour TTL, which bills at 2x input where the five-minute TTL bills at
    // 1.25x — pricing them together understates a heavy month by around 7%.
    // Older builds omit the split, and the five-minute TTL is the API default,
    // so that is what the fallback assumes.
    final creation = usage['cache_creation'];
    final int write5m;
    final int write1h;
    if (creation is Map) {
      write5m = _int(creation['ephemeral_5m_input_tokens']);
      write1h = _int(creation['ephemeral_1h_input_tokens']);
    } else {
      write5m = _int(usage['cache_creation_input_tokens']);
      write1h = 0;
    }

    final details = usage['output_tokens_details'];

    // `usage.iterations` is deliberately ignored. It restates the figures below
    // one entry per inference pass, so adding it doubles the turn.
    return UsageEntry(
      provider: AiProvider.claudeCode,
      at: at.toLocal(),
      model: ModelPricing.normalise(rawModel),
      sessionId: '${decoded['sessionId'] ?? ''}',
      project: decoded['cwd'] is String ? decoded['cwd'] as String : null,
      tokens: TokenTotals(
        input: _int(usage['input_tokens']),
        output: _int(usage['output_tokens']),
        cacheRead: _int(usage['cache_read_input_tokens']),
        cacheWrite5m: write5m,
        cacheWrite1h: write1h,
        // A subset of `output_tokens`, never added to it.
        thinking: details is Map ? _int(details['thinking_tokens']) : 0,
        messages: 1,
      ),
    );
  }
}

int _int(Object? value) => value is num ? value.toInt() : 0;

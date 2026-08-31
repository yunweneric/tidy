/// Claude's own reading of how much of the plan has been used.
///
/// Everything else on the AI Usage page is reconstructed from session logs on
/// this Mac. This is not: it is what Anthropic says, fetched from the same
/// endpoint `claude` itself reads, and it is the only source of a *denominator*
/// for Claude Code. The logs record tokens; they have never recorded the
/// allowance those tokens are spent against, which is why the session bar used
/// to be a clock and the weekly row had no bar at all.
library;

/// How long a fetched reading is reused before asking again.
///
/// The publisher ticks every minute; the percentages move when a reply lands,
/// not when a timer fires. One request a minute against an endpoint that
/// rate-limits is a good way to lose the readings entirely.
const Duration kClaudePlanCacheFor = Duration(minutes: _cacheMinutes);

/// How long a fetched reading is worth drawing.
///
/// Derived from [kClaudePlanCacheFor] rather than picked independently: these
/// two constants are the same decision seen from either end, and when they were
/// separate numbers nothing stopped a future edit making the reading go stale
/// before the cache would refetch it — which shows up as bars that blink out
/// for a minute and come back. Five refetch windows is enough that a network
/// blip leaves the last percentage on screen.
const Duration kClaudePlanStaleAfter = Duration(minutes: _cacheMinutes * 5);

/// Held as a plain number so the two durations above can be derived from one
/// value — `Duration * int` is not a constant expression.
const int _cacheMinutes = 2;

/// How long to stop asking after the account turns out to have no metered
/// limits at all.
///
/// An API-key or Console account answers 200 with every window null, forever.
/// Without this the client asks again every couple of minutes for the life of
/// the app and never gets a different answer.
const Duration kClaudePlanNoLimitsBackoff = Duration(hours: 6);

/// Why there is, or is not, a reading to draw.
///
/// The UI copy distinguishes "not signed in" from "could not reach it", so the
/// fetch has to as well. Collapsing every failure into a null made the panel
/// guess, and it guessed wrong for anyone who was offline rather than signed
/// out.
enum ClaudePlanStatus {
  /// The setting is off. Not a failure — nothing was attempted.
  off,

  /// Claude Code has no stored sign-in on this Mac.
  notSignedIn,

  /// Asked and could not tell: offline, DNS, timeout, a 500.
  unreachable,

  /// Asked too often. [ClaudePlanReading.retryAt] says when to try again.
  rateLimited,

  /// Answered, and this account meters nothing — an API-key or Console plan.
  noLimits,

  /// A reading is in hand.
  ready,
}

/// The outcome of one attempt, and the reading if there was one.
class ClaudePlanReading {
  const ClaudePlanReading(this.status, {this.usage, this.retryAt});

  const ClaudePlanReading.off() : this(ClaudePlanStatus.off);

  final ClaudePlanStatus status;

  /// Present only when [status] is [ClaudePlanStatus.ready] — or when a fresh
  /// attempt failed and a previous reading is still worth drawing.
  final ClaudePlanUsage? usage;

  /// When asking again might work, for the statuses that know.
  final DateTime? retryAt;
}

/// One limit window, as published.
class ClaudeLimitWindow {
  const ClaudeLimitWindow({required this.utilization, this.resetsAt});

  /// 0–100. The API's own number — never derived from token counts here.
  final double utilization;

  /// When the window rolls over.
  ///
  /// Nullable, and it matters: the API sends `null` for a window with nothing
  /// scheduled — typically a model-scoped weekly limit sitting at 0%. Treating
  /// it as required makes the *whole* response fail to parse, which reads to
  /// the user as "limits unavailable" rather than "this one window is idle".
  final DateTime? resetsAt;

  /// What a bar fills to.
  double get fraction => (utilization / 100).clamp(0.0, 1.0);

  /// Time until the reset, or null when none is scheduled. Zero once passed —
  /// the caller redraws rather than counting down through negative numbers.
  Duration? remainingAt(DateTime now) {
    final at = resetsAt;
    if (at == null) return null;
    final left = at.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  Map<String, dynamic> toJson() => {
    'utilization': utilization,
    if (resetsAt != null) 'resets_at': resetsAt!.toUtc().toIso8601String(),
  };

  static ClaudeLimitWindow? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final used = raw['utilization'] ?? raw['percent'];
    if (used is! num) return null;
    return ClaudeLimitWindow(
      utilization: used.toDouble(),
      resetsAt: DateTime.tryParse('${raw['resets_at']}')?.toLocal(),
    );
  }
}

/// A weekly window scoped to one model — Opus, Sonnet, and whatever else the
/// API decides to meter next.
///
/// Named rather than enumerated on purpose. These arrive in the response's
/// `limits` array carrying a display name, and the set changes without notice;
/// a fixed enum would silently drop a model the moment Anthropic added one.
class ClaudeModelLimit {
  const ClaudeModelLimit({required this.model, required this.window});

  /// The API's `scope.model.display_name`, e.g. `Opus`.
  final String model;
  final ClaudeLimitWindow window;

  Map<String, dynamic> toJson() => {'model': model, ...window.toJson()};

  static ClaudeModelLimit? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final model = '${raw['model']}'.trim();
    final window = ClaudeLimitWindow.fromJson(raw);
    if (model.isEmpty || model == 'null' || window == null) return null;
    return ClaudeModelLimit(model: model, window: window);
  }
}

/// Pay-as-you-go credit on top of the plan, where it is switched on.
class ClaudeExtraUsage {
  const ClaudeExtraUsage({
    required this.isEnabled,
    required this.monthlyLimit,
    required this.usedCredits,
    required this.utilization,
  });

  final bool isEnabled;
  final double monthlyLimit;
  final double usedCredits;
  final double utilization;

  Map<String, dynamic> toJson() => {
    'is_enabled': isEnabled,
    'monthly_limit': monthlyLimit,
    'used_credits': usedCredits,
    'utilization': utilization,
  };

  static ClaudeExtraUsage? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final used = raw['utilization'];
    if (used is! num) return null;
    return ClaudeExtraUsage(
      isEnabled: raw['is_enabled'] == true,
      monthlyLimit: (raw['monthly_limit'] as num?)?.toDouble() ?? 0,
      usedCredits: (raw['used_credits'] as num?)?.toDouble() ?? 0,
      utilization: used.toDouble(),
    );
  }
}

/// The whole published picture: the session window, the week, and the
/// per-model weeks.
class ClaudePlanUsage {
  const ClaudePlanUsage({
    required this.fetchedAt,
    this.session,
    this.week,
    this.modelWeeks = const [],
    this.extra,
  });

  /// The rolling five-hour session window.
  final ClaudeLimitWindow? session;

  /// The seven-day window — the one the page could not show before.
  final ClaudeLimitWindow? week;

  /// Per-model weekly windows, sorted by name.
  final List<ClaudeModelLimit> modelWeeks;

  final ClaudeExtraUsage? extra;

  final DateTime fetchedAt;

  bool get isEmpty => session == null && week == null && modelWeeks.isEmpty;

  bool isStaleAt(DateTime now) =>
      now.difference(fetchedAt) > kClaudePlanStaleAfter;

  /// A reading worth drawing at [now], or null.
  ClaudePlanUsage? freshAt(DateTime now) => isStaleAt(now) ? null : this;

  Map<String, dynamic> toJson() => {
    'fetched_at': fetchedAt.toUtc().toIso8601String(),
    if (session != null) 'five_hour': session!.toJson(),
    if (week != null) 'seven_day': week!.toJson(),
    'model_weeks': [for (final entry in modelWeeks) entry.toJson()],
    if (extra != null) 'extra_usage': extra!.toJson(),
  };

  static ClaudePlanUsage? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final fetchedAt = DateTime.tryParse('${raw['fetched_at']}')?.toLocal();
    if (fetchedAt == null) return null;
    return ClaudePlanUsage(
      fetchedAt: fetchedAt,
      session: ClaudeLimitWindow.fromJson(raw['five_hour']),
      week: ClaudeLimitWindow.fromJson(raw['seven_day']),
      modelWeeks: [
        if (raw['model_weeks'] case final List entries)
          for (final entry in entries)
            if (ClaudeModelLimit.fromJson(entry) case final limit?) limit,
      ],
      extra: ClaudeExtraUsage.fromJson(raw['extra_usage']),
    );
  }

  /// Reads the shape `GET /api/oauth/usage` returns.
  ///
  /// Two generations of the same information live in that payload. The windows
  /// used to arrive as dedicated `seven_day_<model>` keys and now arrive as a
  /// `limits` array of scoped entries; accounts are moved between the two
  /// without warning, and a client that reads only one of them shows a blank
  /// panel to half its users. So: prefer the array, fall back to the keys.
  static ClaudePlanUsage parseApi(Map<dynamic, dynamic> json, {DateTime? at}) {
    final scoped = <String, ClaudeLimitWindow>{};

    if (json['limits'] case final List entries) {
      for (final entry in entries) {
        if (entry is! Map) continue;
        // Inactive entries describe a limit that is not being enforced on this
        // account. Drawing one is drawing a bar for a rule that does not apply.
        if (entry['is_active'] != true) continue;
        final name = _displayName(entry['scope']);
        if (name == null) continue;
        // `percent` missing on an active window means nothing has been used
        // yet, not that the window is unknown.
        final used = (entry['percent'] as num?)?.toDouble() ?? 0;
        scoped.putIfAbsent(
          name,
          () => ClaudeLimitWindow(
            utilization: used,
            resetsAt: DateTime.tryParse('${entry['resets_at']}')?.toLocal(),
          ),
        );
      }
    }

    if (scoped.isEmpty) {
      for (final legacy in const [
        ('Opus', 'seven_day_opus'),
        ('Sonnet', 'seven_day_sonnet'),
      ]) {
        final window = ClaudeLimitWindow.fromJson(json[legacy.$2]);
        if (window != null) scoped[legacy.$1] = window;
      }
    }

    final models =
        scoped.entries
            .map((e) => ClaudeModelLimit(model: e.key, window: e.value))
            .toList()
          ..sort((a, b) => a.model.compareTo(b.model));

    return ClaudePlanUsage(
      fetchedAt: at ?? DateTime.now(),
      session: ClaudeLimitWindow.fromJson(json['five_hour']),
      week: ClaudeLimitWindow.fromJson(json['seven_day']),
      modelWeeks: models,
      extra: ClaudeExtraUsage.fromJson(json['extra_usage']),
    );
  }

  static String? _displayName(Object? scope) {
    if (scope is! Map) return null;
    final model = scope['model'];
    if (model is! Map) return null;
    final name = '${model['display_name']}'.trim();
    return name.isEmpty || name == 'null' ? null : name;
  }
}

import FlutterMacOS
import Foundation

/// The menu bar's slice of the AI usage report, as the main engine last sent it.
///
/// Mirrors `AiUsageSummary` in
/// `lib/features/ai_usage/data/models/ai_usage_summary.dart`. Keys cross the
/// channel, so renaming one there means renaming it here.
///
/// Every field is optional-by-default rather than zeroed, because the
/// difference matters on a menu bar: a missing summary must draw nothing, where
/// a zeroed one would draw `$0.00` and claim a day you spent nothing. Only
/// `generatedAt` is required — a summary with no timestamp cannot be aged.
struct AiUsageSummary {
  /// Bumped when the shape changes. A summary written by an older build is
  /// discarded rather than half-read.
  ///
  /// Must match `AiUsageSummary.version` in
  /// `lib/features/ai_usage/data/models/ai_usage_summary.dart`. A mismatch is
  /// not a partial read — `fromMap` rejects the whole summary, and the status
  /// item quietly falls back to a bare glyph with nothing to say why.
  ///
  /// 2 added `windows`, the per-provider limit rows the popover draws. Nothing
  /// here reads them: they cross this channel on their way to the second
  /// Flutter engine, which is what `raw` is for.
  static let version = 2

  var generatedAt: Date
  var tokensToday = 0
  var costToday = 0.0
  var repliesToday = 0
  var sessionsToday = 0

  /// When the current five-hour block opened, or nil if not inside one.
  ///
  /// Inferred from where activity clusters, because neither CLI writes its
  /// limit down. Enough for "how much since I sat down"; **not** enough for a
  /// percentage, which is why the block readout style draws elapsed *time*.
  var blockStartsAt: Date?
  var blockTokens = 0
  var blockCost = 0.0
  var costLastSevenDays = 0.0

  /// Some of the tokens above have no published rate, so the cost is a floor.
  var hasUnpricedModels = false

  /// The raw map, kept so the popover can be handed exactly what arrived
  /// without this struct having to model the parts only Dart reads.
  var raw: [String: Any] = [:]

  static func fromMap(_ map: [String: Any]) -> AiUsageSummary? {
    guard map["version"] as? Int == version,
          let stamp = map["generated_at"] as? String,
          let generatedAt = Self.date(from: stamp)
    else { return nil }

    var summary = AiUsageSummary(generatedAt: generatedAt)
    summary.tokensToday = map["tokens_today"] as? Int ?? 0
    summary.costToday = map["cost_today"] as? Double ?? 0
    summary.repliesToday = map["replies_today"] as? Int ?? 0
    summary.sessionsToday = map["sessions_today"] as? Int ?? 0
    if let block = map["block_starts_at"] as? String {
      summary.blockStartsAt = Self.date(from: block)
    }
    summary.blockTokens = map["block_tokens"] as? Int ?? 0
    summary.blockCost = map["block_cost"] as? Double ?? 0
    summary.costLastSevenDays = map["cost_last_seven_days"] as? Double ?? 0
    summary.hasUnpricedModels = map["has_unpriced_models"] as? Bool ?? false
    summary.raw = map
    return summary
  }

  /// True once the summary is old enough that its "today" may not be today.
  ///
  /// The main window can be shut for hours with the popover still reachable, so
  /// a figure drawn from this morning's sweep is a claim about a day that has
  /// since moved on. Past this the bar shows the icon alone rather than a
  /// number that has quietly stopped being true.
  func isStale(at now: Date = Date()) -> Bool {
    if now.timeIntervalSince(generatedAt) > 60 * 30 { return true }
    return !Calendar.current.isDate(generatedAt, inSameDayAs: now)
  }

  /// How far into the current block, 0–1, or nil when not inside one.
  func blockElapsed(at now: Date = Date()) -> Double? {
    guard let start = blockStartsAt else { return nil }
    let elapsed = now.timeIntervalSince(start) / AiUsageStore.blockLength
    return min(max(elapsed, 0), 1)
  }

  private static let formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    // Dart's `toIso8601String` emits fractional seconds; the default options do
    // not parse them, and the whole summary would be dropped over three digits.
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  private static func date(from raw: String) -> Date? {
    if let parsed = formatter.date(from: raw) { return parsed }
    // Dart omits the fraction when it happens to be zero.
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: raw)
  }
}

/// Holds the last summary, in memory and on disk.
///
/// On disk for the same reason `NetworkStore` reads `settings.json` itself: the
/// status item is drawn before any Flutter engine has finished starting, and a
/// bar that is blank — or worse, wrong — for the first second of every launch
/// is a bug the user can see.
final class AiUsageStore {
  static let shared = AiUsageStore()

  /// Matches `kBlockLength` in
  /// `lib/features/ai_usage/data/models/usage_window.dart`.
  static let blockLength: TimeInterval = 5 * 60 * 60

  /// Posted when a fresh summary lands, so the menu bar item can redraw itself
  /// without the channel needing to know it exists.
  static let didChange = Notification.Name("TidyAiUsageDidChange")

  private(set) var summary: AiUsageSummary?
  private var loaded = false

  private init() {}

  func load() {
    guard !loaded else { return }
    loaded = true
    AppSupport.migrate()
    summary = Self.readFromDisk()
  }

  func publish(_ summary: AiUsageSummary) {
    load()
    self.summary = summary
    writeToDisk(summary)
    NotificationCenter.default.post(name: Self.didChange, object: nil)
  }

  /// What the popover should draw, or nil when there is nothing honest to say.
  func current() -> AiUsageSummary? {
    load()
    guard let summary, !summary.isStale() else { return nil }
    return summary
  }

  // MARK: - Disk

  private static var file: URL? {
    guard let support = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first else { return nil }
    return support
      .appendingPathComponent(AppSupport.directoryName, isDirectory: true)
      .appendingPathComponent("ai_usage_summary.json")
  }

  private static func readFromDisk() -> AiUsageSummary? {
    guard let file,
          let data = try? Data(contentsOf: file),
          let map = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else { return nil }
    return AiUsageSummary.fromMap(map)
  }

  /// Native rather than Dart, so there is one writer. Both engines can publish
  /// in principle; only this file ever touches the bytes.
  private func writeToDisk(_ summary: AiUsageSummary) {
    guard let file = Self.file,
          let data = try? JSONSerialization.data(withJSONObject: summary.raw)
    else { return }
    do {
      try data.write(to: file, options: .atomic)
    } catch {
      NSLog("AI usage: cannot write the summary: \(error.localizedDescription)")
    }
  }
}

/// Dart's window onto [AiUsageStore].
///
/// Registered on **both** Flutter engines. The main window publishes, because
/// it is the only one with an `AiUsageService`; the popover reads, so its panel
/// and the menu bar draw the same figures rather than two opinions.
enum AiUsageChannel {
  static let channelName = "com.yunweneric.tidy/ai_usage"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "publish":
        guard let map = call.arguments as? [String: Any],
              let summary = AiUsageSummary.fromMap(map)
        else {
          result(FlutterError(
            code: "bad_summary",
            message: "The usage summary was missing or of another version.",
            details: nil
          ))
          return
        }
        AiUsageStore.shared.publish(summary)
        result(nil)

      case "summary":
        // `raw`, not a rebuilt map: the popover reads fields this struct does
        // not model, and round-tripping through it would silently drop them.
        result(AiUsageStore.shared.current()?.raw)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

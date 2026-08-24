import Foundation

/// How the menu bar item draws itself. Raw values cross the channel and land in
/// the Dart `NetworkMenuBarStyle` enum, so they must stay in step with it.
enum NetworkMenuBarStyle: String {
  case twoLine
  case sparkline
  case compact
}

/// The network preferences, as the Dart side last wrote them to `settings.json`.
///
/// Read natively at launch for the same reason `ClipboardPrefs` is: the menu bar
/// item is created before any Flutter engine has run, and an item that appears
/// in the wrong style — or appears at all after the user turned it off — for the
/// first second of every launch is a bug the user can see.
///
/// **The keys here must match `AppSettings` in
/// `lib/core/settings/app_settings.dart`.** Renaming one there means renaming it
/// here.
struct NetworkPrefs {
  var menuBarEnabled = true
  var menuBarStyle = NetworkMenuBarStyle.twoLine

  /// Bits per second rather than bytes. Off by default: the rest of the app
  /// talks in bytes, and a cleaner that reports 36 Mbps next to a 4.5 MB cache
  /// is asking the user to convert between units in their head.
  var useBits = false

  static func fromMap(_ map: [String: Any]) -> NetworkPrefs {
    var prefs = NetworkPrefs()
    if let value = map["networkMenuBarEnabled"] as? Bool { prefs.menuBarEnabled = value }
    if let raw = map["networkMenuBarStyle"] as? String,
       let style = NetworkMenuBarStyle(rawValue: raw) {
      prefs.menuBarStyle = style
    }
    if let value = map["networkUseBits"] as? Bool { prefs.useBits = value }
    return prefs
  }
}

/// One period's traffic.
private struct NetworkBucket {
  /// The period's start, epoch seconds.
  var start: Double
  var down: Int
  var up: Int

  /// Per-interface split. Carried on daily rows only — see the class comment.
  var byInterface: [String: [Int]]

  func toMap(includeInterfaces: Bool) -> [String: Any] {
    var map: [String: Any] = ["t": Int(start), "d": down, "u": up]
    if includeInterfaces, !byInterface.isEmpty { map["if"] = byInterface }
    return map
  }

  static func fromMap(_ map: [String: Any]) -> NetworkBucket? {
    guard let start = map["t"] as? Int else { return nil }
    var byInterface: [String: [Int]] = [:]
    if let raw = map["if"] as? [String: [Int]] {
      byInterface = raw.filter { $0.value.count == 2 }
    }
    return NetworkBucket(
      start: Double(start),
      down: map["d"] as? Int ?? 0,
      up: map["u"] as? Int ?? 0,
      byInterface: byInterface
    )
  }
}

/// The traffic history, and the preferences the menu bar needs before Flutter
/// starts.
///
/// Native rather than Dart for the reason `ClipboardStore` documents: two
/// Flutter engines in separate isolates would be two writers racing, and the
/// recording has to keep going while neither of them is doing anything.
///
/// **Three tiers, one file.** Per-minute rows for two days, hourly for three
/// months, daily forever. Every tier is fed from the same sample rather than
/// rolled up out of the tier below it — a rollup is one more thing to get wrong
/// at a period boundary, and the sample is right there.
///
/// The per-interface split is kept on daily rows only. "Wi-Fi or Ethernet this
/// month" is a question someone asks; "which interface during this particular
/// minute" is not, and carrying the map on all three tiers would triple a file
/// that is rewritten every minute.
///
/// **What is not here is as important as what is.** Tidy records only while Tidy
/// is running, so a missing bucket means *not recorded*, never zero. Every
/// minute the app is up gets a row even when nothing moved, which is what makes
/// absence meaningful — and what lets the page draw a gap instead of claiming
/// the user used nothing overnight.
final class NetworkStore {
  static let shared = NetworkStore()

  private static let formatVersion = 1

  private init() {}

  private(set) var prefs = NetworkPrefs()

  /// Per-minute rows, kept for two days.
  private var minutes: [NetworkBucket] = []

  /// Hourly rows, kept for ninety days.
  private var hours: [NetworkBucket] = []

  /// Daily rows, kept indefinitely. A row is about 120 bytes, so a decade of
  /// them is under half a megabyte.
  private var days: [NetworkBucket] = []

  private let minuteRetention: TimeInterval = 48 * 60 * 60
  private let hourRetention: TimeInterval = 90 * 24 * 60 * 60

  /// When this store first recorded anything. The page's coverage line, and the
  /// reason it can say "since 3 August" rather than implying it knows about
  /// everything before that.
  private(set) var startedAt: Double?

  private var loaded = false

  private let io = DispatchQueue(label: "com.yunweneric.tidy.network", qos: .utility)
  private var pendingWrite: DispatchWorkItem?

  // MARK: - Paths

  private var directory: URL? {
    guard let support = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first else { return nil }

    let dir = support
      .appendingPathComponent(AppSupport.directoryName, isDirectory: true)
      .appendingPathComponent("network", isDirectory: true)

    do {
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    } catch {
      NSLog("Network: cannot create the store directory: \(error.localizedDescription)")
      return nil
    }
    return dir
  }

  private var historyFile: URL? { directory?.appendingPathComponent("history.json") }

  private static var settingsFile: URL? {
    guard let support = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first else { return nil }
    return support
      .appendingPathComponent(AppSupport.directoryName, isDirectory: true)
      .appendingPathComponent("settings.json")
  }

  // MARK: - Lifecycle

  /// Never throws: a corrupt history costs the charts, which is a nuisance, not
  /// the app, which is not.
  func load() {
    guard !loaded else { return }
    loaded = true
    AppSupport.migrate()

    prefs = Self.readPrefsFromSettings() ?? NetworkPrefs()

    guard let file = historyFile,
          let data = try? Data(contentsOf: file),
          let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          root["formatVersion"] as? Int == Self.formatVersion
    else { return }

    minutes = Self.buckets(root["minutes"])
    hours = Self.buckets(root["hours"])
    days = Self.buckets(root["days"])
    startedAt = root["startedAt"] as? Double

    // Retention that elapsed while the app was shut.
    prune()
  }

  private static func buckets(_ raw: Any?) -> [NetworkBucket] {
    guard let rows = raw as? [[String: Any]] else { return [] }
    return rows.compactMap(NetworkBucket.fromMap).sorted { $0.start < $1.start }
  }

  private static func readPrefsFromSettings() -> NetworkPrefs? {
    guard let file = settingsFile,
          let data = try? Data(contentsOf: file),
          let map = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else { return nil }
    return NetworkPrefs.fromMap(map)
  }

  func configure(_ prefs: NetworkPrefs) {
    self.prefs = prefs
  }

  // MARK: - Recording

  /// Folds one tick into all three tiers.
  ///
  /// Called on the main thread from `NetworkMonitor`'s timer, once a second. The
  /// work is three dictionary-free array touches; the disk write is debounced
  /// separately.
  func record(_ sample: NetworkSample) {
    load()

    let at = sample.atSeconds
    // A tick with nothing in it still opens its bucket. That is the whole basis
    // for "a missing bucket means the app was not running".
    add(sample, to: &minutes, start: Self.floor(at, to: 60), withInterfaces: false)
    add(sample, to: &hours, start: Self.floor(at, to: 3600), withInterfaces: false)
    add(sample, to: &days, start: Self.startOfDay(at), withInterfaces: true)

    if startedAt == nil { startedAt = at }

    prune()
    scheduleWrite()
  }

  private func add(
    _ sample: NetworkSample,
    to tier: inout [NetworkBucket],
    start: Double,
    withInterfaces: Bool
  ) {
    // Appending in order and only ever touching the tail: samples arrive in
    // time order, so the open bucket is always the last one.
    if var open = tier.last, open.start == start {
      open.down += sample.downBytes
      open.up += sample.upBytes
      if withInterfaces { Self.merge(sample, into: &open.byInterface) }
      tier[tier.count - 1] = open
      return
    }

    // Out-of-order arrival: the clock moved backwards (NTP, or the user changed
    // it). Fold it into the bucket it belongs to rather than starting a second
    // one with the same start, which would double every reader's totals.
    if let index = tier.lastIndex(where: { $0.start == start }) {
      tier[index].down += sample.downBytes
      tier[index].up += sample.upBytes
      if withInterfaces { Self.merge(sample, into: &tier[index].byInterface) }
      return
    }

    var bucket = NetworkBucket(start: start, down: sample.downBytes, up: sample.upBytes, byInterface: [:])
    if withInterfaces { Self.merge(sample, into: &bucket.byInterface) }
    tier.append(bucket)
    tier.sort { $0.start < $1.start }
  }

  private static func merge(_ sample: NetworkSample, into split: inout [String: [Int]]) {
    for interface in sample.interfaces where interface.downBytes > 0 || interface.upBytes > 0 {
      var totals = split[interface.name] ?? [0, 0]
      totals[0] += interface.downBytes
      totals[1] += interface.upBytes
      split[interface.name] = totals
    }
  }

  private func prune() {
    let now = Date().timeIntervalSince1970
    minutes.removeAll { now - $0.start > minuteRetention }
    hours.removeAll { now - $0.start > hourRetention }
    // Daily rows are never pruned. That is the point of the tier.
  }

  func reset() {
    load()
    minutes = []
    hours = []
    days = []
    startedAt = nil
    flush()
  }

  // MARK: - Reading back

  /// The buckets behind one range, already at the granularity the chart wants.
  ///
  /// Aggregation happens here rather than in Dart so a year of daily rows is
  /// twelve numbers by the time it crosses the channel, not three hundred and
  /// sixty-five.
  func series(range: String) -> [String: Any] {
    load()

    let now = Date().timeIntervalSince1970
    let granularity: String
    let rows: [NetworkBucket]
    var includeInterfaces = false

    switch range {
    case "hour":
      granularity = "minute"
      rows = minutes.filter { now - $0.start <= 60 * 60 }
    case "day":
      granularity = "hour"
      rows = hours.filter { now - $0.start <= 24 * 60 * 60 }
    case "week":
      granularity = "day"
      rows = days.filter { now - $0.start <= 7 * 24 * 60 * 60 }
      includeInterfaces = true
    case "month":
      granularity = "day"
      rows = days.filter { now - $0.start <= 31 * 24 * 60 * 60 }
      includeInterfaces = true
    case "sixMonths":
      granularity = "week"
      rows = Self.groupByWeek(days.filter { now - $0.start <= 183 * 24 * 60 * 60 })
      includeInterfaces = true
    case "year":
      granularity = "month"
      rows = Self.groupByMonth(days.filter { now - $0.start <= 366 * 24 * 60 * 60 })
      includeInterfaces = true
    default: // "all"
      granularity = "month"
      rows = Self.groupByMonth(days)
      includeInterfaces = true
    }

    var totalDown = 0
    var totalUp = 0
    var split: [String: [Int]] = [:]
    for row in rows {
      totalDown += row.down
      totalUp += row.up
      for (name, totals) in row.byInterface {
        var existing = split[name] ?? [0, 0]
        existing[0] += totals[0]
        existing[1] += totals[1]
        split[name] = existing
      }
    }

    var payload: [String: Any] = [
      "range": range,
      "granularity": granularity,
      "buckets": rows.map { $0.toMap(includeInterfaces: false) },
      "totalDown": totalDown,
      "totalUp": totalUp,
    ]
    if includeInterfaces { payload["byInterface"] = split }
    if let startedAt { payload["startedAt"] = startedAt }
    return payload
  }

  /// Totals for the calendar day and calendar month the given instant falls in.
  /// Read straight off the daily tier so the tiles agree with the month chart.
  func headline() -> [String: Any] {
    load()

    let now = Date().timeIntervalSince1970
    let dayStart = Self.startOfDay(now)
    let monthStart = Self.startOfMonth(now)

    var today = [0, 0]
    var month = [0, 0]
    for row in days {
      if row.start >= monthStart {
        month[0] += row.down
        month[1] += row.up
      }
      if row.start >= dayStart {
        today[0] += row.down
        today[1] += row.up
      }
    }

    var payload: [String: Any] = [
      "todayDown": today[0],
      "todayUp": today[1],
      "monthDown": month[0],
      "monthUp": month[1],
    ]
    if let startedAt { payload["startedAt"] = startedAt }
    if let busiest = days.max(by: { $0.down + $0.up < $1.down + $1.up }) {
      payload["busiestDay"] = Int(busiest.start)
      payload["busiestDayBytes"] = busiest.down + busiest.up
    }
    return payload
  }

  // MARK: - Aggregation

  private static func groupByWeek(_ rows: [NetworkBucket]) -> [NetworkBucket] {
    group(rows) { start in
      let components = calendar.dateComponents(
        [.yearForWeekOfYear, .weekOfYear],
        from: Date(timeIntervalSince1970: start)
      )
      return calendar.date(from: components)?.timeIntervalSince1970 ?? start
    }
  }

  private static func groupByMonth(_ rows: [NetworkBucket]) -> [NetworkBucket] {
    group(rows) { start in startOfMonth(start) }
  }

  private static func group(
    _ rows: [NetworkBucket],
    by key: (Double) -> Double
  ) -> [NetworkBucket] {
    var grouped: [Double: NetworkBucket] = [:]
    for row in rows {
      let start = key(row.start)
      var bucket = grouped[start] ?? NetworkBucket(start: start, down: 0, up: 0, byInterface: [:])
      bucket.down += row.down
      bucket.up += row.up
      for (name, totals) in row.byInterface {
        var existing = bucket.byInterface[name] ?? [0, 0]
        existing[0] += totals[0]
        existing[1] += totals[1]
        bucket.byInterface[name] = existing
      }
      grouped[start] = bucket
    }
    return grouped.values.sorted { $0.start < $1.start }
  }

  // MARK: - Time

  /// The user's calendar, not UTC. "Today" has to mean the day they are having.
  private static let calendar = Calendar.current

  private static func floor(_ seconds: Double, to period: Double) -> Double {
    (seconds / period).rounded(.down) * period
  }

  private static func startOfDay(_ seconds: Double) -> Double {
    calendar.startOfDay(for: Date(timeIntervalSince1970: seconds)).timeIntervalSince1970
  }

  private static func startOfMonth(_ seconds: Double) -> Double {
    let components = calendar.dateComponents(
      [.year, .month],
      from: Date(timeIntervalSince1970: seconds)
    )
    return calendar.date(from: components)?.timeIntervalSince1970 ?? startOfDay(seconds)
  }

  // MARK: - Persistence

  /// Coalesces a minute of ticks into one write. Sixty atomic rewrites a minute
  /// of a quarter-megabyte file would be exactly the kind of thing this app
  /// exists to find on someone else's Mac.
  private func scheduleWrite() {
    // Leading-edge debounce, unlike the clipboard's trailing one: ticks never
    // stop, so a trailing debounce would keep pushing the write out and the file
    // would only ever be written on quit.
    guard pendingWrite == nil else { return }
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.pendingWrite = nil
      let snapshot = self.snapshot()
      self.io.async { self.write(snapshot) }
    }
    pendingWrite = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: work)
  }

  func flush() {
    pendingWrite?.cancel()
    pendingWrite = nil
    let snapshot = snapshot()
    io.sync { write(snapshot) }
  }

  private func snapshot() -> [String: Any] {
    var root: [String: Any] = [
      "formatVersion": Self.formatVersion,
      "minutes": minutes.map { $0.toMap(includeInterfaces: false) },
      "hours": hours.map { $0.toMap(includeInterfaces: false) },
      "days": days.map { $0.toMap(includeInterfaces: true) },
    ]
    if let startedAt { root["startedAt"] = startedAt }
    return root
  }

  private func write(_ root: [String: Any]) {
    guard let file = historyFile else { return }
    do {
      let data = try JSONSerialization.data(withJSONObject: root)
      try data.write(to: file, options: .atomic)
    } catch {
      NSLog("Network: could not write the history: \(error.localizedDescription)")
    }
  }
}

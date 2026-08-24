import Foundation

/// Running a command and waiting for it.
///
/// Deliberately a one-shot helper for user-initiated actions, not something to
/// call in a loop — per-item subprocess spawning is what the native sizing
/// walker exists to replace.
enum Shell {
  /// Exit status, or -1 if the process could not be launched at all.
  @discardableResult
  static func run(_ executable: String, _ arguments: [String]) -> Int32 {
    guard FileManager.default.isExecutableFile(atPath: executable) else { return -1 }

    let task = Process()
    task.executableURL = URL(fileURLWithPath: executable)
    task.arguments = arguments
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice

    do {
      try task.run()
      task.waitUntilExit()
      return task.terminationStatus
    } catch {
      return -1
    }
  }

  /// Standard output, or nil if the process could not be launched.
  static func capture(_ executable: String, _ arguments: [String]) -> String? {
    guard FileManager.default.isExecutableFile(atPath: executable) else { return nil }

    let task = Process()
    task.executableURL = URL(fileURLWithPath: executable)
    task.arguments = arguments
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice

    do {
      try task.run()
      // Read before waiting: a pipe that fills up deadlocks a process that is
      // still writing to it.
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      task.waitUntilExit()
      return String(data: data, encoding: .utf8)
    } catch {
      return nil
    }
  }
}

/// Routine macOS upkeep.
///
/// Availability is decided by probing the machine rather than by checking an
/// OS version: a task is offered when the tool that performs it is actually
/// present, which is both more accurate and does not rot with each release.
///
/// Most of these want root. Until the privileged helper lands they are listed
/// with `requiresAdmin` set and refused here as well as in the UI — a check
/// that only exists in the interface is not a check.
enum Maintenance {

  private static let lsregister =
    "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

  static func tasks() -> [[String: Any]] {
    var tasks: [[String: Any]] = []

    tasks.append(
      task(
        id: "rebuildLaunchServices",
        requiresAdmin: false,
        available: FileManager.default.isExecutableFile(atPath: lsregister),
        reason: "The Launch Services tool is not on this Mac."
      )
    )

    tasks.append(
      task(
        id: "flushFontCaches",
        requiresAdmin: false,
        available: FileManager.default.isExecutableFile(atPath: "/usr/bin/atsutil"),
        reason: "The font tool is not on this Mac."
      )
    )

    let mailIndex = mailEnvelopeIndex()
    tasks.append(
      task(
        id: "speedUpMail",
        requiresAdmin: false,
        available: mailIndex != nil && FileManager.default.isExecutableFile(atPath: "/usr/bin/sqlite3"),
        reason: mailIndexReason()
      )
    )

    tasks.append(
      task(
        id: "flushDns",
        requiresAdmin: true,
        available: FileManager.default.isExecutableFile(atPath: "/usr/bin/dscacheutil"),
        reason: "The DNS tool is not on this Mac."
      )
    )

    tasks.append(
      task(
        id: "reindexSpotlight",
        requiresAdmin: true,
        available: FileManager.default.isExecutableFile(atPath: "/usr/bin/mdutil"),
        reason: "Spotlight’s tool is not on this Mac."
      )
    )

    tasks.append(
      task(
        id: "thinSnapshots",
        requiresAdmin: true,
        available: FileManager.default.isExecutableFile(atPath: "/usr/bin/tmutil"),
        reason: "Time Machine’s tool is not on this Mac."
      )
    )

    // Periodic scripts were dropped from later macOS releases, so this is a
    // filesystem check rather than a version comparison that would need editing
    // every autumn.
    if FileManager.default.isExecutableFile(atPath: "/usr/sbin/periodic") {
      tasks.append(task(id: "periodicScripts", requiresAdmin: true, available: true, reason: nil))
    }

    // `purge` on Apple Silicon is a placebo: the memory compressor and unified
    // memory make a forced page-out meaningless. Hiding it beats shipping a
    // button that does nothing.
    if !isAppleSilicon() && FileManager.default.isExecutableFile(atPath: "/usr/sbin/purge") {
      tasks.append(task(id: "freeRam", requiresAdmin: true, available: true, reason: nil))
    }

    return tasks
  }

  private static func task(
    id: String,
    requiresAdmin: Bool,
    available: Bool,
    reason: String?
  ) -> [String: Any] {
    var payload: [String: Any] = [
      "id": id,
      "requiresAdmin": requiresAdmin,
      "available": available,
    ]
    if !available, let reason { payload["unavailableReason"] = reason }
    return payload
  }

  // MARK: - Running

  static func run(id: String) -> [String: Any] {
    switch id {
    case "rebuildLaunchServices":
      let status = Shell.run(lsregister, [
        "-kill", "-r", "-domain", "local", "-domain", "system", "-domain", "user",
      ])
      return status == 0
        ? done("Rebuilt. The “Open With” menu should stop showing duplicates.")
        : failed("The rebuild did not finish (error \(status)).")

    case "flushFontCaches":
      let status = Shell.run("/usr/bin/atsutil", ["databases", "-removeUser"])
      return status == 0
        ? done("Font caches cleared. macOS rebuilds them as fonts are used.")
        : failed("The font caches could not be cleared (error \(status)).")

    case "speedUpMail":
      return vacuumMail()

    case "flushDns", "reindexSpotlight", "thinSnapshots", "periodicScripts", "freeRam":
      // Belt and braces: the UI disables these, and so does this.
      return failed("This one needs administrator rights, which Tidy does not have yet.")

    default:
      return failed("Tidy does not know how to run that.")
    }
  }

  /// Compacting Mail's index is the one maintenance task with a number attached
  /// to it, so it reports the number rather than a vague "done".
  private static func vacuumMail() -> [String: Any] {
    guard let index = mailEnvelopeIndex() else {
      return failed("Mail’s index is not where it usually lives on this Mac.")
    }

    let before = fileSize(index)
    let status = Shell.run("/usr/bin/sqlite3", [index, "vacuum;"])
    guard status == 0 else {
      return failed("Mail’s index could not be compacted (error \(status)). Quit Mail and try again.")
    }

    let after = fileSize(index)
    let freed = max(0, before - after)
    var payload = done(
      freed > 0
        ? "Mail’s index is smaller now."
        : "Mail’s index was already compact — nothing to reclaim."
    )
    payload["freedBytes"] = freed
    return payload
  }

  private static func done(_ message: String) -> [String: Any] {
    ["ok": true, "message": message]
  }

  private static func failed(_ message: String) -> [String: Any] {
    ["ok": false, "message": message]
  }

  // MARK: - Probes

  /// `~/Library/Mail/V<n>/MailData/Envelope Index`, where `<n>` moves with each
  /// major Mail release.
  private static func mailEnvelopeIndex() -> String? {
    let root = "\(NSHomeDirectory())/Library/Mail"
    guard let versions = try? FileManager.default.contentsOfDirectory(atPath: root) else {
      return nil
    }
    // Newest format directory first — V10 sorts before V9 alphabetically, so
    // compare the number rather than the string.
    let ordered = versions
      .filter { $0.hasPrefix("V") }
      .sorted { lhs, rhs in
        (Int(lhs.dropFirst()) ?? 0) > (Int(rhs.dropFirst()) ?? 0)
      }
    for version in ordered {
      let candidate = "\(root)/\(version)/MailData/Envelope Index"
      if FileManager.default.fileExists(atPath: candidate) { return candidate }
    }
    return nil
  }

  /// `~/Library/Mail` is TCC-protected, so "no index" and "not allowed to look"
  /// are different answers and the user deserves the right one.
  private static func mailIndexReason() -> String {
    let root = "\(NSHomeDirectory())/Library/Mail"
    guard FileManager.default.fileExists(atPath: root) else {
      return "Mail is not set up on this Mac."
    }
    if (try? FileManager.default.contentsOfDirectory(atPath: root)) == nil {
      return "Mail’s index is behind Full Disk Access."
    }
    return "Mail’s index is not where it usually lives on this Mac."
  }

  private static func fileSize(_ path: String) -> Int {
    let attributes = try? FileManager.default.attributesOfItem(atPath: path)
    return (attributes?[.size] as? NSNumber)?.intValue ?? 0
  }

  private static func isAppleSilicon() -> Bool {
    var value: Int32 = 0
    var size = MemoryLayout<Int32>.size
    guard sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 else { return false }
    return value == 1
  }
}

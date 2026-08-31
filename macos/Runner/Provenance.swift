import Foundation
import SQLite3

/// Where a file came from, as macOS recorded it at the time.
///
/// Two sources, and the cheap one answers most of it. Every file downloaded by
/// a quarantine-aware app carries a `com.apple.quarantine` extended attribute
/// naming the app that fetched it and when. The system also keeps a database of
/// the same events that additionally holds the URL — but only some xattrs carry
/// the event id needed to join to it.
///
/// **This type only ever reads.** Removing a quarantine flag is the one thing on
/// the Protection page that would leave the Mac measurably less safe, so the
/// code to do it stays where it belongs — in `Updater`, applied only to a build
/// this app just verified itself.
enum Provenance {

  /// The quarantine attribute for many paths, keyed by path.
  ///
  /// Microseconds each; the whole of `/Applications` costs less than a
  /// millisecond. Paths with no attribute are simply absent from the result,
  /// which is the common case — many installers clear it, so "no record" is not
  /// evidence of anything and the UI says so.
  ///
  /// The value is `flagsHex;timeHex;AgentName;EventUUID`, and the last field is
  /// frequently empty.
  static func quarantine(paths: [String]) -> [String: [String: Any]] {
    var found: [String: [String: Any]] = [:]

    for path in paths {
      guard let raw = attribute(named: "com.apple.quarantine", of: path) else { continue }
      let fields = raw.components(separatedBy: ";")
      guard fields.count >= 3 else { continue }

      var entry: [String: Any] = [:]
      // Seconds since the epoch, written in hex.
      if let seconds = UInt32(fields[1], radix: 16) {
        entry["at"] = Double(seconds)
      }
      let agent = fields[2].trimmingCharacters(in: .whitespaces)
      if !agent.isEmpty { entry["agent"] = agent }
      if fields.count >= 4 {
        let event = fields[3].trimmingCharacters(in: .whitespaces)
        if !event.isEmpty { entry["eventId"] = event }
      }
      if !entry.isEmpty { found[path] = entry }
    }

    return found
  }

  /// The download history LaunchServices keeps, newest first.
  ///
  /// One read-only `SELECT`. `SQLite3` is a system module in the macOS SDK — no
  /// package, no pod, nothing added to `pubspec.yaml`; the project's rule about
  /// SQLite is about Dart dependencies and the build they drag in, and none of
  /// that applies to forty lines of C API behind a channel.
  static func downloadEvents(limit: Int) -> [String: Any] {
    guard let support = FileManager.default.urls(
      for: .libraryDirectory,
      in: .userDomainMask
    ).first else {
      return ["error": "This Mac reports no Library folder."]
    }

    let file = support
      .appendingPathComponent("Preferences", isDirectory: true)
      .appendingPathComponent("com.apple.LaunchServices.QuarantineEventsV2")

    guard FileManager.default.fileExists(atPath: file.path) else {
      return ["events": [], "total": 0]
    }

    guard let database = open(file) else {
      // A denied or locked read is not an empty history. Reported as an error so
      // the page can say "could not read" rather than "you have downloaded
      // nothing", which is the lie this whole module exists not to tell.
      return ["error": "macOS would not let Tidy read the download history."]
    }
    defer { sqlite3_close(database) }

    var events: [[String: Any]] = []
    var total = 0

    var counter: OpaquePointer?
    if sqlite3_prepare_v2(
      database, "SELECT COUNT(*) FROM LSQuarantineEvent", -1, &counter, nil
    ) == SQLITE_OK, sqlite3_step(counter) == SQLITE_ROW {
      total = Int(sqlite3_column_int(counter, 0))
    }
    sqlite3_finalize(counter)

    let query = """
      SELECT LSQuarantineTimeStamp, LSQuarantineAgentName, LSQuarantineDataURLString,
             LSQuarantineEventIdentifier
      FROM LSQuarantineEvent
      ORDER BY LSQuarantineTimeStamp DESC
      LIMIT ?
      """

    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
      return ["error": "The download history is in a shape Tidy does not recognise."]
    }
    defer { sqlite3_finalize(statement) }

    sqlite3_bind_int(statement, 1, Int32(limit))

    while sqlite3_step(statement) == SQLITE_ROW {
      var row: [String: Any] = [:]
      // Core Data's reference date, not the Unix epoch — 31 years apart, which
      // would put every download in 1970 if it were read as the latter.
      if sqlite3_column_type(statement, 0) != SQLITE_NULL {
        let stamp = sqlite3_column_double(statement, 0)
        row["at"] = stamp + Date.timeIntervalBetween1970AndReferenceDate
      }
      if let agent = text(statement, 1) { row["agent"] = agent }
      if let url = text(statement, 2) { row["url"] = url }
      if let event = text(statement, 3) { row["eventId"] = event }
      events.append(row)
    }

    return ["events": events, "total": total]
  }

  // MARK: - Plumbing

  /// Opens read-only, and falls back to a copy.
  ///
  /// A read-only open of a database in WAL mode still wants to create a `-shm`
  /// alongside it, which fails when the directory is not writable or the file is
  /// held open by LaunchServices. Copying to a scratch directory and opening
  /// that is the standard way out, and costs a megabyte for the length of one
  /// query.
  private static func open(_ file: URL) -> OpaquePointer? {
    var database: OpaquePointer?
    let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX

    if sqlite3_open_v2(file.path, &database, flags, nil) == SQLITE_OK, let database {
      // The open succeeds lazily; the first read is what actually fails.
      var probe: OpaquePointer?
      let ok = sqlite3_prepare_v2(
        database, "SELECT COUNT(*) FROM LSQuarantineEvent", -1, &probe, nil
      ) == SQLITE_OK && sqlite3_step(probe) == SQLITE_ROW
      sqlite3_finalize(probe)
      if ok { return database }
      sqlite3_close(database)
    }

    let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("tidy-quarantine-\(UUID().uuidString).sqlite")
    guard (try? FileManager.default.copyItem(at: file, to: scratch)) != nil else { return nil }
    defer { try? FileManager.default.removeItem(at: scratch) }

    var copy: OpaquePointer?
    guard sqlite3_open_v2(scratch.path, &copy, flags, nil) == SQLITE_OK else {
      sqlite3_close(copy)
      return nil
    }
    return copy
  }

  private static func text(_ statement: OpaquePointer?, _ column: Int32) -> String? {
    guard sqlite3_column_type(statement, column) != SQLITE_NULL,
          let raw = sqlite3_column_text(statement, column) else { return nil }
    let value = String(cString: raw)
    return value.isEmpty ? nil : value
  }

  private static func attribute(named name: String, of path: String) -> String? {
    let size = path.withCString { getxattr($0, name, nil, 0, 0, XATTR_NOFOLLOW) }
    guard size > 0 else { return nil }

    var buffer = [UInt8](repeating: 0, count: size)
    let read = path.withCString { key in
      buffer.withUnsafeMutableBytes { destination in
        getxattr(key, name, destination.baseAddress, size, 0, XATTR_NOFOLLOW)
      }
    }
    guard read > 0 else { return nil }
    return String(bytes: buffer[0..<read], encoding: .utf8)
  }
}

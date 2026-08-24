import Foundation

/// Reading and toggling launchd items — the things that start themselves.
///
/// Three directories matter to a user-space app:
///
/// - `~/Library/LaunchAgents` — the user's own. Ours to enable, disable and
///   remove without any elevation.
/// - `/Library/LaunchAgents` and `/Library/LaunchDaemons` — machine-wide and
///   root-owned. Listed and explained, never touched, until the privileged
///   helper exists.
///
/// `/System/Library/Launch*` is deliberately not scanned. Those are Apple's own
/// and disabling one is how a Mac stops booting properly; a cleaner has no
/// business offering it.
enum LaunchItems {

  // MARK: - Roots

  private static var userAgentsDir: String { "\(NSHomeDirectory())/Library/LaunchAgents" }
  private static let globalAgentsDir = "/Library/LaunchAgents"
  private static let globalDaemonsDir = "/Library/LaunchDaemons"

  // MARK: - Listing

  static func list() -> [[String: Any]] {
    let overrides = disabledOverrides()

    var items: [[String: Any]] = []
    items += scan(userAgentsDir, kind: "agent", scope: "user", overrides: overrides)
    items += scan(globalAgentsDir, kind: "agent", scope: "global", overrides: overrides)
    items += scan(globalDaemonsDir, kind: "daemon", scope: "global", overrides: overrides)
    return items
  }

  private static func scan(
    _ directory: String,
    kind: String,
    scope: String,
    overrides: [String: Bool]
  ) -> [[String: Any]] {
    let fm = FileManager.default
    guard let names = try? fm.contentsOfDirectory(atPath: directory) else {
      // A denied or absent directory is not an empty one, but for these three
      // roots absent is by far the likelier cause and neither is actionable.
      return []
    }

    var items: [[String: Any]] = []
    for name in names where name.hasSuffix(".plist") {
      let path = "\(directory)/\(name)"
      if let item = describe(path: path, kind: kind, scope: scope, overrides: overrides) {
        items.append(item)
      }
    }
    return items
  }

  private static func describe(
    path: String,
    kind: String,
    scope: String,
    overrides: [String: Bool]
  ) -> [String: Any]? {
    let url = URL(fileURLWithPath: path)
    let fallbackLabel = url.deletingPathExtension().lastPathComponent

    // Covers both XML and binary plists; `NSDictionary(contentsOf:)` is
    // deprecated on current SDKs and swallows the reason it failed.
    let plist: [String: Any]?
    if let data = try? Data(contentsOf: url) {
      plist = (try? PropertyListSerialization.propertyList(
        from: data,
        options: [],
        format: nil
      )) as? [String: Any]
    } else {
      plist = nil
    }

    let label = (plist?["Label"] as? String) ?? fallbackLabel
    let program = resolveProgram(plist)

    // A relative or bare command ("node", "sh") cannot be checked against the
    // filesystem without guessing at PATH, and guessing wrong would label a
    // working item as broken. Say "unknown" instead.
    var programMissing = false
    var programUnknown = false
    if let program {
      if program.hasPrefix("/") {
        programMissing = !FileManager.default.fileExists(atPath: program)
      } else {
        programUnknown = true
      }
    } else {
      programUnknown = true
    }

    let modified = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date

    var payload: [String: Any] = [
      "path": path,
      "label": label,
      "kind": kind,
      "scope": scope,
      "enabled": isEnabled(label: label, plist: plist, overrides: overrides),
      "runAtLoad": (plist?["RunAtLoad"] as? Bool) ?? false,
      "keepAlive": truthy(plist?["KeepAlive"]),
      "onDemandOnly": plist?["StartCalendarInterval"] == nil
        && plist?["StartInterval"] == nil
        && plist?["WatchPaths"] == nil,
      "hasSchedule": plist?["StartCalendarInterval"] != nil,
      "programMissing": programMissing,
      "programUnknown": programUnknown,
      "unreadable": plist == nil,
      // A plist that parses to nothing is what an uninstaller leaves behind
      // when it deletes the contents but not the file. launchd can start
      // nothing from it, so it is as dead as a missing program.
      "emptyStub": plist?.isEmpty ?? false,
      "requiresAdmin": scope != "user",
    ]

    if let program { payload["program"] = program }
    if let interval = plist?["StartInterval"] as? Int { payload["startIntervalSeconds"] = interval }
    if let watch = plist?["WatchPaths"] as? [String], !watch.isEmpty { payload["watchesPaths"] = true }
    if let modified { payload["modified"] = Int(modified.timeIntervalSince1970) }

    // The owning .app, when there is one, gives a real display name and an icon
    // instead of a reverse-DNS label nobody can read.
    if let program, let app = owningAppPath(program) {
      payload["appPath"] = app
      payload["name"] = displayName(ofApp: app)
    } else {
      payload["name"] = friendlyName(from: label)
    }

    return payload
  }

  /// `Program`, else the first entry of `ProgramArguments`.
  private static func resolveProgram(_ plist: [String: Any]?) -> String? {
    if let program = plist?["Program"] as? String, !program.isEmpty { return program }
    if let args = plist?["ProgramArguments"] as? [String], let first = args.first, !first.isEmpty {
      return first
    }
    return nil
  }

  /// `KeepAlive` is a Bool in simple plists and a dictionary of conditions in
  /// complicated ones. Either way, present means "launchd restarts this".
  private static func truthy(_ value: Any?) -> Bool {
    if let flag = value as? Bool { return flag }
    if let dict = value as? [String: Any] { return !dict.isEmpty }
    return false
  }

  /// launchd's override database wins over the plist's own `Disabled` key —
  /// that is the whole point of `launchctl disable`.
  private static func isEnabled(
    label: String,
    plist: [String: Any]?,
    overrides: [String: Bool]
  ) -> Bool {
    if let overridden = overrides[label] { return !overridden }
    return !((plist?["Disabled"] as? Bool) ?? false)
  }

  /// Labels the user has explicitly disabled or re-enabled, from
  /// `launchctl print-disabled`.
  ///
  /// The output format drifted between macOS versions — older builds print
  /// `=> true`, newer ones `=> disabled` — so both are accepted.
  private static func disabledOverrides() -> [String: Bool] {
    let output = Shell.capture("/bin/launchctl", ["print-disabled", "gui/\(getuid())"])
    guard let output else { return [:] }

    var overrides: [String: Bool] = [:]
    for line in output.split(separator: "\n") {
      guard let arrow = line.range(of: "=>") else { continue }
      let rawLabel = line[line.startIndex..<arrow.lowerBound]
        .trimmingCharacters(in: .whitespaces)
        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
      let verdict = line[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
      guard !rawLabel.isEmpty else { continue }
      overrides[rawLabel] = (verdict == "true" || verdict == "disabled")
    }
    return overrides
  }

  // MARK: - Naming

  /// Walks up from a binary to the `.app` that contains it, if any.
  private static func owningAppPath(_ program: String) -> String? {
    var url = URL(fileURLWithPath: program)
    while url.path != "/" && !url.path.isEmpty {
      if url.pathExtension == "app" { return url.path }
      let parent = url.deletingLastPathComponent()
      if parent.path == url.path { break }
      url = parent
    }
    return nil
  }

  private static func displayName(ofApp path: String) -> String {
    let bundle = Bundle(path: path)
    let info = bundle?.infoDictionary
    let name = (info?["CFBundleDisplayName"] as? String)
      ?? (info?["CFBundleName"] as? String)
    if let name, !name.isEmpty { return name }
    return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
  }

  /// `com.acme.Widget.helper` → `Widget helper`. Better than showing a reverse
  /// DNS string to someone who does not know what one is.
  private static func friendlyName(from label: String) -> String {
    let parts = label.split(separator: ".").map(String.init)
    guard parts.count > 2 else { return label }

    // Drop the reverse-DNS prefix ("com", "org", "io", plus the vendor).
    let tail = parts.dropFirst(2)
    guard !tail.isEmpty else { return label }

    let words = tail
      .flatMap { splitCamelCase($0) }
      .filter { !$0.isEmpty }
    guard !words.isEmpty else { return label }

    var joined = words.joined(separator: " ")
    joined.replaceSubrange(
      joined.startIndex...joined.startIndex,
      with: joined[joined.startIndex].uppercased()
    )
    return joined
  }

  private static func splitCamelCase(_ token: String) -> [String] {
    var words: [String] = []
    var current = ""
    for character in token {
      if character.isUppercase && !current.isEmpty {
        words.append(current)
        current = String(character)
      } else {
        current.append(character)
      }
    }
    if !current.isEmpty { words.append(current) }
    return words
  }

  // MARK: - Toggling

  /// Enables or disables one user agent, persistently.
  ///
  /// `launchctl disable` writes to launchd's override database, so the change
  /// survives a reboot — moving the plist aside or renaming it would not, and
  /// would also break any app that rewrites its own agent on launch.
  ///
  /// Returns nil on success, or a sentence to show the user.
  static func setEnabled(label: String, scope: String, path: String, enabled: Bool) -> String? {
    guard scope == "user" else {
      return "This one is set up for every user on this Mac, so changing it needs administrator rights."
    }
    guard !label.isEmpty else { return "That item has no label, so launchd cannot address it." }

    let domain = "gui/\(getuid())"
    let target = "\(domain)/\(label)"

    if enabled {
      _ = Shell.run("/bin/launchctl", ["enable", target])
      let bootstrap = Shell.run("/bin/launchctl", ["bootstrap", domain, path])
      // 37 is EALREADY — already loaded, which is exactly what we wanted.
      if bootstrap != 0 && bootstrap != 37 && bootstrap != 5 {
        return "macOS would not start that item (launchctl error \(bootstrap))."
      }
      return nil
    }

    // Order matters: bootout first so it stops now, disable second so it stays
    // stopped. Booting out something that is not running returns an error we
    // deliberately ignore — the persistent disable is the part that counts.
    _ = Shell.run("/bin/launchctl", ["bootout", target])
    let disable = Shell.run("/bin/launchctl", ["disable", target])
    if disable != 0 {
      return "macOS would not disable that item (launchctl error \(disable))."
    }
    return nil
  }

  /// Stops an item before its plist is removed, so launchd is not left holding
  /// a job whose definition has gone.
  static func unload(label: String, scope: String) -> String? {
    guard scope == "user", !label.isEmpty else { return nil }
    _ = Shell.run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])
    return nil
  }

  // MARK: - Machine-wide removal

  /// The only directories a machine-wide item may be removed from.
  ///
  /// `/System/Library/Launch*` is absent and cannot match — none of these are
  /// a prefix of it — which is the point. Those are Apple's own, and removing
  /// one is how a Mac stops booting properly.
  private static let elevatableRoots = [
    "/Library/LaunchAgents/",
    "/Library/LaunchDaemons/",
    "/Library/PrivilegedHelperTools/",
  ]

  private static func isElevatable(_ path: String) -> Bool {
    guard !path.contains("..") else { return false }
    return elevatableRoots.contains { path.hasPrefix($0) }
  }

  /// Removes a machine-wide launch item behind one macOS authorization prompt.
  ///
  /// Tidy has no privileged helper, so this is `osascript`'s
  /// `with administrator privileges` — the system's own password dialog, shown
  /// by macOS and not by us. One invocation does both the bootout and the move,
  /// so the user is asked once rather than twice.
  ///
  /// It **moves to the Trash**; it never deletes. A machine-wide launch item is
  /// exactly the kind of thing that turns out to have mattered, and the whole
  /// value of this operation is that it can be walked back. Cancelling the
  /// password prompt is a normal outcome, not an error, and leaves everything
  /// where it was.
  static func removeElevated(path: String, label: String, kind: String) -> String? {
    guard !path.isEmpty else { return "There is no file to remove." }
    guard isElevatable(path) else {
      return "Tidy only removes machine-wide items from LaunchAgents, "
        + "LaunchDaemons and PrivilegedHelperTools."
    }

    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: path) else {
      return "That file is already gone."
    }

    let destination = trashDestination(for: path)

    var commands: [String] = []
    if !label.isEmpty {
      // Daemons live in the system domain; machine-wide agents load per GUI
      // session. A bootout that finds nothing running exits non-zero, which is
      // expected here and deliberately ignored — the move is what counts.
      let domain = kind == "daemon" ? "system" : "gui/\(getuid())"
      commands.append("/bin/launchctl bootout \(shQuote("\(domain)/\(label)")) 2>/dev/null || true")
    }
    commands.append("/bin/mv -f \(shQuote(path)) \(shQuote(destination))")
    // A sentinel rather than an exit status: osascript exits non-zero both for
    // a genuine failure and for a cancelled prompt, and those want different
    // words in front of the user.
    commands.append("echo tidy-removed")

    let script = "do shell script \(appleScriptLiteral(commands.joined(separator: "; ")))"
      + " with administrator privileges"

    let output = Shell.capture("/usr/bin/osascript", ["-e", script])
    guard let output, output.contains("tidy-removed") else {
      return "Nothing was removed — the password prompt was cancelled, or macOS "
        + "refused the change."
    }
    return nil
  }

  /// A free filename in the user's Trash. Root-owned files land there like any
  /// other, and stay recoverable from Finder.
  private static func trashDestination(for path: String) -> String {
    let trash = "\(NSHomeDirectory())/.Trash"
    let name = (path as NSString).lastPathComponent
    let stem = (name as NSString).deletingPathExtension
    let ext = (name as NSString).pathExtension
    let suffix = ext.isEmpty ? "" : ".\(ext)"

    var candidate = "\(trash)/\(name)"
    var attempt = 2
    while FileManager.default.fileExists(atPath: candidate) {
      candidate = "\(trash)/\(stem) \(attempt)\(suffix)"
      attempt += 1
    }
    return candidate
  }

  /// Single-quotes a value for `/bin/sh`, so a path with a space or a quote in
  /// it cannot turn into extra arguments.
  private static func shQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  /// Wraps a shell command as an AppleScript string literal.
  private static func appleScriptLiteral(_ value: String) -> String {
    let escaped = value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
  }
}

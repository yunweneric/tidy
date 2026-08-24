import Cocoa
import FlutterMacOS
import ServiceManagement

/// Native helpers the Dart side cannot do safely (or at all) by shelling out.
///
/// Removal goes through `FileManager` rather than `rm`: `trashItem` is what
/// makes an uninstall recoverable, and both APIs report *which* item failed
/// instead of collapsing everything into one shell exit code.
enum SystemChannel {
  static let channelName = "com.yunweneric.tidy/system"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      handle(call: call, result: result)
    }
  }

  private static func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "trashItems":
      remove(call: call, result: result, toTrash: true)
    case "deleteItems":
      remove(call: call, result: result, toTrash: false)
    case "diskUsage":
      result(diskUsage())
    case "sizeOfPaths":
      let paths = (call.arguments as? [String: Any])?["paths"] as? [String] ?? []
      // fts walking is blocking and can take seconds over a large tree.
      DispatchQueue.global(qos: .userInitiated).async {
        let sizes = DirectorySizer.sizes(of: paths)
        DispatchQueue.main.async { result(sizes) }
      }
    case "childSizes":
      let args = call.arguments as? [String: Any]
      let path = args?["path"] as? String ?? ""
      DispatchQueue.global(qos: .userInitiated).async {
        let children = DirectorySizer.children(of: path)
        DispatchQueue.main.async { result(children) }
      }
    case "iconsForPaths":
      result(icons(for: call))
    case "revealInFinder":
      if let path = (call.arguments as? [String: Any])?["path"] as? String {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
      }
      result(nil)
    case "openFullDiskAccessSettings":
      FullDiskAccess.openSettings()
      result(nil)
    case "openSettingsPane":
      let anchor = (call.arguments as? [String: Any])?["anchor"] as? String
      FullDiskAccess.openSettingsPane(anchor: anchor ?? "Privacy_AllFiles")
      result(nil)
    case "fullDiskAccessStatus":
      result(["granted": FullDiskAccess.isGranted])
    case "canReadPaths":
      let paths = (call.arguments as? [String: Any])?["paths"] as? [String] ?? []
      result(Dictionary(uniqueKeysWithValues: paths.map { ($0, FullDiskAccess.canRead($0)) }))
    case "loginItemStatus":
      result(loginItemStatus())
    case "setLoginItem":
      let enabled = (call.arguments as? [String: Any])?["enabled"] as? Bool ?? false
      result(setLoginItem(enabled: enabled))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Login item

  /// Whether the app is set to launch at login.
  ///
  /// `SMAppService` arrived in macOS 13 and the deployment target is 11, so
  /// older systems report the capability as unavailable and the Settings row
  /// hides itself rather than showing a switch that does nothing.
  private static func loginItemStatus() -> [String: Any] {
    guard #available(macOS 13.0, *) else {
      return ["available": false, "enabled": false]
    }
    return ["available": true, "enabled": SMAppService.mainApp.status == .enabled]
  }

  private static func setLoginItem(enabled: Bool) -> [String: Any] {
    guard #available(macOS 13.0, *) else {
      return ["ok": false, "message": "Launching at login needs macOS 13 or later."]
    }
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      return ["ok": true]
    } catch {
      return ["ok": false, "message": error.localizedDescription]
    }
  }

  // MARK: - Removal

  private static func remove(
    call: FlutterMethodCall,
    result: @escaping FlutterResult,
    toTrash: Bool
  ) {
    guard let args = call.arguments as? [String: Any],
          let paths = args["paths"] as? [String] else {
      result(FlutterError(code: "bad_args", message: "paths is required", details: nil))
      return
    }

    // File I/O off the main thread; large bundles take a moment.
    DispatchQueue.global(qos: .userInitiated).async {
      var removed: [String] = []
      var failures: [[String: String]] = []
      // Original path -> where it landed in the Trash. `trashItem` is the only
      // moment anyone knows both halves: afterwards the Trash holds a file with
      // no record of where it came from, and macOS keeps its own put-back index
      // in a binary `.DS_Store` no other app can read. Reporting the pair here
      // is what lets Recycle Bin offer a real "Put Back" later.
      var trashed: [String: String] = [:]

      for path in paths {
        guard isRemovable(path) else {
          failures.append([
            "path": path,
            "error": "Refused: protected system location",
          ])
          continue
        }

        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
          // Already gone — treat as success so the caller's accounting matches.
          removed.append(path)
          continue
        }

        do {
          if toTrash {
            var landed: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &landed)
            if let landed = landed as URL? { trashed[path] = landed.path }
          } else {
            do {
              try FileManager.default.removeItem(at: url)
            } catch {
              // Retry once after clearing immutable flags / read-only modes.
              makeWritable(url)
              try FileManager.default.removeItem(at: url)
            }
          }
          removed.append(path)
        } catch {
          failures.append(["path": path, "error": error.localizedDescription])
        }
      }

      DispatchQueue.main.async {
        result(["removed": removed, "failures": failures, "trashed": trashed])
      }
    }
  }

  /// Last line of defence before anything is deleted. The Dart scanners already
  /// constrain their search roots; this makes the dangerous paths unreachable
  /// even if a caller gets it wrong.
  private static func isRemovable(_ rawPath: String) -> Bool {
    let url = URL(fileURLWithPath: rawPath)
    let path = url.standardized.path

    if path.isEmpty || path == "/" { return false }
    if path.hasPrefix("/System") { return false }
    if protectedPaths.contains(path) { return false }
    if isTrashRoot(path) { return false }

    // Resolve symlinks too, so a link inside an allowed root cannot be used to
    // reach a protected target. Both forms have to clear the deny list.
    let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
    if resolved != path {
      if resolved.isEmpty || resolved == "/" { return false }
      if resolved.hasPrefix("/System") { return false }
      if protectedPaths.contains(resolved) { return false }
      if isTrashRoot(resolved) { return false }
    }

    // Refuse volume roots and mount points: deleting one of those means
    // deleting whatever is mounted there.
    if isMountPoint(path) { return false }

    // Refuse top-level entries like "/Applications" or "/Users" themselves,
    // while still allowing "/Applications/Some.app".
    let components = path.split(separator: "/")
    if components.count < 2 { return false }

    return true
  }

  /// True when `path` is a Trash folder rather than something inside one.
  ///
  /// Emptying the bin deletes its *contents*; deleting `~/.Trash` or a volume's
  /// `.Trashes` takes the folder macOS puts things into, and Finder does not
  /// always recreate it. Checked as strings rather than added to
  /// `protectedPaths` because that set is rebuilt per path and enumerating
  /// mounted volumes there would be a syscall on every candidate.
  private static func isTrashRoot(_ path: String) -> Bool {
    if path == "\(NSHomeDirectory())/.Trash" { return true }
    if path.hasSuffix("/.Trash") && path.hasPrefix("/Users/") { return true }
    if path.hasSuffix("/.Trashes") { return true }

    // "/Volumes/Disk/.Trashes/501" — the per-user bin on another volume.
    let url = URL(fileURLWithPath: path)
    if url.deletingLastPathComponent().lastPathComponent == ".Trashes",
       Int(url.lastPathComponent) != nil {
      return true
    }
    return false
  }

  /// True when `path` is where a filesystem is mounted.
  private static func isMountPoint(_ path: String) -> Bool {
    var buffer = statfs()
    guard statfs(path, &buffer) == 0 else { return false }
    let mounted = withUnsafePointer(to: &buffer.f_mntonname) {
      String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
    }
    return mounted == path
  }

  /// Clears the immutable flag and restores write permission so `removeItem`
  /// can proceed. Go's module cache (mode 0444 inside 0555 directories) and
  /// user-locked files both fail without this.
  private static func makeWritable(_ url: URL) {
    let fm = FileManager.default
    let path = url.path

    if let attrs = try? fm.attributesOfItem(atPath: path),
       let flags = attrs[.immutable] as? Bool, flags {
      try? fm.setAttributes([.immutable: false], ofItemAtPath: path)
    }

    guard let walker = fm.enumerator(
      at: url,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles ]
    ) else { return }

    for case let child as URL in walker {
      guard let perms = (try? fm.attributesOfItem(atPath: child.path))?[.posixPermissions] as? NSNumber
      else { continue }
      let writable = perms.uint16Value | 0o200
      if writable != perms.uint16Value {
        try? fm.setAttributes([.posixPermissions: NSNumber(value: writable)], ofItemAtPath: child.path)
      }
    }
  }

  private static var protectedPaths: Set<String> {
    let home = NSHomeDirectory()
    var paths: Set<String> = [
      "/", "/Applications", "/Library", "/Users", "/usr", "/bin", "/sbin",
      "/etc", "/var", "/tmp", "/private", "/opt", "/Network", "/Volumes",
      "/cores", "/dev", home,
    ]

    // The user's Library and its standard subfolders are containers, not junk.
    let libraryChildren = [
      "", "/Application Support", "/Caches", "/Preferences", "/Logs",
      "/Containers", "/Group Containers", "/Application Scripts",
      "/Saved Application State", "/HTTPStorages", "/WebKit", "/Cookies",
      "/LaunchAgents", "/Fonts", "/Keychains", "/Mail", "/Messages",
      "/Safari", "/Mobile Documents",
    ]
    for child in libraryChildren {
      paths.insert("\(home)/Library\(child)")
    }

    for folder in ["Desktop", "Documents", "Downloads", "Pictures", "Music", "Movies", "Public", "Applications"] {
      paths.insert("\(home)/\(folder)")
    }

    return paths
  }

  // MARK: - Disk

  private static func diskUsage() -> [String: Any] {
    let url = URL(fileURLWithPath: NSHomeDirectory())
    do {
      let values = try url.resourceValues(forKeys: [
        .volumeTotalCapacityKey,
        .volumeAvailableCapacityForImportantUsageKey,
      ])
      let total = Int64(values.volumeTotalCapacity ?? 0)
      let free = values.volumeAvailableCapacityForImportantUsage ?? 0
      return ["total": total, "free": free]
    } catch {
      return ["total": 0, "free": 0]
    }
  }

  // MARK: - Icons

  /// PNG icons keyed by path.
  ///
  /// `NSWorkspace` resolves .icns files, asset-catalog icons and generic
  /// fallbacks alike, which is both faster and more complete than converting
  /// bundle resources with `iconutil`.
  private static func icons(for call: FlutterMethodCall) -> [String: FlutterStandardTypedData] {
    guard let args = call.arguments as? [String: Any],
          let paths = args["paths"] as? [String] else {
      return [:]
    }
    let size = CGFloat((args["size"] as? Double) ?? 64)

    var output: [String: FlutterStandardTypedData] = [:]
    for path in paths {
      if let data = pngIcon(forFile: path, size: size) {
        output[path] = FlutterStandardTypedData(bytes: data)
      }
    }
    return output
  }

  private static func pngIcon(forFile path: String, size: CGFloat) -> Data? {
    guard FileManager.default.fileExists(atPath: path) else { return nil }

    let icon = NSWorkspace.shared.icon(forFile: path)
    let pixels = Int(size * 2) // Render @2x so Retina displays stay crisp.

    guard let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: pixels,
      pixelsHigh: pixels,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ) else { return nil }

    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    icon.draw(
      in: NSRect(x: 0, y: 0, width: size, height: size),
      from: .zero,
      operation: .sourceOver,
      fraction: 1.0
    )
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])
  }
}

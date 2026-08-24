import Cocoa
import FlutterMacOS

/// Native helpers the Dart side cannot do safely (or at all) by shelling out.
///
/// Removal goes through `FileManager` rather than `rm`: `trashItem` is what
/// makes an uninstall recoverable, and both APIs report *which* item failed
/// instead of collapsing everything into one shell exit code.
enum SystemChannel {
  static let channelName = "com.yunweneric.macuninstaller/system"

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
    case "iconsForPaths":
      result(icons(for: call))
    case "revealInFinder":
      if let path = (call.arguments as? [String: Any])?["path"] as? String {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
      }
      result(nil)
    case "openFullDiskAccessSettings":
      openFullDiskAccessSettings()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
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
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
          } else {
            try FileManager.default.removeItem(at: url)
          }
          removed.append(path)
        } catch {
          failures.append(["path": path, "error": error.localizedDescription])
        }
      }

      DispatchQueue.main.async {
        result(["removed": removed, "failures": failures])
      }
    }
  }

  /// Last line of defence before anything is deleted. The Dart scanners already
  /// constrain their search roots; this makes the dangerous paths unreachable
  /// even if a caller gets it wrong.
  private static func isRemovable(_ rawPath: String) -> Bool {
    let path = URL(fileURLWithPath: rawPath).standardized.path

    if path.isEmpty || path == "/" { return false }
    if path.hasPrefix("/System") { return false }
    if protectedPaths.contains(path) { return false }

    // Refuse top-level entries like "/Applications" or "/Users" themselves,
    // while still allowing "/Applications/Some.app".
    let components = path.split(separator: "/")
    if components.count < 2 { return false }

    return true
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

  // MARK: - Privacy settings

  private static func openFullDiskAccessSettings() {
    let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
    )
    if let url {
      NSWorkspace.shared.open(url)
    }
  }
}

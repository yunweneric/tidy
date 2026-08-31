import Cocoa
import FlutterMacOS

/// The Protection module's native surface: signatures and provenance.
///
/// Everything here answers a question about a file that is already on this Mac.
/// Nothing here consults a list, and nothing here reaches the network — the
/// module's whole claim is that it reports facts macOS already holds, and a
/// channel that quietly fetched something would break it.
///
/// Registered from `MainFlutterWindow` only. The menu bar popover has no
/// Protection view and should not carry a handler it cannot reach.
enum ProtectionChannel {
  static let channelName = "com.yunweneric.tidy/protection"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      handle(call: call, result: result)
    }
  }

  private static func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]

    switch call.method {

    // Batched deliberately: one round trip for every path, not one per path.
    // Reading a signature is milliseconds, so the channel crossing would
    // otherwise be the expensive half.
    case "signingInfo":
      let paths = arguments["paths"] as? [String] ?? []
      channelBackground({
        var found: [String: Any] = [:]
        for path in paths { found[path] = CodeSignature.inspect(path: path) }
        return found
      }, deliver: result)

    case "quarantineInfo":
      let paths = arguments["paths"] as? [String] ?? []
      channelBackground({ Provenance.quarantine(paths: paths) }, deliver: result)

    case "downloadEvents":
      let limit = arguments["limit"] as? Int ?? 200
      channelBackground({ Provenance.downloadEvents(limit: limit) }, deliver: result)

    // The two slow ones. Both are a button on one row, never part of a sweep —
    // see the note on `CodeSignature.validate`.
    case "validateSignature":
      let path = arguments["path"] as? String ?? ""
      channelBackground({ CodeSignature.validate(path: path) }, deliver: result)

    case "assessGatekeeper":
      let path = arguments["path"] as? String ?? ""
      channelBackground({ CodeSignature.assess(path: path) }, deliver: result)

    /// Which browsers are open right now.
    ///
    /// Asked because removing an extension folder under a running browser is
    /// undone by the browser — see `BrowserExtensionService`. Cheap enough to
    /// answer on the main thread.
    case "runningBrowsers":
      let running = NSWorkspace.shared.runningApplications.compactMap {
        $0.bundleIdentifier
      }
      result(Array(Set(running)))

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

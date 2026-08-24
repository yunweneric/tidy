import Cocoa
import FlutterMacOS

/// The updater's native surface.
///
/// Registered on the main engine only. The popover is a `.transient`
/// `NSPopover` that closes on the first click outside it, and an install that
/// quits the app from a panel which has already vanished is not something to
/// offer. If the popover ever grows an update affordance, it routes the action
/// to the window through `PopoverChannel`, the way "Open Clipboard" already
/// does.
enum UpdateChannel {
  static let channelName = "com.yunweneric.tidy/updates"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      handle(call: call, result: result)
    }
  }

  private static func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]

    switch call.method {
    case "prepareUpdate":
      guard let zipPath = arguments["zipPath"] as? String else {
        result(FlutterError(code: "bad_args", message: "zipPath is required", details: nil))
        return
      }
      let expected = arguments["expectedSha256"] as? String
      // Hashing tens of megabytes and walking every sealed resource with
      // `kSecCSCheckNestedCode` is seconds, not milliseconds.
      DispatchQueue.global(qos: .userInitiated).async {
        let payload = Updater.prepare(zipPath: zipPath, expectedSha256: expected)
        DispatchQueue.main.async { result(payload) }
      }

    case "installUpdate":
      guard let staged = arguments["stagedPath"] as? String else {
        result(FlutterError(code: "bad_args", message: "stagedPath is required", details: nil))
        return
      }
      // On the main thread on purpose: the success path calls `NSApp.terminate`.
      result(Updater.install(stagedPath: staged))

    case "discardUpdate":
      if let staged = arguments["stagedPath"] as? String {
        Updater.discard(stagedPath: staged)
      }
      result(["ok": true])

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

import Cocoa
import FlutterMacOS

/// The Recycle Bin module's native surface.
///
/// Separate from `SystemChannel` for the same reason `PerformanceChannel` is:
/// the two speak about different things. `SystemChannel` is the app's one way
/// to *remove* a file, and this channel deliberately does not duplicate it —
/// emptying the bin goes back through `deleteItems` so it passes the same
/// `isRemovable` guard as every other deletion here.
enum RecycleBinChannel {
  static let channelName = "com.yunweneric.tidy/recycle-bin"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      handle(call: call, result: result)
    }
  }

  private static func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]

    switch call.method {
    case "readBins":
      // Sizing walks every subtree in the Trash; seconds, not milliseconds.
      DispatchQueue.global(qos: .userInitiated).async {
        let payload = Trash.read()
        DispatchQueue.main.async { result(payload) }
      }

    case "restoreItems":
      let moves = (arguments["moves"] as? [[String: String]]) ?? []
      DispatchQueue.global(qos: .userInitiated).async {
        let payload = Trash.restore(moves: moves)
        DispatchQueue.main.async { result(payload) }
      }

    case "chooseFolder":
      // NSOpenPanel is main-thread only, and the method handler already is one.
      let prompt = arguments["prompt"] as? String ?? "Choose"
      let message = arguments["message"] as? String ?? ""
      result(Trash.chooseFolder(prompt: prompt, message: message))

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

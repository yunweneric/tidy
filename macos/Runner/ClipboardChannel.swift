import AppKit
import FlutterMacOS
import Foundation

/// Dart's window onto [ClipboardStore].
///
/// Registered on **both** Flutter engines — the main window and the menu bar
/// popover. They are separate Dart isolates, so each needs its own channel, but
/// both reach the one native store: no cache to reconcile and no second writer.
enum ClipboardChannel {
  static let channelName = "com.yunweneric.tidy/clipboard"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      handle(call: call, result: result)
    }

    // The store pushes; Dart does not poll. A copy is an event the system hands
    // us, so making the UI ask every second for something that mostly has not
    // happened would be the wrong shape.
    ClipboardStore.shared.addObserver { [weak channel] in
      channel?.invokeMethod("clipboardDidChange", arguments: nil)
    }
  }

  private static func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    let store = ClipboardStore.shared

    switch call.method {
    case "history":
      store.load()
      result(store.entries.map { $0.toMap() })

    case "blob":
      guard let id = arguments["id"] as? String, let entry = store.entry(id: id) else {
        result(nil)
        return
      }
      background {
        store.blobData(for: entry).map { FlutterStandardTypedData(bytes: $0) }
      } deliver: { result($0) }

    case "fullText":
      guard let id = arguments["id"] as? String, let entry = store.entry(id: id) else {
        result(nil)
        return
      }
      background { store.fullText(for: entry) } deliver: { result($0) }

    case "copyToPasteboard":
      guard let id = arguments["id"] as? String, let entry = store.entry(id: id) else {
        result(outcome("That item is no longer in the history."))
        return
      }
      let wrote = ClipboardMonitor.shared.copyToPasteboard(entry)
      result(outcome(wrote ? nil : "Nothing was left to copy — its contents have been cleared."))

    case "setPinned":
      guard let id = arguments["id"] as? String, let pinned = arguments["pinned"] as? Bool else {
        result(outcome("Missing arguments."))
        return
      }
      store.setPinned(id: id, pinned: pinned)
      result(outcome(nil))

    case "delete":
      store.delete(ids: arguments["ids"] as? [String] ?? [])
      result(outcome(nil))

    case "clear":
      store.clear(keepPinned: arguments["keepPinned"] as? Bool ?? true)
      result(outcome(nil))

    case "configure":
      store.load()
      store.configure(ClipboardPrefs.fromMap(arguments))
      result(outcome(nil))

    case "revealSource":
      guard let id = arguments["id"] as? String,
            let entry = store.entry(id: id),
            let path = entry.paths.first
      else {
        result(outcome("That item has no file to show."))
        return
      }
      NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
      result(outcome(nil))

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// The standard codec has no notion of a missing value, so an outcome is a
  /// map with a flag rather than an optional error.
  private static func outcome(_ error: String?) -> [String: Any] {
    guard let error else { return ["ok": true] }
    return ["ok": false, "message": error]
  }

  /// `FlutterResult` must be called on the platform thread, so anything that
  /// touches the disk hops off and back.
  private static func background<T>(
    _ work: @escaping () -> T,
    deliver: @escaping (T) -> Void
  ) {
    DispatchQueue.global(qos: .userInitiated).async {
      let value = work()
      DispatchQueue.main.async { deliver(value) }
    }
  }
}

import FlutterMacOS
import Foundation

/// Dart's window onto [NetworkMonitor] and [NetworkStore].
///
/// Registered on **both** Flutter engines — the main window and the menu bar
/// popover. They are separate Dart isolates, so each needs its own channel, but
/// both reach the one native monitor: no second sampler, and no two histories to
/// reconcile.
enum NetworkChannel {
  static let channelName = "com.yunweneric.tidy/network"

  /// Posted when Dart changes the preferences, so the menu bar item can restyle
  /// itself without the channel needing to know it exists.
  static let prefsChanged = Notification.Name("TidyNetworkPrefsChanged")

  /// One per engine, held for the life of the app. A released handler would stop
  /// delivering samples, silently.
  private static var handlers: [Handler] = []

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    let handler = Handler(channel: channel)
    channel.setMethodCallHandler { call, result in
      handler.handle(call: call, result: result)
    }
    handlers.append(handler)
  }

  /// One engine's end of the channel.
  ///
  /// The sampler runs whether or not anyone is listening — the menu bar and the
  /// history both need it. What this gates is the **push**: an engine that has
  /// not asked for live samples does not get woken sixty times a minute to
  /// repaint a panel nobody can see. Same reasoning as the popover's ticker.
  private final class Handler {
    init(channel: FlutterMethodChannel) {
      self.channel = channel
    }

    private let channel: FlutterMethodChannel
    private var observer: UUID?

    deinit {
      if let observer { NetworkMonitor.shared.removeObserver(observer) }
    }

    func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
      let arguments = call.arguments as? [String: Any] ?? [:]

      switch call.method {
      case "live":
        result(livePayload())

      case "startLive":
        startLive()
        result(livePayload())

      case "stopLive":
        stopLive()
        result(nil)

      // Read on the platform thread deliberately. The store is fed from the
      // sampler's main-thread timer, so answering from a background queue would
      // be a second reader racing a writer over the same arrays — and the work
      // is filtering a few thousand structs, which is not what a background hop
      // is for. Only the file write goes off-thread, inside the store.
      case "history":
        result(NetworkStore.shared.series(range: arguments["range"] as? String ?? "day"))

      case "headline":
        result(NetworkStore.shared.headline())

      case "configure":
        let prefs = NetworkPrefs.fromMap(arguments)
        NetworkStore.shared.configure(prefs)
        NotificationCenter.default.post(name: NetworkChannel.prefsChanged, object: nil)
        result(outcome(nil))

      case "reset":
        NetworkStore.shared.reset()
        result(outcome(nil))

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    private func startLive() {
      guard observer == nil else { return }
      observer = NetworkMonitor.shared.addObserver { [weak self] sample in
        var payload = sample.toMap()
        // Rides along with every reading. The popover engine is started with
        // `includeUi: false` and has no `AppSettings` of its own, so this is
        // the only way it learns which units the user asked for — and it is
        // free, because the store already holds them.
        payload["useBits"] = NetworkStore.shared.prefs.useBits
        self?.channel.invokeMethod("networkDidSample", arguments: payload)
      }
    }

    private func stopLive() {
      guard let observer else { return }
      NetworkMonitor.shared.removeObserver(observer)
      self.observer = nil
    }

    /// The current reading plus the five-minute ring, so a panel that has just
    /// opened draws a populated chart rather than filling one in a pixel at a
    /// time over the next five minutes.
    private func livePayload() -> [String: Any] {
      let monitor = NetworkMonitor.shared
      var payload = monitor.latest.toMap()
      payload["useBits"] = NetworkStore.shared.prefs.useBits
      payload["recent"] = monitor.ring.map { sample in
        [
          "at": sample.atSeconds,
          "down": sample.downBytesPerSecond,
          "up": sample.upBytesPerSecond,
        ]
      }
      return payload
    }

    /// The standard codec has no notion of a missing value, so an outcome is a
    /// map with a flag rather than an optional error.
    private func outcome(_ error: String?) -> [String: Any] {
      guard let error else { return ["ok": true] }
      return ["ok": false, "message": error]
    }
  }
}

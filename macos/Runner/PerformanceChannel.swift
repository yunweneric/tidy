import Cocoa
import FlutterMacOS

/// The Performance module's native surface: launchd items, running processes,
/// machine-wide vitals and maintenance tasks.
///
/// Separate from `SystemChannel` because the two have different shapes.
/// `SystemChannel` is about files — sizing, removing, revealing. Nothing here
/// touches a file except to read a plist; the rest is launchd, libproc and a
/// handful of Apple's own command line tools.
enum PerformanceChannel {
  static let channelName = "com.yunweneric.macuninstaller/performance"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      handle(call: call, result: result)
    }
  }

  private static func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]

    switch call.method {

    // MARK: Launch items

    case "launchItems":
      // Reads three directories and shells out to launchctl once; comfortably
      // long enough to drop a frame if it ran on the main thread.
      background { LaunchItems.list() } deliver: { result($0) }

    case "setLaunchItemEnabled":
      let label = arguments["label"] as? String ?? ""
      let scope = arguments["scope"] as? String ?? "user"
      let path = arguments["path"] as? String ?? ""
      let enabled = arguments["enabled"] as? Bool ?? true
      background {
        LaunchItems.setEnabled(label: label, scope: scope, path: path, enabled: enabled)
      } deliver: { error in
        result(outcome(error))
      }

    case "unloadLaunchItem":
      let label = arguments["label"] as? String ?? ""
      let scope = arguments["scope"] as? String ?? "user"
      background {
        LaunchItems.unload(label: label, scope: scope)
      } deliver: { error in
        result(outcome(error))
      }

    case "removeLaunchItemElevated":
      let path = arguments["path"] as? String ?? ""
      let label = arguments["label"] as? String ?? ""
      let kind = arguments["kind"] as? String ?? "agent"
      background {
        LaunchItems.removeElevated(path: path, label: label, kind: kind)
      } deliver: { error in
        result(outcome(error))
      }

    // MARK: Processes

    case "processSamples":
      background { ProcessMonitor.sample() } deliver: { result($0) }

    case "resetProcessSamples":
      ProcessMonitor.reset()
      result(nil)

    case "terminateProcess":
      let pid = pid_t((arguments["pid"] as? Int) ?? 0)
      let force = arguments["force"] as? Bool ?? false
      // Termination is fast and `NSRunningApplication` wants the main thread.
      result(outcome(ProcessMonitor.terminate(pid: pid, force: force)))

    // MARK: System vitals

    case "systemVitals":
      // Takes its own short CPU baseline when it has no history, so it is not
      // instant and has no business on the main thread.
      background { SystemVitals.read() } deliver: { result($0) }

    case "resetSystemVitals":
      SystemVitals.reset()
      result(nil)

    // MARK: Maintenance

    case "maintenanceTasks":
      background { Maintenance.tasks() } deliver: { result($0) }

    case "runMaintenanceTask":
      let id = arguments["id"] as? String ?? ""
      background { Maintenance.run(id: id) } deliver: { result($0) }

    // MARK: Settings

    case "openLoginItemsSettings":
      // macOS 13 moved login items out of Users & Groups into their own pane,
      // and only the new pane lists the modern `SMAppService` registrations.
      let candidates = [
        "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
        "x-apple.systempreferences:com.apple.preferences.users",
      ]
      for candidate in candidates {
        if let url = URL(string: candidate), NSWorkspace.shared.open(url) { break }
      }
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// A nil error means it worked. Built explicitly rather than putting an
  /// optional in the dictionary — the standard codec has no notion of a
  /// missing value, only of a key that is not there.
  private static func outcome(_ error: String?) -> [String: Any] {
    guard let error else { return ["ok": true] }
    return ["ok": false, "message": error]
  }

  /// Runs `work` off the main thread and delivers the answer back on it —
  /// `FlutterResult` must be called from the platform thread.
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

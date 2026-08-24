import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var menuBarController: MenuBarController?

  /// The menu bar item is installed from `applicationWillFinishLaunching`.
  /// `applicationDidFinishLaunching` never reaches this subclass through
  /// FlutterAppDelegate, so anything set up there would silently never run —
  /// the status item simply would not appear. Deferring to the next main
  /// run-loop turn keeps the work after NSApp has finished launching.
  override func applicationWillFinishLaunching(_ notification: Notification) {
    super.applicationWillFinishLaunching(notification)

    DispatchQueue.main.async { [weak self] in
      self?.menuBarController = MenuBarController()
    }
  }

  /// The menu bar item outlives the window, so closing the window must not
  /// terminate the app.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  /// Clicking the dock icon after closing the window brings it back.
  override func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag, let window = sender.windows.first(where: { $0 is MainFlutterWindow }) {
      window.makeKeyAndOrderFront(nil)
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

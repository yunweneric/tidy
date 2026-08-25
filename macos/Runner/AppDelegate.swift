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
    // Before anything opens the support folder under either name.
    AppSupport.migrate()
    super.applicationWillFinishLaunching(notification)

    DispatchQueue.main.async { [weak self] in
      let controller = MenuBarController()
      self?.menuBarController = controller

      // Capture is deliberately native and owned here rather than by a Flutter
      // engine: the app outlives its window, and a history that stopped
      // recording when the window closed would be a history with holes in it.
      ClipboardMonitor.shared.start()

      // Native and owned here for the same reason, and one more: the menu bar
      // readout has to be live before any window exists, and a history that only
      // recorded while the window was open would be a history full of holes.
      NetworkMonitor.shared.start()

      HotKey.shared.register { controller.showPopover(section: "clipboard") }

      // An update that was prepared but never installed, or one whose relaunch
      // helper was killed before it finished tidying up, leaves a staging
      // folder beside the app. This app in particular should not leave litter.
      DispatchQueue.global(qos: .utility).async { Updater.sweepLeftovers() }
    }

    addCloseWindowItem()
  }

  /// Adds "Close Window" (⌘W) to the Window menu.
  ///
  /// Flutter's stock `MainMenu.xib` ships no File menu, and Close lives in File
  /// on macOS — so out of the box this app has no ⌘W at all, and the only way
  /// to put the window away is the red button. The Window menu is where it goes
  /// for an app with no documents to close.
  ///
  /// It sends `performClose:` down the responder chain rather than naming a
  /// window, which is what routes it through `windowShouldClose` and therefore
  /// hides rather than quits — the same path the red button takes.
  private func addCloseWindowItem() {
    guard let windowMenu = NSApp.windowsMenu else { return }
    // `applicationWillFinishLaunching` can run more than once in a relaunch, and
    // a second ⌘W in the same menu would be a duplicate row with an ambiguous
    // shortcut.
    guard !windowMenu.items.contains(where: { $0.action == #selector(NSWindow.performClose(_:)) })
    else { return }

    let item = NSMenuItem(
      title: "Close Window",
      action: #selector(NSWindow.performClose(_:)),
      keyEquivalent: "w"
    )
    // No target: the responder chain finds the key window, so the item greys
    // itself out when there is no window to close.
    windowMenu.insertItem(item, at: 0)
    windowMenu.insertItem(.separator(), at: 1)
  }

  /// The clipboard index is written on a debounce, so a quit between a copy and
  /// that write would lose it. This is also where "clear on quit" happens.
  override func applicationWillTerminate(_ notification: Notification) {
    HotKey.shared.unregister()
    ClipboardMonitor.shared.stop()
    // Not on the way into an update. "Clear on quit" is a promise about the
    // user quitting, and an update relaunch is not a quit they made — wiping
    // their history behind an update they asked for would be the setting
    // betraying them rather than serving them.
    if !Updater.isRelaunchingForUpdate {
      ClipboardStore.shared.clearOnQuitIfAsked()
    }
    // The history is written on a debounce too, so quitting between ticks would
    // otherwise lose up to a minute of it.
    NetworkMonitor.shared.stop()
    NetworkStore.shared.flush()
    super.applicationWillTerminate(notification)
  }

  /// The menu bar item outlives the window, so closing the window must not
  /// terminate the app.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  /// Clicking the Dock icon after hiding the window brings it back.
  ///
  /// Also the path for opening the app a second time while it is already
  /// running — with no window on screen macOS does not launch a new copy, it
  /// sends this instead, and without it the click would appear to do nothing.
  override func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag { MainFlutterWindow.present() }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  override func awakeFromNib() {
    // The nib can load before applicationWillFinishLaunching, and creating the
    // view controller starts the Dart isolate that reads settings.json.
    AppSupport.migrate()

    // Before the view controller, because this is what the window is painted
    // with until Flutter's first frame lands — and on a cold start that gap is
    // long enough to see. `SplashGate` on the Dart side covers everything
    // after it; this covers everything before.
    self.backgroundColor = AppearancePrefs.launchBackground

    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // The dashboard is a wide, table-driven layout; the nib's 800x600 default
    // is narrow enough to overflow it, so open at a size that fits and keep
    // that as the floor when resizing.
    self.minSize = NSSize(width: 1100, height: 720)

    var windowFrame = self.frame
    windowFrame.size = NSSize(
      width: max(windowFrame.width, 1280),
      height: max(windowFrame.height, 820)
    )
    self.setFrame(windowFrame, display: true)
    self.center()

    // Let the Flutter view run the full height of the frame, so the app's own
    // backdrop — gradient, glows and all — reaches the top edge instead of
    // stopping under a system-drawn title bar in the wrong colour. The traffic
    // lights float on top of it; AppSpacing.titleBar is the room reserved for
    // them on the Dart side.
    self.styleMask.insert(.fullSizeContentView)
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.isMovableByWindowBackground = true

    // The app keeps running in the menu bar after the window is closed, so the
    // window must survive being closed and be reopenable.
    self.isReleasedWhenClosed = false

    // Closing hides the window instead — see `windowShouldClose`.
    self.delegate = self

    RegisterGeneratedPlugins(registry: flutterViewController)
    SystemChannel.register(with: flutterViewController.engine.binaryMessenger)
    // Only the main window: the menu-bar popover shows metrics, not launchd
    // items, so its engine has no use for this channel.
    PerformanceChannel.register(with: flutterViewController.engine.binaryMessenger)
    // Same reasoning: the popover shows metrics, not the Trash.
    RecycleBinChannel.register(with: flutterViewController.engine.binaryMessenger)
    // This one goes on both engines. The store is a single native singleton, so
    // two channels onto it is two windows onto one list, not two copies of it.
    ClipboardChannel.register(with: flutterViewController.engine.binaryMessenger)
    // Both engines again, and for the same reason: one native sampler, one
    // history, two windows onto it.
    NetworkChannel.register(with: flutterViewController.engine.binaryMessenger)
    // Both engines. This window publishes the AI summary because it is the only
    // one with a service that can compute one; the popover reads it back, so
    // the panel and the menu bar draw the same figures rather than two
    // opinions.
    AiUsageChannel.register(with: flutterViewController.engine.binaryMessenger)
    // Main window only: the menu bar preferences are pushed from the settings
    // UI, and the popover has none.
    MenuBarChannel.register(with: flutterViewController.engine.binaryMessenger)
    // Reverse direction only, for "open Tidy at the clipboard" from the
    // popover. The popover's own engine has the other half of this channel.
    PopoverChannel.registerMainWindow(with: flutterViewController.engine.binaryMessenger)
    // Main window only — see UpdateChannel for why the popover does not get it.
    UpdateChannel.register(with: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  /// The red button hides the window rather than closing it.
  ///
  /// Tidy is a menu bar app that happens to have a window: the clipboard
  /// recorder, the network sampler and the three status items all keep running
  /// after the window goes away, and closing it is "put this away", not "quit".
  /// `applicationShouldTerminateAfterLastWindowClosed` already says as much,
  /// but that only decides whether the *app* survives — the window itself would
  /// still be torn down, and with it the first-responder chain, the view's
  /// place in the engine, and everything the user had on screen. Reopening then
  /// costs a rebuild, and any scan running at the time is gone.
  ///
  /// Ordering it out instead means the window is never closed at all. Nothing
  /// is deallocated, the Flutter engine keeps rendering into a view that simply
  /// is not on screen, and reopening is one `makeKeyAndOrderFront` with the
  /// user's place kept — the same thing the window does when the app is hidden.
  ///
  /// Quit is still quit. ⌘Q and "Quit Tidy" in the menu bar both terminate, and
  /// that is the only thing that should.
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    orderOut(nil)
    return false
  }

  /// Brings the window back from [windowShouldClose].
  ///
  /// Here rather than at the three call sites — the Dock icon, the menu bar's
  /// "Open Tidy", and the popover handing over a route — because "show the
  /// window" has to mean the same thing in all three, and one of them forgetting
  /// to activate is a window that comes back behind whatever the user was
  /// already looking at.
  static func present() {
    NSApp.activate(ignoringOtherApps: true)
    guard let window = NSApp.windows.first(where: { $0 is MainFlutterWindow })
    else { return }
    window.makeKeyAndOrderFront(nil)
  }
}

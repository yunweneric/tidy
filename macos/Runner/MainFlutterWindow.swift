import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
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

    RegisterGeneratedPlugins(registry: flutterViewController)
    SystemChannel.register(with: flutterViewController.engine.binaryMessenger)
    // Only the main window: the menu-bar popover shows metrics, not launchd
    // items, so its engine has no use for this channel.
    PerformanceChannel.register(with: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}

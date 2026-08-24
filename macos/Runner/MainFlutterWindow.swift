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

    // The app keeps running in the menu bar after the window is closed, so the
    // window must survive being closed and be reopenable.
    self.isReleasedWhenClosed = false

    RegisterGeneratedPlugins(registry: flutterViewController)
    SystemChannel.register(with: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}

import Cocoa
import FlutterMacOS

/// Owns the menu bar status item and the popover it presents.
///
/// The popover hosts a *second* Flutter engine running the `menuBarMain`
/// entrypoint, so the panel is real Flutter UI rather than an NSMenu. That
/// engine is its own Dart isolate — the two views stay in sync through the
/// on-disk scan cache, not through shared memory.
final class MenuBarController: NSObject, NSPopoverDelegate {
  private static let channelName = "com.yunweneric.macuninstaller/popover"

  private let statusItem: NSStatusItem
  private let popover = NSPopover()
  private let engine: FlutterEngine
  private var channel: FlutterMethodChannel?

  // The panel is a dashboard now, not a menu: three vitals tiles across the
  // top and a live process table below them need room to be read at a glance,
  // which a menu-width strip does not have.
  private let panelWidth: CGFloat = 460
  private let minPanelHeight: CGFloat = 320
  private let maxPanelHeight: CGFloat = 760

  override init() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    engine = FlutterEngine(
      name: "menu_bar",
      project: FlutterDartProject(),
      allowHeadlessExecution: true
    )
    super.init()

    configureStatusItem()
    configurePopover()
  }

  // MARK: - Status item

  private func configureStatusItem() {
    guard let button = statusItem.button else { return }

    button.image = Self.statusImage()
    button.image?.isTemplate = true // Adapts to light/dark menu bars.
    button.toolTip = "Tidy"
    button.target = self
    button.action = #selector(statusItemClicked(_:))
    button.sendAction(on: [.leftMouseUp, .rightMouseUp])
  }

  /// SF Symbol availability varies by macOS version, so fall back down a list
  /// and finally to a drawn glyph rather than shipping an invisible button.
  private static func statusImage() -> NSImage? {
    let candidates = [
      "internaldrive.badge.xmark",
      "externaldrive.badge.minus",
      "trash.circle",
      "trash",
    ]
    for name in candidates {
      if let image = NSImage(systemSymbolName: name, accessibilityDescription: "Tidy") {
        return image
      }
    }
    return NSImage(named: NSImage.trashEmptyName)
  }

  @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
    if NSApp.currentEvent?.type == .rightMouseUp {
      showContextMenu()
    } else {
      togglePopover()
    }
  }

  private func showContextMenu() {
    let menu = NSMenu()
    menu.addItem(
      withTitle: "Open Tidy",
      action: #selector(openMainWindow),
      keyEquivalent: ""
    ).target = self
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Quit Tidy",
      action: #selector(quit),
      keyEquivalent: "q"
    ).target = self

    statusItem.menu = menu
    statusItem.button?.performClick(nil)
    // Detach again so the next left-click opens the popover, not the menu.
    statusItem.menu = nil
  }

  // MARK: - Popover

  private func configurePopover() {
    engine.run(withEntrypoint: "menuBarMain")

    let controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    RegisterGeneratedPlugins(registry: controller)
    // The popover reads the machine's vitals and what is running, so it needs
    // the Performance channel as well as the file one. Without this the panel
    // renders and every native call quietly returns nothing.
    SystemChannel.register(with: engine.binaryMessenger)
    PerformanceChannel.register(with: engine.binaryMessenger)
    RecycleBinChannel.register(with: engine.binaryMessenger)

    channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: engine.binaryMessenger
    )
    channel?.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }

    popover.contentViewController = controller
    popover.contentSize = NSSize(width: panelWidth, height: 520)
    popover.behavior = .transient
    popover.animates = true
    popover.delegate = self
  }

  private func togglePopover() {
    if popover.isShown {
      popover.performClose(nil)
    } else {
      showPopover()
    }
  }

  private func showPopover() {
    guard let button = statusItem.button else { return }
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    NSApp.activate(ignoringOtherApps: true)
    channel?.invokeMethod("popoverDidOpen", arguments: nil)
  }

  /// The panel samples CPU and running processes on a timer while it is on
  /// screen. Nobody is reading it once it closes, and a cleaner that samples
  /// every two seconds forever is the kind of thing this app exists to find.
  func popoverDidClose(_ notification: Notification) {
    channel?.invokeMethod("popoverDidClose", arguments: nil)
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setPopoverHeight":
      if let height = (call.arguments as? [String: Any])?["height"] as? Double {
        setPopoverHeight(CGFloat(height))
      }
      result(nil)
    case "closePopover":
      popover.performClose(nil)
      result(nil)
    case "openMainWindow":
      popover.performClose(nil)
      openMainWindow()
      result(nil)
    case "quitApp":
      result(nil)
      quit()
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func setPopoverHeight(_ height: CGFloat) {
    let clamped = min(max(height, minPanelHeight), maxPanelHeight)
    guard abs(popover.contentSize.height - clamped) > 1 else { return }
    popover.contentSize = NSSize(width: panelWidth, height: clamped)
  }

  @objc private func openMainWindow() {
    NSApp.activate(ignoringOtherApps: true)

    if let window = NSApp.windows.first(where: { $0 is MainFlutterWindow }) {
      window.makeKeyAndOrderFront(nil)
    }
  }

  @objc private func quit() {
    NSApp.terminate(nil)
  }
}


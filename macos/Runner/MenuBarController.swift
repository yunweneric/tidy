import Cocoa
import FlutterMacOS

/// Owns the menu bar status items and the popover they present.
///
/// There are two icons and one popover. The icons are separate because they
/// answer different questions — "how is my Mac doing" and "what did I copy" —
/// and a single icon that hides one behind the other makes the clipboard a
/// place you have to remember rather than a place you can see. The popover is
/// shared because the panel behind it is one Flutter view: a second popover
/// would need a second engine, which is a whole Dart isolate to save an
/// anchor point.
///
/// The popover hosts a *second* Flutter engine running the `menuBarMain`
/// entrypoint, so the panel is real Flutter UI rather than an NSMenu. That
/// engine is its own Dart isolate — the two views stay in sync through the
/// on-disk scan cache, not through shared memory.
final class MenuBarController: NSObject, NSPopoverDelegate {
  private static let channelName = "com.yunweneric.tidy/popover"

  /// The vitals icon: disk, memory, what is running.
  private let statusItem: NSStatusItem

  /// The clipboard icon: what was copied recently.
  private let clipboardItem: NSStatusItem

  /// The network readout: how fast bytes are moving right now.
  ///
  /// Unlike the other two this one carries *text*, not a glyph, and it is the
  /// only status item the user can turn off — a live readout is the one thing
  /// here that permanently occupies menu bar width, and menu bar width is the
  /// scarcest real estate on the machine.
  private var networkItem: NSStatusItem?
  private var networkObserver: UUID?
  private var prefsObserver: Any?

  /// The widest the readout has been this session, so the item stops shuffling
  /// its neighbours every time a digit is added or dropped.
  private var networkItemWidth: CGFloat = 0

  /// Which icon the popover is currently hanging from, so a second click on
  /// the *same* icon closes it while a click on the other one moves it.
  private weak var anchor: NSStatusBarButton?

  private let popover = NSPopover()
  private let engine: FlutterEngine
  private var channel: FlutterMethodChannel?
  private var appearanceObserver: Any?

  // The panel is a dashboard now, not a menu: three vitals tiles across the
  // top and a live process table below them need room to be read at a glance,
  // which a menu-width strip does not have.
  private let panelWidth: CGFloat = 460

  /// The clipboard panel is a column of one-line rows. Dashboard width would
  /// be a lot of empty gutter, and the hover preview shows the full content
  /// beside it anyway.
  private let clipboardPanelWidth: CGFloat = 320

  /// The network panel is two big numbers and a chart. Same column width as the
  /// clipboard for the same reason — dashboard width would be empty gutter.
  private let networkPanelWidth: CGFloat = 320

  private let minPanelHeight: CGFloat = 160
  private let maxPanelHeight: CGFloat = 760

  /// Whichever width the panel currently on screen asked for.
  private var currentWidth: CGFloat = 460

  private lazy var preview = ClipPreviewPanel()

  override init() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    clipboardItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    engine = FlutterEngine(
      name: "menu_bar",
      project: FlutterDartProject(),
      allowHeadlessExecution: true
    )
    super.init()

    configureStatusItem()
    configureClipboardItem()
    configureNetworkItem()
    configurePopover()
    observeNetwork()
  }

  // MARK: - Status item

  /// Names an item and puts it back on the menu bar.
  ///
  /// Both halves matter, and neither is belt-and-braces.
  ///
  /// **The name.** An `NSStatusItem` with no `autosaveName` is filed by AppKit
  /// under an ordinal — `Item-0`, `Item-1`, `Item-2` — allocated in creation
  /// order. That is a shared namespace, not a private one, and macOS 26 keeps
  /// the menu bar's visibility state centrally now that Control Center owns the
  /// bar: `com.apple.controlcenter` here carries `NSStatusItem Visible Item-0`
  /// through `Item-9`, every one of them `0`. Any app whose items are unnamed
  /// inherits that "hidden" verdict — which is exactly what happened to all
  /// three of ours, and to at least one other app's on this machine. A stable
  /// name of our own takes the items out of the shared bucket.
  ///
  /// **The visibility.** `behavior` deliberately does not include
  /// `.removalAllowed`, so there is no supported gesture that hides these
  /// items — a stored `false` is an artefact of the ordinal collision above,
  /// never something the user asked for. Setting it back on every launch is
  /// therefore not overriding a preference; it is refusing to inherit someone
  /// else's.
  private static func claim(_ item: NSStatusItem, as name: String) {
    item.autosaveName = name
    item.isVisible = true
  }

  private func configureStatusItem() {
    Self.claim(statusItem, as: "TidyVitals")
    guard let button = statusItem.button else { return }

    button.image = Self.statusImage()
    button.image?.isTemplate = true // Adapts to light/dark menu bars.
    button.toolTip = "Tidy"
    button.target = self
    button.action = #selector(statusItemClicked(_:))
    button.sendAction(on: [.leftMouseUp, .rightMouseUp])
  }

  /// The app's own mark, so the status item and the Dock tile are the same
  /// thing at two sizes — a stock SF Symbol here made the menu bar look like it
  /// belonged to some other app.
  ///
  /// `MenuBarIcon` is a template asset: black-on-transparent, recoloured by
  /// AppKit to match a light or dark menu bar. The SF Symbol ladder stays as a
  /// fallback for the case where the asset catalog fails to resolve, because an
  /// invisible status button is worse than a generic one.
  private static func statusImage() -> NSImage? {
    if let mark = NSImage(named: "MenuBarIcon") {
      mark.size = NSSize(width: 18, height: 18)
      return mark
    }

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

  private func configureClipboardItem() {
    Self.claim(clipboardItem, as: "TidyClipboard")
    guard let button = clipboardItem.button else { return }

    button.image = Self.clipboardImage()
    button.image?.isTemplate = true
    button.toolTip = "Clipboard history"
    button.target = self
    button.action = #selector(clipboardItemClicked(_:))
    button.sendAction(on: [.leftMouseUp, .rightMouseUp])
  }

  /// Same fallback ladder as the vitals icon, for the same reason: SF Symbol
  /// availability varies by macOS version.
  private static func clipboardImage() -> NSImage? {
    let candidates = [
      "list.clipboard",
      "doc.on.clipboard",
      "doc.on.doc",
      "paperclip",
    ]
    for name in candidates {
      if let image = NSImage(systemSymbolName: name, accessibilityDescription: "Clipboard") {
        return image
      }
    }
    return NSImage(named: NSImage.multipleDocumentsName)
  }

  // MARK: - Network readout

  /// Creates the readout, or removes it, to match the user's preference.
  ///
  /// Removing rather than hiding: `NSStatusItem.isVisible = false` leaves a
  /// zero-width item that still reserves its slot in the ordering, and the
  /// setting is meant to give the menu bar space back.
  private func configureNetworkItem() {
    NetworkStore.shared.load()

    guard NetworkStore.shared.prefs.menuBarEnabled else {
      if let networkItem { NSStatusBar.system.removeStatusItem(networkItem) }
      networkItem = nil
      networkItemWidth = 0
      return
    }

    guard networkItem == nil else {
      // Already there; the style may have changed under it. A compact readout
      // must be allowed to shrink back out of a two-line item's width, so the
      // "only ever grows" floor is dropped here and rebuilt from the new style.
      networkItemWidth = 0
      networkItem?.length = NSStatusItem.variableLength
      renderNetwork(NetworkMonitor.shared.latest)
      return
    }

    // Variable length, unlike the two glyph items: the readout is text, and how
    // wide it needs to be depends on how fast the machine is moving bytes.
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    networkItem = item
    // Named, like the other two — and named rather than positional especially
    // here, because this item comes and goes with the preference and an
    // ordinal would land on a different item each time it did.
    Self.claim(item, as: "TidyNetwork")

    guard let button = item.button else { return }
    button.toolTip = "Network activity"
    button.target = self
    button.action = #selector(networkItemClicked(_:))
    button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    renderNetwork(NetworkMonitor.shared.latest)
  }

  private func observeNetwork() {
    networkObserver = NetworkMonitor.shared.addObserver { [weak self] sample in
      self?.renderNetwork(sample)
    }
    prefsObserver = NotificationCenter.default.addObserver(
      forName: NetworkChannel.prefsChanged,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.configureNetworkItem()
    }
  }

  @objc private func networkItemClicked(_ sender: NSStatusBarButton) {
    if NSApp.currentEvent?.type == .rightMouseUp {
      showContextMenu()
    } else {
      togglePopover(from: sender, section: "network")
    }
  }

  private func renderNetwork(_ sample: NetworkSample) {
    guard let item = networkItem, let button = item.button else { return }

    let prefs = NetworkStore.shared.prefs
    let bits = prefs.useBits
    let down = NetworkMonitor.formatRate(sample.downBytesPerSecond, bits: bits)
    let up = NetworkMonitor.formatRate(sample.upBytesPerSecond, bits: bits)

    switch prefs.menuBarStyle {
    case .twoLine:
      button.image = nil
      button.imagePosition = .noImage
      button.attributedTitle = Self.stackedTitle(down: down, up: up)
    case .sparkline:
      button.image = Self.sparklineImage(from: NetworkMonitor.shared.ring)
      button.imagePosition = .imageLeading
      button.attributedTitle = Self.stackedTitle(down: down, up: up)
    case .compact:
      button.image = nil
      button.imagePosition = .noImage
      button.attributedTitle = Self.compactTitle(down: down, up: up)
    }

    // `variableLength` re-measures on every title change, so the item — and
    // every icon to its left — twitches sideways each time a digit appears or
    // disappears. Pinning the length to the widest it has been stops that. It
    // only ever grows within a session, and resets when the style changes.
    var width = button.attributedTitle.size().width + Self.networkTitleInset
    if button.imagePosition != .noImage, let image = button.image {
      width += image.size.width + Self.networkImageGap
    }
    let rounded = (width / 4).rounded(.up) * 4
    if rounded > networkItemWidth {
      networkItemWidth = rounded
      item.length = rounded
    }
  }

  /// Padding either side of the readout, matching what AppKit gives a status
  /// item's own content.
  private static let networkTitleInset: CGFloat = 12
  private static let networkImageGap: CGFloat = 3

  /// Two stacked lines inside a 22pt menu bar. The font is small and its digits
  /// are monospaced so the columns line up and the numbers do not jiggle;
  /// `labelColor` follows the menu bar between light and dark on its own, which
  /// a hard-coded white or black would not.
  private static func stackedTitle(down: String, up: String) -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.maximumLineHeight = 10
    paragraph.minimumLineHeight = 10
    paragraph.alignment = .right

    return NSAttributedString(
      string: "↓ \(down)\n↑ \(up)",
      attributes: [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
        .foregroundColor: NSColor.labelColor,
        .paragraphStyle: paragraph,
        // Nudged up so the pair sits centred rather than riding the baseline.
        .baselineOffset: 2,
      ]
    )
  }

  /// One line, for people who would rather have the width back.
  private static func compactTitle(down: String, up: String) -> NSAttributedString {
    NSAttributedString(
      string: "↓ \(down)  ↑ \(up)",
      attributes: [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
        .foregroundColor: NSColor.labelColor,
      ]
    )
  }

  /// The last minute of activity, drawn as two mirrored area charts — download
  /// filling downward from the middle, upload filling upward.
  ///
  /// A template image, so AppKit tints it for the menu bar it lands on. That
  /// costs the colour, which is fine: at this size a shape reads and a hue does
  /// not, and a coloured menu bar icon is the wrong citizen anyway.
  private static func sparklineImage(from ring: [NetworkSample]) -> NSImage {
    let width: CGFloat = 34
    let height: CGFloat = 16
    let samples = Array(ring.suffix(60))

    let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
      guard samples.count > 1 else { return true }

      // Scaled to the window's own peak, not an absolute ceiling: the point is
      // the shape of the last minute, and a fixed ceiling would leave every
      // ordinary minute as a flat line along the bottom.
      let peak = samples
        .map { max($0.downBytesPerSecond, $0.upBytesPerSecond) }
        .max() ?? 0
      guard peak > 0 else { return true }

      let middle = rect.midY
      let half = rect.height / 2
      let step = rect.width / CGFloat(samples.count - 1)

      func draw(_ value: (NetworkSample) -> Double, upward: Bool) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: middle))
        for (index, sample) in samples.enumerated() {
          let fraction = CGFloat(value(sample) / peak)
          let y = upward ? middle + fraction * half : middle - fraction * half
          path.line(to: NSPoint(x: rect.minX + CGFloat(index) * step, y: y))
        }
        path.line(to: NSPoint(x: rect.maxX, y: middle))
        path.close()
        path.fill()
      }

      NSColor.black.withAlphaComponent(0.55).setFill()
      draw({ $0.downBytesPerSecond }, upward: false)
      NSColor.black.setFill()
      draw({ $0.upBytesPerSecond }, upward: true)
      return true
    }

    image.isTemplate = true
    return image
  }

  @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
    if NSApp.currentEvent?.type == .rightMouseUp {
      showContextMenu()
    } else {
      togglePopover(from: sender, section: nil)
    }
  }

  @objc private func clipboardItemClicked(_ sender: NSStatusBarButton) {
    if NSApp.currentEvent?.type == .rightMouseUp {
      showContextMenu()
    } else {
      togglePopover(from: sender, section: "clipboard")
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
    // Clear, so what shows through is the popover's own material — the same
    // blurred, appearance-following backdrop macOS gives its menus. The panel
    // paints its cards and text on top of that and nothing else.
    controller.backgroundColor = .clear
    RegisterGeneratedPlugins(registry: controller)
    // The popover reads the machine's vitals and what is running, so it needs
    // the Performance channel as well as the file one. Without this the panel
    // renders and every native call quietly returns nothing.
    SystemChannel.register(with: engine.binaryMessenger)
    PerformanceChannel.register(with: engine.binaryMessenger)
    RecycleBinChannel.register(with: engine.binaryMessenger)
    ClipboardChannel.register(with: engine.binaryMessenger)
    NetworkChannel.register(with: engine.binaryMessenger)

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

    // The popover engine is started headless, before any window exists, and
    // does not reliably pick up the system appearance the way the main window
    // does — it has been observed rendering the light theme onto a dark
    // popover material. So the appearance is told to it explicitly rather than
    // inferred, both on demand and whenever the user switches.
    appearanceObserver = DistributedNotificationCenter.default.addObserver(
      forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.publishAppearance()
    }
  }

  private static var isDarkAppearance: Bool {
    NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
  }

  private func publishAppearance() {
    channel?.invokeMethod("appearanceChanged", arguments: ["dark": Self.isDarkAppearance])
  }

  /// A click on an icon opens its panel, and a second click on the *same* icon
  /// closes it. A click on the other icon while the panel is open moves the
  /// panel rather than dismissing it — the two icons are two views of one
  /// panel, and going between them should not cost a round trip through
  /// closed.
  private func togglePopover(from button: NSStatusBarButton, section: String?) {
    // `isShown` can outlive the window — Dart closes the popover itself after
    // a clip is copied — and a stale true means every later click is read as
    // "close the thing that is already closed". The window is the truth.
    let onScreen = popover.isShown
      && (popover.contentViewController?.view.window?.isVisible ?? false)

    if onScreen && anchor === button {
      popover.performClose(nil)
      return
    }
    if popover.isShown {
      // close(), not performClose(): the animated close is still running when
      // the next show starts, and the popover comes back up empty.
      popover.close()
    }
    showPopover(section: section, from: button)
  }

  /// Opens the popover on the vitals icon. The hot key comes in here with
  /// "clipboard", which lands on the clipboard icon instead — a panel about
  /// clips should hang from the icon that means clips.
  func showPopover(section: String?) {
    let preferred: NSStatusBarButton?
    switch section {
    case "clipboard": preferred = clipboardItem.button
    // Falls back to the vitals icon when the readout is switched off — the panel
    // is still reachable, it just has no icon of its own to hang from.
    case "network": preferred = networkItem?.button ?? statusItem.button
    default: preferred = statusItem.button
    }
    showPopover(section: section, from: preferred ?? statusItem.button)
  }

  private func showPopover(section: String?, from button: NSStatusBarButton?) {
    guard let button else { return }
    if popover.isShown,
       popover.contentViewController?.view.window?.isVisible == true {
      // Already open on this icon: no need to re-present it, but the caller
      // still wants the panel pointed at their section.
      channel?.invokeMethod("popoverDidOpen", arguments: arguments(for: section))
      return
    }
    if popover.isShown { popover.close() }
    // Activating a regular app orders *all* its windows front, and if the main
    // window is sitting on another Space macOS switches Spaces to get there.
    // That is what happened when the status item was clicked from someone
    // else's full screen app: the panel never appeared over the full screen
    // window, it appeared on the Space Tidy's own window was on. So activate
    // only when there is nothing to be dragged out of another Space.
    if !mainWindowIsOnAnotherSpace {
      NSApp.activate(ignoringOtherApps: true)
    }
    currentWidth = switch section {
    case "clipboard": clipboardPanelWidth
    case "network": networkPanelWidth
    default: panelWidth
    }
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    anchor = button
    // Width is applied *after* showing, not before. A hidden Flutter view
    // produces no frames, so a resize asked for while the popover is off
    // screen waits for a frame that cannot arrive and times out a second
    // later. On screen the same call is answered immediately.
    popover.contentSize = NSSize(width: currentWidth, height: popover.contentSize.height)
    letPanelFollowTheMenuBar()
    publishAppearance()
    channel?.invokeMethod("popoverDidOpen", arguments: arguments(for: section))
  }

  /// True when the main window exists on a Space other than the one the user
  /// is looking at — the case where activating would move them.
  private var mainWindowIsOnAnotherSpace: Bool {
    guard let window = NSApp.windows.first(where: { $0 is MainFlutterWindow }),
          window.isVisible
    else { return false }
    return !window.isOnActiveSpace
  }

  /// The status item is visible from every Space, including inside another
  /// app's full screen. Its panel has to be able to follow it there.
  ///
  /// AppKit creates the popover's window lazily, on first show, and gives it
  /// the app's default behaviour — which ties it to one Space. This runs after
  /// every show rather than once at setup because there is no window to
  /// configure until then.
  private func letPanelFollowTheMenuBar() {
    guard let window = popover.contentViewController?.view.window else { return }
    window.collectionBehavior.insert(.canJoinAllSpaces)
    window.collectionBehavior.insert(.fullScreenAuxiliary)

    // Regardless: the app may not be the active one, and an inactive app's
    // ordinary orderFront is ignored.
    window.orderFrontRegardless()
    window.makeKey()
  }

  private func showClipPreview(id: String, rowTop: CGFloat) {
    guard let entry = ClipboardStore.shared.entries.first(where: { $0.id == id }),
          let window = popover.contentViewController?.view.window
    else {
      preview.hide()
      return
    }
    preview.show(entry: entry, beside: window, rowTop: rowTop)
  }

  private func arguments(for section: String?) -> [String: Any]? {
    guard let section else { return nil }
    return ["section": section]
  }

  /// The panel samples CPU and running processes on a timer while it is on
  /// screen. Nobody is reading it once it closes, and a cleaner that samples
  /// every two seconds forever is the kind of thing this app exists to find.
  func popoverDidClose(_ notification: Notification) {
    anchor = nil
    // The preview belongs to a row that is no longer on screen.
    preview.hide()
    channel?.invokeMethod("popoverDidClose", arguments: nil)
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "appearance":
      result(["dark": Self.isDarkAppearance])
    case "setPopoverHeight":
      if let height = (call.arguments as? [String: Any])?["height"] as? Double {
        setPopoverHeight(CGFloat(height))
      }
      result(nil)
    case "showClipPreview":
      let arguments = call.arguments as? [String: Any] ?? [:]
      showClipPreview(
        id: arguments["id"] as? String ?? "",
        rowTop: CGFloat((arguments["top"] as? Double) ?? 0)
      )
      result(nil)
    case "hideClipPreview":
      preview.hide()
      result(nil)
    case "closePopover":
      popover.performClose(nil)
      result(nil)
    case "openMainWindow":
      popover.performClose(nil)
      openMainWindow()
      // The popover runs in its own engine and cannot reach the main window's
      // router, so the route is handed across natively.
      if let route = (call.arguments as? [String: Any])?["route"] as? String {
        PopoverChannel.navigateMainWindow(to: route)
      }
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
    popover.contentSize = NSSize(width: currentWidth, height: clamped)
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

  deinit {
    if let appearanceObserver {
      DistributedNotificationCenter.default.removeObserver(appearanceObserver)
    }
    if let prefsObserver {
      NotificationCenter.default.removeObserver(prefsObserver)
    }
    if let networkObserver {
      NetworkMonitor.shared.removeObserver(networkObserver)
    }
  }
}


/// The main window's end of the popover channel.
///
/// Reverse direction only: the popover cannot reach the main window's router
/// across the isolate boundary, so `openMainWindow` carries a route and this
/// hands it to the engine that owns one.
enum PopoverChannel {
  static let channelName = "com.yunweneric.tidy/popover"

  /// Held for the life of the app; the main window's engine outlives its
  /// window, and a channel that was let go would silently stop delivering.
  private static var mainWindowChannel: FlutterMethodChannel?

  static func registerMainWindow(with messenger: FlutterBinaryMessenger) {
    mainWindowChannel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
  }

  static func navigateMainWindow(to route: String) {
    mainWindowChannel?.invokeMethod("navigateTo", arguments: ["route": route])
  }
}

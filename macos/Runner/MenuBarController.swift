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
    // Named on the line after each is made, before the next one exists. See
    // `claim` for why the gap between those two lines is the whole bug.
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    Self.claim(statusItem, as: "TidyVitals")
    clipboardItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    Self.claim(clipboardItem, as: "TidyClipboard")
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

  /// Files an item under a name of our own, on the line after it is created.
  ///
  /// Without an `autosaveName`, AppKit files a status item under an ordinal —
  /// `Item-0`, `Item-1`, `Item-2` — handed out in creation order. That
  /// namespace is **shared with every other app on the machine**, not private
  /// to this one, and macOS 26 keeps menu bar visibility centrally now that
  /// Control Center owns the bar: `com.apple.controlcenter` carries
  /// `NSStatusItem Visible Item-0` through `Item-9`, and the switches in
  /// System Settings › Control Center › Menu Bar write into exactly those keys.
  /// Turning *another* app's icon off there turns off whichever of ours happens
  /// to be holding that ordinal — which is not hypothetical: switching Cursor's
  /// item off hid all of Tidy's, and switching it back on brought them back.
  ///
  /// It is also why adding the readout took the other two with it. Ordinals are
  /// positional, so a third item renumbers its neighbours, and each one lands
  /// on a different stranger's verdict.
  ///
  /// The ordinal is handed out by `statusItem(withLength:)` itself, so the name
  /// has to be assigned on the very next line. Naming later still moves an item
  /// out of the shared bucket, but only after it has already read somebody
  /// else's answer on the way in.
  private static func claim(_ item: NSStatusItem, as name: String) {
    item.autosaveName = name
  }

  /// Asks for an item to be on the bar.
  ///
  /// `behavior` deliberately does not include `.removalAllowed`, so nothing in
  /// Tidy hides these: a stored `false` is either an inherited ordinal verdict
  /// or Control Center's, never something the user asked of *us*. Asking for
  /// `true` is not overriding a preference, it is declining to inherit someone
  /// else's.
  ///
  /// Called on every launch and again every time the readout is switched,
  /// because switching it is the other moment the bar gets rearranged
  /// underneath the items that are staying put.
  private static func show(_ item: NSStatusItem) {
    item.isVisible = true
  }

  private func configureStatusItem() {
    guard let button = statusItem.button else { return }

    // Sized and centred by `menuBarGlyph`, which also marks it a template so
    // AppKit recolours it for a light or dark menu bar.
    button.image = Self.statusImage()
    button.imagePosition = .imageOnly
    button.toolTip = "Tidy"
    button.target = self
    button.action = #selector(statusItemClicked(_:))
    button.sendAction(on: [.leftMouseUp, .rightMouseUp])

    Self.show(statusItem)
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
      return menuBarGlyph(mark)
    }

    return symbolGlyph(
      [
        "internaldrive.badge.xmark",
        "externaldrive.badge.minus",
        "trash.circle",
        "trash",
      ],
      describedAs: "Tidy"
    ) ?? NSImage(named: NSImage.trashEmptyName).map(menuBarGlyph)
  }

  // MARK: - Glyphs

  /// The canvas every glyph is drawn into, and the box its *ink* is fitted
  /// inside it.
  ///
  /// 18pt canvas in a 22pt menu bar leaves the breathing room macOS gives its
  /// own items. 16pt of ink inside it is what the system glyphs sitting either
  /// side of us measure — Wi-Fi, the keyboard indicator, Control Center — so a
  /// glyph normalised to it reads as the same size as its neighbours rather
  /// than the same size as some canvas nobody can see.
  private static let glyphCanvas = NSSize(width: 18, height: 18)
  private static let glyphInk = NSSize(width: 16, height: 16)

  /// Redraws a glyph so its ink is centred inside `glyphCanvas` and fitted to
  /// `glyphInk`.
  ///
  /// A status button places its image using the image's own size and alignment
  /// rect, so glyphs from different sources line up only by luck: the app mark
  /// is a square 22pt asset, an SF Symbol is whatever its design and the system
  /// font make it — typically taller than it is wide, and carrying an alignment
  /// rect inset for its optical baseline. Left alone the two sit at different
  /// scales *and* on different lines.
  ///
  /// **Fitted by ink, not by canvas.** Matching the canvases is not enough,
  /// because a canvas is mostly transparency and every source pads differently:
  /// the app mark carries 15×13 of drawing inside 22×22, an SF Symbol barely
  /// 1pt. Scaling those canvases to a common size scales the *padding* to a
  /// common size and leaves the mark visibly the runt of the menu bar. So the
  /// transparent margin is measured off first and only what is drawn gets
  /// scaled, which is also the only reading of "the same size" that matches
  /// what the eye is comparing.
  ///
  /// What comes out has identical bounds and no alignment inset, so "centred
  /// the same" falls out of AppKit's own centring rather than being chased per
  /// icon.
  private static func menuBarGlyph(_ source: NSImage) -> NSImage {
    let ink = inkBounds(of: source) ?? NSRect(origin: .zero, size: source.size)
    guard ink.width > 0, ink.height > 0 else { return source }

    let scale = min(glyphInk.width / ink.width, glyphInk.height / ink.height)
    let drawn = NSSize(width: ink.width * scale, height: ink.height * scale)

    let glyph = NSImage(size: glyphCanvas, flipped: false) { rect in
      source.draw(
        in: NSRect(
          x: rect.midX - drawn.width / 2,
          y: rect.midY - drawn.height / 2,
          width: drawn.width,
          height: drawn.height
        ),
        from: ink,
        operation: .sourceOver,
        fraction: 1
      )
      return true
    }
    glyph.isTemplate = true // Adapts to light/dark menu bars.
    return glyph
  }

  /// The part of a glyph that actually has something drawn in it, in the
  /// image's own coordinates.
  ///
  /// Runs twice, at launch, over images of a few hundred pixels — the naive
  /// scan is far cheaper than the machinery that would avoid it.
  private static func inkBounds(of image: NSImage) -> NSRect? {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0
    else { return nil }

    var minX = bitmap.pixelsWide, maxX = -1
    var minY = bitmap.pixelsHigh, maxY = -1
    for y in 0..<bitmap.pixelsHigh {
      for x in 0..<bitmap.pixelsWide {
        // Anti-aliased edges fade to nothing, so the threshold is just above
        // "transparent" rather than at it — otherwise the bounds creep outward
        // by a pixel of haze that is not really part of the drawing.
        guard let pixel = bitmap.colorAt(x: x, y: y), pixel.alphaComponent > 0.05
        else { continue }
        minX = min(minX, x)
        maxX = max(maxX, x)
        minY = min(minY, y)
        maxY = max(maxY, y)
      }
    }
    guard maxX >= minX, maxY >= minY else { return nil }

    let scaleX = image.size.width / CGFloat(bitmap.pixelsWide)
    let scaleY = image.size.height / CGFloat(bitmap.pixelsHigh)
    // `colorAt` counts rows down from the top; an NSImage counts up from the
    // bottom, so the row range has to be turned over on the way out.
    return NSRect(
      x: CGFloat(minX) * scaleX,
      y: CGFloat(bitmap.pixelsHigh - 1 - maxY) * scaleY,
      width: CGFloat(maxX - minX + 1) * scaleX,
      height: CGFloat(maxY - minY + 1) * scaleY
    )
  }

  /// The first SF Symbol in `names` that this macOS version has, normalised.
  ///
  /// The ladder exists because symbol availability varies by OS version, and an
  /// invisible status button is worse than a generic one. The point size does
  /// not decide the final size — `menuBarGlyph` does, off the ink — it decides
  /// how many pixels there are to measure and rescale, so it is asked for
  /// generously rather than left to the control font.
  private static func symbolGlyph(_ names: [String], describedAs description: String) -> NSImage? {
    let configuration = NSImage.SymbolConfiguration(pointSize: 32, weight: .regular)
    for name in names {
      guard let image = NSImage(systemSymbolName: name, accessibilityDescription: description)
      else { continue }
      return menuBarGlyph(image.withSymbolConfiguration(configuration) ?? image)
    }
    return nil
  }

  private func configureClipboardItem() {
    guard let button = clipboardItem.button else { return }

    button.image = Self.clipboardImage()
    button.imagePosition = .imageOnly
    button.toolTip = "Clipboard history"
    button.target = self
    button.action = #selector(clipboardItemClicked(_:))
    button.sendAction(on: [.leftMouseUp, .rightMouseUp])

    Self.show(clipboardItem)
  }

  /// Same fallback ladder as the vitals icon, for the same reason: SF Symbol
  /// availability varies by macOS version.
  private static func clipboardImage() -> NSImage? {
    symbolGlyph(
      [
        "list.clipboard",
        "doc.on.clipboard",
        "doc.on.doc",
        "paperclip",
      ],
      describedAs: "Clipboard"
    ) ?? NSImage(named: NSImage.multipleDocumentsName).map(menuBarGlyph)
  }

  // MARK: - Network readout

  /// Creates the readout, or removes it, to match the user's preference.
  ///
  /// Removing rather than hiding: `NSStatusItem.isVisible = false` leaves a
  /// zero-width item that still reserves its slot in the ordering, and the
  /// setting is meant to give the menu bar space back.
  private func configureNetworkItem() {
    NetworkStore.shared.load()

    // The two glyph items are re-asserted here as well as at launch. Adding or
    // removing an item is exactly when macOS re-reads what belongs on the bar,
    // and the last thing to have written an answer for them may have been
    // Control Center, on some other app's behalf.
    Self.show(statusItem)
    Self.show(clipboardItem)

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
    //
    // Named on the next line, and more sharply here than anywhere else: this is
    // the one item that comes and goes with a preference, so an ordinal would
    // be re-issued to somebody every time it did.
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    Self.claim(item, as: "TidyNetwork")
    networkItem = item

    guard let button = item.button else { return }
    button.toolTip = "Network activity"
    button.target = self
    button.action = #selector(networkItemClicked(_:))
    button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    renderNetwork(NetworkMonitor.shared.latest)

    // Shown once the readout is in it, unlike the two glyph items. Those are
    // `squareLength` and have a width from the moment they exist; this one is
    // `variableLength`, so until the first `renderNetwork` it measures nothing,
    // and asking to be shown at zero width is a question with no good answer.
    Self.show(item)
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

    let readout = Self.readout(
      down: down,
      up: up,
      style: prefs.menuBarStyle,
      ring: NetworkMonitor.shared.ring
    )
    // The rates used to be the button's title, which is what VoiceOver read.
    // They are ink in an image now, so the numbers have to be said out loud
    // somewhere else.
    readout.accessibilityDescription = "Down \(down), up \(up)"
    button.image = readout
    button.imagePosition = .imageOnly

    // `variableLength` re-measures on every change, so the item — and every
    // icon to its left — twitches sideways each time a digit appears or
    // disappears. Pinning the length to the widest it has been stops that. It
    // only ever grows within a session, and resets when the style changes.
    let rounded = ((readout.size.width + Self.networkInset) / 4).rounded(.up) * 4
    if rounded > networkItemWidth {
      networkItemWidth = rounded
      item.length = rounded
    }
  }

  /// Padding either side of the readout, matching what AppKit gives a status
  /// item's own content.
  private static let networkInset: CGFloat = 12

  /// The gap between the chart and the numbers beside it.
  private static let networkGap: CGFloat = 4

  /// The whole readout as one template image, centred on the bar's middle.
  ///
  /// Drawn rather than handed to `attributedTitle` because AppKit gives no way
  /// to say where a title sits vertically. It centres the string's *typographic*
  /// box — ascender to descender, with `stackedTitle`'s forced line height
  /// clipping both — and for two stacked lines that box is not where the ink is,
  /// so the pair rides low. The fix for that used to be a hand-tuned
  /// `baselineOffset` calibrated against a 22pt bar; macOS 26's menu bar is
  /// taller, and a nudge that centred the numbers there leaves them high here.
  /// The chart had the same problem from the other side: `.imageLeading` centres
  /// it against the title's box rather than the bar's.
  ///
  /// Composing both moves the centring from AppKit's guess to arithmetic — one
  /// canvas exactly the bar's own thickness, every piece placed against its
  /// middle — so the chart and the numbers share a centre line whatever height
  /// the bar turns out to have.
  private static func readout(
    down: String,
    up: String,
    style: NetworkMenuBarStyle,
    ring: [NetworkSample]
  ) -> NSImage {
    let text =
      style == .compact
      ? compactTitle(down: down, up: up)
      : stackedTitle(down: down, up: up)

    // `boundingRect` rather than `size()`: the stacked style is two lines, and
    // only line-fragment layout measures the second one.
    let measured = text.boundingRect(
      with: NSSize(
        width: CGFloat.greatestFiniteMagnitude,
        height: CGFloat.greatestFiniteMagnitude
      ),
      options: [.usesLineFragmentOrigin]
    )
    let textSize = NSSize(
      width: measured.width.rounded(.up),
      height: measured.height.rounded(.up)
    )

    let chart = style == .sparkline ? sparklineImage(from: ring) : nil
    let chartWidth = chart.map { $0.size.width + networkGap } ?? 0

    let image = NSImage(
      size: NSSize(
        width: chartWidth + textSize.width,
        height: NSStatusBar.system.thickness
      ),
      flipped: false
    ) { rect in
      if let chart {
        chart.draw(
          in: NSRect(
            x: rect.minX,
            y: rect.midY - chart.size.height / 2,
            width: chart.size.width,
            height: chart.size.height
          )
        )
      }
      text.draw(
        with: NSRect(
          x: rect.minX + chartWidth,
          y: rect.midY - textSize.height / 2,
          width: textSize.width,
          height: textSize.height
        ),
        options: [.usesLineFragmentOrigin]
      )
      return true
    }

    // Template, so the menu bar tints it. That is the same `labelColor` the
    // text used to ask for, arrived at by the route that also follows the bar
    // between light and dark without being told.
    image.isTemplate = true
    return image
  }

  /// Two stacked lines. The font is small and its digits are monospaced so the
  /// columns line up and the numbers do not jiggle.
  ///
  /// Drawn in black rather than `labelColor` because `readout` templates the
  /// composited image, which keeps the alpha and throws the colour away — the
  /// menu bar supplies the ink.
  private static func stackedTitle(down: String, up: String) -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.maximumLineHeight = 10
    paragraph.minimumLineHeight = 10
    paragraph.alignment = .right

    return NSAttributedString(
      string: "↓ \(down)\n↑ \(up)",
      attributes: [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
        .foregroundColor: NSColor.black,
        .paragraphStyle: paragraph,
      ]
    )
  }

  /// One line, for people who would rather have the width back. Black for the
  /// same reason as `stackedTitle`.
  private static func compactTitle(down: String, up: String) -> NSAttributedString {
    NSAttributedString(
      string: "↓ \(down)  ↑ \(up)",
      attributes: [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
        .foregroundColor: NSColor.black,
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

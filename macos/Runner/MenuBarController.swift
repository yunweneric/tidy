import Cocoa
import FlutterMacOS

/// Owns the menu bar status items and the popover they present.
///
/// **N icons, one popover.** The popover is shared because the panel behind it
/// is one Flutter view: a second popover would need a second engine, which is a
/// whole Dart isolate to save an anchor point. Which icons exist is the user's
/// choice, and it is the one preference here with a cost they can see:
///
/// - `.consolidated` — one icon. Every surface is a tab inside its panel.
/// - `.separate` — an icon per surface. Icons answer different questions, and
///   one that hides another makes the clipboard a place you have to remember
///   rather than a place you can see. It costs menu bar width to say so.
///
/// The bar is rebuilt wholesale by `syncStatusItems()` whenever that preference
/// changes. Nothing here is ever hidden — see `show(_:)` — so a surface the
/// user switched off has its item *removed*, and one they switched on is made
/// fresh, named on the very next line.
///
/// The popover hosts a *second* Flutter engine running the `menuBarMain`
/// entrypoint, so the panel is real Flutter UI rather than an NSMenu. That
/// engine is its own Dart isolate — the two views stay in sync through the
/// on-disk scan cache, not through shared memory.
final class MenuBarController: NSObject, NSPopoverDelegate {
  private static let channelName = "com.yunweneric.tidy/popover"

  /// Every status item currently on the bar, by the surface it speaks for.
  ///
  /// The single source of truth for what exists. It used to be three fields,
  /// which meant "is this item on the bar" was answered three different ways
  /// and adding a fourth meant finding all of them.
  private var items: [MenuBarSurface: NSStatusItem] = [:]

  /// The widest each text readout has been since its style last changed, so an
  /// item stops shuffling its neighbours every time a digit is added or
  /// dropped. Only the surfaces with `hasReadout` ever appear here.
  private var itemWidths: [MenuBarSurface: CGFloat] = [:]

  private var networkObserver: UUID?
  private var prefsObserver: Any?
  private var menuBarPrefsObserver: Any?
  private var aiUsageObserver: Any?

  /// The item a context menu is currently attached to, so it can be detached
  /// again from the same one. Previously always the vitals item, which stopped
  /// being safe once the vitals item became something the user can remove.
  private weak var contextMenuItem: NSStatusItem?

  /// Which icon the popover is currently hanging from, so a second click on
  /// the *same* icon closes it while a click on the other one moves it.
  private weak var anchor: NSStatusBarButton?

  private let popover = NSPopover()
  private let engine: FlutterEngine
  private var channel: FlutterMethodChannel?
  private var appearanceObserver: Any?

  /// See `forwardClicksIntoThePanel`. Held so it can be torn down with the
  /// controller rather than outliving it.
  private var clickForwarder: Any?

  // The panel is a dashboard now, not a menu: three vitals tiles across the
  // top and a live process table below them need room to be read at a glance,
  // which a menu-width strip does not have. The narrower surfaces declare their
  // own width on `MenuBarSurface`; this one is also what the consolidated panel
  // uses for *every* tab, because a tab strip that resized its own container
  // would move the thing you were about to click.
  private let panelWidth: CGFloat = 460

  private let minPanelHeight: CGFloat = 160
  private let maxPanelHeight: CGFloat = 760

  /// Whichever width the panel currently on screen asked for.
  private var currentWidth: CGFloat = 460

  /// The section on screen, so a height reported from Dart is filed against
  /// whichever panel actually measured it.
  private var currentSection = MenuBarController.dashboardSection

  /// What each section measured the last time it was open.
  ///
  /// The panel reports its own height, which it can only do once Dart has laid
  /// the section out — a frame or two after the popover is already on screen.
  /// Without somewhere to remember it, every visit to a section ends with the
  /// panel visibly growing or shrinking under a reader who has already started
  /// reading. Remembering costs one number per section and makes the second
  /// visit onwards arrive at the right size.
  private var panelHeights: [String: CGFloat] = [:]

  /// The section the vitals icon means. It is the one that arrives as `nil`,
  /// having no section to ask for, so it needs a name to be filed under.
  private static let dashboardSection = MenuBarSurface.dashboard.rawValue

  private lazy var preview = ClipPreviewPanel()

  override init() {
    engine = FlutterEngine(
      name: "menu_bar",
      project: FlutterDartProject(),
      allowHeadlessExecution: true
    )
    super.init()

    // Preferences first, and read from `settings.json` rather than waited for:
    // the items are built on the next line, which is long before any Flutter
    // engine has finished starting. A bar that collapses to one icon and then
    // sprouts three more a second later is a bug the user can see.
    MenuBarStore.shared.load()
    AiUsageStore.shared.load()

    syncStatusItems()
    configurePopover()
    observeNetwork()
    observePreferences()
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

  /// Builds the bar to match the preferences, and rebuilds it when they change.
  ///
  /// Generalised from what the network readout did alone, and it keeps that
  /// function's shape because each branch of it was load-bearing:
  ///
  /// - **Switched off → removed**, not hidden. `isVisible = false` leaves a
  ///   zero-width item still holding its slot in the ordering, and the point of
  ///   the setting is to give the width back.
  /// - **Already there → reconfigured in place.** Tearing an item down and
  ///   rebuilding it re-issues its ordinal, which is the whole hazard `claim`
  ///   describes. The style may have changed under it, so the width floor is
  ///   dropped and rebuilt rather than kept.
  /// - **Survivors re-asserted.** Adding or removing *any* item is exactly when
  ///   macOS re-reads what belongs on the bar, and the last thing to have
  ///   written an answer for the others may have been Control Center, on some
  ///   other app's behalf.
  private func syncStatusItems() {
    let wanted = MenuBarStore.shared.prefs.visibleSurfaces

    for (surface, item) in items where !wanted.contains(surface) {
      NSStatusBar.system.removeStatusItem(item)
      items[surface] = nil
      itemWidths[surface] = nil
    }

    // In declared order, so the bar reads the same way every time rather than
    // in whatever order a dictionary happened to hand them over.
    for surface in MenuBarSurface.ordered where wanted.contains(surface) {
      if let existing = items[surface] {
        // The readout's style may have moved under it. A compact readout has to
        // be allowed to shrink back out of a two-line item's width, so the
        // "only ever grows" floor is dropped here and rebuilt from the new one.
        if surface.hasReadout {
          itemWidths[surface] = nil
          existing.length = NSStatusItem.variableLength
        }
        render(surface)
        Self.show(existing)
        continue
      }
      make(surface)
    }
  }

  /// Creates one item and puts it on the bar.
  private func make(_ surface: MenuBarSurface) {
    // Text items measure themselves; glyph items are square from the moment
    // they exist.
    let length = surface.hasReadout
      ? NSStatusItem.variableLength
      : NSStatusItem.squareLength

    // Named on the line after it is made, before anything else can be created.
    // See `claim` for why the gap between those two lines is the whole bug.
    let item = NSStatusBar.system.statusItem(withLength: length)
    Self.claim(item, as: surface.autosaveName)
    items[surface] = item

    guard let button = item.button else { return }
    button.toolTip = surface.tooltip
    button.target = self
    button.action = #selector(itemClicked(_:))
    button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    button.imagePosition = .imageOnly
    render(surface)

    // A readout is shown once there is something in it. Until the first render
    // a `variableLength` item measures nothing, and asking to be shown at zero
    // width is a question with no good answer.
    Self.show(item)
  }

  /// Draws whatever this surface puts in the bar — a glyph, or live text.
  private func render(_ surface: MenuBarSurface) {
    switch surface {
    case .dashboard:
      // Sized and centred by `menuBarGlyph`, which also marks it a template so
      // AppKit recolours it for a light or dark menu bar.
      items[surface]?.button?.image = Self.statusImage()
    case .clipboard:
      items[surface]?.button?.image = Self.clipboardImage()
    case .network:
      renderNetwork(NetworkMonitor.shared.latest)
    case .aiUsage:
      renderAiUsage()
    }
  }

  /// The surface a button belongs to, or nil if it is not one of ours.
  private func surface(for button: NSStatusBarButton) -> MenuBarSurface? {
    items.first { $0.value.button === button }?.key
  }

  /// The item an anchor should hang from.
  ///
  /// Falls back to whatever is on the bar when the asked-for surface has no
  /// icon — the panel is still reachable, it just has no icon of its own. That
  /// is the ⌘⇧V-with-no-clipboard-icon case, and in the consolidated layout it
  /// is every case.
  private func anchorButton(for surface: MenuBarSurface?) -> NSStatusBarButton? {
    if let surface, let button = items[surface]?.button { return button }
    if let button = items[.dashboard]?.button { return button }
    return MenuBarSurface.ordered.compactMap { items[$0]?.button }.first
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

  private func observeNetwork() {
    networkObserver = NetworkMonitor.shared.addObserver { [weak self] sample in
      self?.renderNetwork(sample)
    }
  }

  /// Rebuilds the bar whenever anything it is drawn from moves.
  ///
  /// Three sources, because three different things can change what is on the
  /// bar: which items the user wants, how the network readout is styled, and
  /// what the AI readout has to say.
  private func observePreferences() {
    let center = NotificationCenter.default

    menuBarPrefsObserver = center.addObserver(
      forName: MenuBarStore.prefsChanged,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.syncStatusItems()
    }

    // The network style and units live under the network module's own key, so
    // they arrive on its notification rather than the menu bar's.
    prefsObserver = center.addObserver(
      forName: NetworkChannel.prefsChanged,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.syncStatusItems()
    }

    aiUsageObserver = center.addObserver(
      forName: AiUsageStore.didChange,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.renderAiUsage()
    }
  }

  @objc private func itemClicked(_ sender: NSStatusBarButton) {
    if NSApp.currentEvent?.type == .rightMouseUp {
      showContextMenu(from: sender)
      return
    }
    // In the consolidated layout every click is the dashboard's — the panel's
    // tab strip is what picks a surface from there, not the icon.
    let clicked = surface(for: sender)
    let section = MenuBarStore.shared.prefs.layout == .consolidated
      ? nil
      : clicked.map(\.rawValue)
    togglePopover(from: sender, section: section)
  }

  private func renderNetwork(_ sample: NetworkSample) {
    guard let item = items[.network], let button = item.button else { return }

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
    pin(item, for: .network, to: readout.size.width)
  }

  /// Stops a text item shuffling its neighbours as its content changes width.
  ///
  /// `variableLength` re-measures on every change, so the item — and every icon
  /// to its left — twitches sideways each time a digit appears or disappears.
  /// Pinning the length to the widest it has been stops that. It only ever
  /// grows while a style holds, and `syncStatusItems` drops the floor when the
  /// style changes so a narrower readout can shrink back into it.
  private func pin(_ item: NSStatusItem, for surface: MenuBarSurface, to width: CGFloat) {
    let rounded = ((width + Self.readoutInset) / 4).rounded(.up) * 4
    guard rounded > (itemWidths[surface] ?? 0) else { return }
    itemWidths[surface] = rounded
    item.length = rounded
  }

  // MARK: - AI usage readout

  /// Today's AI spend as ink in the bar, or nothing when there is nothing
  /// honest to put there.
  ///
  /// The item stays — it is the anchor for the AI panel — but it falls back to
  /// its glyph rather than drawing a number. `AiUsageStore.current()` returns
  /// nil once the summary is stale or from another day, and `$0.00` would claim
  /// a day you spent nothing on rather than a day nobody has measured.
  private func renderAiUsage() {
    guard let item = items[.aiUsage], let button = item.button else { return }

    guard let summary = AiUsageStore.shared.current() else {
      button.image = Self.aiUsageImage()
      // Back to a glyph, so the pinned text width has to go with it — and so
      // does any tooltip written for figures that are no longer on the bar.
      button.toolTip = MenuBarSurface.aiUsage.tooltip
      itemWidths[.aiUsage] = nil
      item.length = NSStatusItem.squareLength
      return
    }

    let prefs = MenuBarStore.shared.prefs
    let style = prefs.aiStyle
    let scope = prefs.aiScope
    let shares = Self.aiShares(summary.readouts(in: scope), scope: scope)
    let cost = Self.formatUsd(summary.cost(in: scope))
    let readout = Self.aiReadout(
      cost: cost,
      tokens: Self.formatCount(summary.tokens(in: scope)),
      style: style,
      shares: shares
    )
    // Ink in an image, so the figures have to be said out loud somewhere else —
    // and said honestly, since the bar has no room for the caveat.
    readout.accessibilityDescription =
      style == .percentAndBlock && !shares.isEmpty
      ? shares.map(\.spoken).joined(separator: ", ")
      : "\(cost) of AI usage today, at published API rates"
    // The one figure that cannot say what it is a share of. The tooltip is
    // where that gets said, so it is written per render rather than left as the
    // surface's standing line.
    button.toolTip =
      style == .percentAndBlock && !shares.isEmpty
      ? shares.map(\.spoken).joined(separator: "\n")
      : MenuBarSurface.aiUsage.tooltip
    button.image = readout

    item.length = NSStatusItem.variableLength
    pin(item, for: .aiUsage, to: readout.size.width)
  }

  /// What the percentage style draws: one bar and one figure per provider that
  /// has a share worth drawing.
  ///
  /// A provider with no share is left out rather than drawn empty — Claude Code
  /// between blocks, or Codex before its first reading — because an empty track
  /// reads as "none of it used", which is a claim about an allowance nothing
  /// here knows.
  private static func aiShares(
    _ readouts: [AiProviderReadout],
    scope: AiReadoutScope
  ) -> [AiShare] {
    let now = Date()
    let drawable = readouts.compactMap { readout -> (AiProviderReadout, Double)? in
      guard let share = readout.share(at: now) else { return nil }
      return (readout, share)
    }

    // A tag only when position cannot say which provider a figure belongs to:
    // the scope asked for both and only one of them turned out to have a share.
    // With both drawn, bar order says it; with one asked for, the setting does.
    let tagged = scope.providers.count > 1 && drawable.count == 1

    return drawable.map { readout, share in
      let percent = percentText(share)
      return AiShare(
        share: share,
        label: tagged ? "\(readout.provider.tag) \(percent)" : percent,
        // Two different claims, and this is the only place either gets to say
        // which it is out loud.
        spoken: readout.isMeasured
          ? "\(readout.provider.label) has used \(percent) of its published limit"
          : "\(percent) into \(readout.provider.label)'s five-hour block — elapsed time, not an allowance"
      )
    }
  }

  /// A share as text, in whole numbers, and never rounded into a lie.
  ///
  /// `100%` says a window is spent and `0%` says it is untouched, so neither is
  /// allowed to be the result of rounding towards it: the two ends are held back
  /// until the reading really is there.
  private static func percentText(_ share: Double) -> String {
    let value = min(max(share * 100, 0), 100)
    if value > 0, value < 1 { return "<1%" }
    if value > 99, value < 100 { return "99%" }
    return "\(Int(value.rounded()))%"
  }

  /// One provider's share, ready to draw: how full its bar is, what the figure
  /// beside it says, and what that figure means when there is room to say it.
  private struct AiShare {
    let share: Double
    let label: String
    let spoken: String
  }

  /// The AI item's glyph, for when there is no figure to draw.
  private static func aiUsageImage() -> NSImage? {
    symbolGlyph(
      ["brain.head.profile", "brain", "cpu", "sparkles"],
      describedAs: "AI usage"
    ) ?? NSImage(named: NSImage.actionTemplateName).map(menuBarGlyph)
  }

  /// Money, without dragging a `NumberFormatter` in for two decimal places.
  ///
  /// Deliberately not localised. The rates it is derived from are published in
  /// US dollars and nothing here converts them, so a figure that rendered as
  /// `12,34 €` would be claiming an exchange rate this app has never seen.
  private static func formatUsd(_ amount: Double) -> String {
    if amount <= 0 { return "$0.00" }
    return String(format: "$%.2f", amount)
  }

  private static func formatCount(_ count: Int) -> String {
    switch count {
    case 1_000_000_000...:
      return String(format: "%.2fB", Double(count) / 1_000_000_000)
    case 1_000_000...:
      return String(format: "%.1fM", Double(count) / 1_000_000)
    case 1_000...:
      return String(format: "%.1fK", Double(count) / 1_000)
    default:
      return "\(count)"
    }
  }

  /// Padding either side of a text readout, matching what AppKit gives a status
  /// item's own content.
  private static let readoutInset: CGFloat = 12

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

  /// The AI readout as one template image, composed the same way.
  ///
  /// Same arithmetic as `readout(down:up:style:ring:)` and for the same reason:
  /// one canvas exactly the bar's thickness, every piece placed against its
  /// middle, so nothing rides high or low when macOS changes how tall a menu
  /// bar is.
  private static func aiReadout(
    cost: String,
    tokens: String,
    style: AiMenuBarStyle,
    shares: [AiShare]
  ) -> NSImage {
    // The percentage style is the only one that draws more than one figure, and
    // a bar for each, so it composes its own pieces rather than sharing the
    // single bar-then-text layout the other three use.
    if style == .percentAndBlock, !shares.isEmpty {
      return aiSharesImage(shares)
    }

    let text: NSAttributedString
    switch style {
    // A percentage style with nothing to be a percentage of — no open block and
    // no published reading — falls back to the cost rather than to a dash: a
    // figure that is true beats a placeholder that is only honest.
    case .cost, .block, .percentAndBlock:
      text = aiFigureTitle(cost)
    case .costAndTokens:
      text = aiStackedTitle(cost: cost, tokens: tokens)
    }

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

    // Only the block style carries a bar here, and only while there is a share
    // to fill it with. The first in scope, which with both providers on is
    // Claude Code's five-hour block — the window this style was built for.
    let bar = style == .block ? shares.first.map { blockImage($0.share) } : nil
    let barWidth = bar.map { $0.size.width + networkGap } ?? 0

    let image = NSImage(
      size: NSSize(
        width: barWidth + textSize.width,
        height: NSStatusBar.system.thickness
      ),
      flipped: false
    ) { rect in
      if let bar {
        bar.draw(
          in: NSRect(
            x: rect.minX,
            y: rect.midY - bar.size.height / 2,
            width: bar.size.width,
            height: bar.size.height
          )
        )
      }
      text.draw(
        with: NSRect(
          x: rect.minX + barWidth,
          y: rect.midY - textSize.height / 2,
          width: textSize.width,
          height: textSize.height
        ),
        options: [.usesLineFragmentOrigin]
      )
      return true
    }

    image.isTemplate = true
    return image
  }

  /// The gap between one provider's readout and the next.
  ///
  /// Wider than the gap between a bar and its own figure, which is what keeps
  /// `▮▮▯▯ 47%  ▮▯▯▯ 27%` reading as two pairs rather than four things.
  private static let aiShareGap: CGFloat = 8

  /// Every share in the scope, laid out left to right in provider order.
  private static func aiSharesImage(_ shares: [AiShare]) -> NSImage {
    let pieces = shares.map { share -> (bar: NSImage, text: NSAttributedString, size: NSSize) in
      let text = aiFigureTitle(share.label)
      let measured = text.boundingRect(
        with: NSSize(
          width: CGFloat.greatestFiniteMagnitude,
          height: CGFloat.greatestFiniteMagnitude
        ),
        options: [.usesLineFragmentOrigin]
      )
      return (
        blockImage(share.share),
        text,
        NSSize(width: measured.width.rounded(.up), height: measured.height.rounded(.up))
      )
    }

    let width =
      pieces.reduce(0) { $0 + $1.bar.size.width + networkGap + $1.size.width }
      + aiShareGap * CGFloat(max(pieces.count - 1, 0))

    let image = NSImage(
      size: NSSize(width: width, height: NSStatusBar.system.thickness),
      flipped: false
    ) { rect in
      var x = rect.minX
      for piece in pieces {
        piece.bar.draw(
          in: NSRect(
            x: x,
            y: rect.midY - piece.bar.size.height / 2,
            width: piece.bar.size.width,
            height: piece.bar.size.height
          )
        )
        x += piece.bar.size.width + networkGap
        piece.text.draw(
          with: NSRect(
            x: x,
            y: rect.midY - piece.size.height / 2,
            width: piece.size.width,
            height: piece.size.height
          ),
          options: [.usesLineFragmentOrigin]
        )
        x += piece.size.width + aiShareGap
      }
      return true
    }

    image.isTemplate = true
    return image
  }

  /// One line: a cost, or a share. Black for the same reason `stackedTitle` is
  /// — the composited image is templated, so the menu bar supplies the ink.
  private static func aiFigureTitle(_ figure: String) -> NSAttributedString {
    NSAttributedString(
      string: figure,
      attributes: [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
        .foregroundColor: NSColor.black,
      ]
    )
  }

  /// Cost over tokens, stacked the way the network readout stacks its rates.
  private static func aiStackedTitle(cost: String, tokens: String) -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.maximumLineHeight = 10
    paragraph.minimumLineHeight = 10
    paragraph.alignment = .right

    return NSAttributedString(
      string: "\(cost)\n\(tokens)",
      attributes: [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
        .foregroundColor: NSColor.black,
        .paragraphStyle: paragraph,
      ]
    )
  }

  /// A share, as a small bar of segments.
  ///
  /// **What the share is depends on who it is for**, and this cannot tell:
  /// Codex publishes a portion of its own allowance, while Claude Code
  /// publishes nothing and gets a portion of the clock instead. Both fill the
  /// same track. Which one a figure is comes from the tooltip, not from here.
  ///
  /// Segments rather than a continuous fill, matching the panel's own bars. A
  /// solid bar 24pt wide moves half a point between 47% and 49%, which is not a
  /// difference anybody reads at menu bar size; six blocks quantise it into
  /// something countable at a glance. Every segment is drawn either way — an
  /// unlit one at low alpha — so a bar at 0% is still visibly a bar.
  private static func blockImage(_ share: Double) -> NSImage {
    let segments = 6
    let gap: CGFloat = 1
    let size = NSSize(width: 24, height: 6)
    // Rounded, not ceiled: ceiling lights a sixth of the bar for a window that
    // is 2% used, which over-reports by more than the reading itself.
    let filled = Int((Double(segments) * min(max(share, 0), 1)).rounded())

    let image = NSImage(size: size, flipped: false) { rect in
      let width =
        (rect.width - gap * CGFloat(segments - 1)) / CGFloat(segments)
      for index in 0..<segments {
        let box = NSRect(
          x: rect.minX + (width + gap) * CGFloat(index),
          y: rect.minY,
          width: width,
          height: rect.height
        )
        let path = NSBezierPath(
          roundedRect: box,
          xRadius: box.width / 3,
          yRadius: box.width / 3
        )
        // Lit at full strength, unlit at a third of it. The whole bar is 24pt
        // in a menu bar that gets a fraction of a second's attention; anything
        // subtler than this is not a reading, it is a smudge. Kept in step with
        // `_ReadoutBar` in the settings preview.
        (index < filled
          ? NSColor.black
          : NSColor.black.withAlphaComponent(0.32)).setFill()
        path.fill()
      }
      return true
    }
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

  /// Right-click menu, on whichever icon was right-clicked.
  ///
  /// It used to be attached to the vitals item whatever had been clicked, which
  /// was safe while that item always existed. It does not any more — the user
  /// can switch it off — so the menu is hung on the item that asked for it and
  /// taken off the same one afterwards.
  private func showContextMenu(from button: NSStatusBarButton?) {
    guard let button,
          let surface = surface(for: button),
          let item = items[surface]
    else { return }

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

    contextMenuItem = item
    item.menu = menu
    item.button?.performClick(nil)
    // Detach again so the next left-click opens the popover, not the menu.
    item.menu = nil
    contextMenuItem = nil
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
    // Read-only from here: the panel draws the summary this engine cannot
    // compute, published by the main window.
    AiUsageChannel.register(with: engine.binaryMessenger)

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
    forwardClicksIntoThePanel()

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

  /// Hands clicks to the panel's view controller, because AppKit will not.
  ///
  /// A view nested inside an `NSPopover` does not get `mouseDown:`/`mouseUp:`
  /// forwarded up its responder chain: the events arrive at the window, the
  /// window hit-tests them to `FlutterView`, and there they stop — they never
  /// reach `FlutterViewController`, which is the responder that turns them
  /// into Flutter pointer events. The symptom is a panel that looks alive and
  /// is not: hovering highlights rows, because hover comes in through the view
  /// controller's own tracking area and skips the chain entirely, while not one
  /// click in the panel does anything. Nothing in the app reports an error,
  /// because nothing in the app is ever asked.
  ///
  /// It is an AppKit bug, and a known one — Flutter carried the same
  /// workaround in `FlutterViewWrapper` (flutter/engine#40241) for the version
  /// of it that "Reduce Transparency" triggered, and dropped it once Apple
  /// called that fixed in 13.3.1. It is back, and it does not need Reduce
  /// Transparency to reproduce on macOS 26.
  ///
  /// So the panel repairs the chain a layer further out: catch the events as
  /// they pass through the app and deliver them where AppKit should have. Only
  /// clicks inside the popover's own view are taken, and dragging comes along
  /// with the click because a drag that never got its mouse-down is not a drag.
  private func forwardClicksIntoThePanel() {
    clickForwarder = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged]
    ) { [weak self] event in
      guard let self,
            let controller = self.popover.contentViewController,
            let window = controller.view.window,
            event.window === window,
            let hit = window.contentView?.hitTest(event.locationInWindow),
            hit.isDescendant(of: controller.view)
      else { return event }

      switch event.type {
      case .leftMouseDown: controller.mouseDown(with: event)
      case .leftMouseUp: controller.mouseUp(with: event)
      default: controller.mouseDragged(with: event)
      }
      // Swallowed: it has been delivered by hand, and letting it carry on would
      // be the same click twice on any macOS where AppKit does deliver it.
      return nil
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
    guard popover.isShown else {
      showPopover(section: section, from: button)
      return
    }

    // Moving between two of our own icons, which is the one case where the
    // panel is not appearing or disappearing — it is relocating.
    //
    // The animation is what stopped it reading that way. A show fades and
    // scales the panel up from nothing, so following a close with one turned
    // every move into "out, then in", with a beat of empty menu bar between
    // them. Off for the move, those two beats become one. It goes back on
    // straight afterwards: for an actual opening, from nothing, at the icon
    // that was just clicked, the fade is the right macOS behaviour and its
    // absence is what would look wrong.
    popover.animates = false
    defer { popover.animates = true }
    // close(), not performClose(): the animated close is still running when
    // the next show starts, and the popover comes back up empty.
    popover.close()
    showPopover(section: section, from: button)
  }

  /// Opens the popover on the icon that means [section].
  ///
  /// The hot key comes in here with "clipboard", which lands on the clipboard
  /// icon — a panel about clips should hang from the icon that means clips.
  /// When that icon is switched off, or in the consolidated layout where there
  /// is only one, `anchorButton(for:)` falls back to whatever is on the bar:
  /// the panel is still reachable, it just has no icon of its own.
  func showPopover(section: String?) {
    let surface = section.flatMap(MenuBarSurface.init(rawValue:))
    showPopover(section: section, from: anchorButton(for: surface))
  }

  private func showPopover(section: String?, from button: NSStatusBarButton?) {
    guard let button else { return }
    if popover.isShown,
       popover.contentViewController?.view.window?.isVisible == true {
      // Already open on this icon: no need to re-present it, but the caller
      // still wants the panel pointed at their section — and a different
      // section is a different size. Guarded, because an unchanged size is
      // still a resize as far as the Flutter view is concerned, and it blocks
      // for a frame to answer one.
      currentSection = section ?? Self.dashboardSection
      currentWidth = width(for: section)
      let size = NSSize(width: currentWidth, height: height(for: section))
      if size != popover.contentSize { popover.contentSize = size }
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
    currentSection = section ?? Self.dashboardSection
    currentWidth = width(for: section)
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    anchor = button
    // Size is applied *after* showing, not before. A hidden Flutter view
    // produces no frames, so a resize asked for while the popover is off
    // screen waits for a frame that cannot arrive and times out a second
    // later. On screen the same call is answered immediately.
    //
    // Both dimensions in one assignment, and the height taken from what this
    // section measured last time rather than from whatever the previous
    // section happened to leave behind — otherwise a panel that is already up
    // and readable resizes a beat later, which is the part that reads as a
    // glitch rather than as a transition.
    popover.contentSize = NSSize(width: currentWidth, height: height(for: section))
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

  /// How wide the panel should be for [section].
  ///
  /// One width for every tab in the consolidated layout. The narrow surfaces
  /// get some gutter there, which is the cheaper of the two costs: a tab strip
  /// whose container jumped 140pt sideways on each click would move the tab you
  /// were about to press next.
  private func width(for section: String?) -> CGFloat {
    guard MenuBarStore.shared.prefs.layout == .separate else { return panelWidth }
    return section.flatMap(MenuBarSurface.init(rawValue:))?.panelWidth ?? panelWidth
  }

  /// What this section measured last time, or whatever is on screen now the
  /// first time it is opened — there is nothing better to guess with, and one
  /// settle on first visit is the cost of not storing a made-up number.
  private func height(for section: String?) -> CGFloat {
    panelHeights[section ?? Self.dashboardSection] ?? popover.contentSize.height
  }

  /// What rides along with `popoverDidOpen`.
  ///
  /// Never nil now: the layout has to reach Dart even when the section does
  /// not, because it decides whether the panel draws a tab strip and this
  /// engine has no `AppSettings` of its own to look it up in. The AI window
  /// style travels the same road for the same reason — nothing native draws
  /// with it; it is the popover's to apply.
  private func arguments(for section: String?) -> [String: Any] {
    var arguments: [String: Any] = [
      "layout": MenuBarStore.shared.prefs.layout.rawValue,
      "aiWindowStyle": MenuBarStore.shared.prefs.aiWindowStyle.rawValue,
    ]
    if let section { arguments["section"] = section }
    return arguments
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
    case "setSection":
      // A tab click in the consolidated layout, while the popover is already
      // open. Dart has switched panels itself; this is so the height filed for
      // the new section is adopted rather than the old one's being kept.
      //
      // Deliberately *not* how a section arrives on open — see the note on
      // `popoverDidOpen` in `popover_bridge.dart`. Announcing a section
      // separately from the open is what the resize handshake does not survive.
      if let section = (call.arguments as? [String: Any])?["section"] as? String {
        adoptSection(section)
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

  /// Points an already-open popover at another section.
  ///
  /// Only the height moves. The width is fixed across tabs in the consolidated
  /// layout, which is the only layout that can reach this, so re-applying it
  /// would be a resize the Flutter view has to stop and answer for nothing.
  private func adoptSection(_ section: String) {
    guard currentSection != section else { return }
    currentSection = section
    let height = height(for: section)
    guard abs(popover.contentSize.height - height) > 1 else { return }
    popover.contentSize = NSSize(width: currentWidth, height: height)
  }

  private func setPopoverHeight(_ height: CGFloat) {
    let clamped = min(max(height, minPanelHeight), maxPanelHeight)
    panelHeights[currentSection] = clamped
    guard abs(popover.contentSize.height - clamped) > 1 else { return }
    popover.contentSize = NSSize(width: currentWidth, height: clamped)
  }

  @objc private func openMainWindow() {
    MainFlutterWindow.present()
  }

  @objc private func quit() {
    NSApp.terminate(nil)
  }

  deinit {
    if let appearanceObserver {
      DistributedNotificationCenter.default.removeObserver(appearanceObserver)
    }
    for observer in [prefsObserver, menuBarPrefsObserver, aiUsageObserver] {
      if let observer { NotificationCenter.default.removeObserver(observer) }
    }
    if let networkObserver {
      NetworkMonitor.shared.removeObserver(networkObserver)
    }
    if let clickForwarder {
      NSEvent.removeMonitor(clickForwarder)
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

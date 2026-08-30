import FlutterMacOS
import Foundation

/// How many status items Tidy puts on the bar.
///
/// Raw values cross the channel and land in the Dart `MenuBarLayout`
/// (`lib/features/menubar/domain/menu_bar_surface.dart`), so they must stay in
/// step with it.
enum MenuBarLayout: String {
  /// One icon; every surface is a tab inside its popover.
  case consolidated
  /// An icon per surface, each with its own switch.
  case separate
}

/// One feature that can show up in the menu bar.
///
/// Mirrors the Dart `MenuBarSurface`. The raw value is the section string that
/// already crossed the channel before either enum existed, which is why it is
/// hyphenated rather than camel-cased.
enum MenuBarSurface: String, CaseIterable {
  case dashboard
  case aiUsage = "ai-usage"
  case clipboard
  case network

  /// What AppKit files this item's visibility under.
  ///
  /// **Never `nil`, and never reused between two live items.** Without a name
  /// of its own AppKit files a status item under an ordinal in a namespace
  /// shared with every other app on the machine — see `MenuBarController.claim`
  /// for the incident that produced this rule.
  var autosaveName: String {
    switch self {
    case .dashboard: "TidyVitals"
    case .aiUsage: "TidyAiUsage"
    case .clipboard: "TidyClipboard"
    case .network: "TidyNetwork"
    }
  }

  var tooltip: String {
    switch self {
    case .dashboard: "Tidy"
    case .aiUsage: "AI usage today, at published API rates — not a bill"
    case .clipboard: "Clipboard history"
    case .network: "Network activity"
    }
  }

  /// The popover's width when this surface is the whole panel.
  ///
  /// Only consulted in `.separate`. The consolidated panel is one width for
  /// every tab, because a tab strip that resizes its own container moves the
  /// thing you are about to click.
  var panelWidth: CGFloat {
    switch self {
    case .dashboard: 460
    case .aiUsage, .clipboard, .network: 320
    }
  }

  /// Whether this surface draws text in the bar rather than just a glyph.
  ///
  /// The two that do are the two that cost real width, and the reason the
  /// consolidated layout exists.
  var hasReadout: Bool {
    switch self {
    case .aiUsage, .network: true
    case .dashboard, .clipboard: false
    }
  }

  /// Display order on the bar, left to right as AppKit lays them out.
  static let ordered: [MenuBarSurface] = [.dashboard, .aiUsage, .clipboard, .network]
}

/// How the AI usage readout draws itself.
///
/// Raw values cross the channel and land in the Dart `AiMenuBarStyle`.
enum AiMenuBarStyle: String {
  case cost
  case costAndTokens
  case block
  case percentAndBlock
}

/// Whose usage the AI readout is about.
///
/// The bar has no room to label what it is showing, so it shows one thing and
/// this is where that is chosen. Raw values cross the channel and land in the
/// Dart `AiReadoutScope`. The popover behind the item is unaffected: it has
/// room for a section per provider and draws every one it found.
enum AiReadoutScope: String {
  case both
  case claudeCode
  case codex

  /// The providers this covers, in bar order.
  var providers: [AiProvider] {
    switch self {
    case .both: AiProvider.allCases
    case .claudeCode: [.claudeCode]
    case .codex: [.codex]
    }
  }

  func covers(_ provider: AiProvider) -> Bool { providers.contains(provider) }
}

/// How the popover draws one AI limit window.
///
/// Raw values cross the channel and land in the Dart `AiWindowStyle`. Nothing
/// native draws with this — it is carried so `MenuBarController` can hand it to
/// the popover engine on open, which has no `AppSettings` to read it from.
enum AiWindowStyle: String {
  case expanded
  case compact
}

/// The menu bar preferences, as the Dart side last wrote them to `settings.json`.
///
/// Read natively at launch for the same reason `NetworkPrefs` and
/// `ClipboardPrefs` are: the status items are created in
/// `MenuBarController.init`, before any Flutter engine has run. An item that
/// appears after the user turned it off — or a bar that collapses to one icon
/// and then sprouts three more a second later — is a bug the user can see.
///
/// **The keys here must match `AppSettings` in
/// `lib/core/settings/app_settings.dart`.** Renaming one there means renaming
/// it here; the failure is silent, and lands as the wrong menu bar.
struct MenuBarPrefs: Equatable {
  /// One item, until the user asks for more. Keep this default in step with
  /// `MenuBarLayout.fromName`'s fallback on the Dart side.
  var layout = MenuBarLayout.consolidated

  var showVitals = true
  var showAiUsage = false
  var showClipboard = true
  var showNetwork = false

  var aiStyle = AiMenuBarStyle.cost

  /// Keep this default in step with `AiReadoutScope.fromName`'s fallback on the
  /// Dart side.
  var aiScope = AiReadoutScope.both

  /// Keep this default in step with `AiWindowStyle.fromName`'s fallback on the
  /// Dart side.
  var aiWindowStyle = AiWindowStyle.expanded

  /// The surfaces the user has switched on, in bar order.
  ///
  /// The switches answer *what Tidy offers*; [layout] answers *how* — an icon
  /// each, or tabs behind one icon. They used to answer only the first of those
  /// and were ignored entirely in `.consolidated`, which is how the panel came
  /// to show a Clipboard tab to someone who had switched Clipboard off.
  var enabledSurfaces: [MenuBarSurface] {
    let wanted = MenuBarSurface.ordered.filter { surface in
      switch surface {
      case .dashboard: showVitals
      case .aiUsage: showAiUsage
      case .clipboard: showClipboard
      case .network: showNetwork
      }
    }
    // Never nothing. An app with no icon at all has no way back into its own
    // settings from the bar, and the popover is the only route for someone who
    // has closed the window.
    return wanted.isEmpty ? [.dashboard] : wanted
  }

  /// Which items belong on the bar right now.
  ///
  /// In `.consolidated` that is exactly one by definition; the surfaces the
  /// switches named are tabs inside its panel instead — see [enabledSurfaces].
  var visibleSurfaces: [MenuBarSurface] {
    layout == .separate ? enabledSurfaces : [.dashboard]
  }

  /// This preference set with everything the *popover* alone cares about
  /// normalised away, so two sets that differ only there compare equal.
  ///
  /// `aiWindowStyle` is the only such field and the reason this exists: nothing
  /// on the bar draws with it, and rebuilding the status items for it would
  /// flicker the bar for a change the bar cannot show.
  var barIdentity: MenuBarPrefs {
    var copy = self
    copy.aiWindowStyle = .expanded
    return copy
  }

  static func fromMap(_ map: [String: Any]) -> MenuBarPrefs {
    var prefs = MenuBarPrefs()
    if let raw = map["menuBarLayout"] as? String,
       let layout = MenuBarLayout(rawValue: raw) {
      prefs.layout = layout
    }
    if let value = map["menuBarShowVitals"] as? Bool { prefs.showVitals = value }
    if let value = map["menuBarShowAiUsage"] as? Bool { prefs.showAiUsage = value }
    if let value = map["menuBarShowClipboard"] as? Bool { prefs.showClipboard = value }
    // Kept under the network module's own key rather than renamed: `NetworkPrefs`
    // reads the same string, and a rename on one side of the boundary and not
    // the other is exactly the silent failure `docs/feature.md` §4a describes.
    if let value = map["networkMenuBarEnabled"] as? Bool { prefs.showNetwork = value }
    if let raw = map["aiMenuBarStyle"] as? String,
       let style = AiMenuBarStyle(rawValue: raw) {
      prefs.aiStyle = style
    }
    if let raw = map["aiMenuBarScope"] as? String,
       let scope = AiReadoutScope(rawValue: raw) {
      prefs.aiScope = scope
    }
    if let raw = map["aiWindowStyle"] as? String,
       let style = AiWindowStyle(rawValue: raw) {
      prefs.aiWindowStyle = style
    }
    return prefs
  }
}

/// Holds the menu bar preferences for the native side.
///
/// Deliberately thinner than `NetworkStore`: there is nothing to persist here
/// that Dart does not already own. This only reads.
final class MenuBarStore {
  static let shared = MenuBarStore()

  /// Posted when Dart changes the preferences, so the status items can be
  /// rebuilt without the channel needing to know they exist.
  static let prefsChanged = Notification.Name("TidyMenuBarPrefsChanged")

  private(set) var prefs = MenuBarPrefs()
  private var loaded = false

  private init() {}

  func load() {
    guard !loaded else { return }
    loaded = true
    AppSupport.migrate()
    prefs = Self.readFromSettings() ?? MenuBarPrefs()
  }

  func configure(_ prefs: MenuBarPrefs) {
    load()
    guard prefs != self.prefs else { return }
    // Held either way — the popover asks for the current value on every open —
    // but only announced when the *bar* would look different for it. See
    // `barIdentity`.
    let rebuild = prefs.barIdentity != self.prefs.barIdentity
    self.prefs = prefs
    guard rebuild else { return }
    NotificationCenter.default.post(name: Self.prefsChanged, object: nil)
  }

  private static var settingsFile: URL? {
    guard let support = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first else { return nil }
    return support
      .appendingPathComponent(AppSupport.directoryName, isDirectory: true)
      .appendingPathComponent("settings.json")
  }

  private static func readFromSettings() -> MenuBarPrefs? {
    guard let file = settingsFile,
          let data = try? Data(contentsOf: file),
          let map = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else { return nil }
    return MenuBarPrefs.fromMap(map)
  }
}

/// Dart's window onto [MenuBarStore].
///
/// Main window only. The popover has no settings UI, and the native side reads
/// the same `settings.json` itself at launch — the channel is for everything
/// after that.
enum MenuBarChannel {
  static let channelName = "com.yunweneric.tidy/menu_bar"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "configure":
        let map = call.arguments as? [String: Any] ?? [:]
        MenuBarStore.shared.configure(MenuBarPrefs.fromMap(map))
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

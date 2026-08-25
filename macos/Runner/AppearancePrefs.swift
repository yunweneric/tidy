import Cocoa
import Foundation

/// The theme the Dart side last wrote to `settings.json`, read natively at
/// launch so the window is already the right colour when it first appears.
///
/// The same pattern as `MenuBarPrefs` and `NetworkStore`, and for the same
/// reason: the window is ordered on screen before any Flutter engine has
/// produced a frame, so whatever `NSWindow` is painted with is what the user
/// sees for that moment. Left alone it is the *system* window background — and
/// since Tidy now defaults to dark, that means a white flash on every launch on
/// a Mac set to light appearance, followed by the dark splash.
///
/// Only the background colour is taken from this, never the window's
/// `appearance`. A background is a one-shot paint that Flutter covers on its
/// first frame, so a value that goes stale — the user switching theme in
/// Settings after launch — is invisible rather than wrong. `appearance` would
/// keep applying to the traffic lights and native menus for the rest of the
/// session, and getting that right needs Dart to push changes across a channel
/// rather than the native side reading a file once.
enum AppearancePrefs {
  /// Mirrors Dart's `ThemeMode` and the strings `AppSettings` persists.
  enum Theme: String {
    case light
    case dark
    case system

    /// Must match `AppSettings.themeMode`'s fallback.
    static let fallback = Theme.dark
  }

  /// The app's canvas colour, as `AppColorTokens.canvas` — `#15112E` dark,
  /// `#F3F1FD` light. The same two values `flutter_native_splash` is given in
  /// `pubspec.yaml`, so every surface that paints before Flutter does agrees.
  static var launchBackground: NSColor {
    isDark
      ? NSColor(srgbRed: 0x15 / 255, green: 0x11 / 255, blue: 0x2E / 255, alpha: 1)
      : NSColor(srgbRed: 0xF3 / 255, green: 0xF1 / 255, blue: 0xFD / 255, alpha: 1)
  }

  /// The stored preference with `system` already answered by AppKit, so the
  /// question left is only light or dark.
  private static var isDark: Bool {
    switch stored {
    case .light: false
    case .dark: true
    case .system: isSystemDark
    }
  }

  private static var stored: Theme {
    guard let file = settingsFile,
          let data = try? Data(contentsOf: file),
          let map = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let name = map["themeMode"] as? String,
          let theme = Theme(rawValue: name)
    else { return .fallback }
    return theme
  }

  private static var isSystemDark: Bool {
    NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
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
}

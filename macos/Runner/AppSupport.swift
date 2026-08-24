import Foundation

/// The app's Application Support folder, and the one-time move onto its new
/// name.
///
/// The folder was called `MacUninstaller` for as long as the product was. The
/// rename to Tidy would otherwise orphan everything the app has written —
/// settings, the scan cache, the trash ledger that makes Recycle Bin's "Put
/// Back" possible, and the clipboard history — leaving a first launch that
/// looks like a fresh install and a folder nobody ever cleans up.
///
/// Runs before anything reads the folder. Both Flutter engines and the native
/// clipboard store all reach it through here, and `migrated` is a static `let`,
/// which Swift initialises exactly once no matter how many of them ask first.
enum AppSupport {
  static let directoryName = "Tidy"
  private static let legacyDirectoryName = "MacUninstaller"

  /// Forces the migration. The value is meaningless; asking for it is the point.
  @discardableResult
  static func migrate() -> Bool { migrated }

  private static let migrated: Bool = {
    guard let root = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first else { return false }

    let old = root.appendingPathComponent(legacyDirectoryName, isDirectory: true)
    let new = root.appendingPathComponent(directoryName, isDirectory: true)

    let manager = FileManager.default
    // Already migrated, or a clean install. Note the new folder winning is
    // deliberate: if both exist, the new one is the live data and the old one
    // is a leftover we must not overwrite it with.
    guard manager.fileExists(atPath: old.path),
          !manager.fileExists(atPath: new.path)
    else { return false }

    do {
      try manager.moveItem(at: old, to: new)
      NSLog("Tidy: moved Application Support/\(legacyDirectoryName) to \(directoryName).")
      return true
    } catch {
      // Not fatal. Everything downstream treats a missing folder as a clean
      // install, so the cost is the old data being ignored rather than a crash.
      NSLog("Tidy: could not move the support folder: \(error.localizedDescription)")
      return false
    }
  }()
}

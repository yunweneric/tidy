import Cocoa

/// Detecting and requesting Full Disk Access.
///
/// There is no API to *request* FDA — macOS grants it only when the user adds
/// the app by hand in System Settings. All an app can do is deep-link there,
/// explain why, and detect the outcome by attempting a protected read.
enum FullDiskAccess {
  /// Paths that are readable only with `kTCCServiceSystemPolicyAllFiles`.
  ///
  /// Reading one and failing produces no user prompt — TCC just returns EPERM —
  /// which is what makes this a safe probe rather than a nag.
  ///
  /// Note this uses the *user's* TCC.db (mode 0644). The system copy at
  /// `/Library/Application Support/com.apple.TCC/TCC.db` is root-owned 0600, so
  /// probing it reports "denied" even when FDA is granted — the single most
  /// common bug in FDA detection code.
  private static var probePaths: [String] {
    let home = NSHomeDirectory()
    return [
      "\(home)/Library/Application Support/com.apple.TCC/TCC.db",
      "\(home)/Library/Safari/CloudTabs.db",
      "\(home)/Library/Messages/chat.db",
      // Files, not directories: the probe below opens a handle, and `open()`
      // on a directory succeeds for reasons that have nothing to do with TCC.
      "\(home)/Library/Cookies/Cookies.binarycookies",
      "\(home)/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.RecentDocuments.sfl3",
    ]
  }

  static var isGranted: Bool {
    let fm = FileManager.default

    for path in probePaths where fm.fileExists(atPath: path) {
      guard let handle = FileHandle(forReadingAtPath: path) else {
        // The file exists but cannot be opened: TCC denied it.
        return false
      }
      try? handle.close()
      return true
    }

    // Nothing to probe: a fresh account that has never opened Safari, Mail or
    // Messages. Report granted rather than blocking the user behind a
    // permission request we cannot verify.
    //
    // This used to fall back to listing `~/Library/Containers`, which was a
    // mistake. That directory is other apps' data, and on Sonoma and later
    // touching it trips `kTCCServiceSystemPolicyAppData` — so a probe whose
    // whole point was to be silent put "Tidy would like to access data from
    // other apps" on screen at launch, before onboarding had said a word about
    // it. See `AppDataAccess`, which asks for that deliberately instead.
    return true
  }

  /// Whether a specific path is readable, for per-scanner degradation.
  static func canRead(_ path: String) -> Bool {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
      return true // Nothing there to be denied.
    }
    if isDirectory.boolValue {
      return (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil
    }
    guard let handle = FileHandle(forReadingAtPath: path) else { return false }
    try? handle.close()
    return true
  }

  /// Opens System Settings on the Full Disk Access list.
  ///
  /// Ventura renamed the pane, so the pre-13 URL silently opens the wrong page.
  static func openSettings() {
    openSettingsPane(anchor: "Privacy_AllFiles")
  }

  /// Any Privacy & Security anchor: `Privacy_AllFiles`, `Privacy_Accessibility`,
  /// `Privacy_FilesAndFolders`, `Privacy_Automation`, …
  static func openSettingsPane(anchor: String) {
    let modern = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(anchor)"
    let legacy = "x-apple.systempreferences:com.apple.preference.security?\(anchor)"

    let candidate: String
    if #available(macOS 13.0, *) {
      candidate = modern
    } else {
      candidate = legacy
    }

    if let url = URL(string: candidate) {
      NSWorkspace.shared.open(url)
    }
  }
}

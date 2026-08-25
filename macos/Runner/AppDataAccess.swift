import Cocoa

/// Detecting and requesting access to other apps' data.
///
/// Sonoma split a slice off Full Disk Access: reaching into another app's
/// container under `~/Library/Containers` or `~/Library/Group Containers` now
/// needs `kTCCServiceSystemPolicyAppData`, and macOS asks for it with
///
/// > "Tidy" would like to access data from other apps.
/// > Keeping app data separate makes it easier to manage your privacy and
/// > security.
///
/// Unlike Full Disk Access there is no way to *check* this without asking:
/// the first access is the request, and the dialog is macOS's own. That makes
/// the order of operations the whole design problem — touch a container before
/// the user has been told why, and the first thing the app ever does is put an
/// alarming dialog on screen. Tidy asks on the onboarding permissions step,
/// beside Full Disk Access, and never before.
///
/// Once the user has answered, the answer is cached by TCC and probing is
/// free. "Have we asked yet" is not something TCC will tell us, so the Dart
/// side records it — see `AppSettings.hasRequestedAppDataAccess`.
enum AppDataAccess {
  /// Somebody else's container to read.
  ///
  /// Our own container is not protected, so probing it would report success
  /// with the permission denied. The `.` filter skips `.DS_Store` and friends;
  /// the bundle-id check skips Tidy itself.
  private static func foreignContainer() -> String? {
    let root = "\(NSHomeDirectory())/Library/Containers"
    let ours = Bundle.main.bundleIdentifier

    // `contentsOfDirectory` on the root is itself the protected call, so this
    // is where the prompt appears.
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: root)
    else { return nil }

    for name in names where !name.hasPrefix(".") && name != ours {
      let data = "\(root)/\(name)/Data"
      var isDirectory: ObjCBool = false
      if FileManager.default.fileExists(atPath: data, isDirectory: &isDirectory),
         isDirectory.boolValue {
        return data
      }
    }
    return nil
  }

  /// Reads another app's container, prompting if macOS has not asked yet.
  ///
  /// Full Disk Access subsumes this, so an app that already holds FDA is
  /// reported as granted without touching anything — no point asking for a
  /// subset of a permission the user has already given.
  static func request() -> Bool {
    if FullDiskAccess.isGranted { return true }

    guard let container = foreignContainer() else {
      // Either the listing was denied, or the account genuinely has no other
      // sandboxed apps installed. The second is not a denial, but it is also
      // not something to claim access on the strength of.
      return (try? FileManager.default.contentsOfDirectory(
        atPath: "\(NSHomeDirectory())/Library/Containers"
      )) != nil
    }

    return (try? FileManager.default.contentsOfDirectory(atPath: container)) != nil
  }

  /// The same probe, for use once the user has already answered.
  ///
  /// Identical to [request] by necessity — there is no read-only variant of a
  /// permission whose check is the request. The distinction is in the name and
  /// in who calls it: this one is for a screen reporting state, and its caller
  /// is expected to know that the question has been put once already.
  static var isGranted: Bool { request() }

  /// Opens System Settings on the list this permission appears in.
  ///
  /// It is filed under Files and Folders rather than under Full Disk Access,
  /// which is not where anyone looks for it.
  static func openSettings() {
    FullDiskAccess.openSettingsPane(anchor: "Privacy_FilesAndFolders")
  }
}

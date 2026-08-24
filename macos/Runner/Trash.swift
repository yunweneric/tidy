import Cocoa

/// Reading and acting on the macOS Trash.
///
/// There is more than one Trash. Every writable volume gets its own
/// `.Trashes/<uid>`, and Finder never merges them into the one bin it draws in
/// the Dock — which is exactly why an external drive stays full after someone
/// has "emptied the Trash". Each folder is reported separately so the UI can
/// name the volume the space is actually on.
///
/// Nothing here deletes. Permanent removal goes through `SystemChannel`, so it
/// passes the same `isRemovable` guard as every other deletion in the app.
enum Trash {

  /// One trash folder.
  struct Location {
    let path: String
    let label: String
    let isHome: Bool

    /// True when the folder exists and can be listed. Reading `~/.Trash`
    /// requires Full Disk Access; without it macOS returns EPERM, which is a
    /// denial and must never be reported as an empty bin.
    let readable: Bool

    var map: [String: Any] {
      ["id": path, "path": path, "label": label, "isHome": isHome, "readable": readable]
    }
  }

  /// Finder's own bookkeeping, which lives in the trash folder alongside the
  /// items. `.DS_Store` is the put-back index — listing it invites someone to
  /// delete it, which silently loses "Put Back" for everything still in there.
  private static let bookkeeping: Set<String> = [".DS_Store", ".localized"]

  // MARK: - Locations

  static func locations() -> [Location] {
    var found: [Location] = [homeLocation()]

    let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsReadOnlyKey, .volumeURLKey]
    let volumes = FileManager.default.mountedVolumeURLs(
      includingResourceValuesForKeys: keys,
      options: [.skipHiddenVolumes]
    ) ?? []

    for volume in volumes {
      let volumePath = volume.standardizedFileURL.path
      // The boot volume's trash is the user's own `~/.Trash`, already added.
      if volumePath == "/" { continue }

      let values = try? volume.resourceValues(forKeys: Set(keys))
      if values?.volumeIsReadOnly == true { continue }

      let path = "\(volumePath)/.Trashes/\(getuid())"
      // A volume that has never had anything deleted on it has no trash folder
      // at all. That is not an empty bin worth a tab — it is nothing.
      guard FileManager.default.fileExists(atPath: path) else { continue }

      found.append(
        Location(
          path: path,
          label: values?.volumeName ?? volume.lastPathComponent,
          isHome: false,
          readable: canList(path)
        )
      )
    }

    return found
  }

  private static func homeLocation() -> Location {
    let path = "\(NSHomeDirectory())/.Trash"
    return Location(
      path: path,
      label: "This Mac",
      isHome: true,
      // A missing `~/.Trash` is genuinely empty; only an existing-but-unlistable
      // one is a permission problem.
      readable: !FileManager.default.fileExists(atPath: path) || canList(path)
    )
  }

  private static func canList(_ path: String) -> Bool {
    (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil
  }

  // MARK: - Reading

  /// Every trash folder and everything in them, in one call.
  ///
  /// Sizes are allocated bytes from `DirectorySizer`, batched across all
  /// locations — a trash with two thousand items in it is one walk, not two
  /// thousand round trips.
  static func read() -> [String: Any] {
    let locations = locations()
    var entries: [(url: URL, locationId: String)] = []

    for location in locations where location.readable {
      let root = URL(fileURLWithPath: location.path)
      let children = (try? FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: resourceKeys,
        options: []
      )) ?? []

      for child in children where !bookkeeping.contains(child.lastPathComponent) {
        entries.append((child, location.path))
      }
    }

    let sizes = DirectorySizer.sizes(of: entries.map { $0.url.path })

    let items: [[String: Any]] = entries.map { entry in
      let values = try? entry.url.resourceValues(forKeys: Set(resourceKeys))
      let deleted = values?.addedToDirectoryDate ?? values?.contentModificationDate

      return [
        "path": entry.url.path,
        "name": entry.url.lastPathComponent,
        "locationId": entry.locationId,
        "size": sizes[entry.url.path] ?? 0,
        "isDirectory": values?.isDirectory ?? false,
        "isPackage": values?.isPackage ?? false,
        "kind": values?.localizedTypeDescription ?? "",
        "extension": entry.url.pathExtension.lowercased(),
        "deletedAt": deleted?.timeIntervalSince1970 ?? 0,
      ]
    }

    return ["locations": locations.map { $0.map }, "items": items]
  }

  private static let resourceKeys: [URLResourceKey] = [
    .isDirectoryKey,
    .isPackageKey,
    .localizedTypeDescriptionKey,
    .addedToDirectoryDateKey,
    .contentModificationDateKey,
  ]

  // MARK: - Restoring

  /// Moves items out of a trash folder and back onto the disk.
  ///
  /// `moves` is a list of `["from": trashed path, "to": destination folder]`.
  /// Both ends are checked: the source has to be something that is genuinely
  /// sitting in one of this user's trash folders, and the destination has to be
  /// somewhere outside them. Without the first check this method would be a
  /// general-purpose "move any file anywhere" call reachable from the UI layer.
  static func restore(moves: [[String: String]]) -> [String: Any] {
    let trashRoots = Set(locations().map { $0.path })
    let fm = FileManager.default

    var restored: [[String: String]] = []
    var failures: [[String: String]] = []

    for move in moves {
      guard let from = move["from"], let to = move["to"] else { continue }

      let source = URL(fileURLWithPath: from).standardizedFileURL
      guard trashRoots.contains(source.deletingLastPathComponent().path) else {
        failures.append(["path": from, "error": "Refused: that item is not in a Trash folder"])
        continue
      }
      guard fm.fileExists(atPath: source.path) else {
        failures.append(["path": from, "error": "It is no longer in the Trash"])
        continue
      }

      let destination = URL(fileURLWithPath: to).standardizedFileURL
      guard isSafeDestination(destination, trashRoots: trashRoots) else {
        failures.append(["path": from, "error": "Refused: that is not somewhere Tidy can restore to"])
        continue
      }

      do {
        // The original folder may itself have been deleted since. Recreating it
        // is what someone means by "put it back".
        if !fm.fileExists(atPath: destination.path) {
          try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        }

        let target = uniqueURL(in: destination, named: source.lastPathComponent)
        try fm.moveItem(at: source, to: target)
        restored.append(["from": from, "to": target.path])
      } catch {
        failures.append(["path": from, "error": error.localizedDescription])
      }
    }

    return ["restored": restored, "failures": failures]
  }

  private static func isSafeDestination(_ url: URL, trashRoots: Set<String>) -> Bool {
    let path = url.path
    if path.isEmpty || path == "/" { return false }
    if path.hasPrefix("/System") { return false }
    // Restoring into a trash folder is not restoring.
    for root in trashRoots where path == root || path.hasPrefix("\(root)/") { return false }
    return true
  }

  /// `Report.pdf` → `Report 2.pdf` when something is already there.
  ///
  /// Overwriting is not an option: the file already at the destination is not
  /// the one the user asked to bring back, and losing it to a restore would be
  /// the worst possible outcome of a button labelled "Put Back".
  private static func uniqueURL(in directory: URL, named name: String) -> URL {
    let fm = FileManager.default
    var candidate = directory.appendingPathComponent(name)
    guard fm.fileExists(atPath: candidate.path) else { return candidate }

    let base = (name as NSString).deletingPathExtension
    let ext = (name as NSString).pathExtension
    var counter = 2

    repeat {
      let suffixed = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
      candidate = directory.appendingPathComponent(suffixed)
      counter += 1
    } while fm.fileExists(atPath: candidate.path) && counter < 1000

    return candidate
  }

  // MARK: - Choosing somewhere to restore to

  /// Asks the user for a folder. Returns nil when they cancel, which is a
  /// normal outcome and not an error.
  static func chooseFolder(prompt: String, message: String) -> String? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.prompt = prompt
    panel.message = message
    panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())

    NSApp.activate(ignoringOtherApps: true)
    guard panel.runModal() == .OK else { return nil }
    return panel.url?.path
  }
}

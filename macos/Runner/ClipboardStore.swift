import Foundation

/// What kind of thing was copied. Raw values cross the channel and land in the
/// Dart `ClipboardKind` enum, so they must stay in step with it.
enum ClipboardKind: String {
  case text
  case link
  case richText
  case image
  case files
}

/// One thing the user copied.
///
/// The same struct is both the on-disk record and the channel payload — one
/// representation rather than a model plus a DTO plus a conversion nobody
/// remembers to update.
struct ClipboardEntry {
  /// SHA-256 of the copied bytes, in hex. Doubles as the dedupe key: copying
  /// the same thing twice finds the existing row rather than adding one.
  let id: String
  var kind: ClipboardKind

  /// A short line for the list. Never the whole payload — a 2 MB paste must not
  /// make the index unreadable.
  var preview: String

  /// Inline for short text. Longer text and every binary live in `blobs/`.
  var text: String?
  var blobExtension: String?

  var byteCount: Int
  var characterCount: Int
  var paths: [String]
  var pixelWidth: Int
  var pixelHeight: Int

  var sourceAppName: String?
  var sourceBundleId: String?

  var firstCopiedAt: Double
  var lastCopiedAt: Double
  var copyCount: Int

  var pinned: Bool
  var sensitive: Bool

  var hasBlob: Bool { blobExtension != nil }

  func toMap() -> [String: Any] {
    var map: [String: Any] = [
      "id": id,
      "kind": kind.rawValue,
      "preview": preview,
      "byteCount": byteCount,
      "characterCount": characterCount,
      "paths": paths,
      "pixelWidth": pixelWidth,
      "pixelHeight": pixelHeight,
      "firstCopiedAt": firstCopiedAt,
      "lastCopiedAt": lastCopiedAt,
      "copyCount": copyCount,
      "pinned": pinned,
      "sensitive": sensitive,
      "hasBlob": hasBlob,
    ]
    // The standard codec has no notion of a missing value, so absent optionals
    // are simply left out and the Dart side reads them as null.
    if let text { map["text"] = text }
    if let blobExtension { map["blobExtension"] = blobExtension }
    if let sourceAppName { map["sourceAppName"] = sourceAppName }
    if let sourceBundleId { map["sourceBundleId"] = sourceBundleId }
    return map
  }

  init?(map: [String: Any]) {
    guard let id = map["id"] as? String,
          let rawKind = map["kind"] as? String,
          let kind = ClipboardKind(rawValue: rawKind)
    else { return nil }

    self.id = id
    self.kind = kind
    preview = map["preview"] as? String ?? ""
    text = map["text"] as? String
    blobExtension = map["blobExtension"] as? String
    byteCount = map["byteCount"] as? Int ?? 0
    characterCount = map["characterCount"] as? Int ?? 0
    paths = map["paths"] as? [String] ?? []
    pixelWidth = map["pixelWidth"] as? Int ?? 0
    pixelHeight = map["pixelHeight"] as? Int ?? 0
    sourceAppName = map["sourceAppName"] as? String
    sourceBundleId = map["sourceBundleId"] as? String
    firstCopiedAt = map["firstCopiedAt"] as? Double ?? 0
    lastCopiedAt = map["lastCopiedAt"] as? Double ?? 0
    copyCount = map["copyCount"] as? Int ?? 1
    pinned = map["pinned"] as? Bool ?? false
    sensitive = map["sensitive"] as? Bool ?? false
  }

  init(
    id: String,
    kind: ClipboardKind,
    preview: String,
    text: String?,
    blobExtension: String?,
    byteCount: Int,
    characterCount: Int,
    paths: [String],
    pixelWidth: Int,
    pixelHeight: Int,
    sourceAppName: String?,
    sourceBundleId: String?,
    at: Double,
    sensitive: Bool
  ) {
    self.id = id
    self.kind = kind
    self.preview = preview
    self.text = text
    self.blobExtension = blobExtension
    self.byteCount = byteCount
    self.characterCount = characterCount
    self.paths = paths
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
    self.sourceAppName = sourceAppName
    self.sourceBundleId = sourceBundleId
    firstCopiedAt = at
    lastCopiedAt = at
    copyCount = 1
    pinned = false
    self.sensitive = sensitive
  }
}

/// How much history to keep, and what never to record.
///
/// Mirrors the `clipboard*` keys in the app's own `settings.json`, which is
/// where the Dart side keeps them. Read from that file at launch so a start
/// with no window open still honours the user's limits, then kept current by
/// `configure` from Dart.
struct ClipboardPrefs {
  var enabled = false
  var maxItems = 200

  /// Zero means never expire.
  var retentionDays = 7
  var captureImages = true
  var storeSensitive = false
  var clearOnQuit = false
  var excludedBundleIds: Set<String> = ClipboardPrefs.defaultExclusions

  /// A single copied image larger than this is recorded as metadata with no
  /// blob — the row is still useful, the disk cost is not.
  var maxImageBytes = 20 * 1024 * 1024
  var maxBlobBytes = 500 * 1024 * 1024

  /// Password managers that do not all mark their pasteboard writes concealed.
  /// The marker is checked first regardless; this is the backstop.
  static let defaultExclusions: Set<String> = [
    "com.agilebits.onepassword7",
    "com.1password.1password",
    "com.apple.keychainaccess",
    "com.bitwarden.desktop",
    "com.lastpass.LastPass",
    "in.sinew.Enpass-Desktop",
    "com.dashlane.dashlanephonefinal",
    "com.keepassium.keepassium",
    "org.keepassxc.keepassxc",
  ]

  static func fromMap(_ map: [String: Any]) -> ClipboardPrefs {
    var prefs = ClipboardPrefs()
    if let value = map["clipboardEnabled"] as? Bool { prefs.enabled = value }
    if let value = map["clipboardMaxItems"] as? Int { prefs.maxItems = value }
    if let value = map["clipboardRetentionDays"] as? Int { prefs.retentionDays = value }
    if let value = map["clipboardCaptureImages"] as? Bool { prefs.captureImages = value }
    if let value = map["clipboardStoreSensitive"] as? Bool { prefs.storeSensitive = value }
    if let value = map["clipboardClearOnQuit"] as? Bool { prefs.clearOnQuit = value }
    if let value = map["clipboardExcludedApps"] as? [String] {
      // Added to rather than replacing the defaults: a user removing an entry
      // they never added is not a thing they can do, and silently stopping the
      // guard on 1Password because the list round-tripped empty would be bad.
      prefs.excludedBundleIds = defaultExclusions.union(value)
    }
    return prefs
  }

  func toMap() -> [String: Any] {
    [
      "clipboardEnabled": enabled,
      "clipboardMaxItems": maxItems,
      "clipboardRetentionDays": retentionDays,
      "clipboardCaptureImages": captureImages,
      "clipboardStoreSensitive": storeSensitive,
      "clipboardClearOnQuit": clearOnQuit,
      "clipboardExcludedApps": Array(excludedBundleIds),
    ]
  }
}

/// The clipboard history, and the only thing that owns it.
///
/// Deliberately native rather than Dart. The app has two Flutter engines in
/// separate isolates — the main window and the menu bar popover — and elsewhere
/// they reconcile through an on-disk cache. Doing that here would be two
/// writers racing on every copy. One Swift singleton in the app process gives
/// both engines the same list and no race, and keeps recording while no engine
/// is doing anything at all.
final class ClipboardStore {
  static let shared = ClipboardStore()

  private static let formatVersion = 1

  /// Text longer than this goes to a blob. The index is parsed on every popover
  /// open, so it stays small — the same argument `ScanCache` makes for icons.
  private static let inlineTextLimit = 4096

  private init() {}

  private(set) var prefs = ClipboardPrefs()

  /// Newest first. Pinning does not reorder — the page groups pinned rows
  /// itself, and a pin that jumped a row out of its day heading would be
  /// confusing.
  private(set) var entries: [ClipboardEntry] = []

  private var observers: [() -> Void] = []
  private var loaded = false

  private let io = DispatchQueue(label: "com.yunweneric.macuninstaller.clipboard", qos: .utility)
  private var pendingWrite: DispatchWorkItem?

  // MARK: - Paths

  private var directory: URL? {
    guard let support = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first else { return nil }

    // Brand.supportDirectoryName on the Dart side. Still "MacUninstaller"
    // because the bundle id is, and everything else the app writes is here.
    let dir = support
      .appendingPathComponent("MacUninstaller", isDirectory: true)
      .appendingPathComponent("clipboard", isDirectory: true)

    do {
      try FileManager.default.createDirectory(at: blobs(in: dir), withIntermediateDirectories: true)
    } catch {
      NSLog("Clipboard: cannot create the store directory: \(error.localizedDescription)")
      return nil
    }
    return dir
  }

  private func blobs(in dir: URL) -> URL {
    dir.appendingPathComponent("blobs", isDirectory: true)
  }

  private var indexFile: URL? { directory?.appendingPathComponent("index.json") }

  func blobURL(for entry: ClipboardEntry) -> URL? {
    guard let ext = entry.blobExtension, let dir = directory else { return nil }
    return blobs(in: dir).appendingPathComponent("\(entry.id).\(ext)")
  }

  private static var settingsFile: URL? {
    guard let support = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first else { return nil }
    return support
      .appendingPathComponent("MacUninstaller", isDirectory: true)
      .appendingPathComponent("settings.json")
  }

  // MARK: - Lifecycle

  /// Reads the index and the user's settings. Never throws: a corrupt store
  /// costs the history, which is a nuisance, not the app, which is not.
  func load() {
    guard !loaded else { return }
    loaded = true

    prefs = Self.readPrefsFromSettings() ?? ClipboardPrefs()

    guard let file = indexFile,
          let data = try? Data(contentsOf: file),
          let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          root["formatVersion"] as? Int == Self.formatVersion,
          let raw = root["entries"] as? [[String: Any]]
    else { return }

    entries = raw.compactMap(ClipboardEntry.init(map:))
    // Applies a retention window that may have elapsed while the app was shut.
    if trim() { scheduleWrite() }
  }

  /// The clipboard settings as the Dart side last wrote them.
  ///
  /// Reading Dart's file rather than keeping a second copy: two files would
  /// disagree the first time one write failed, and the failure mode is
  /// recording more than the user asked for.
  private static func readPrefsFromSettings() -> ClipboardPrefs? {
    guard let file = settingsFile,
          let data = try? Data(contentsOf: file),
          let map = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else { return nil }
    return ClipboardPrefs.fromMap(map)
  }

  func addObserver(_ observer: @escaping () -> Void) {
    observers.append(observer)
  }

  private func notify() {
    let observers = self.observers
    DispatchQueue.main.async { observers.forEach { $0() } }
  }

  // MARK: - Recording

  /// Adds a capture, or folds it into the identical entry already held.
  ///
  /// `blob` is written under the entry id; passing nil for an entry that
  /// declares an extension means the payload was over the size ceiling and the
  /// row keeps its metadata without its content.
  func record(_ entry: ClipboardEntry, blob: Data?) {
    guard prefs.enabled else { return }
    if entry.sensitive && !prefs.storeSensitive { return }
    if let bundleId = entry.sourceBundleId, prefs.excludedBundleIds.contains(bundleId) { return }

    if let index = entries.firstIndex(where: { $0.id == entry.id }) {
      var existing = entries[index]
      existing.copyCount += 1
      existing.lastCopiedAt = entry.lastCopiedAt
      // The app it came from this time is the useful one; the first attribution
      // is rarely what the user is looking at the row to remember.
      existing.sourceAppName = entry.sourceAppName ?? existing.sourceAppName
      existing.sourceBundleId = entry.sourceBundleId ?? existing.sourceBundleId
      entries.remove(at: index)
      entries.insert(existing, at: 0)
    } else {
      entries.insert(entry, at: 0)
      if let blob, let url = blobURL(for: entry) {
        io.async { try? blob.write(to: url, options: .atomic) }
      }
    }

    _ = trim()
    scheduleWrite()
    notify()
  }

  // MARK: - Mutations

  func setPinned(id: String, pinned: Bool) {
    guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
    entries[index].pinned = pinned
    scheduleWrite()
    notify()
  }

  func delete(ids: [String]) {
    let doomed = Set(ids)
    guard entries.contains(where: { doomed.contains($0.id) }) else { return }
    let removed = entries.filter { doomed.contains($0.id) }
    entries.removeAll { doomed.contains($0.id) }
    removeBlobs(for: removed)
    scheduleWrite()
    notify()
  }

  func clear(keepPinned: Bool) {
    let removed = keepPinned ? entries.filter { !$0.pinned } : entries
    guard !removed.isEmpty else { return }
    entries = keepPinned ? entries.filter(\.pinned) : []
    removeBlobs(for: removed)
    scheduleWrite()
    notify()
  }

  func configure(_ prefs: ClipboardPrefs) {
    self.prefs = prefs
    if trim() {
      scheduleWrite()
      notify()
    }
  }

  /// Called on quit when the user asked for the history not to outlive the
  /// session. Writes synchronously: there is no later.
  func clearOnQuitIfAsked() {
    guard prefs.clearOnQuit else {
      flush()
      return
    }
    clear(keepPinned: true)
    flush()
  }

  // MARK: - Trimming

  /// Applies every ceiling. Returns whether anything went.
  ///
  /// Pinned entries survive all three: a pin is the user saying "not this one",
  /// and a cap that overrides it makes pinning worthless.
  @discardableResult
  private func trim() -> Bool {
    var removed: [ClipboardEntry] = []

    if prefs.retentionDays > 0 {
      let cutoff = Date().timeIntervalSince1970 * 1000
        - Double(prefs.retentionDays) * 86_400_000
      removed += entries.filter { !$0.pinned && $0.lastCopiedAt < cutoff }
      entries.removeAll { !$0.pinned && $0.lastCopiedAt < cutoff }
    }

    // Pinned entries do not count against the cap. "Keep the last 200" is a
    // statement about the history scrolling past, not about the handful the
    // user explicitly held on to.
    if entries.filter({ !$0.pinned }).count > prefs.maxItems {
      var kept: [ClipboardEntry] = []
      var unpinned = 0
      for entry in entries {
        if entry.pinned {
          kept.append(entry)
        } else if unpinned < prefs.maxItems {
          kept.append(entry)
          unpinned += 1
        } else {
          removed.append(entry)
        }
      }
      entries = kept
    }

    removed += trimBlobDirectory()

    guard !removed.isEmpty else { return false }
    removeBlobs(for: removed)
    return true
  }

  /// Drops the oldest blob-carrying entries until the folder is under its
  /// ceiling. Text-only entries cost nothing and are never touched here.
  private func trimBlobDirectory() -> [ClipboardEntry] {
    guard let dir = directory else { return [] }
    let blobDir = blobs(in: dir)

    let files = (try? FileManager.default.contentsOfDirectory(
      at: blobDir,
      includingPropertiesForKeys: [.fileAllocatedSizeKey]
    )) ?? []

    var total = 0
    for file in files {
      let size = (try? file.resourceValues(forKeys: [.fileAllocatedSizeKey]))?.fileAllocatedSize
      total += size ?? 0
    }
    guard total > prefs.maxBlobBytes else { return [] }

    var removed: [ClipboardEntry] = []
    for entry in entries.reversed() where entry.hasBlob && !entry.pinned {
      guard total > prefs.maxBlobBytes else { break }
      total -= entry.byteCount
      removed.append(entry)
    }
    let doomed = Set(removed.map(\.id))
    entries.removeAll { doomed.contains($0.id) }
    return removed
  }

  private func removeBlobs(for entries: [ClipboardEntry]) {
    let urls = entries.compactMap { blobURL(for: $0) }
    guard !urls.isEmpty else { return }
    io.async { urls.forEach { try? FileManager.default.removeItem(at: $0) } }
  }

  // MARK: - Persistence

  /// Coalesces a burst of copies into one write. Copying five things in a row
  /// is one file rewrite, not five.
  private func scheduleWrite() {
    pendingWrite?.cancel()
    let snapshot = entries
    let work = DispatchWorkItem { [weak self] in self?.write(snapshot) }
    pendingWrite = work
    io.asyncAfter(deadline: .now() + 1.0, execute: work)
  }

  func flush() {
    pendingWrite?.cancel()
    pendingWrite = nil
    let snapshot = entries
    io.sync { write(snapshot) }
  }

  private func write(_ snapshot: [ClipboardEntry]) {
    guard let file = indexFile else { return }
    let root: [String: Any] = [
      "formatVersion": Self.formatVersion,
      "entries": snapshot.map { $0.toMap() },
    ]
    do {
      let data = try JSONSerialization.data(withJSONObject: root)
      try data.write(to: file, options: .atomic)
    } catch {
      NSLog("Clipboard: could not write the index: \(error.localizedDescription)")
    }
  }

  // MARK: - Reading back

  func entry(id: String) -> ClipboardEntry? {
    entries.first { $0.id == id }
  }

  /// The full text of an entry, inline or from its blob.
  func fullText(for entry: ClipboardEntry) -> String? {
    if let text = entry.text { return text }
    guard entry.kind != .image, let url = blobURL(for: entry) else { return nil }
    return try? String(contentsOf: url, encoding: .utf8)
  }

  func blobData(for entry: ClipboardEntry) -> Data? {
    guard let url = blobURL(for: entry) else { return nil }
    return try? Data(contentsOf: url)
  }

  /// Whether text of this length is small enough to sit in the index.
  static func fitsInline(_ text: String) -> Bool {
    text.utf8.count <= inlineTextLimit
  }
}

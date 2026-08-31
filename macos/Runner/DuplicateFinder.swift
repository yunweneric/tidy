import CryptoKit
import Foundation

/// Finds byte-identical files, and reports what removing them would *actually*
/// free.
///
/// The naive version of this feature — group by size, hash everything, multiply
/// by the copy count — overstates reclaimable space on APFS badly enough to be
/// a lie. Two things break it, and both are handled here:
///
/// * **Hardlinks.** Two paths, one inode, one set of blocks. Deleting one frees
///   nothing at all.
/// * **Clones.** `cp` on APFS is a clone by default, as is a Finder duplicate:
///   two inodes sharing every extent. They are byte-identical by construction,
///   so they dominate any duplicate list, and `st_blocks` reports the full size
///   for each — so a clone-blind scan promises gigabytes that do not exist.
///
/// `ATTR_CMNEXT_PRIVATESIZE` is the honest number: bytes belonging to this file
/// and no other. For a pristine clone it is near zero, and the UI can then say
/// so rather than quietly inflating the total.
enum DuplicateFinder {
  /// Hashing reads the whole file, so it only happens for files that already
  /// share an exact size with something else. This first pass is cheaper still:
  /// two files that differ at all usually differ early.
  private static let headBytes = 64 * 1024
  private static let chunkBytes = 1 << 20

  /// Bundles are one thing to the user and to the app that owns them. Removing
  /// a single duplicated resource from inside `Photos Library.photoslibrary`
  /// corrupts it, so the walk never descends into one.
  private static let opaqueSuffixes = [
    ".app", ".photoslibrary", ".framework", ".bundle", ".xcodeproj", ".xcworkspace",
    ".rtfd", ".fcpbundle", ".imovielibrary", ".tvlibrary", ".logicx", ".band",
  ]

  private struct Candidate {
    let path: String
    let logicalSize: Int64
    let allocatedSize: Int64
    let device: dev_t
    let inode: UInt64
    let modified: TimeInterval
  }

  /// Groups of byte-identical files found under `roots`.
  ///
  /// `minBytes` keeps the list to duplicates worth a decision — a thousand
  /// identical 4 KB dotfiles are noise, not reclaimable space. `maxGroups`
  /// bounds what crosses the channel; a home directory can hold tens of
  /// thousands of duplicate groups and no one reviews that many.
  static func groups(roots: [String], minBytes: Int64, maxGroups: Int) -> [[String: Any]] {
    var bySize: [Int64: [Candidate]] = [:]
    for root in roots {
      collect(root: root, minBytes: minBytes, into: &bySize)
    }

    var found: [[String: Any]] = []
    // Biggest first: if the cap truncates, it truncates the part nobody would
    // have scrolled to.
    for size in bySize.keys.sorted(by: >) {
      guard let bucket = bySize[size], bucket.count > 1 else { continue }
      for group in identicalSets(in: bucket) {
        found.append(describe(group))
        if found.count >= maxGroups { return found }
      }
    }
    return found
  }

  // MARK: - Walking

  private static func collect(
    root: String,
    minBytes: Int64,
    into bySize: inout [Int64: [Candidate]]
  ) {
    withFTS(root) { handle, entry in
      let info = Int32(entry.pointee.fts_info)

      if info == FTS_D {
        // Prune the whole subtree, and prune anything hidden: `.git` objects
        // and `node_modules` are full of legitimate identical files that are
        // not the user's to delete one by one.
        let name = (String(cString: entry.pointee.fts_path) as NSString).lastPathComponent
        if name.hasPrefix(".") || opaqueSuffixes.contains(where: { name.hasSuffix($0) }) {
          _ = fts_set(handle, entry, FTS_SKIP)
        }
        return
      }

      guard info == FTS_F, let stat = entry.pointee.fts_statp else { return }
      let logical = Int64(stat.pointee.st_size)
      guard logical >= minBytes else { return }

      let path = String(cString: entry.pointee.fts_path)
      bySize[logical, default: []].append(
        Candidate(
          path: path,
          logicalSize: logical,
          allocatedSize: Int64(stat.pointee.st_blocks) * 512,
          device: stat.pointee.st_dev,
          inode: stat.pointee.st_ino,
          modified: Double(stat.pointee.st_mtimespec.tv_sec)
        )
      )
    }
  }

  // MARK: - Content matching

  /// Splits a same-size bucket into sets that really are byte-identical.
  ///
  /// Hardlinks collapse first: one inode is hashed once however many names
  /// point at it, and the extra names travel with it so the UI can still show
  /// them (and say that deleting them frees nothing).
  private static func identicalSets(in bucket: [Candidate]) -> [[Candidate]] {
    var byInode: [String: [Candidate]] = [:]
    for candidate in bucket {
      byInode["\(candidate.device):\(candidate.inode)", default: []].append(candidate)
    }
    guard byInode.count > 1 else { return [] }

    let representatives = byInode.values.map { $0[0] }

    var sets: [[Candidate]] = []
    for headGroup in bucketed(representatives, by: { digest(of: $0.path, limit: headBytes) }) {
      for fullGroup in bucketed(headGroup, by: { digest(of: $0.path, limit: nil) }) {
        sets.append(
          fullGroup.flatMap { byInode["\($0.device):\($0.inode)"] ?? [$0] }
        )
      }
    }
    return sets
  }

  /// Groups by a hash, dropping anything that ends up alone — a file with no
  /// hash match is not a duplicate, and a file we could not read is not a file
  /// we should offer to delete.
  private static func bucketed(
    _ candidates: [Candidate],
    by hash: (Candidate) -> String?
  ) -> [[Candidate]] {
    guard candidates.count > 1 else { return [] }
    var buckets: [String: [Candidate]] = [:]
    for candidate in candidates {
      guard let key = hash(candidate) else { continue }
      buckets[key, default: []].append(candidate)
    }
    return buckets.values.filter { $0.count > 1 }
  }

  /// SHA-256 of the first `limit` bytes, or the whole file when nil. Streamed:
  /// duplicate candidates are by definition the big files, and reading a 4 GB
  /// video into memory to hash it would be worse than not having the feature.
  private static func digest(of path: String, limit: Int?) -> String? {
    guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
    defer { try? handle.close() }

    var hasher = SHA256()
    var remaining = limit ?? Int.max
    while remaining > 0 {
      let want = min(remaining, chunkBytes)
      guard let chunk = try? handle.read(upToCount: want), !chunk.isEmpty else { break }
      hasher.update(data: chunk)
      remaining -= chunk.count
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  // MARK: - Reporting

  /// Turns one identical set into the payload the Dart side renders.
  ///
  /// The keeper is the oldest copy — the one most likely to be the original the
  /// others were made from — with the shallowest path breaking ties. It is
  /// named separately rather than just omitted, because "3 copies, keeping the
  /// one in Documents" is a claim the user can check.
  private static func describe(_ group: [Candidate]) -> [String: Any] {
    let ordered = group.sorted {
      $0.modified != $1.modified
        ? $0.modified < $1.modified
        : $0.path.count < $1.path.count
    }
    let keeper = ordered[0]
    var seenInodes: Set<String> = ["\(keeper.device):\(keeper.inode)"]

    var copies: [[String: Any]] = []
    for candidate in ordered.dropFirst() {
      let key = "\(candidate.device):\(candidate.inode)"
      // A second name for a byte we are already keeping. Real, listable, and
      // worth exactly zero bytes.
      let isHardlink = !seenInodes.insert(key).inserted
      let priv = isHardlink ? 0 : privateSize(of: candidate.path, fallback: candidate.allocatedSize)
      copies.append([
        "path": candidate.path,
        "size": candidate.allocatedSize,
        "reclaimable": priv,
        // Any sharing at all. `privateSize` is exact, so this does not need a
        // threshold: a file that owns every one of its blocks reports its full
        // allocated size, and anything less means some of it belongs to the
        // copy being kept as well.
        "sharesStorage": isHardlink || priv < candidate.allocatedSize,
        "modified": candidate.modified,
      ])
    }

    return [
      "name": (keeper.path as NSString).lastPathComponent,
      "keeping": keeper.path,
      "logicalSize": keeper.logicalSize,
      "copies": copies,
    ]
  }

  /// Bytes this file owns outright — what deleting it would really free.
  ///
  /// Falls back to allocated size when the volume does not answer (only APFS
  /// tracks per-file private size), which is the pre-clone behaviour and errs
  /// towards the number every other tool reports.
  private static func privateSize(of path: String, fallback: Int64) -> Int64 {
    var request = attrlist()
    request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
    request.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS)
    request.forkattr = attrgroup_t(ATTR_CMNEXT_PRIVATESIZE)

    // u_int32_t length + attribute_set_t (5 words) + off_t, with room to spare.
    var buffer = [UInt8](repeating: 0, count: 64)
    let status = buffer.withUnsafeMutableBytes { raw in
      getattrlist(path, &request, raw.baseAddress, raw.count, UInt32(FSOPT_ATTR_CMN_EXTENDED))
    }
    guard status == 0 else { return fallback }

    var length: UInt32 = 0
    var returned = attribute_set_t()
    var privateBytes: off_t = 0
    let header = MemoryLayout<UInt32>.size
    let setSize = MemoryLayout<attribute_set_t>.size
    guard buffer.count >= header + setSize + MemoryLayout<off_t>.size else { return fallback }

    buffer.withUnsafeBytes { raw in
      guard let base = raw.baseAddress else { return }
      memcpy(&length, base, header)
      memcpy(&returned, base + header, setSize)
      memcpy(&privateBytes, base + header + setSize, MemoryLayout<off_t>.size)
    }

    // The kernel is free to return fewer attributes than asked for; trusting
    // the buffer without checking would read whatever was there before.
    guard length >= UInt32(header + setSize + MemoryLayout<off_t>.size),
      returned.forkattr & attrgroup_t(ATTR_CMNEXT_PRIVATESIZE) != 0
    else { return fallback }

    return max(0, Int64(privateBytes))
  }

  // MARK: - fts

  /// Walks `root`, handing each entry to `visit` along with the open handle so
  /// it can `fts_set(…, FTS_SKIP)` to prune a subtree.
  ///
  /// Options match `DirectorySizer`: physical (never follow a symlink into a
  /// loop), one device (never wander into a mounted image or network share),
  /// and no chdir (safe alongside other walkers).
  private static func withFTS(
    _ root: String,
    _ visit: (UnsafeMutablePointer<FTS>, UnsafeMutablePointer<FTSENT>) -> Void
  ) {
    root.withCString { cRoot in
      let mutableRoot = UnsafeMutablePointer(mutating: cRoot)
      var argv: [UnsafeMutablePointer<CChar>?] = [mutableRoot, nil]

      argv.withUnsafeMutableBufferPointer { buffer in
        let options = FTS_PHYSICAL | FTS_XDEV | FTS_NOCHDIR
        guard let handle = fts_open(buffer.baseAddress!, options, nil) else { return }
        defer { fts_close(handle) }

        while let entry = fts_read(handle) {
          switch Int32(entry.pointee.fts_info) {
          case FTS_DP:
            continue  // Post-order visit; already seen on the way down.
          case FTS_DNR, FTS_ERR, FTS_NS:
            continue  // Unreadable, almost always TCC. Skip rather than abort.
          default:
            visit(handle, entry)
          }
        }
      }
    }
  }
}

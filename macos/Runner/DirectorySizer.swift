import Foundation

/// Fast on-disk sizing, replacing one `du -sk` subprocess per path.
///
/// `fts(3)` is the fastest directory walker available on local APFS — faster
/// than `getattrlistbulk` outside network volumes, and a fraction of the code.
/// Shelling out to `du` is roughly 3x slower before you count process spawn, and
/// a scan of `~/Library` measures thousands of paths.
enum DirectorySizer {
  /// Sizes many paths, walking several subtrees at once.
  ///
  /// Directory traversal is latency-bound rather than bandwidth-bound, so this
  /// tops out well below the core count; past ~8 workers contention on the APFS
  /// b-tree makes it slower, not faster.
  static func sizes(of paths: [String], concurrency: Int = 6) -> [String: Int64] {
    guard !paths.isEmpty else { return [:] }

    var results: [String: Int64] = [:]
    let lock = NSLock()
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = max(1, min(concurrency, 8))

    for path in paths {
      queue.addOperation {
        let bytes = size(of: path)
        lock.lock()
        results[path] = bytes
        lock.unlock()
      }
    }
    queue.waitUntilAllOperationsAreFinished()
    return results
  }

  /// Allocated bytes for `path` and everything beneath it.
  ///
  /// Uses `st_blocks * 512`, not `st_size`. On APFS the difference is not
  /// academic: a sparse file such as Docker's `Docker.raw` reports 64 GB
  /// logically while occupying 8, and reporting the logical figure means
  /// promising the user 56 GB that does not exist.
  static func size(of path: String) -> Int64 {
    var total: Int64 = 0

    withFTS(path) { entry in
      switch Int32(entry.pointee.fts_info) {
      case FTS_F, FTS_DEFAULT, FTS_SL, FTS_SLNONE:
        if let stat = entry.pointee.fts_statp {
          total += Int64(stat.pointee.st_blocks) * 512
        }
      case FTS_D:
        // Directories themselves occupy blocks too; count them once, on the
        // pre-order visit.
        if let stat = entry.pointee.fts_statp {
          total += Int64(stat.pointee.st_blocks) * 512
        }
      default:
        break
      }
      return true
    }

    return total
  }

  /// One entry per immediate child, with its full recursive size. Backs the
  /// disk map and the "what is big in here" views.
  static func children(of path: String, concurrency: Int = 6) -> [[String: Any]] {
    let fm = FileManager.default
    guard let names = try? fm.contentsOfDirectory(atPath: path) else { return [] }

    let paths = names.map { "\(path)/\($0)" }
    let sized = sizes(of: paths, concurrency: concurrency)

    return paths.compactMap { child in
      var isDirectory: ObjCBool = false
      guard fm.fileExists(atPath: child, isDirectory: &isDirectory) else { return nil }
      let attributes = try? fm.attributesOfItem(atPath: child)
      let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970
      return [
        "path": child,
        "size": sized[child] ?? 0,
        "isDirectory": isDirectory.boolValue,
        "modified": modified ?? 0,
      ]
    }
  }

  // MARK: - fts

  /// Walks `root`, calling `visit` for each entry. Returning false stops early.
  private static func withFTS(_ root: String, _ visit: (UnsafeMutablePointer<FTSENT>) -> Bool) {
    root.withCString { cRoot in
      let mutableRoot = UnsafeMutablePointer(mutating: cRoot)
      var argv: [UnsafeMutablePointer<CChar>?] = [mutableRoot, nil]

      argv.withUnsafeMutableBufferPointer { buffer in
        // FTS_PHYSICAL: never follow symlinks — otherwise a link loop double
        // counts, or walks somewhere it was never asked to go.
        // FTS_XDEV: never cross a mount point. Without it a scan of the home
        // directory wanders into mounted disk images, Time Machine backups and
        // network shares, where a single stat can block for half a minute.
        // FTS_NOCHDIR: leave the process working directory alone; fts otherwise
        // chdir()s, which is not safe with concurrent walkers.
        let options = FTS_PHYSICAL | FTS_XDEV | FTS_NOCHDIR
        guard let handle = fts_open(buffer.baseAddress!, options, nil) else { return }
        defer { fts_close(handle) }

        while let entry = fts_read(handle) {
          switch Int32(entry.pointee.fts_info) {
          case FTS_DP:
            continue // Post-order visit of a directory already counted.
          case FTS_DNR, FTS_ERR, FTS_NS:
            continue // Unreadable — usually TCC. Skip rather than abort.
          default:
            break
          }
          if !visit(entry) { return }
        }
      }
    }
  }
}

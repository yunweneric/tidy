import Cocoa
import CryptoKit
import Security

/// Unpacking, checking and installing a downloaded update.
///
/// Dart downloads the zip, because that is where progress can be shown without
/// inventing a second channel for it. From the moment there is a file on disk,
/// everything is here — whether the archive is what it claims to be is a
/// question about code signatures, and replacing a running application is a
/// question about atomic filesystem operations. Dart can answer neither.
enum Updater {

  /// Set immediately before the app quits to make way for the new copy.
  ///
  /// `AppDelegate.applicationWillTerminate` reads it, and has to: "clear the
  /// clipboard when I quit" is a promise about the user quitting. An update
  /// relaunch is not a quit they made, and wiping their history behind an
  /// update they asked for would be the setting betraying them rather than
  /// serving them.
  static private(set) var isRelaunchingForUpdate = false

  /// The prefix on every directory this file creates.
  ///
  /// Dot-prefixed so a staged copy sitting in `/Applications` is invisible to
  /// Finder, Spotlight and Launchpad while it waits, and fixed so
  /// [sweepLeftovers] can be exact rather than heuristic. This app in
  /// particular should not leave litter behind.
  private static let stagePrefix = ".tidy-update-"

  private static let lsregister =
    "/System/Library/Frameworks/CoreServices.framework/Frameworks/"
    + "LaunchServices.framework/Support/lsregister"

  /// Why a step failed, in two registers: [code] for the Dart side to branch
  /// on, [message] for the sentence in front of the user.
  ///
  /// Nothing here is allowed to surface as "something went wrong". The whole
  /// reason this is native is that macOS said something specific, and the user
  /// needs it to decide what to do next — retry, install by hand, or stop.
  struct Failure: Error {
    let code: String
    let message: String
    var detail: String?

    /// True when installing the disk image by hand would work where this did
    /// not, so the UI can offer that instead of only apologising.
    var manualFallback = false

    var payload: [String: Any] {
      var map: [String: Any] = [
        "ok": false,
        "code": code,
        "message": message,
        "canRetryManually": manualFallback,
      ]
      if let detail { map["detail"] = detail }
      return map
    }
  }

  // MARK: - Prepare

  /// Verifies the downloaded archive and stages the app inside it.
  ///
  /// Blocking: the digest is a full read of the archive and `kSecCSCheckNestedCode`
  /// walks every sealed resource in the bundle. Both are seconds, not
  /// milliseconds. Call it off the main thread.
  static func prepare(zipPath: String, expectedSha256: String?) -> [String: Any] {
    do {
      let staged = try stage(zipPath: zipPath, expectedSha256: expectedSha256)
      return [
        "ok": true,
        "stagedPath": staged.path,
        "version": staged.version,
        "canRetryManually": false,
      ]
    } catch let failure as Failure {
      return failure.payload
    } catch {
      return Failure(
        code: "prepare_failed",
        message: "The update could not be prepared.",
        detail: error.localizedDescription
      ).payload
    }
  }

  private static func stage(
    zipPath: String,
    expectedSha256: String?
  ) throws -> (path: String, version: String) {
    guard FileManager.default.fileExists(atPath: zipPath) else {
      throw Failure(
        code: "unreadable_download",
        message: "The downloaded update is no longer on disk."
      )
    }

    // 1. The archive is the one the release described. First because it is the
    //    cheapest check, and because everything downstream only means anything
    //    if these are the announced bytes. The digest arrives over the same
    //    connection as the download, so it catches a truncated or corrupted
    //    transfer — step 4 is what establishes trust.
    let digest = try sha256(ofFileAt: zipPath)
    if let expected = expectedSha256?.lowercased(), !expected.isEmpty {
      guard digest == expected else {
        throw Failure(
          code: "hash_mismatch",
          message: "The download did not match what the release said it would "
            + "be. Nothing has been installed.",
          detail: "expected \(expected), got \(digest)"
        )
      }
    } else if !isDeveloperIDSigned(Bundle.main.bundleURL) {
      // No checksum and no signature to fall back on is no verification at all.
      throw Failure(
        code: "unverifiable",
        message: "The update published no checksum, and this build is not "
          + "signed, so there is no way to check it. It was not installed."
      )
    }

    // 2. Unpack beside the installed app.
    //
    //    Beside it, not in a temp directory, for one reason that decides
    //    everything else: `renamex_np` is `rename(2)`, which cannot cross
    //    filesystems. Staging in the app's own folder is the only way to be
    //    certain of a single volume whether the app lives in /Applications, in
    //    ~/Applications, or on an external disk.
    let installed = Bundle.main.bundleURL
    let parent = installed.deletingLastPathComponent()
    let stage = parent.appendingPathComponent(stagePrefix + UUID().uuidString)

    do {
      try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
    } catch {
      // /Applications is drwxrwxr-x root:admin, so a standard (non-admin)
      // account lands here. Asking for an administrator password would work,
      // and is deliberately not offered: a cleaner that asks for admin rights
      // to modify itself is exactly the shape of thing people should refuse.
      throw Failure(
        code: "stage_unwritable",
        message: "\(appName) could not write next to itself in \(parent.path). "
          + "Install the update from the disk image instead.",
        detail: error.localizedDescription,
        manualFallback: true
      )
    }

    var keep = false
    defer { if !keep { try? FileManager.default.removeItem(at: stage) } }

    // `ditto`, categorically not `unzip` or a zip library. An `.app` is not an
    // ordinary directory tree: `FlutterMacOS.framework` is `Versions/A` plus
    // three symlinks, and the signature seals those symlinks *as symlinks*.
    // Anything that materialises a symlink as a copy of its target produces a
    // bundle that fails verification for reasons indistinguishable from
    // tampering. `--noqtn` stops a quarantine flag stored inside the archive
    // from being restored onto the unpacked files.
    let unpacked = Shell.run("/usr/bin/ditto", ["-x", "-k", "--noqtn", zipPath, stage.path])
    guard unpacked == 0 else {
      throw Failure(
        code: "unpack_failed",
        message: "The download could not be unpacked — it may have arrived "
          + "incomplete.",
        detail: "ditto exited \(unpacked)"
      )
    }

    guard let app = appBundle(in: stage) else {
      throw Failure(
        code: "no_app_in_archive",
        message: "The download did not contain a copy of \(appName)."
      )
    }

    let version = try validate(staged: app)

    // 3. Belt and braces. Nothing should have set a quarantine flag — the app
    //    is not sandboxed, declares no `LSFileQuarantineEnabled`, and `ditto
    //    --noqtn` refused to restore one — but a single quarantined file
    //    anywhere inside the bundle turns the first launch after the swap into
    //    a Gatekeeper dialog nobody asked for.
    clearQuarantine(at: app)

    keep = true
    return (app.path, version)
  }

  // MARK: - Validation

  /// Everything that has to be true before a downloaded bundle may replace the
  /// running one. None of it is advisory; any one failing aborts the install.
  private static func validate(staged app: URL) throws -> String {
    // 1. It is a bundle, and it is ours. Before the signature check, so that
    //    "you downloaded the wrong app" reads as that rather than as tampering.
    let plist = app.appendingPathComponent("Contents/Info.plist")
    guard let info = NSDictionary(contentsOf: plist) as? [String: Any],
          let identifier = info["CFBundleIdentifier"] as? String else {
      throw Failure(
        code: "no_info_plist",
        message: "The downloaded app is not a valid application bundle."
      )
    }
    guard identifier == Bundle.main.bundleIdentifier else {
      throw Failure(
        code: "wrong_bundle_id",
        message: "The download is not \(appName).",
        detail: "bundle id \(identifier)"
      )
    }

    let candidate = info["CFBundleShortVersionString"] as? String ?? ""
    let running =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    // 2. Strictly newer, and not a nicety. Without it, a feed that has been
    //    tampered with — or merely rolled back by mistake — can move everyone
    //    onto an older build with a known hole in it, and every check below
    //    still passes, because an old copy of this app is a correctly signed
    //    copy of this app.
    guard compare(candidate, running) == .orderedDescending else {
      throw Failure(
        code: "not_newer",
        message: "The download is version \(candidate), which is not newer "
          + "than \(running)."
      )
    }

    // 3. The signature, in process.
    //
    //    `kSecCSCheckNestedCode` is what `--deep` does: it validates
    //    `App.framework` and `FlutterMacOS.framework` as code rather than as
    //    sealed resources, and a signature covering only the outer wrapper is
    //    not a signature over what will actually run. `kSecCSStrictValidate`
    //    closes the loopholes that let a file be added to a sealed bundle.
    //
    //    `kSecCSConsiderExpiration` is deliberately absent. Developer ID
    //    signatures carry a secure timestamp and stay valid after the
    //    certificate expires — that is exactly how Gatekeeper treats them — so
    //    setting it would mean that on the day the certificate rolls over,
    //    every installed copy starts refusing every update, including the one
    //    that would fix it.
    if isDeveloperIDSigned(Bundle.main.bundleURL) {
      try verifySignature(of: app)
      try verifyGatekeeper(app)
    } else {
      // Every build made before this shipped is ad-hoc signed, and an ad-hoc
      // designated requirement is a `cdhash` of that one binary, which no
      // future build can ever match. There is nothing to check against, so the
      // checksum from step 1 of `stage` stands in its place — it was made
      // mandatory there for exactly this case.
      NSLog("[tidy][updates] this build is not Developer ID signed; "
        + "installing on the checksum alone")
    }

    return candidate
  }

  /// Checks the staged bundle against the running app's designated requirement.
  ///
  /// The running app's own requirement, and not merely because it is *a*
  /// reasonable yardstick. That string is the same predicate TCC stored when
  /// the user granted Full Disk Access, and it is re-evaluated against the
  /// running process on every protected read. An update that satisfies it keeps
  /// the grant; one that does not would launch, look fine, and quietly be
  /// unable to read anything it could read yesterday. Refusing to install is
  /// strictly better than that.
  private static func verifySignature(of app: URL) throws {
    guard let requirement = CodeSignature.selfDesignatedRequirement() else {
      throw Failure(
        code: "requirement_failed",
        message: "\(appName) could not work out what a valid update looks like."
      )
    }

    let verdict = CodeSignature.validate(path: app.path, against: requirement)
    guard verdict["ok"] as? Bool == true else {
      let detail = verdict["reason"] as? String
      NSLog("[tidy][updates] signature check failed: \(detail ?? "unknown")")
      var reported = Failure(
        code: "signature_rejected",
        message: "The download is not signed by the same developer as this copy "
          + "of \(appName), or it was changed on the way here. It has not been "
          + "installed."
      )
      reported.detail = detail
      throw reported
    }
  }

  /// Asks Gatekeeper whether it would let the bundle run.
  ///
  /// There is no public API for this — `SecAssessment.h` is not in the macOS
  /// SDK — so it is `spctl` or nothing. It reads the ticket stapled into the
  /// bundle, so it answers without a network round trip. A build that was
  /// notarised but never stapled fails here on an offline Mac, which is the
  /// correct answer and the reason the release script staples before zipping.
  private static func verifyGatekeeper(_ app: URL) throws {
    guard CodeSignature.assess(path: app.path)["ok"] as? Bool == true else {
      throw Failure(
        code: "gatekeeper_rejected",
        message: "macOS refused the download — it may not be notarised. It has "
          + "not been installed."
      )
    }
  }

  // MARK: - Install

  /// Puts the staged bundle where the running one is, then arranges for the new
  /// copy to be launched once this process is gone.
  ///
  /// The swap is one `renamex_np` with `RENAME_SWAP`: an atomic exchange of two
  /// directory entries. Replacing a running `.app` is only dangerous if you
  /// write into the files it has mapped — renaming the directory they live in
  /// touches no inode at all, because the kernel tracks vnodes rather than
  /// paths, so this process carries on running quite happily under its new
  /// name.
  ///
  /// Doing it here rather than from a detached helper script is what makes the
  /// failure modes survivable. There is no instant in which the app does not
  /// exist at its path; the exchange either happened or did not; and it runs
  /// while there is still a window to report a failure to. A helper that
  /// deletes the old bundle and copies the new one in has a window in which it
  /// can die and leave a Mac with no application on it.
  static func install(stagedPath: String) -> [String: Any] {
    let staged = URL(fileURLWithPath: stagedPath)
    let installed = Bundle.main.bundleURL

    guard FileManager.default.fileExists(atPath: staged.path) else {
      return Failure(
        code: "missing_staged",
        message: "The prepared update is no longer on disk."
      ).payload
    }

    let swapped = staged.path.withCString { from in
      installed.path.withCString { to in
        renamex_np(from, to, UInt32(RENAME_SWAP)) == 0
      }
    }

    guard swapped else {
      let code = errno
      switch code {
      case EACCES, EPERM, EROFS:
        return Failure(
          code: "swap_unwritable",
          message: "\(appName) could not replace itself in "
            + "\(installed.deletingLastPathComponent().path). Install the "
            + "update from the disk image instead.",
          detail: String(cString: strerror(code)),
          manualFallback: true
        ).payload
      case EXDEV:
        // Staging happens beside the app precisely so this cannot happen, so
        // reaching it means the app moved in between.
        return Failure(
          code: "cross_volume",
          message: "\(appName) moved while the update was being prepared. "
            + "Check for updates again."
        ).payload
      default:
        return Failure(
          code: "swap_failed",
          message: "The update could not be installed.",
          detail: String(cString: strerror(code)),
          manualFallback: true
        ).payload
      }
    }

    // After the exchange the two paths have traded contents: the staging folder
    // now holds the version being replaced, and is what gets cleaned up once
    // this process is gone.
    return relaunch(removing: staged.deletingLastPathComponent())
  }

  /// Spawns the one thing that cannot happen inside this process — starting the
  /// new copy after this one has exited — and then quits.
  ///
  /// `posix_spawn` with `POSIX_SPAWN_SETSID` rather than `Process`: a child of
  /// a GUI app belongs to the launchd job LaunchServices created for that app,
  /// and launchd is entitled to tear the whole job down when the app exits.
  /// Making the helper a session leader reparents it to launchd itself, so it
  /// outlives us for certain.
  ///
  /// It waits on the pid rather than sleeping a fixed amount, because
  /// `applicationWillTerminate` flushes the clipboard index and the network
  /// history and there is no honest number to guess. The thirty-second cap
  /// exists only so a hung quit cannot leave a shell spinning forever; by then
  /// the swap has already happened, so launching anyway is the right answer.
  private static func relaunch(removing leftovers: URL) -> [String: Any] {
    let app = Bundle.main.bundleURL.path
    let pid = getpid()

    let script = """
      n=0
      while /bin/kill -0 \(pid) 2>/dev/null && [ $n -lt 300 ]; do
        /bin/sleep 0.1
        n=$((n+1))
      done
      /bin/rm -rf \(shellQuote(leftovers.path))
      \(shellQuote(lsregister)) -f \(shellQuote(app)) >/dev/null 2>&1 || true
      /usr/bin/open \(shellQuote(app))
      """

    guard spawnDetached("/bin/sh", ["-c", script]) else {
      // The update *is* installed. Say exactly that: the next thing the user
      // should do is quit and reopen, not download it again.
      return Failure(
        code: "relaunch_failed",
        message: "The update is installed, but \(appName) could not restart "
          + "itself. Quit \(appName) and open it again."
      ).payload
    }

    isRelaunchingForUpdate = true
    NSLog("[tidy][updates] swapped in the new bundle; relaunching")
    // Long enough for the result to reach Dart and the UI to say what is
    // happening, short enough that nobody wonders whether it worked.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { NSApp.terminate(nil) }
    return ["ok": true]
  }

  private static func spawnDetached(_ executable: String, _ arguments: [String]) -> Bool {
    var attributes: posix_spawnattr_t?
    posix_spawnattr_init(&attributes)
    defer { posix_spawnattr_destroy(&attributes) }
    posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))

    let arguments: [String] = [executable] + arguments
    // A deliberately bare environment: inheriting this process's into something
    // that outlives it is how a stale `DYLD_` variable ends up set in the
    // relaunched app.
    let environment: [String] = ["PATH=/usr/bin:/bin:/usr/sbin:/sbin"]

    var argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) }
    argv.append(nil)
    var envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup($0) }
    envp.append(nil)
    defer {
      argv.forEach { free($0) }
      envp.forEach { free($0) }
    }

    var pid: pid_t = 0
    return posix_spawn(&pid, executable, nil, &attributes, argv, envp) == 0
  }

  // MARK: - Housekeeping

  /// Removes a staged bundle the user decided against.
  static func discard(stagedPath: String) {
    let staged = URL(fileURLWithPath: stagedPath)
    let container = staged.deletingLastPathComponent()
    let target = container.lastPathComponent.hasPrefix(stagePrefix) ? container : staged
    try? FileManager.default.removeItem(at: target)
  }

  /// Removes staging folders a previous run left behind.
  ///
  /// A prepare the user never installed, or an install whose helper was killed
  /// before its `rm`. Called at launch. The fixed prefix is what lets this be
  /// exact rather than a guess at what looks like litter.
  @discardableResult
  static func sweepLeftovers() -> Int {
    let parent = Bundle.main.bundleURL.deletingLastPathComponent()
    let entries = (try? FileManager.default.contentsOfDirectory(
      at: parent,
      includingPropertiesForKeys: nil,
      options: [.skipsSubdirectoryDescendants]
    )) ?? []

    var removed = 0
    for entry in entries where entry.lastPathComponent.hasPrefix(stagePrefix) {
      if (try? FileManager.default.removeItem(at: entry)) != nil { removed += 1 }
    }
    if removed > 0 {
      NSLog("[tidy][updates] removed \(removed) leftover staging folder(s)")
    }
    return removed
  }

  /// Version, build and install location of the running bundle.
  static func currentBundle() -> [String: Any] {
    let bundle = Bundle.main
    let parent = bundle.bundleURL.deletingLastPathComponent()

    // `isWritableFile` is `access(2)`, which honours ACLs as well as the mode
    // bits. `attributesOfItem` does not, and /Applications is exactly the kind
    // of directory an MDM puts an ACL on.
    let writable = FileManager.default.isWritableFile(atPath: parent.path)
    let readOnly = (try? parent.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?
      .volumeIsReadOnly ?? false

    return [
      "version": bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
      "build": bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
      "bundlePath": bundle.bundleURL.path,
      // Running straight out of the disk image it arrived in, or off a network
      // share. Nothing can be installed over that, and the UI has to say so
      // rather than offering a button that cannot work.
      "installWritable": writable && !readOnly,
    ]
  }

  // MARK: - Helpers

  private static let appName = AppSupport.directoryName

  private static func sha256(ofFileAt path: String) throws -> String {
    guard let handle = FileHandle(forReadingAtPath: path) else {
      throw Failure(
        code: "unreadable_download",
        message: "The downloaded file could not be opened."
      )
    }
    defer { try? handle.close() }

    // Read in slices, so a bundle of tens of megabytes is never resident all at
    // once just to be hashed.
    var digest = SHA256()
    while true {
      let chunk = autoreleasepool { handle.readData(ofLength: 1 << 20) }
      if chunk.isEmpty { break }
      digest.update(data: chunk)
    }
    return digest.finalize().map { String(format: "%02x", $0) }.joined()
  }

  /// Whether a bundle carries a real signature rather than an ad-hoc one.
  ///
  /// The distinction that matters: an ad-hoc signature's designated requirement
  /// is a hash of that exact binary, so there is nothing a *different* build
  /// could ever be checked against.
  private static func isDeveloperIDSigned(_ url: URL) -> Bool {
    let info = CodeSignature.inspect(path: url.path)
    guard info["signed"] as? Bool == true else { return false }
    if info["adhoc"] as? Bool == true { return false }
    return info["teamIdentifier"] != nil
  }

  /// Strips `com.apple.quarantine` from every path in the bundle.
  ///
  /// `removexattr(2)` rather than `/usr/bin/xattr`: on macOS 11 through 13 that
  /// is a `#!/usr/bin/python3` script, and on a Mac without the Command Line
  /// Tools installed, running it opens the "install developer tools?" dialog —
  /// mid-update, over the app's own window. The deployment target is 11.0.
  ///
  /// Safe with respect to the signature: `com.apple.quarantine` is one of the
  /// attributes codesign excludes from the seal, which is why clearing it has
  /// never invalidated anybody's app.
  private static func clearQuarantine(at root: URL) {
    func strip(_ path: String) {
      // ENOATTR is the overwhelmingly common answer and is not an error.
      _ = path.withCString { removexattr($0, "com.apple.quarantine", XATTR_NOFOLLOW) }
    }

    strip(root.path)
    guard let walker = FileManager.default.enumerator(
      at: root,
      includingPropertiesForKeys: nil,
      options: []
    ) else { return }
    for case let url as URL in walker { strip(url.path) }
  }

  private static func appBundle(in directory: URL) -> URL? {
    let entries = (try? FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil,
      options: [.skipsSubdirectoryDescendants]
    )) ?? []
    return entries.first { $0.pathExtension == "app" }
  }

  /// Dotted numeric comparison. Not a full semver implementation and does not
  /// need to be — the only versions it ever sees are the ones this repo's
  /// release script emits.
  static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
    let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
    let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
    for index in 0..<max(left.count, right.count) {
      let a = index < left.count ? left[index] : 0
      let b = index < right.count ? right[index] : 0
      if a != b { return a < b ? .orderedAscending : .orderedDescending }
    }
    return .orderedSame
  }

  /// Single-quotes a path for `/bin/sh`. The relauncher is built by string
  /// interpolation, and an application can legally live at a path with a space
  /// or a quote in it.
  private static func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }
}

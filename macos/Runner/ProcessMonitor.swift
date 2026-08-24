import Cocoa
import Darwin

/// Live CPU and memory per process.
///
/// Two things here are easy to get wrong and worth stating:
///
/// **CPU is a rate, not a reading.** `proc_pid_rusage` reports cumulative CPU
/// nanoseconds since the process started, so a single sample tells you what a
/// process has used since boot, not what it is using now. The percentage comes
/// from the delta between two samples divided by the wall-clock time between
/// them — which is why the first tick reports nothing rather than a number that
/// looks authoritative and is meaningless.
///
/// **Memory is `ri_phys_footprint`, not resident size.** RSS counts shared
/// pages once per process, so summing it across a machine over-reports wildly.
/// Phys footprint is what Activity Monitor's "Memory" column shows.
enum ProcessMonitor {

  private struct Reading {
    let cpuNanos: UInt64
    let atNanos: UInt64
  }

  private static let lock = NSLock()
  private static var previous: [Int32: Reading] = [:]

  /// Processes that would take the session down with them. macOS would refuse
  /// most of these anyway, but a cleaner should not be offering the button.
  private static let neverQuit: Set<String> = [
    "launchd", "kernel_task", "loginwindow", "WindowServer", "logind",
  ]

  /// Clears the sampling history, so the next tick starts a fresh baseline.
  static func reset() {
    lock.lock()
    previous.removeAll()
    lock.unlock()
  }

  // MARK: - Sampling

  static func sample() -> [String: Any] {
    let now = DispatchTime.now().uptimeNanoseconds
    let myUid = getuid()

    var pids = [pid_t](repeating: 0, count: 8192)
    let byteCount = proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.size * pids.count))
    guard byteCount > 0 else {
      return ["processes": [], "restrictedCount": 0]
    }
    let count = Int(byteCount) / MemoryLayout<pid_t>.size

    // Apps get their real name and icon from AppKit; a bare executable path
    // would show "Google Chrome Helper (Renderer)" as a file name.
    var apps: [pid_t: NSRunningApplication] = [:]
    for app in NSWorkspace.shared.runningApplications {
      apps[app.processIdentifier] = app
    }

    var rows: [[String: Any]] = []
    var restricted = 0
    var live: [Int32: Reading] = [:]

    lock.lock()
    let history = previous
    lock.unlock()

    for index in 0..<count {
      let pid = pids[index]
      guard pid > 0 else { continue }

      // Owner first: reading usage for another user's process needs privileges
      // we do not have, so those are counted and skipped rather than listed as
      // a row of dashes.
      guard let uid = uidOf(pid) else { continue }
      guard uid == myUid else {
        restricted += 1
        continue
      }

      guard let usage = rusage(of: pid) else { continue }

      let cpuNanos = usage.ri_user_time &+ usage.ri_system_time
      live[pid] = Reading(cpuNanos: cpuNanos, atNanos: now)

      var cpuPercent: Double?
      if let earlier = history[pid], now > earlier.atNanos, cpuNanos >= earlier.cpuNanos {
        let elapsed = Double(now - earlier.atNanos)
        let used = Double(cpuNanos - earlier.cpuNanos)
        if elapsed > 0 { cpuPercent = (used / elapsed) * 100 }
      }

      let app = apps[pid]
      let executable = pathOf(pid)
      let name = app?.localizedName
        ?? executable.map { URL(fileURLWithPath: $0).lastPathComponent }
        ?? nameOf(pid)
        ?? "pid \(pid)"

      var row: [String: Any] = [
        "pid": Int(pid),
        "name": name,
        "memoryBytes": Int(usage.ri_phys_footprint),
        "isApp": app != nil,
        "quittable": !neverQuit.contains(nameOf(pid) ?? ""),
      ]
      if let cpuPercent { row["cpuPercent"] = cpuPercent }
      if let executable { row["path"] = executable }
      if let bundle = app?.bundleURL?.path { row["bundlePath"] = bundle }

      rows.append(row)
    }

    lock.lock()
    previous = live
    lock.unlock()

    return ["processes": rows, "restrictedCount": restricted]
  }

  // MARK: - libproc wrappers

  private static func rusage(of pid: pid_t) -> rusage_info_v0? {
    var info = rusage_info_v0()
    let status = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
        proc_pid_rusage(pid, RUSAGE_INFO_V0, rebound)
      }
    }
    return status == 0 ? info : nil
  }

  private static func uidOf(_ pid: pid_t) -> uid_t? {
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    let written = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
    return written == size ? info.pbi_uid : nil
  }

  private static func nameOf(_ pid: pid_t) -> String? {
    // MAXCOMLEN is a C macro and does not reach Swift; proc_name truncates to
    // 2 * MAXCOMLEN (32) characters regardless.
    var buffer = [CChar](repeating: 0, count: 33)
    let written = proc_name(pid, &buffer, UInt32(buffer.count))
    guard written > 0 else { return nil }
    return String(cString: buffer)
  }

  private static func pathOf(_ pid: pid_t) -> String? {
    // PROC_PIDPATHINFO_MAXSIZE is a C macro (4 * MAXPATHLEN) and does not
    // reach Swift either.
    var buffer = [CChar](repeating: 0, count: 4 * Int(PATH_MAX))
    let written = proc_pidpath(pid, &buffer, UInt32(buffer.count))
    guard written > 0 else { return nil }
    return String(cString: buffer)
  }

  // MARK: - Quitting

  /// Asks a process to quit. Returns nil on success, or a sentence to show.
  ///
  /// Apps go through `NSRunningApplication.terminate()`, which is a polite
  /// request the app can answer with a save dialog — `kill` would discard
  /// unsaved work without asking, which is not a cleaner's call to make.
  static func terminate(pid: pid_t, force: Bool) -> String? {
    guard pid > 1 else { return "That is a core macOS process and cannot be quit." }
    guard pid != getpid() else { return "Tidy cannot quit itself." }

    if let name = nameOf(pid), neverQuit.contains(name) {
      return "Quitting \(name) would end your login session."
    }

    guard let uid = uidOf(pid) else { return "That process is no longer running." }
    guard uid == getuid() else {
      return "That process belongs to macOS. Quitting it needs administrator rights."
    }

    if let app = NSRunningApplication(processIdentifier: pid) {
      let quit = force ? app.forceTerminate() : app.terminate()
      return quit ? nil : "macOS would not quit that app."
    }

    let signal = force ? SIGKILL : SIGTERM
    if kill(pid, signal) == 0 { return nil }
    return "Could not quit that process: \(String(cString: strerror(errno)))."
  }
}

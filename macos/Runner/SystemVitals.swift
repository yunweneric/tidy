import Cocoa
import Darwin

/// One machine-wide reading: CPU, memory, swap, uptime and thermal state.
///
/// This is the data a menu bar is *for* — the numbers you want at a glance
/// without opening anything. `ProcessMonitor` answers "which process", this
/// answers "how is the machine".
///
/// Two things are easy to get wrong here, and they are the same two that
/// `ProcessMonitor` documents:
///
/// **CPU is a rate.** `host_statistics` reports cumulative ticks since boot, so
/// one reading describes the machine's whole life. The percentage is the delta
/// between two readings. Unlike the process monitor, this one takes its own
/// 200ms baseline when it has no history rather than returning nothing — the
/// menu bar's headline number cannot be a dash for the first two seconds every
/// time the panel opens.
///
/// **Memory used is not "total minus free".** macOS keeps free memory near zero
/// on purpose; the meaningful figure is what Activity Monitor calls Memory Used
/// — app memory plus wired plus compressed — and cached files are *available*,
/// not used.
enum SystemVitals {

  private struct Ticks {
    let busy: UInt64
    let user: UInt64
    let system: UInt64
    let total: UInt64
    let atNanos: UInt64
  }

  /// A baseline older than this describes the past, not the present, so it is
  /// thrown away and a fresh one taken in-call.
  private static let staleBaselineNanos: UInt64 = 30_000_000_000

  private static let lock = NSLock()
  private static var previous: Ticks?

  /// Drops the sampling history so the next read measures from now.
  static func reset() {
    lock.lock()
    previous = nil
    lock.unlock()
  }

  // MARK: - Reading

  static func read() -> [String: Any] {
    var payload: [String: Any] = [
      "coreCount": ProcessInfo.processInfo.processorCount,
      "uptimeSeconds": ProcessInfo.processInfo.systemUptime,
      "thermalState": thermalName(),
    ]

    if let cpu = cpuLoad() {
      payload["cpuPercent"] = cpu.busy
      payload["cpuUserPercent"] = cpu.user
      payload["cpuSystemPercent"] = cpu.system
    }

    var loads = [Double](repeating: 0, count: 3)
    if getloadavg(&loads, 3) == 3 {
      payload["loadAverage"] = loads[0]
    }

    readMemory(into: &payload)
    readSwap(into: &payload)

    return payload
  }

  // MARK: - CPU

  private static func cpuLoad() -> (busy: Double, user: Double, system: Double)? {
    lock.lock()
    var baseline = previous
    lock.unlock()

    let now = DispatchTime.now().uptimeNanoseconds
    if let held = baseline, now &- held.atNanos > staleBaselineNanos {
      baseline = nil
    }

    if baseline == nil {
      guard let first = ticks() else { return nil }
      usleep(200_000)
      baseline = first
    }

    guard let earlier = baseline, let latest = ticks() else { return nil }

    lock.lock()
    previous = latest
    lock.unlock()

    let elapsed = Double(latest.total &- earlier.total)
    guard elapsed > 0 else { return nil }

    return (
      busy: Double(latest.busy &- earlier.busy) / elapsed * 100,
      user: Double(latest.user &- earlier.user) / elapsed * 100,
      system: Double(latest.system &- earlier.system) / elapsed * 100
    )
  }

  private static func ticks() -> Ticks? {
    var size = mach_msg_type_number_t(
      MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
    )
    var info = host_cpu_load_info_data_t()

    let status = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { rebound in
        host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rebound, &size)
      }
    }
    guard status == KERN_SUCCESS else { return nil }

    // Nice time is user time at a lower priority; folding it into user keeps
    // busy + idle equal to total.
    let user = UInt64(info.cpu_ticks.0) + UInt64(info.cpu_ticks.3)
    let system = UInt64(info.cpu_ticks.1)
    let idle = UInt64(info.cpu_ticks.2)

    return Ticks(
      busy: user + system,
      user: user,
      system: system,
      total: user + system + idle,
      atNanos: DispatchTime.now().uptimeNanoseconds
    )
  }

  // MARK: - Memory

  private static func readMemory(into payload: inout [String: Any]) {
    var size = mach_msg_type_number_t(
      MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
    )
    var stats = vm_statistics64_data_t()

    let status = withUnsafeMutablePointer(to: &stats) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { rebound in
        host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &size)
      }
    }
    guard status == KERN_SUCCESS else { return }

    var pageSize: vm_size_t = 0
    host_page_size(mach_host_self(), &pageSize)
    let page = UInt64(pageSize == 0 ? 4096 : pageSize)

    let wired = UInt64(stats.wire_count) * page
    let compressed = UInt64(stats.compressor_page_count) * page
    let purgeable = UInt64(stats.purgeable_count) * page
    let anonymous = UInt64(stats.internal_page_count) * page
    let cached = UInt64(stats.external_page_count) * page

    // App memory: anonymous pages minus the purgeable ones, which the kernel
    // is free to drop the moment anything else wants the space.
    let app = anonymous > purgeable ? anonymous - purgeable : 0
    let total = ProcessInfo.processInfo.physicalMemory

    payload["memoryTotalBytes"] = Int(total)
    payload["memoryUsedBytes"] = Int(app + wired + compressed)
    payload["memoryAppBytes"] = Int(app)
    payload["memoryWiredBytes"] = Int(wired)
    payload["memoryCompressedBytes"] = Int(compressed)
    payload["memoryCachedBytes"] = Int(cached)

    // Activity Monitor's pressure gauge is driven by paging behaviour Apple
    // does not publish. Wired plus compressed over physical is the closest
    // honest stand-in: both are memory that cannot simply be handed back, so
    // it climbs for the same reasons and at roughly the same time.
    if total > 0 {
      payload["memoryPressurePercent"] = Double(wired + compressed) / Double(total) * 100
    }
  }

  private static func readSwap(into payload: inout [String: Any]) {
    var usage = xsw_usage()
    var size = MemoryLayout<xsw_usage>.size
    guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return }

    payload["swapUsedBytes"] = Int(usage.xsu_used)
    payload["swapTotalBytes"] = Int(usage.xsu_total)
  }

  // MARK: - Thermal

  private static func thermalName() -> String {
    switch ProcessInfo.processInfo.thermalState {
    case .nominal: return "nominal"
    case .fair: return "fair"
    case .serious: return "serious"
    case .critical: return "critical"
    @unknown default: return "nominal"
    }
  }
}

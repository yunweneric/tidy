import Darwin
import Foundation
import SystemConfiguration

/// One interface's share of a reading.
struct NetworkInterfaceRate {
  let name: String

  /// "Wi-Fi", "Ethernet" — what macOS calls this interface in Network settings.
  /// Falls back to the BSD name when SystemConfiguration has nothing to say.
  let displayName: String

  let downBytesPerSecond: Double
  let upBytesPerSecond: Double

  /// Bytes since this interface's counters were last reset — which is boot for
  /// a built-in one, and plug-in for a USB adapter.
  let sinceBootDown: UInt64
  let sinceBootUp: UInt64

  /// What this interface contributed to *this* tick.
  let downBytes: Int
  let upBytes: Int

  func toMap() -> [String: Any] {
    [
      "name": name,
      "displayName": displayName,
      "downBytesPerSecond": downBytesPerSecond,
      "upBytesPerSecond": upBytesPerSecond,
      "sinceBootDown": Int(clamping: sinceBootDown),
      "sinceBootUp": Int(clamping: sinceBootUp),
      "downBytes": downBytes,
      "upBytes": upBytes,
    ]
  }
}

/// One reading: how fast the machine is moving bytes right now, and how many it
/// moved since the previous reading.
struct NetworkSample {
  let atSeconds: Double
  let downBytesPerSecond: Double
  let upBytesPerSecond: Double

  /// The bytes behind the rate. This — not the rate — is what the history
  /// records, so a slow tick and a fast one both count what actually moved.
  let downBytes: Int
  let upBytes: Int

  let interfaces: [NetworkInterfaceRate]

  static let empty = NetworkSample(
    atSeconds: 0,
    downBytesPerSecond: 0,
    upBytesPerSecond: 0,
    downBytes: 0,
    upBytes: 0,
    interfaces: []
  )

  func toMap() -> [String: Any] {
    [
      "at": atSeconds,
      "downBytesPerSecond": downBytesPerSecond,
      "upBytesPerSecond": upBytesPerSecond,
      "downBytes": downBytes,
      "upBytes": upBytes,
      "interfaces": interfaces.map { $0.toMap() },
    ]
  }
}

/// Watches the machine's network interfaces and turns their cumulative byte
/// counters into rates and history.
///
/// Three things are easy to get wrong here, and all three have a comment where
/// they are handled:
///
/// **The counters are cumulative, so a rate is a delta.** Exactly the discipline
/// `SystemVitals` documents for CPU ticks. One reading describes the machine's
/// whole life since boot; the number anyone wants is the difference between two.
///
/// **The counters reset.** Not just at boot — toggling Wi-Fi, unplugging a USB
/// adapter, or waking from sleep can restart an interface at zero. A naive
/// subtraction then underflows into a multi-exabyte "download".
///
/// **Tunnels double-count.** Bytes sent through a VPN cross `utun0` *and* the
/// physical link underneath it. Adding both reports twice the traffic to anyone
/// running a VPN, which is a large and silent lie.
final class NetworkMonitor {
  static let shared = NetworkMonitor()

  private init() {}

  /// One second. Fast enough that the menu bar reads as live, slow enough that a
  /// `sysctl` per tick costs nothing measurable — Activity Monitor samples at
  /// the same cadence.
  private let interval: TimeInterval = 1

  /// How many per-second readings are held for the live chart. Five minutes:
  /// long enough to see a download start and finish, short enough to stay in
  /// memory. Deliberately not persisted — per-second detail is meaningless
  /// after a restart and would dwarf the history file.
  private let ringCapacity = 300

  private var timer: Timer?
  private var previous: [String: (down: UInt64, up: UInt64)] = [:]
  private var previousAtNanos: UInt64?

  private(set) var latest = NetworkSample.empty
  private(set) var ring: [NetworkSample] = []

  private var observers: [UUID: (NetworkSample) -> Void] = [:]

  /// BSD name → the name macOS shows in Network settings. Looked up rarely: it
  /// changes only when hardware is plugged or unplugged.
  private var displayNames: [String: String] = [:]
  private var displayNamesReadAt: Date?

  // MARK: - Lifecycle

  func start() {
    guard timer == nil else { return }

    refreshDisplayNames()
    // A first read with no previous one yields no rate — it only establishes the
    // baseline the next tick measures from.
    previous = Self.readCounters()
    previousAtNanos = DispatchTime.now().uptimeNanoseconds

    // `.common` rather than the default mode: a default-mode timer stops while a
    // menu is tracking, which is precisely when someone is looking at the menu
    // bar and expecting the numbers to move.
    let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
      self?.tick()
    }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }

  /// Drops the baseline so the next tick measures from now. Used after a wake,
  /// where the elapsed time is real but nobody wants one tick to carry ten
  /// minutes of traffic.
  func reset() {
    previous = Self.readCounters()
    previousAtNanos = DispatchTime.now().uptimeNanoseconds
  }

  @discardableResult
  func addObserver(_ observer: @escaping (NetworkSample) -> Void) -> UUID {
    let token = UUID()
    observers[token] = observer
    return token
  }

  func removeObserver(_ token: UUID) {
    observers.removeValue(forKey: token)
  }

  // MARK: - Sampling

  private func tick() {
    let now = DispatchTime.now().uptimeNanoseconds
    let counters = Self.readCounters()

    guard let earlierAt = previousAtNanos else {
      previous = counters
      previousAtNanos = now
      return
    }

    let elapsed = Double(now &- earlierAt) / 1_000_000_000
    previousAtNanos = now
    guard elapsed > 0 else { return }

    var rates: [NetworkInterfaceRate] = []
    var totalDown = 0
    var totalUp = 0

    for (name, current) in counters {
      // An interface we have never seen contributes nothing on its first tick:
      // its counter is a total since *its* reset, not since ours.
      guard let earlier = previous[name] else { continue }

      // Lower than last time means the counter restarted under us — Wi-Fi
      // toggled, adapter re-plugged, machine rebooted. Count nothing and let the
      // new value become the baseline, rather than subtracting into an underflow
      // that would read as terabytes.
      let down = current.down >= earlier.down ? Int(current.down - earlier.down) : 0
      let up = current.up >= earlier.up ? Int(current.up - earlier.up) : 0

      totalDown += down
      totalUp += up

      rates.append(
        NetworkInterfaceRate(
          name: name,
          displayName: displayName(for: name),
          downBytesPerSecond: Double(down) / elapsed,
          upBytesPerSecond: Double(up) / elapsed,
          sinceBootDown: current.down,
          sinceBootUp: current.up,
          downBytes: down,
          upBytes: up
        )
      )
    }

    previous = counters

    let sample = NetworkSample(
      atSeconds: Date().timeIntervalSince1970,
      // Over a long gap — a sleep — this is the average across the gap rather
      // than a spike, which is the honest reading and also the one that does not
      // wreck the chart's scale.
      downBytesPerSecond: Double(totalDown) / elapsed,
      upBytesPerSecond: Double(totalUp) / elapsed,
      downBytes: totalDown,
      upBytes: totalUp,
      interfaces: rates.sorted { $0.name < $1.name }
    )

    latest = sample
    ring.append(sample)
    if ring.count > ringCapacity { ring.removeFirst(ring.count - ringCapacity) }

    NetworkStore.shared.record(sample)
    observers.values.forEach { $0(sample) }

    refreshDisplayNamesIfStale()
  }

  // MARK: - Counters

  /// Reads every interface's cumulative byte counters.
  ///
  /// `sysctl(NET_RT_IFLIST2)` rather than `getifaddrs`: the `if_data` that
  /// `getifaddrs` hands back carries **32-bit** byte counters, which wrap every
  /// 4 GB. On any real connection that is a wrong number several times a day.
  /// `if_data64`, which only the routing-table interface exposes, does not wrap.
  private static func readCounters() -> [String: (down: UInt64, up: UInt64)] {
    var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]

    var length = 0
    guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0, length > 0 else {
      return [:]
    }

    var buffer = [UInt8](repeating: 0, count: length)
    guard sysctl(&mib, u_int(mib.count), &buffer, &length, nil, 0) == 0 else {
      return [:]
    }

    var result: [String: (down: UInt64, up: UInt64)] = [:]

    buffer.withUnsafeBytes { raw in
      var offset = 0
      let headerSize = MemoryLayout<if_msghdr>.size
      let messageSize = MemoryLayout<if_msghdr2>.size

      while offset + headerSize <= length {
        // `if_msghdr` and `if_msghdr2` agree on their first three fields, so the
        // shorter one is enough to learn how long this record is and what it is.
        let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
        let messageLength = Int(header.ifm_msglen)
        guard messageLength > 0, offset + messageLength <= length else { break }
        defer { offset += messageLength }

        guard header.ifm_type == RTM_IFINFO2, messageLength >= messageSize else { continue }

        // Loaded unaligned: route messages are packed, and `if_data64`'s 64-bit
        // fields would otherwise fault on a misaligned load.
        let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)

        guard let name = interfaceName(in: raw, messageOffset: offset, messageLength: messageLength),
              isCounted(name)
        else { continue }

        result[name] = (down: message.ifm_data.ifi_ibytes, up: message.ifm_data.ifi_obytes)
      }
    }

    return result
  }

  /// The `sockaddr_dl` that follows the header carries the BSD name, `sdl_nlen`
  /// bytes into its variable-length `sdl_data`. Read straight out of the buffer
  /// rather than through the fixed 12-byte tuple the Swift importer produces for
  /// `sdl_data`, which would truncate a longer name.
  private static func interfaceName(
    in raw: UnsafeRawBufferPointer,
    messageOffset: Int,
    messageLength: Int
  ) -> String? {
    /// `sdl_len`, `sdl_family`, `sdl_index`, `sdl_type`, `sdl_nlen`, `sdl_alen`,
    /// `sdl_slen` — 8 bytes before the name begins.
    let nameOffsetInAddress = 8

    let addressOffset = messageOffset + MemoryLayout<if_msghdr2>.size
    guard addressOffset + nameOffsetInAddress <= messageOffset + messageLength else { return nil }

    let address = raw.loadUnaligned(fromByteOffset: addressOffset, as: sockaddr_dl.self)
    let nameLength = Int(address.sdl_nlen)
    guard nameLength > 0 else { return nil }

    let start = addressOffset + nameOffsetInAddress
    guard start + nameLength <= messageOffset + messageLength else { return nil }

    let bytes = (0..<nameLength).map { raw[start + $0] }
    return String(decoding: bytes, as: UTF8.self)
  }

  /// Physical links only.
  ///
  /// An allowlist rather than a block list, because the block list is the part
  /// that goes stale: macOS keeps inventing interfaces (`awdl0` for AirDrop,
  /// `llw0` for low-latency Wi-Fi, `anpi0` on Apple silicon, `bridge100` for a
  /// VM, `utun*` for every VPN and for iCloud Private Relay), and a new one
  /// nobody has heard of must default to *not counted* rather than to
  /// double-counting whatever it shadows.
  ///
  /// `en*` covers Wi-Fi, Ethernet and USB/Thunderbolt adapters; `pdp_ip*` is
  /// cellular; `ppp*` is a dial-up or PPPoE link.
  private static func isCounted(_ name: String) -> Bool {
    name.hasPrefix("en") || name.hasPrefix("pdp_ip") || name.hasPrefix("ppp")
  }

  // MARK: - Friendly names

  private func displayName(for name: String) -> String {
    displayNames[name] ?? name
  }

  private func refreshDisplayNamesIfStale() {
    guard let readAt = displayNamesReadAt else {
      refreshDisplayNames()
      return
    }
    // Only changes when hardware is plugged or unplugged, so a minute is
    // generous.
    guard Date().timeIntervalSince(readAt) > 60 else { return }
    refreshDisplayNames()
  }

  private func refreshDisplayNames() {
    displayNamesReadAt = Date()

    guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return }

    var names: [String: String] = [:]
    for interface in interfaces {
      guard let bsd = SCNetworkInterfaceGetBSDName(interface) as String? else { continue }
      if let localized = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? {
        names[bsd] = localized
      }
    }
    displayNames = names
  }

  // MARK: - Formatting

  /// The menu bar's rate string. Must stay in step with `formatRate` in
  /// `lib/features/network/data/models/network_units.dart` — the menu bar and
  /// the panel showing different numbers for the same instant is the bug this
  /// would otherwise ship with.
  static func formatRate(_ bytesPerSecond: Double, bits: Bool) -> String {
    if bits {
      return format(bytesPerSecond * 8, base: 1000, units: ["bps", "Kbps", "Mbps", "Gbps"])
    }
    return format(bytesPerSecond, base: 1024, units: ["B/s", "KB/s", "MB/s", "GB/s"])
  }

  /// Three significant digits, so the field stays the same width whether the
  /// number is 4.47 or 447 — which is what stops the status item shuffling its
  /// neighbours every second.
  private static func format(_ value: Double, base: Double, units: [String]) -> String {
    var amount = max(value, 0)
    var index = 0
    while amount >= base, index < units.count - 1 {
      amount /= base
      index += 1
    }

    let decimals: Int
    if index == 0 {
      decimals = 0
    } else if amount < 10 {
      decimals = 2
    } else if amount < 100 {
      decimals = 1
    } else {
      decimals = 0
    }

    return String(format: "%.\(decimals)f %@", amount, units[index])
  }
}

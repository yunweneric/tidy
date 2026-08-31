import Foundation
import FlutterMacOS

/// The two things every method-channel handler in this app needs.
///
/// They were `private static` on `PerformanceChannel` until `ProtectionChannel`
/// wanted both. Copying them would have been the Swift-side version of the
/// cross-feature import `docs/feature.md` §2 forbids: two copies of the rule
/// that a `FlutterResult` may only be called from the platform thread, and one
/// of them eventually drifting.

/// A nil error means it worked.
///
/// Built explicitly rather than putting an optional in the dictionary — the
/// standard codec has no notion of a missing value, only of a key that is not
/// there.
func channelOutcome(_ error: String?) -> [String: Any] {
  guard let error else { return ["ok": true] }
  return ["ok": false, "message": error]
}

/// Runs `work` off the main thread and delivers the answer back on it.
///
/// `FlutterResult` must be called from the platform thread, and everything
/// worth putting behind a channel is long enough to drop a frame if it is not.
func channelBackground<T>(
  _ work: @escaping () -> T,
  deliver: @escaping (T) -> Void
) {
  DispatchQueue.global(qos: .userInitiated).async {
    let value = work()
    DispatchQueue.main.async { deliver(value) }
  }
}

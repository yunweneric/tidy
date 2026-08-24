import Carbon.HIToolbox
import Cocoa

/// One system-wide keyboard shortcut.
///
/// Carbon's `RegisterEventHotKey` rather than an `NSEvent` global monitor: the
/// monitor route needs Accessibility permission and sees every keystroke the
/// user makes, which is a large thing to ask for one shortcut. This route asks
/// for nothing and only ever hears the combination it registered.
final class HotKey {
  static let shared = HotKey()

  private init() {}

  private var reference: EventHotKeyRef?
  private var handler: EventHandlerRef?
  private var action: (() -> Void)?

  /// ⌘⇧V. Chosen because it is what clipboard managers on this platform use;
  /// it is also Paste and Match Style inside some apps, and those apps win
  /// while they are frontmost.
  private static let keyCode = UInt32(kVK_ANSI_V)
  private static let modifiers = UInt32(cmdKey | shiftKey)

  /// Registers the shortcut. Failure is logged and survivable — a taken
  /// combination costs the shortcut, and nothing else.
  func register(action: @escaping () -> Void) {
    guard reference == nil else { return }
    self.action = action

    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: OSType(kEventHotKeyPressed)
    )

    let callback: EventHandlerUPP = { _, _, userData in
      guard let userData else { return noErr }
      Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().fire()
      return noErr
    }

    let status = InstallEventHandler(
      GetApplicationEventTarget(),
      callback,
      1,
      &eventType,
      Unmanaged.passUnretained(self).toOpaque(),
      &handler
    )
    guard status == noErr else {
      NSLog("Clipboard: could not install the hot key handler (\(status)).")
      return
    }

    let id = EventHotKeyID(signature: OSType(0x54_44_59_43), id: 1) // 'TDYC'
    let registered = RegisterEventHotKey(
      Self.keyCode,
      Self.modifiers,
      id,
      GetApplicationEventTarget(),
      0,
      &reference
    )
    if registered != noErr {
      NSLog("Clipboard: ⌘⇧V is already taken by something else (\(registered)).")
      reference = nil
    }
  }

  func unregister() {
    if let reference { UnregisterEventHotKey(reference) }
    if let handler { RemoveEventHandler(handler) }
    reference = nil
    handler = nil
  }

  private func fire() {
    DispatchQueue.main.async { [weak self] in self?.action?() }
  }
}

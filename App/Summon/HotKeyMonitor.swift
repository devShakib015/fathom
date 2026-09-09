import AppKit
import Carbon.HIToolbox

/// Registers one system-wide key combination and calls back when it is pressed.
///
/// Carbon, deliberately. The modern-looking alternative —
/// `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` — requires
/// Accessibility permission, which grants the ability to observe every
/// keystroke in every application. That is an enormous thing to ask for in
/// exchange for making a panel appear, and a user who reads the prompt
/// carefully should refuse it.
///
/// `RegisterEventHotKey` asks for no permission at all and delivers only the
/// combination it registered. It has been the right answer since long before
/// the alternative existed, and it still is.
final class HotKeyMonitor {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var onPress: (() -> Void)?

    /// Carbon dispatches to a C function with no context, so the callback has
    /// to be reachable from a static. One monitor at a time is all Fathom
    /// needs; a second registration replaces the first rather than silently
    /// competing with it.
    private static var active: HotKeyMonitor?

    private static let signature: OSType = 0x4654484B  // 'FTHK'

    init() {}

    deinit { unregisterFromAnyThread() }

    /// Returns false when macOS refuses the combination — almost always because
    /// something else already owns it. Reported rather than swallowed: a hotkey
    /// that silently does nothing is indistinguishable from a broken feature.
    @discardableResult
    func register(_ hotKey: HotKey, onPress: @escaping () -> Void) -> Bool {
        unregister()
        guard hotKey.isUsable else { return false }

        self.onPress = onPress
        Self.active = self

        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard id.signature == HotKeyMonitor.signature else { return noErr }
            DispatchQueue.main.async { HotKeyMonitor.active?.onPress?() }
            return noErr
        }, 1, &type, nil, &handler)

        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(hotKey.keyCode, hotKey.modifiers, id,
                                         GetApplicationEventTarget(), 0, &ref)
        if status != noErr {
            unregister()
            return false
        }
        return true
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        onPress = nil
        if Self.active === self { Self.active = nil }
    }

    private nonisolated func unregisterFromAnyThread() {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}

import AppKit
import Carbon.HIToolbox
import Foundation

/// A key combination that works whichever app is in front.
///
/// Registered through Carbon's `RegisterEventHotKey` rather than an
/// `NSEvent` global monitor. That is not nostalgia — a global keyboard monitor
/// requires Accessibility permission, and asking a person to hand over the
/// ability to read every keystroke in every app so that a widget can appear is
/// an offer nobody should accept. `RegisterEventHotKey` asks for nothing,
/// receives only the combination it registered, and cannot see anything else.
struct HotKey: Codable, Hashable {
    /// A virtual key code (`kVK_ANSI_F`, etc.). Layout-independent: this is the
    /// physical key, so a combination stays where the user put it when they
    /// switch to a different keyboard layout.
    var keyCode: UInt32
    /// Carbon modifier mask — `cmdKey`, `optionKey`, `controlKey`, `shiftKey`.
    var modifiers: UInt32

    static let `default` = HotKey(keyCode: UInt32(kVK_ANSI_F),
                                  modifiers: UInt32(cmdKey | optionKey))

    /// Whether this is safe to register.
    ///
    /// A bare key with no modifiers would swallow that key system-wide — the
    /// user would type it into every other app and get a widget instead. The
    /// registration would succeed, which is exactly why this is checked here.
    var isUsable: Bool {
        modifiers & UInt32(cmdKey | optionKey | controlKey) != 0
    }

    /// The combination as a person reads it: ⌘⌥F.
    var displayName: String {
        var out = ""
        if modifiers & UInt32(controlKey) != 0 { out += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { out += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { out += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { out += "⌘" }
        return out + (Self.keyNames[keyCode] ?? "?")
    }

    /// Builds one from what AppKit reports, for a "press the keys you want" field.
    static func from(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> HotKey {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        return HotKey(keyCode: UInt32(keyCode), modifiers: mods)
    }

    /// Only the keys worth binding. A combination whose key cannot be named is
    /// one the user cannot be told about, so it is not offered.
    static let keyNames: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_Space): "Space", UInt32(kVK_Return): "Return",
        UInt32(kVK_Escape): "Esc", UInt32(kVK_Tab): "Tab",
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
        UInt32(kVK_ANSI_Grave): "`", UInt32(kVK_ANSI_Slash): "/",
        UInt32(kVK_ANSI_Backslash): "\\", UInt32(kVK_ANSI_Semicolon): ";",
        UInt32(kVK_ANSI_Quote): "'", UInt32(kVK_ANSI_Comma): ",",
        UInt32(kVK_ANSI_Period): ".", UInt32(kVK_ANSI_Minus): "-",
        UInt32(kVK_ANSI_Equal): "=", UInt32(kVK_ANSI_LeftBracket): "[",
        UInt32(kVK_ANSI_RightBracket): "]",
    ]
}

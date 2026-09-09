import Testing
import Foundation
import Carbon.HIToolbox

/// The summoned panel and the key that calls it.
///
/// The interesting failure here is not a panel that does not appear — that is
/// loud. It is a combination that registers successfully and then swallows a
/// key the user needs everywhere else.
@Suite("Summon")
struct SummonTests {

    @Test("a bare key is refused")
    func bareKeyRefused() {
        // Registering this would succeed and then eat every F the user typed,
        // in every application, forever.
        let bare = HotKey(keyCode: UInt32(kVK_ANSI_F), modifiers: 0)
        #expect(!bare.isUsable)
    }

    @Test("shift alone is not enough either")
    func shiftAloneRefused() {
        // ⇧F is a capital F. Same problem, less obvious.
        let shifted = HotKey(keyCode: UInt32(kVK_ANSI_F), modifiers: UInt32(shiftKey))
        #expect(!shifted.isUsable)
    }

    @Test("command, option or control each make it usable")
    func modifiersAccepted() {
        for modifier in [cmdKey, optionKey, controlKey] {
            let key = HotKey(keyCode: UInt32(kVK_ANSI_F), modifiers: UInt32(modifier))
            #expect(key.isUsable)
        }
    }

    @Test("the name reads in the order macOS writes it")
    func displayName() {
        let key = HotKey(keyCode: UInt32(kVK_ANSI_F),
                         modifiers: UInt32(cmdKey | optionKey | controlKey | shiftKey))
        #expect(key.displayName == "⌃⌥⇧⌘F")
        #expect(HotKey.default.displayName == "⌥⌘F")
    }

    @Test("AppKit modifier flags map across")
    func fromAppKit() {
        let key = HotKey.from(keyCode: UInt16(kVK_ANSI_K), flags: [.command, .shift])
        #expect(key.keyCode == UInt32(kVK_ANSI_K))
        #expect(key.modifiers == UInt32(cmdKey | shiftKey))
        #expect(key.displayName == "⇧⌘K")
    }

    @Test("every offered key has a name")
    func namesAreComplete() {
        // A combination whose key cannot be named is one the user cannot be
        // told about, so the picker refuses it — this checks the table it
        // refuses against is not empty of anything obvious.
        #expect(HotKey.keyNames[UInt32(kVK_Space)] == "Space")
        #expect(HotKey.keyNames[UInt32(kVK_ANSI_1)] == "1")
        #expect(HotKey.keyNames.count > 60)
    }

    @Test("a summon defaults to something usable")
    func defaults() {
        let summon = Summon(documentID: UUID())
        #expect(summon.isEnabled)
        #expect(summon.hotKey.isUsable)
        #expect(summon.dismissOnBlur)
        #expect(summon.scale > 1)          // read, not glanced at
        #expect(summon.refresh >= Summon.refreshFloor)
    }

    @Test("a stored summon missing every optional field still decodes")
    func decodesOldRecords() throws {
        // The same tolerance every other stored type has: a record written by
        // an earlier build must not strand the panel.
        let json = #"{"documentID":"5B1F0F1A-0000-4000-A000-0000000000A1"}"#
        let summon = try JSONDecoder().decode(Summon.self, from: Data(json.utf8))
        #expect(summon.isEnabled)
        #expect(summon.placement == .centre)
        #expect(summon.hotKey == .default)
    }

    @Test("a summon round-trips")
    func roundTrip() throws {
        var summon = Summon(documentID: UUID())
        summon.placement = .underCursor
        summon.hotKey = HotKey.from(keyCode: UInt16(kVK_Space), flags: [.control])
        summon.scale = 3.5
        let back = try JSONDecoder().decode(
            Summon.self, from: try JSONEncoder().encode(summon))
        #expect(back == summon)
    }

    @Test("every placement follows the pointer's display")
    func placementFollowsPointer() {
        // On a multi-display Mac the pointer is the only honest evidence of
        // where the person is looking; the main screen is just where the menu
        // bar lives.
        for placement in Summon.Placement.allCases {
            #expect(placement.followsPointer)
        }
    }
}

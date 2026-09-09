import Testing
import Foundation

/// What a design does when it is clicked, and what it tells people about that.
///
/// The interesting failure is not an action that does nothing. It is a document
/// format that can be mailed to somebody and do something they did not expect —
/// so most of what is tested here is the closed vocabulary and the disclosure.
@Suite("Actions")
struct ActionTests {

    @Test("an element has no action by default")
    func defaultsToNothing() {
        let element = Element.new(.text, in: Starters.systemSmall)
        #expect(element.action == nil)
    }

    @Test("an action with no value is not set")
    func needsValue() {
        #expect(!Action(kind: .openURL, value: "").isSet)
        #expect(Action(kind: .openURL, value: "https://example.com").isSet)
        // Refresh needs nothing to act on.
        #expect(Action(kind: .refresh).isSet)
        #expect(!Action(kind: .none).isSet)
    }

    @Test("every kind that needs a value says so, and offers a placeholder")
    func placeholders() {
        for kind in Action.Kind.allCases where kind.needsValue {
            #expect(!kind.placeholder.isEmpty)
        }
        #expect(!Action.Kind.none.needsValue)
        #expect(!Action.Kind.refresh.needsValue)
    }

    @Test("the vocabulary cannot express running a command")
    func noArbitraryExecution() {
        // A Fathom document is designed to be shared. A format that could carry
        // "run this command" would be a format for mailing people malware, so
        // the closed set is the security boundary and this test is the fence
        // around it.
        let kinds = Set(Action.Kind.allCases.map(\.rawValue))
        #expect(kinds == ["none", "openURL", "openApp", "revealPath", "runShortcut", "refresh"])
    }

    @Test("every set action can describe itself in words")
    func disclosure() {
        // Anything that cannot be described cannot be disclosed, and anything
        // that cannot be disclosed must not be in the format.
        for kind in Action.Kind.allCases where kind != .none {
            let action = Action(kind: kind, value: kind.needsValue ? "something" : "")
            #expect(action.disclosure?.isEmpty == false)
        }
        #expect(Action(kind: .none).disclosure == nil)
    }

    @Test("a document lists what clicking it will do, including nested elements")
    func declaredActions() {
        var doc = Starters.systemSmall
        var group = Element.new(.group, in: doc)
        var child = Element.new(.text, in: doc)
        child.action = Action(kind: .openURL, value: "https://example.com")
        group.children = [child]
        doc.elements.append(group)

        #expect(doc.declaredActions == ["Open https://example.com"])
    }

    @Test("identical actions are listed once")
    func deduplicated() {
        var doc = Starters.systemSmall
        for index in doc.elements.indices {
            doc.elements[index].action = Action(kind: .refresh)
        }
        #expect(doc.declaredActions == ["Refresh the widget"])
    }

    @Test("a shared design that does something when clicked is not inert")
    func notInert() throws {
        var doc = Starters.systemSmall
        doc.elements[0].action = Action(kind: .runShortcut, value: "Start my day")

        let inspection = try DocumentTransfer.inspect(try DocumentTransfer.data(for: doc))
        #expect(!inspection.isInert)
        #expect(inspection.actions == ["Run the shortcut “Start my day”"])
    }

    @Test("an action survives a round trip, and an old document has none")
    func coding() throws {
        var element = Element.new(.text, in: Starters.systemSmall)
        element.action = Action(kind: .openApp, value: "Calendar")
        let back = try JSONDecoder().decode(
            Element.self, from: try JSONEncoder().encode(element))
        #expect(back.action == element.action)

        // Written before actions existed: decodes, with none.
        let old = #"""
        {"id":"5B1F0F1A-0000-4000-A000-000000000001","kind":"text",
         "frame":{"x":0,"y":0,"width":1,"height":1},
         "style":{"font":{"size":12,"weight":"regular","design":"default","monospacedDigits":false},
         "foreground":{"hex":"#FFFFFF","opacity":1}}}
        """#
        let decoded = try JSONDecoder().decode(Element.self, from: Data(old.utf8))
        #expect(decoded.action == nil)
    }
}

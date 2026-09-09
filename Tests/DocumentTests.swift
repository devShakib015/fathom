import Testing
import Foundation

/// The document format, and the promise that opening an older one still works.
@Suite("Documents")
struct DocumentTests {

    static func decode(_ json: String) throws -> WidgetDoc {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WidgetDoc.self, from: json.data(using: .utf8)!)
    }

    /// A document exactly as schema 1 wrote them: no `children`, no
    /// `visibleWhen`, no `origin`, and none of the style fields added later.
    ///
    /// This is the test that protects people's work. Every field added since
    /// has to decode with a default, or an update silently stops opening the
    /// widgets somebody built.
    static let schemaOne = """
        {
          "schemaVersion": 1,
          "id": "5B1F0F1A-0000-4000-A000-0000000000A1",
          "name": "Old widget",
          "family": "small",
          "minimumRefresh": 64,
          "background": { "kind": "glass", "color": {"hex":"#101E1A","opacity":1},
                          "gradientEnd": {"hex":"#060B0A","opacity":1}, "angle": 135 },
          "sources": [ {"id":"5B1F0F1A-0000-4000-A000-000000000001","name":"System","kind":"system"} ],
          "elements": [
            {
              "id": "11111111-0000-4000-A000-000000000001",
              "name": "Time",
              "kind": "text",
              "text": "18:42",
              "frame": {"x":0.1,"y":0.1,"width":0.8,"height":0.3},
              "style": {
                "font": {"size":42,"weight":"semibold","design":"rounded","monospacedDigits":true},
                "foreground": {"hex":"#E8F2EE","opacity":1},
                "alignment":"leading","lineLimit":1,"cornerRadius":0,"lineWidth":6,"opacity":1
              },
              "binding": {
                "sourceID":"5B1F0F1A-0000-4000-A000-000000000001",
                "keyPath":"date.now",
                "format":{"kind":"date","precision":0,"dateStyle":"time","prefix":"","suffix":""},
                "fallback":"--:--"
              }
            }
          ]
        }
        """

    @Test("a schema-1 document still opens")
    func backwardCompatible() throws {
        let doc = try Self.decode(Self.schemaOne)
        #expect(doc.name == "Old widget")
        #expect(doc.elements.count == 1)
        let element = doc.elements[0]
        #expect(element.children.isEmpty)
        #expect(element.visibleWhen == nil)
        // Fields added after schema 1 must land on their defaults, not throw.
        #expect(element.style.rotation == 0)
        #expect(element.style.arcSweep == 360)
        #expect(element.style.contentMode == .fit)
        #expect(element.binding?.expression == nil)
        #expect(doc.origin == nil)
    }

    @Test("a document survives a round trip through JSON")
    func roundTrip() throws {
        let original = Starters.weatherMedium
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(WidgetDoc.self, from: encoder.encode(original))
        #expect(restored == original)
    }

    @Test("nested children survive a round trip")
    func nestedRoundTrip() throws {
        let original = Starters.weekAheadLarge
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(WidgetDoc.self, from: encoder.encode(original))
        let repeaters = restored.elements.filter { $0.kind == .repeater }
        #expect(repeaters.count == 1)
        #expect(repeaters[0].children.count == 3)
        #expect(restored == original)
    }

    @Test("refresh can never be stored below the measured floor")
    func refreshFloor() throws {
        // The system substitutes its own minimum and honours it exactly, so a
        // smaller number in a document would only mislead whoever reads it.
        let doc = WidgetDoc(name: "Eager", minimumRefresh: 5)
        #expect(doc.minimumRefresh == WidgetDoc.refreshFloor)
        var loaded = try Self.decode(Self.schemaOne)
        loaded.minimumRefresh = 1
        #expect(loaded.sanitised.minimumRefresh == WidgetDoc.refreshFloor)
    }

    @Test("declared hosts list every endpoint a document will contact")
    func declaredHosts() {
        #expect(Starters.weatherMedium.declaredHosts == ["api.open-meteo.com"])
        #expect(Starters.systemSmall.declaredHosts.isEmpty)
    }

    @Test("frames are clamped so an element cannot be lost off-canvas")
    func frameClamping() {
        let wild = Frame(x: -9, y: 9, width: 0, height: 99).normalised
        #expect(wild.x >= -0.5 && wild.x <= 1.5)
        #expect(wild.width >= 0.01)
        #expect(Frame(x: 0.5, y: 0.25, width: 0.5, height: 0.5)
            .resolved(in: CGSize(width: 200, height: 100)) == CGRect(x: 100, y: 25, width: 100, height: 50))
    }
}

/// Reaching elements nested inside containers.
@Suite("Element tree")
struct ElementTreeTests {

    static func sample() -> [Element] {
        let child = Element(name: "Child", kind: .text,
                            frame: Frame(x: 0, y: 0, width: 1, height: 1), text: "row")
        let container = Element(name: "Repeater", kind: .repeater,
                                frame: .full, children: [child])
        let sibling = Element(name: "Sibling", kind: .divider, frame: .full)
        return [sibling, container]
    }

    @Test("find and update reach any depth")
    func findAndUpdate() {
        var elements = Self.sample()
        let childID = elements[1].children[0].id
        #expect(elements.find(childID)?.name == "Child")

        elements.update(childID) { $0.text = "changed" }
        #expect(elements.find(childID)?.text == "changed")
        // The parent must not be disturbed by editing its child.
        #expect(elements[1].children.count == 1)
    }

    @Test("deleting a container takes its contents with it")
    func deleteSubtree() {
        var elements = Self.sample()
        let containerID = elements[1].id
        let childID = elements[1].children[0].id
        elements.remove(ids: [containerID])
        // An orphaned child would live on in a document that cannot draw it.
        #expect(elements.find(childID) == nil)
        #expect(elements.count == 1)
    }

    @Test("duplicating a container gives fresh ids all the way down")
    func reidentify() {
        let elements = Self.sample()
        let copy = elements.reidentified()
        #expect(copy[1].id != elements[1].id)
        #expect(copy[1].children[0].id != elements[1].children[0].id)
        // Two views of one element would edit together, which is not a copy.
        #expect(Set(copy.allIDs()).isDisjoint(with: elements.allIDs()))
    }

    @Test("parent lookup and insertion target")
    func parents() {
        var elements = Self.sample()
        let containerID = elements[1].id
        let childID = elements[1].children[0].id
        #expect(elements.parent(of: childID) == containerID)
        #expect(elements.parent(of: containerID) == nil)

        let added = Element(kind: .symbol, frame: .full)
        elements.insert(added, into: containerID)
        #expect(elements.find(added.id) != nil)
        #expect(elements[1].children.count == 2)
    }

    @Test("insertion targets the container itself, or the container around it")
    func insertionTarget() {
        var doc = WidgetDoc(name: "t")
        doc.elements = Self.sample()
        let containerID = doc.elements[1].id
        let childID = doc.elements[1].children[0].id
        // Selecting a repeater and adding should add *into* it.
        #expect(doc.containerForInsertion(near: containerID) == containerID)
        // Selecting its child should add beside the child, in the same parent.
        #expect(doc.containerForInsertion(near: childID) == containerID)
        #expect(doc.containerForInsertion(near: doc.elements[0].id) == nil)
    }

    @Test("flattening is depth-first with the nesting depth")
    func flatten() {
        let flat = Self.sample().flattened()
        #expect(flat.map(\.depth) == [0, 0, 1])
    }
}

/// Which widget kind a slot maps to.
@Suite("Slots")
struct SlotTests {

    @Test("slot one keeps the original key and widget kind")
    func slotOneIsUnchanged() {
        // Placements are keyed on `kind`; changing slot one's would orphan
        // every widget anybody has already put on their desktop.
        #expect(WidgetSlot(family: .small, index: 1).key == "small")
        #expect(WidgetSlot(family: .small, index: 1).widgetKind == "FathomSmall")
        #expect(WidgetSlot(family: .extraLarge, index: 1).widgetKind == "FathomExtraLarge")
    }

    @Test("later slots are suffixed, never colliding with slot one")
    func laterSlots() {
        #expect(WidgetSlot(family: .medium, index: 3).key == "medium.3")
        #expect(WidgetSlot(family: .medium, index: 3).widgetKind == "FathomMedium3")
        let kinds = WidgetSlot.everything.map(\.widgetKind)
        #expect(Set(kinds).count == kinds.count)
    }

    @Test("every declared slot has a widget to render it")
    func countsMatchTheBundle() {
        // Ten concrete Widget structs are written out in FathomWidget.swift; if
        // the counts here grow without one being added, the extra slot is a
        // dead entry in the app that no gallery item can fill.
        #expect(WidgetSlot.everything.count == 10)
        #expect(WidgetSlot.all(for: .small).count == 4)
        #expect(WidgetSlot.all(for: .extraLarge).count == 1)
    }
}

/// Rates computed from counters between reloads.
@Suite("Counter samples")
struct CounterTests {

    @Test("a rate needs a previous reading and is per second")
    func rate() {
        let then = Date(timeIntervalSince1970: 1000)
        let now = Date(timeIntervalSince1970: 1064)
        let previous = CounterSamples.Sample(at: then, values: ["net.in": 1000])
        let rate = CounterSamples.rate("net.in", now: 1000 + 6400, at: now, previous: previous)
        #expect(rate == 100)
    }

    @Test("no previous reading means no answer, not zero")
    func firstReading() {
        // Zero would render as a confident "0 B/s" when the truth is "not yet
        // known", and the element should show its fallback instead.
        #expect(CounterSamples.rate("net.in", now: 5, at: Date(), previous: nil) == nil)
    }

    @Test("a counter going backwards is a reboot, not a negative rate")
    func counterReset() {
        let previous = CounterSamples.Sample(at: Date(timeIntervalSince1970: 1000),
                                             values: ["net.in": 9999])
        let rate = CounterSamples.rate("net.in", now: 5,
                                       at: Date(timeIntervalSince1970: 1064), previous: previous)
        #expect(rate == nil)
    }

    @Test("a binding missing a format field still decodes")
    func tolerantFormat() throws {
        // Synthesised Codable refuses the whole document over one absent field,
        // and the failure is invisible: slot one falls back to any document of
        // the right size, so the desktop shows a different design rather than
        // an error. Measured on a real widget before this was fixed.
        let json = """
        {"sourceID":"5B1F0F1A-0000-4000-A000-000000000001","keyPath":"date.now",
         "format":{"kind":"text","precision":0,"prefix":"","suffix":""},"fallback":"—"}
        """
        let binding = try JSONDecoder().decode(DataBinding.self, from: Data(json.utf8))
        #expect(binding.keyPath == "date.now")
        #expect(binding.format.kind == .text)
        #expect(binding.format.dateStyle == .time)      // the missing one
    }

    @Test("a binding with nothing but a source id decodes")
    func minimalBinding() throws {
        let json = #"{"sourceID":"5B1F0F1A-0000-4000-A000-000000000001"}"#
        let binding = try JSONDecoder().decode(DataBinding.self, from: Data(json.utf8))
        #expect(binding.keyPath.isEmpty)
        #expect(binding.fallback == "—")
        #expect(binding.expression == nil)
    }

    @Test("an empty format object decodes to the text default")
    func emptyFormat() throws {
        let format = try JSONDecoder().decode(Format.self, from: Data("{}".utf8))
        #expect(format.kind == .text)
        #expect(format.precision == 0)
        #expect(format.prefix.isEmpty)
    }

    @Test("a format still round-trips with every field set")
    func formatRoundTrip() throws {
        let format = Format(kind: .bytes, precision: 2, dateStyle: .shortWeekday,
                            prefix: "~", suffix: " free")
        let back = try JSONDecoder().decode(Format.self, from: try JSONEncoder().encode(format))
        #expect(back == format)
    }
}

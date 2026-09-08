import Testing
import Foundation

/// What a shared document discloses about itself.
///
/// Being wrong here means telling somebody a widget is inert when it will call
/// an endpoint every minute, which is the one failure in this project that
/// would matter to a person who never opens the app.
@Suite("Sharing")
struct SharingTests {

    @Test("a document with no sources discloses nothing to worry about")
    func inertDocument() throws {
        let data = try DocumentTransfer.data(for: Starters.systemSmall)
        let inspection = try DocumentTransfer.inspect(data)
        #expect(inspection.hosts.isEmpty)
        #expect(inspection.permissions.isEmpty)
        #expect(inspection.isInert)
        #expect(inspection.elementCount == 8)
    }

    @Test("every endpoint a document will contact is listed")
    func hostsAreDisclosed() throws {
        let data = try DocumentTransfer.data(for: Starters.weatherMedium)
        let inspection = try DocumentTransfer.inspect(data)
        #expect(inspection.hosts == ["api.open-meteo.com"])
        #expect(!inspection.isInert)
    }

    @Test("a source that wants personal data is called out separately")
    func permissionsAreDisclosed() throws {
        var doc = WidgetDoc(name: "Agenda", sources: [DataSource(name: "Calendar", kind: .calendar)])
        doc.elements = [Element(kind: .text, frame: .full, text: "x")]
        let inspection = try DocumentTransfer.inspect(try DocumentTransfer.data(for: doc))
        #expect(inspection.permissions == [.calendar])
        #expect(!inspection.isInert)
    }

    @Test("a document from a newer build is flagged rather than trusted")
    func newerSchema() throws {
        // Decoding succeeds — every field is optional — so nothing else would
        // notice. The recipient should still be told the drawing may be wrong.
        let json = """
            {"schemaVersion": 99, "id":"11111111-0000-4000-A000-000000000001",
             "name":"From the future","family":"small","minimumRefresh":64,
             "background":{"kind":"glass","color":{"hex":"#101E1A","opacity":1},
                           "gradientEnd":{"hex":"#060B0A","opacity":1},"angle":135},
             "sources":[],"elements":[]}
            """.data(using: .utf8)!
        let inspection = try DocumentTransfer.inspect(json)
        #expect(inspection.isFromNewerVersion)
        #expect(!inspection.isInert)
    }

    @Test("importing twice gives two widgets rather than replacing one")
    func freshIdentity() throws {
        let data = try DocumentTransfer.data(for: Starters.systemSmall)
        let first = try DocumentTransfer.inspect(data)
        let second = try DocumentTransfer.inspect(data)
        #expect(first.doc.id != second.doc.id)
        // And neither collides with the document it was exported from.
        #expect(first.doc.id != Starters.systemSmall.id)
    }

    @Test("catalog provenance does not travel")
    func originIsStripped() throws {
        var doc = Starters.systemSmall
        doc.origin = "clock-stack.mint.small"
        let inspection = try DocumentTransfer.inspect(try DocumentTransfer.data(for: doc))
        // An entry id means something on the Mac that made it and nothing on
        // the one receiving it.
        #expect(inspection.doc.origin == nil)
    }

    @Test("nested elements survive the trip and are counted")
    func nestedSurvive() throws {
        let inspection = try DocumentTransfer.inspect(
            try DocumentTransfer.data(for: Starters.weekAheadLarge))
        let repeaters = inspection.doc.elements.filter { $0.kind == .repeater }
        #expect(repeaters.first?.children.count == 3)
        // Children count toward the total, since they are elements somebody
        // will have to look at.
        #expect(inspection.elementCount == Starters.weekAheadLarge.elements.allIDs().count)
    }

    @Test("a filename is safe to write even from an awkward name")
    func filenames() {
        var doc = WidgetDoc(name: "Weather / Dubai: \"now\"")
        #expect(!DocumentTransfer.suggestedFilename(for: doc).contains("/"))
        doc.name = "   "
        #expect(DocumentTransfer.suggestedFilename(for: doc) == "Widget.fathom")
    }

    @Test("a font this Mac lacks is reported, and still renders")
    func missingFonts() throws {
        var doc = Starters.systemSmall
        doc.elements[0].style.font.family = "A Font Nobody Has 12345"
        let inspection = try DocumentTransfer.inspect(try DocumentTransfer.data(for: doc))
        #expect(inspection.missingFonts == ["A Font Nobody Has 12345"])
        #expect(!inspection.isInert)
        // Falling back matters more than reporting: a widget that refuses to
        // draw over a typeface is worse than one drawn in San Francisco.
        #expect(!doc.elements[0].style.font.isAvailable)
    }

    @Test("garbage is refused rather than half-imported")
    func rejectsGarbage() {
        #expect(throws: (any Error).self) {
            try DocumentTransfer.inspect("{\"not\":\"a widget\"}".data(using: .utf8)!)
        }
    }
}

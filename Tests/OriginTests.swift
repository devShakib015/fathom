import Testing
import Foundation

/// Provenance, and the way back from an edit.
///
/// `origin` was written from the day the catalogue existed and read by nothing,
/// with a comment promising it "lets the editor offer revert to the original".
/// Six hundred and eighty designs meant to be duplicated and edited, and no way
/// back from the first edit made to one.
@Suite("Origin")
struct OriginTests {

    private var entry: CatalogEntry { Catalog.entries[0] }

    @Test("a catalogue document records where it came from")
    func recordsOrigin() {
        let doc = entry.document()
        #expect(doc.origin == entry.id)
        #expect(Catalog.entry(entry.id)?.id == entry.id)
    }

    @Test("an untouched catalogue document reports no changes")
    func unchanged() {
        // If this were ever wrong, Revert would offer itself on a design nobody
        // had touched — and reverting would be a no-op that still cost an undo
        // step. Seen on screen: a design added from the catalogue offered
        // Revert immediately, because the stored copy had been through
        // `sanitised` and the comparison had not.
        #expect(!entry.document().differsFromOriginal)
        #expect(!entry.document().sanitised.differsFromOriginal)
    }

    @Test("an edited document reports changes and can be put back")
    func revert() throws {
        var doc = entry.document()
        let original = doc
        doc.elements.removeAll()
        doc.background.kind = doc.background.kind == .color ? .gradient : .color

        #expect(doc.differsFromOriginal)
        let restored = try #require(doc.shippedOriginal)
        #expect(restored.elements.count == original.elements.count)
        #expect(restored.background.kind == original.background.kind)
    }

    @Test("reverting keeps the document's own identity and name")
    func keepsIdentity() throws {
        // The id must survive or every placement referring to this document
        // breaks; the name is the user's choice, and reverting a design is not
        // undoing a rename.
        var doc = entry.document()
        doc.name = "My clock"
        doc.elements.removeAll()

        let restored = try #require(doc.shippedOriginal)
        #expect(restored.id == doc.id)
        #expect(restored.name == "My clock")
    }

    @Test("a document from nowhere has nothing to revert to")
    func noOrigin() {
        let doc = Starters.systemSmall
        #expect(doc.origin == nil)
        #expect(doc.shippedOriginal == nil)
        #expect(!doc.differsFromOriginal)
    }

    @Test("an origin naming an entry that no longer exists is harmless")
    func staleOrigin() {
        // A design shared from a later version, or one whose template was
        // renamed. Offering a Revert that cannot be performed is worse than
        // offering none.
        var doc = entry.document()
        doc.origin = "no-such-entry"
        #expect(doc.shippedOriginal == nil)
        #expect(!doc.differsFromOriginal)
    }
}

import Testing
import Foundation

/// Putting a different palette on a design that already exists.
///
/// The failure to guard against is not an ugly widget. It is a restyle that
/// throws away work — a rebuild wearing new colours looks correct and has
/// quietly discarded every edit the user made.
@Suite("Restyle")
struct RestyleTests {

    private var mint: Theme { Theme.named("mint-deep") }
    private var mono: Theme { Theme.named("mono") }

    /// A catalogue design, which knows which palette it is wearing.
    private func catalogueDoc() -> WidgetDoc? {
        Catalog.entries.first { Catalog.entry($0.id)?.themeID == "mint-deep" }?.document()
    }

    @Test("the palette a catalogue design wears is readable from its origin")
    func knowsCurrentTheme() throws {
        let doc = try #require(catalogueDoc())
        #expect(Restyle.currentTheme(of: doc)?.id == "mint-deep")
    }

    @Test("a hand-made design wears no known palette")
    func noTheme() {
        #expect(Restyle.currentTheme(of: Starters.systemSmall) == nil)
    }

    @Test("restyling keeps every element, its text and its bindings")
    func preservesWork() throws {
        // The whole point. A rebuild would produce the same colours and lose
        // the user's edits, which is the failure this is built to avoid.
        var doc = try #require(catalogueDoc())
        doc.elements[0].text = "my own words"
        let before = doc.elements.count

        let after = Restyle.apply(mono, to: doc, from: Restyle.currentTheme(of: doc))
        #expect(after.elements.count == before)
        #expect(after.elements[0].text == "my own words")
        #expect(after.elements[0].binding?.keyPath == doc.elements[0].binding?.keyPath)
        #expect(after.elements[0].frame == doc.elements[0].frame)
    }

    @Test("known colours are exchanged for their counterparts")
    func exactMapping() throws {
        var doc = try #require(catalogueDoc())
        doc.elements[0].style.foreground = ColorSpec(mint.text)

        let after = Restyle.apply(mono, to: doc, from: mint)
        #expect(after.elements[0].style.foreground.hex == mono.text)
    }

    @Test("a colour the user chose is left alone")
    func preservesCustomColours() throws {
        // A design built from one theme is made entirely of that theme's
        // colours, so anything else in it was chosen deliberately.
        var doc = try #require(catalogueDoc())
        doc.elements[0].style.foreground = ColorSpec("#FF00FF")

        let after = Restyle.apply(mono, to: doc, from: mint)
        #expect(after.elements[0].style.foreground.hex == "#FF00FF")
    }

    @Test("opacity survives the exchange")
    func keepsOpacity() throws {
        var doc = try #require(catalogueDoc())
        doc.elements[0].style.foreground = ColorSpec(mint.dim, opacity: 0.4)

        let after = Restyle.apply(mono, to: doc, from: mint)
        #expect(after.elements[0].style.foreground.hex == mono.dim)
        #expect(after.elements[0].style.foreground.opacity == 0.4)
    }

    @Test("the backdrop becomes the new palette's own")
    func backdropReplaced() throws {
        let doc = try #require(catalogueDoc())
        let after = Restyle.apply(mono, to: doc, from: mint)
        #expect(after.background.kind == mono.background.kind)
    }

    @Test("with no old palette, colours are classified by what they look like")
    func roleFallback() {
        // A hand-made design has no map to work from, so near-white becomes
        // body text and a saturated colour becomes an accent.
        var doc = Starters.systemSmall
        doc.elements[0].style.foreground = ColorSpec("#FFFFFF")

        let after = Restyle.apply(mono, to: doc, from: nil)
        #expect(after.elements[0].style.foreground.hex == mono.text)
    }

    @Test("nested elements are restyled too")
    func recursive() throws {
        var doc = try #require(catalogueDoc())
        var group = Element.new(.group, in: doc)
        var child = Element.new(.text, in: doc)
        child.style.foreground = ColorSpec(mint.accent)
        group.children = [child]
        doc.elements.append(group)

        let after = Restyle.apply(mono, to: doc, from: mint)
        #expect(after.elements.last?.children.first?.style.foreground.hex == mono.accent)
    }

    @Test("every palette can be restyled into every other")
    func everyPairing() {
        // This is the test that was missing. The first real restyle crashed the
        // app: two palettes use one hex for two roles — Mono is white for both
        // accent and text — and a Swift dictionary literal with a repeated key
        // traps at runtime rather than failing to compile. Testing one pairing
        // proved nothing about the other three hundred and ninety-nine.
        var doc = Starters.systemSmall
        doc.origin = nil

        for from in Theme.all {
            for to in Theme.all {
                var themed = doc
                themed.elements[0].style.foreground = ColorSpec(from.accent)
                let result = Restyle.apply(to, to: themed, from: from)
                #expect(result.elements.count == themed.elements.count)
            }
        }
    }

    @Test("a palette that uses one colour twice maps it to the calmer role")
    func duplicateRoles() {
        // Mono's accent and text are both white. Mapping it to the new accent
        // would make a whole design shout in one colour; text keeps it readable.
        var doc = Starters.systemSmall
        doc.elements[0].style.foreground = ColorSpec(mono.text)

        let after = Restyle.apply(mint, to: doc, from: mono)
        #expect(after.elements[0].style.foreground.hex == mint.text)
    }

    @Test("a restyled design reports the palette it is wearing, not the one it came with")
    func reportsAppliedPalette() throws {
        // Seen on screen before this existed: a design restyled into sand and
        // cream, with the picker still insisting it was Mono.
        let doc = try #require(catalogueDoc())
        #expect(Restyle.currentTheme(of: doc)?.id == "mint-deep")

        let after = Restyle.apply(mono, to: doc, from: mint)
        #expect(after.paletteID == "mono")
        #expect(Restyle.currentTheme(of: after)?.id == "mono")
    }

    @Test("restyling does not disturb where the design came from")
    func provenanceSurvives() throws {
        // origin and paletteID answer different questions. Overwriting origin
        // on a restyle would make Revert restore the new colours, which is not
        // reverting.
        let doc = try #require(catalogueDoc())
        let after = Restyle.apply(mono, to: doc, from: mint)
        #expect(after.origin == doc.origin)
        #expect(after.differsFromOriginal)
        #expect(after.shippedOriginal?.paletteID == nil)
    }
}

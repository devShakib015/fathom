import Testing
import AppKit

/// The icons the picker offers.
///
/// A name that does not resolve renders as a question mark on somebody's
/// desktop and nothing anywhere says why — so the catalogue is checked against
/// this machine's own symbol table rather than trusted.
@Suite("Symbol catalogue")
struct SymbolCatalogueTests {

    @Test("every offered icon actually exists")
    func allResolve() {
        let missing = SymbolCatalogue.all.filter {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil
        }
        #expect(missing.isEmpty, "these SF Symbols do not resolve: \(missing.joined(separator: ", "))")
    }

    @Test("the catalogue is big enough to be worth opening, and grouped")
    func shape() {
        #expect(SymbolCatalogue.all.count > 120)
        #expect(SymbolCatalogue.groups.count >= 8)
        #expect(SymbolCatalogue.groups.allSatisfy { !$0.symbols.isEmpty })
    }

    @Test("no icon is listed twice")
    func noDuplicates() {
        #expect(Set(SymbolCatalogue.all).count == SymbolCatalogue.all.count)
    }

    @Test("search finds icons by group name, not just by symbol name")
    func searchByGroup() {
        // Nothing is called "weather", so a plain name match would return
        // nothing for the most obvious thing anyone would type.
        let byGroup = SymbolCatalogue.search("weather")
        #expect(byGroup.contains { $0.name == "Weather" })

        let byName = SymbolCatalogue.search("battery")
        #expect(byName.flatMap(\.symbols).contains { $0.contains("battery") })

        #expect(SymbolCatalogue.search("").count == SymbolCatalogue.groups.count)
        #expect(SymbolCatalogue.search("zzzzz").isEmpty)
    }
}

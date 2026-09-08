import AppKit

/// The fonts installed on this Mac.
///
/// Looked up once and cached: `availableFontFamilies` walks the font system,
/// and a document with twenty text elements would otherwise ask twenty times
/// per render, sixty-four seconds apart, forever.
enum FontCatalogue {
    /// Every family, sorted, with the system font represented by nil rather
    /// than by a name — "System" is not a font family and asking for it by
    /// name gets you something else.
    static let families: [String] = NSFontManager.shared.availableFontFamilies.sorted()

    private static let lookup: Set<String> = Set(families)

    static func has(_ family: String) -> Bool { lookup.contains(family) }

    /// Families a document names that this Mac does not have. The answer the
    /// import sheet needs, and the reason a shared design can look wrong
    /// without anybody being told why.
    static func missing(in doc: WidgetDoc) -> [String] {
        func walk(_ elements: [Element]) -> [String] {
            elements.flatMap { element -> [String] in
                var found: [String] = []
                if let family = element.style.font.family, !family.isEmpty, !has(family) {
                    found.append(family)
                }
                return found + walk(element.children)
            }
        }
        return Array(Set(walk(doc.elements))).sorted()
    }
}

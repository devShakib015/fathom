import Foundation

/// Puts a different palette onto a design that already exists.
///
/// Not a rebuild. Rebuilding from the template with another theme would give a
/// correct-looking result and throw away everything the user had done to it —
/// moved elements, edited text, added bindings. Restyling has to change the
/// colours and nothing else, which means the problem is: given a colour in this
/// document, what is the corresponding colour in the new palette?
///
/// There are two ways to know, and the good one is only sometimes available.
enum Restyle {

    /// Applies `theme` to `doc`, using `from` as the palette it is currently
    /// wearing when that is known.
    static func apply(_ theme: Theme, to doc: WidgetDoc, from current: Theme?) -> WidgetDoc {
        var copy = doc
        let map = colourMap(from: current, to: theme)
        copy.background = background(for: theme, replacing: doc.background, using: map)
        copy.elements = recolour(doc.elements, with: map, theme: theme)
        copy.paletteID = theme.id
        return copy
    }

    /// The palette a catalogue design is wearing, read back out of its origin.
    static func currentTheme(of doc: WidgetDoc) -> Theme? {
        // What it is wearing now takes precedence over what it came with.
        if let paletteID = doc.paletteID { return Theme.named(paletteID) }
        guard let origin = doc.origin, let entry = Catalog.entry(origin) else { return nil }
        return Theme.named(entry.themeID)
    }

    // MARK: - Knowing which colour is which

    /// An exact old-hex to new-hex substitution, when the old palette is known.
    ///
    /// This is the good way. A catalogue design is built entirely out of one
    /// theme's colours, so every colour in it has an exact counterpart and
    /// anything *not* in the map is a colour the user chose deliberately — and
    /// is therefore left alone, which is the behaviour you want.
    private static func colourMap(from current: Theme?, to theme: Theme) -> [String: String] {
        guard let current else { return [:] }

        // Built by insertion, never as a dictionary literal.
        //
        // A palette may use one hex for two roles — Mono is white for both its
        // accent and its text, Paper is near-black for two — and a Swift
        // dictionary literal with a repeated key is a runtime trap, not a
        // compile error. It crashed the app on the first real restyle, of a
        // Mono design, which is the palette most likely to be picked for
        // "black and white".
        //
        // Where a colour serves two roles the more neutral one wins. Mapping
        // Mono's white to the new accent would make an entire design shout in
        // one colour; mapping it to the new text keeps it readable, which is
        // the failure worth choosing.
        var map: [String: String] = [:]
        func add(_ from: String?, _ to: String?) {
            guard let from, let to else { return }
            let key = from.uppercased()
            if map[key] == nil { map[key] = to }
        }
        add(current.text, theme.text)
        add(current.accent, theme.accent)
        add(current.accentAlt, theme.accentAlt)
        add(current.dim, theme.dim)
        add(current.surface, theme.surface ?? theme.accent)
        add(current.surfaceEnd, theme.surfaceEnd ?? theme.surface ?? theme.accent)
        return map
    }

    /// When the old palette is unknown, classify each colour by what it looks
    /// like.
    ///
    /// A guess, and it says so by being a separate path. Near-white is body
    /// text, saturated is an accent, and everything between is the dim tone —
    /// which is how these palettes are built, so it holds for hand-made designs
    /// that follow the same instinct and degrades to something plausible when
    /// they do not.
    private static func byRole(_ spec: ColorSpec, theme: Theme) -> String {
        let (luminance, saturation) = describe(spec.hex)
        if saturation > 0.22 { return luminance > 0.55 ? theme.accent : theme.accentAlt }
        if luminance > 0.72 { return theme.text }
        return theme.dim
    }

    private static func describe(_ hex: String) -> (luminance: Double, saturation: Double) {
        let trimmed = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard trimmed.count >= 6, let value = Int(trimmed.prefix(6), radix: 16) else {
            return (0.5, 0)
        }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        let high = max(r, g, b), low = min(r, g, b)
        // Rec. 709 luma, and HSL saturation's numerator over its range.
        return (0.2126 * r + 0.7152 * g + 0.0722 * b, high - low)
    }

    // MARK: - Applying it

    private static func swap(_ spec: ColorSpec?, map: [String: String], theme: Theme) -> ColorSpec? {
        guard let spec else { return nil }
        if let exact = map[spec.hex.uppercased()] {
            return ColorSpec(exact, opacity: spec.opacity)
        }
        // No map at all means no old palette was known, so guess by role.
        // A map that exists but does not contain this colour means the user
        // chose it, and it stays.
        guard map.isEmpty else { return spec }
        return ColorSpec(byRole(spec, theme: theme), opacity: spec.opacity)
    }

    private static func background(for theme: Theme, replacing old: Background,
                                   using map: [String: String]) -> Background {
        // The backdrop is the one part that is replaced outright rather than
        // mapped: a palette's ground is the palette, and a glass theme has to be
        // able to turn a painted design back into glass.
        var background = theme.background
        background.angle = old.angle
        return background
    }

    private static func recolour(_ elements: [Element], with map: [String: String],
                                 theme: Theme) -> [Element] {
        elements.map { element in
            var element = element
            var style = element.style
            style.foreground = swap(style.foreground, map: map, theme: theme) ?? style.foreground
            style.fill = swap(style.fill, map: map, theme: theme)
            style.gradientEnd = swap(style.gradientEnd, map: map, theme: theme)
            style.strokeColor = swap(style.strokeColor, map: map, theme: theme)
            // Shadows are black with an opacity in every palette; recolouring
            // them turns a soft drop shadow into a coloured halo.
            element.style = style
            element.children = recolour(element.children, with: map, theme: theme)
            return element
        }
    }
}

import Foundation
import WidgetKit

/// A widget, as data.
///
/// The extension cannot be recompiled per user — WidgetKit extensions are
/// compiled SwiftUI and macOS will not load code at runtime — so the user's
/// widget has to *be* a document that one universal extension interprets.
/// Everything else about Fathom follows from that.
struct WidgetDoc: Codable, Identifiable, Hashable {
    /// Bumped whenever a change cannot be read by an older build. Present
    /// from the first version so that the day a document is handed to
    /// somebody else, there is already something to check.
    var schemaVersion: Int
    var id: UUID
    var name: String
    var family: Family
    var background: Background
    var elements: [Element]
    var sources: [DataSource]
    /// Never below the measured system floor; see `refreshFloor`.
    var minimumRefresh: TimeInterval
    /// Which catalog entry this document was duplicated from, if any.
    ///
    /// Purely provenance — it lets the editor offer "revert to the original"
    /// and lets the gallery show what you already have. It changes nothing
    /// about rendering, which is why it does not move the schema version: an
    /// older build ignoring it renders exactly the same widget.
    var origin: String?
    /// The palette this design is *wearing*, when it is not the one it came
    /// with.
    ///
    /// Separate from `origin` because they answer different questions and
    /// conflating them breaks both. `origin` is where the design came from and
    /// is what Revert goes back to; overwriting it on a restyle would make
    /// Revert restore the new colours, which is not reverting. Without this
    /// field the palette picker kept naming the original theme after a
    /// restyle — seen on screen, a design in sand and cream insisting it was
    /// Mono.
    var paletteID: String?

    /// 2 added binding expressions; 3 added nested children, conditional
    /// visibility, four element kinds and the second wave of style properties;
    /// 4 added named font families.
    ///
    /// Every addition decodes with a default, so an older document still
    /// opens. The number exists for the other direction: a document using a
    /// newer feature, opened by an older build, would silently render
    /// something subtly wrong rather than fail — which is exactly the kind of
    /// quiet wrongness that matters once documents can be handed around.
    static let currentSchemaVersion = 4

    /// macOS substitutes its own minimum reload interval and then honours it
    /// exactly: measured at 64.15 s ± 0.15 over an hour, with no widening.
    /// Asking for less is not refused, it is silently rounded up, so storing
    /// anything smaller would only mislead whoever reads the document later.
    static let refreshFloor: TimeInterval = 64

    init(id: UUID = UUID(),
         name: String,
         family: Family = .small,
         background: Background = .glass,
         elements: [Element] = [],
         sources: [DataSource] = [],
         minimumRefresh: TimeInterval = WidgetDoc.refreshFloor,
         origin: String? = nil,
         paletteID: String? = nil) {
        self.schemaVersion = WidgetDoc.currentSchemaVersion
        self.id = id
        self.name = name
        self.family = family
        self.background = background
        self.elements = elements
        self.sources = sources
        self.minimumRefresh = max(minimumRefresh, WidgetDoc.refreshFloor)
        self.origin = origin
        self.paletteID = paletteID
    }

    /// Every host this document will contact when it refreshes. Sorted and
    /// de-duplicated so it reads as a disclosure rather than a log.
    var declaredHosts: [String] {
        Array(Set(sources.compactMap(\.host))).sorted()
    }

    func source(_ id: UUID) -> DataSource? {
        sources.first { $0.id == id }
    }

    /// A document read from disk may have been written by a newer build, or
    /// hand-edited. Clamp the things that would otherwise render wrong rather
    /// than refusing to open it.
    /// The catalogue design this one started as, if any.
    var shippedOriginal: WidgetDoc? {
        guard let origin, let entry = Catalog.entry(origin) else { return nil }
        // Sanitised, because everything in the library has been through
        // `sanitised` on the way in and out of the store. Comparing a stored
        // document against a raw template build finds differences that the
        // store itself introduced — frames normalised, refresh clamped — and
        // reports a design as edited the moment it is added.
        var original = entry.document().sanitised
        // Identity and title are the user's, not the catalogue's. Reverting is
        // about the design going back to how it shipped; it is not about
        // undoing a rename, and it must not break a placement that refers to
        // this document by id.
        original.id = id
        original.name = name
        return original
    }

    /// Whether anything has been changed since it came out of the catalogue.
    ///
    /// Compared by encoding rather than by `==`, so a field added to the format
    /// later cannot quietly make every document look modified — and with
    /// element identifiers normalised away first, because a template mints
    /// fresh ones on every build. Without that, an untouched design compares
    /// unequal to itself and Revert offers itself to everybody, always.
    var differsFromOriginal: Bool {
        guard let original = shippedOriginal else { return false }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let a = try? encoder.encode(comparable),
              let b = try? encoder.encode(original.comparable) else { return false }
        return a != b
    }

    /// The same document with element identities replaced by their position in
    /// the tree. Only ever used for comparison.
    private var comparable: WidgetDoc {
        var copy = self
        var counter = 0
        func renumber(_ elements: [Element]) -> [Element] {
            elements.map { element in
                var element = element
                counter += 1
                element.id = UUID(uuidString:
                    String(format: "00000000-0000-0000-0000-%012d", counter)) ?? element.id
                element.children = renumber(element.children)
                return element
            }
        }
        copy.elements = renumber(elements)
        return copy
    }

    /// Every distinct thing this design does when clicked, in plain words.
    var declaredActions: [String] {
        var found: [String] = []
        func walk(_ elements: [Element]) {
            for element in elements {
                if let line = element.action?.disclosure, !found.contains(line) {
                    found.append(line)
                }
                walk(element.children)
            }
        }
        walk(elements)
        return found
    }

    var sanitised: WidgetDoc {
        var copy = self
        copy.minimumRefresh = max(minimumRefresh, WidgetDoc.refreshFloor)
        copy.elements = elements.map {
            var e = $0
            e.frame = $0.frame.normalised
            // A caption the shipped starters carried that the URL migration
            // alone would leave contradicting its own endpoint.
            if let replacement = DataSource.legacyCaptions[e.text] { e.text = replacement }
            return e
        }
        copy.sources = sources.map(\.migrated)
        return copy
    }

    enum Family: String, Codable, CaseIterable {
        case small, medium, large, extraLarge
        /// A strip in the menu bar. Not a WidgetKit family — Fathom draws this
        /// one itself — but a family all the same, because the aspect ratio is
        /// fixed and nothing composed for a square reads in a 22-point band.
        /// Overlays could be a host rather than a family precisely because they
        /// impose no shape; this does.
        case menuBar
        /// A strip hanging under the notch. Compact by nature: it is glanced
        /// at, not read, and it shares the menu bar's problem of a shape that
        /// nothing square survives.
        case island

        /// nil for surfaces WidgetKit knows nothing about.
        var widgetFamily: WidgetFamily? {
            switch self {
            case .small: .systemSmall
            case .medium: .systemMedium
            case .large: .systemLarge
            case .extraLarge: .systemExtraLarge
            case .menuBar, .island: nil
            }
        }

        /// Whether a placed WidgetKit widget can show this. The menu bar and
        /// anything after it are Fathom's own surfaces.
        var isWidgetKitFamily: Bool { widgetFamily != nil }

        init?(_ family: WidgetFamily) {
            switch family {
            case .systemSmall: self = .small
            case .systemMedium: self = .medium
            case .systemLarge: self = .large
            case .systemExtraLarge: self = .extraLarge
            default: return nil
            }
        }

        var displayName: String {
            switch self {
            case .small: "Small"
            case .medium: "Medium"
            case .large: "Large"
            case .extraLarge: "Extra large"
            case .menuBar: "Menu bar"
            case .island: "Island"
            }
        }

        /// The point size macOS 26 actually uses, read out of WidgetKit's own
        /// timeline cache filenames rather than guessed:
        /// `~/Library/Containers/<ext>/Data/SystemData/com.apple.chrono/timelines/`
        /// names each file `systemSmall----164.00w-164.00h-27.88r-…`.
        ///
        /// The renderer never trusts this for layout — it uses the real
        /// geometry it is handed — but font sizes are authored against it, and
        /// the editor canvas needs the right aspect ratio. Note that `large`
        /// is square on macOS, not portrait as it is on iOS.
        var referenceSize: CGSize {
            switch self {
            case .small: CGSize(width: 164, height: 164)
            case .medium: CGSize(width: 344, height: 164)
            case .large: CGSize(width: 344, height: 344)
            case .extraLarge: CGSize(width: 704, height: 344)
            // 22 is `NSStatusBar.system.thickness`, measured rather than
            // guessed. The width is a starting point; a menu bar item can be
            // any width and says so.
            case .menuBar: CGSize(width: 160, height: 22)
            // Wide enough for two values and a symbol, tall enough to read at
            // a glance without covering anything.
            case .island: CGSize(width: 240, height: 34)
            }
        }

        /// macOS 26 rounds every widget to the same radius regardless of size,
        /// which is why the preview cannot derive it from the width.
        static let cornerRadius: Double = 27.88
    }
}

/// What sits behind the elements.
///
/// A struct with a `kind` discriminator rather than an enum with associated
/// values: the JSON stays flat, and switching a background from colour to
/// gradient in the editor does not throw away the colour you had.
struct Background: Codable, Hashable {
    var kind: Kind
    var color: ColorSpec
    var gradientEnd: ColorSpec
    var angle: Double

    init(kind: Kind,
         color: ColorSpec = ColorSpec(Palette.surfaceHex),
         gradientEnd: ColorSpec = ColorSpec(Palette.backgroundHex),
         angle: Double = 135) {
        self.kind = kind
        self.color = color
        self.gradientEnd = gradientEnd
        self.angle = angle
    }

    enum Kind: String, Codable, CaseIterable {
        case none
        case color
        case gradient
        /// Tahoe's material. The reason macOS 26 is the floor.
        case glass

        var displayName: String {
            switch self {
            case .none: "None"
            case .color: "Colour"
            case .gradient: "Gradient"
            case .glass: "Liquid Glass"
            }
        }
    }

    static let glass = Background(kind: .glass)
    static let none = Background(kind: .none)
}

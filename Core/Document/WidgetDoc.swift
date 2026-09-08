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

    static let currentSchemaVersion = 1

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
         minimumRefresh: TimeInterval = WidgetDoc.refreshFloor) {
        self.schemaVersion = WidgetDoc.currentSchemaVersion
        self.id = id
        self.name = name
        self.family = family
        self.background = background
        self.elements = elements
        self.sources = sources
        self.minimumRefresh = max(minimumRefresh, WidgetDoc.refreshFloor)
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
    var sanitised: WidgetDoc {
        var copy = self
        copy.minimumRefresh = max(minimumRefresh, WidgetDoc.refreshFloor)
        copy.elements = elements.map {
            var e = $0
            e.frame = $0.frame.normalised
            return e
        }
        return copy
    }

    enum Family: String, Codable, CaseIterable {
        case small, medium, large, extraLarge

        var widgetFamily: WidgetFamily {
            switch self {
            case .small: .systemSmall
            case .medium: .systemMedium
            case .large: .systemLarge
            case .extraLarge: .systemExtraLarge
            }
        }

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
            }
        }

        /// Nominal point size. The renderer never trusts this for layout — it
        /// uses the real geometry it is given — but font sizes are authored
        /// against it, and the editor canvas needs an aspect ratio.
        var referenceSize: CGSize {
            switch self {
            case .small: CGSize(width: 170, height: 170)
            case .medium: CGSize(width: 364, height: 170)
            case .large: CGSize(width: 364, height: 382)
            case .extraLarge: CGSize(width: 742, height: 382)
            }
        }
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

import Foundation

/// One place on the desktop that a document can be assigned to.
///
/// `StaticConfiguration` gives a widget no way to be configured after it is
/// placed, so the only way to have two medium widgets showing different designs
/// is to ship two medium widget *kinds*. That is what a slot is: a fixed,
/// pre-declared position that the app assigns a document to.
///
/// It is not elegant — the widget gallery lists every slot — and it is here
/// because the elegant version does not run at all (trap 7). Given the choice
/// between a picker that never appears and a numbered list that works, this is
/// the one that puts widgets on the desktop.
struct WidgetSlot: Hashable, Sendable, Identifiable {
    let family: WidgetDoc.Family
    /// One-based, matching what the widget gallery shows.
    let index: Int

    var id: String { key }

    /// Slot one keeps the bare family name as its key, so assignments made
    /// before slots existed carry over untouched and placements keep their
    /// widget kind. Migration is a thing you avoid rather than write.
    var key: String {
        index == 1 ? family.rawValue : "\(family.rawValue).\(index)"
    }

    /// The `kind` string WidgetKit identifies this widget by. Changing one
    /// orphans every placement using it, so slot one's is left exactly as it
    /// was.
    var widgetKind: String {
        let base = "Fathom\(family.rawValue.prefix(1).uppercased())\(family.rawValue.dropFirst())"
        return index == 1 ? base : "\(base)\(index)"
    }

    var displayName: String {
        index == 1 ? family.displayName : "\(family.displayName) \(index)"
    }

    /// How many of each size Fathom offers.
    ///
    /// Deliberately uneven. Every slot is a permanent entry in the widget
    /// gallery, so the count is a judgement about how many of a size somebody
    /// realistically keeps on one desktop, not a number chosen for symmetry.
    static let counts: [WidgetDoc.Family: Int] = [
        .small: 4, .medium: 3, .large: 2, .extraLarge: 1,
    ]

    static func all(for family: WidgetDoc.Family) -> [WidgetSlot] {
        (1...(counts[family] ?? 1)).map { WidgetSlot(family: family, index: $0) }
    }

    static var everything: [WidgetSlot] {
        WidgetDoc.Family.allCases.flatMap(all(for:))
    }
}

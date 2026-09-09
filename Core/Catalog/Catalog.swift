import Foundation

/// A layout, before it has been given a palette.
///
/// A template is not a document — it is a function from a theme and a family to
/// one. That is what makes the catalog generated rather than stored: nothing is
/// ever out of step with the current schema, there is no build step, and adding
/// twenty palettes adds hundreds of entries without adding a byte to the app.
struct CatalogTemplate: Identifiable, Sendable {
    let id: String
    let name: String
    let category: Category
    let tags: [String]
    /// Only the families this layout was actually composed for. A design laid
    /// out for a square reads badly stretched into a 2:1 box, and offering it
    /// there would pad the count at the cost of the catalogue's credibility.
    let families: [WidgetDoc.Family]
    /// Sources the layout needs before it can show anything real.
    let needs: Set<DataSource.Kind>
    let build: @Sendable (Theme, WidgetDoc.Family) -> WidgetDoc

    enum Category: String, CaseIterable, Sendable {
        case time = "Time"
        case system = "System"
        case storage = "Storage"
        case battery = "Battery"
        case network = "Network"
        case weather = "Weather"
        case calendar = "Calendar"
        case minimal = "Minimal"

        var symbol: String {
            switch self {
            case .time: "clock"
            case .system: "cpu"
            case .storage: "internaldrive"
            case .battery: "battery.100"
            case .network: "wifi"
            case .weather: "cloud.sun"
            case .calendar: "calendar"
            case .minimal: "circle.dotted"
            }
        }
    }
}

/// One template, one theme, one family — a widget somebody can place.
struct CatalogEntry: Identifiable, Hashable, Sendable {
    let id: String
    let templateID: String
    let themeID: String
    let family: WidgetDoc.Family
    let name: String
    let themeName: String
    let category: CatalogTemplate.Category
    let tags: [String]
    let needs: Set<DataSource.Kind>

    /// Built on demand. A document is a few kilobytes of value types and takes
    /// microseconds to compose, so there is no reason to hold a thousand of
    /// them in memory when the gallery is showing twelve.
    func document() -> WidgetDoc {
        guard let template = Catalog.template(templateID) else {
            return WidgetDoc(name: name, family: family)
        }
        var doc = template.build(Theme.named(themeID), family)
        doc.name = name
        doc.origin = id
        return doc
    }

    var searchText: String {
        ([name, themeName, category.rawValue, family.displayName] + tags)
            .joined(separator: " ")
            .lowercased()
    }
}

enum Catalog {
    static let templates: [CatalogTemplate] = Templates.all

    /// The entry a document came from, if it came from one.
    ///
    /// `WidgetDoc.origin` has been written since the catalogue existed and read
    /// by nothing, which made it a promise in a comment: "it lets the editor
    /// offer revert to the original". Six hundred and eighty designs meant to be
    /// duplicated and edited, and no way back from an edit.
    static func entry(_ id: String) -> CatalogEntry? {
        entries.first { $0.id == id }
    }

    static func template(_ id: String) -> CatalogTemplate? {
        templates.first { $0.id == id }
    }

    /// Every template, in every palette, in every family it suits.
    ///
    /// Computed once and held: the entries are small value types and the list
    /// is what search and filtering run against.
    static let entries: [CatalogEntry] = {
        var out: [CatalogEntry] = []
        for template in templates {
            for family in template.families {
                for theme in Theme.all {
                    out.append(CatalogEntry(
                        id: "\(template.id).\(theme.id).\(family.rawValue)",
                        templateID: template.id,
                        themeID: theme.id,
                        family: family,
                        name: template.name,
                        themeName: theme.name,
                        category: template.category,
                        tags: template.tags,
                        needs: template.needs))
                }
            }
        }
        return out
    }()

    static var count: Int { entries.count }

    /// The honest arithmetic behind the number, for anywhere it is shown.
    static var composition: String {
        let layouts = templates.count
        let combos = templates.reduce(0) { $0 + $1.families.count }
        return "\(layouts) layouts across \(combos) sizes × \(Theme.all.count) palettes"
    }

    static func search(_ query: String,
                       category: CatalogTemplate.Category? = nil,
                       family: WidgetDoc.Family? = nil,
                       theme: String? = nil) -> [CatalogEntry] {
        let terms = query.lowercased()
            .split(whereSeparator: { $0 == " " || $0 == "," })
            .map(String.init)

        return entries.filter { entry in
            if let category, entry.category != category { return false }
            if let family, entry.family != family { return false }
            if let theme, entry.themeID != theme { return false }
            guard !terms.isEmpty else { return true }
            let haystack = entry.searchText
            return terms.allSatisfy { haystack.contains($0) }
        }
    }
}

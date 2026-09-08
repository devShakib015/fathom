import Foundation

/// Where a widget's live values come from.
///
/// Two kinds in v1. `system` costs nothing and always works; `json` is the
/// one that matters, because a 64-second refresh floor is only interesting if
/// the thing being refreshed is the user's own endpoint.
struct DataSource: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var kind: Kind
    /// `json` only. Kept as a string rather than a `URL` so a half-typed
    /// address in the editor still round-trips through save and reload.
    var url: String?

    init(id: UUID = UUID(), name: String, kind: Kind, url: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.url = url
    }

    enum Kind: String, Codable, CaseIterable {
        case system
        case json
        /// Calendar events. Needs the user's permission, so it is a source you
        /// add rather than one that is always there.
        case calendar
        case reminders

        var displayName: String {
            switch self {
            case .system: "This Mac"
            case .json: "Web endpoint"
            case .calendar: "Calendar"
            case .reminders: "Reminders"
            }
        }

        var symbol: String {
            switch self {
            case .system: "cpu"
            case .json: "globe"
            case .calendar: "calendar"
            case .reminders: "checklist"
            }
        }

        /// Whether adding this source will ask the user for something.
        var needsPermission: Bool { self == .calendar || self == .reminders }
    }

    /// Placeholders a `json` URL may carry, filled in at fetch time.
    ///
    /// This is what makes a shared weather widget mean "the weather where you
    /// are" instead of "the weather where its author was". Without it every
    /// template in the catalogue would have a city baked into it, and a design
    /// format built for sharing would ship two hundred widgets that are subtly
    /// about somebody else's life.
    static let tokens: [(token: String, label: String)] = [
        ("{latitude}", "Your latitude"),
        ("{longitude}", "Your longitude"),
        ("{city}", "Your town or city"),
        ("{countryCode}", "Your two-letter country code"),
        ("{timezone}", "Your IANA time zone"),
    ]

    /// Substitutes the location tokens. Anything not recognised is left alone,
    /// so a URL that legitimately contains braces still works.
    static func fill(_ url: String, with place: Place) -> String {
        var out = url
        let pairs: [(String, String)] = [
            ("{latitude}", trimmed(place.latitude)),
            ("{lat}", trimmed(place.latitude)),
            ("{longitude}", trimmed(place.longitude)),
            ("{lon}", trimmed(place.longitude)),
            ("{lng}", trimmed(place.longitude)),
            ("{city}", place.city ?? ""),
            ("{countryCode}", place.countryCode ?? ""),
            ("{timezone}", place.timeZone ?? TimeZone.current.identifier),
        ]
        for (token, value) in pairs {
            guard out.contains(token) else { continue }
            let escaped = value.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed) ?? value
            out = out.replacingOccurrences(of: token, with: escaped)
        }
        return out
    }

    /// Four decimal places is about eleven metres, which is far more precision
    /// than any weather endpoint uses and far less than would make the URL a
    /// record of where somebody sits.
    private static func trimmed(_ value: Double) -> String {
        String(format: "%.4f", value)
    }

    /// Whether this source's URL depends on where the user is.
    var usesLocation: Bool {
        guard kind == .json, let url else { return false }
        return Self.tokens.contains { url.contains($0.token) }
            || url.contains("{lat}") || url.contains("{lon}") || url.contains("{lng}")
    }

    /// The coordinates every weather starter and template shipped with before
    /// location existed.
    ///
    /// Documents already saved in someone's library still carry them, so a
    /// build that only fixes the templates leaves the actual widgets on the
    /// actual desktop still reporting a city nobody in the conversation lives
    /// in. The match is the exact shipped string and nothing looser: a user who
    /// deliberately typed their own coordinates keeps them.
    private static let shippedPlaceholder = "latitude=25.2048&longitude=55.2708"

    var migrated: DataSource {
        guard kind == .json, let url, url.contains(Self.shippedPlaceholder) else { return self }
        var copy = self
        copy.url = url.replacingOccurrences(of: Self.shippedPlaceholder,
                                            with: "latitude={latitude}&longitude={longitude}")
        return copy
    }

    /// The host this source will contact, if any. Fathom shows these before a
    /// document is ever placed, which is the whole reason sharing is designed
    /// for now and shipped later: the moment a widget can be handed to someone
    /// else, "what will this call?" has to be answerable without running it.
    var host: String? {
        // Tokens are stripped before parsing: a URL with `{latitude}` in the
        // query is not a legal URL, and the honest answer to "what will this
        // call?" must not depend on whether location has been granted yet.
        guard kind == .json, let url else { return nil }
        let bare = url.replacingOccurrences(of: "\\{[A-Za-z]+\\}", with: "0",
                                            options: .regularExpression)
        return URL(string: bare)?.host
    }

    static func system() -> DataSource {
        DataSource(name: "System", kind: .system)
    }

    /// The fields this source offers, for the editor's browser before anything
    /// has been read.
    var schema: [(path: String, label: String)] {
        switch kind {
        case .system: SystemSource.schemaDescription
        case .calendar: CalendarSource.eventSchema
        case .reminders: CalendarSource.reminderSchema
        case .json: []
        }
    }
}

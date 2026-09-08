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
    }

    /// The host this source will contact, if any. Fathom shows these before a
    /// document is ever placed, which is the whole reason sharing is designed
    /// for now and shipped later: the moment a widget can be handed to someone
    /// else, "what will this call?" has to be answerable without running it.
    var host: String? {
        guard kind == .json, let url, let parsed = URL(string: url) else { return nil }
        return parsed.host
    }

    static func system() -> DataSource {
        DataSource(name: "System", kind: .system)
    }
}

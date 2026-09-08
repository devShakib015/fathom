import Foundation

/// The strip that hangs under the notch.
///
/// A singleton rather than a list, because there is one notch and an island is
/// a place rather than a thing you can have several of. Overlays are the answer
/// when you want many.
///
/// Two documents: a compact one that is always there, and an optional expanded
/// one that appears on hover. That is the whole behaviour — the island is
/// glanced at, and anything that demands reading belongs in the expanded state
/// or somewhere else entirely.
///
/// macOS 26 offers no island API. This is a window Fathom draws and positions
/// itself, which is why the placement is measured from the screen's safe area
/// rather than assumed.
struct Island: Codable, Hashable {
    var documentID: UUID
    /// Shown while the pointer is over it. nil means it never expands.
    var expandedDocumentID: UUID?
    var isEnabled: Bool
    var expandOnHover: Bool
    var refresh: TimeInterval
    var screenIndex: Int
    /// Points below the menu bar. Zero hangs it flush, which is the look people
    /// mean when they say island.
    var topGap: Double

    static let refreshFloor: TimeInterval = 1
    static let defaultRefresh: TimeInterval = 3

    init(documentID: UUID) {
        self.documentID = documentID
        self.expandedDocumentID = nil
        self.isEnabled = true
        self.expandOnHover = true
        self.refresh = Island.defaultRefresh
        self.screenIndex = 0
        self.topGap = 0
    }

    enum CodingKeys: String, CodingKey {
        case documentID, expandedDocumentID, isEnabled, expandOnHover, refresh, screenIndex, topGap
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        documentID = try c.decode(UUID.self, forKey: .documentID)
        expandedDocumentID = try c.decodeIfPresent(UUID.self, forKey: .expandedDocumentID)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        expandOnHover = try c.decodeIfPresent(Bool.self, forKey: .expandOnHover) ?? true
        refresh = max(try c.decodeIfPresent(TimeInterval.self, forKey: .refresh)
                      ?? Island.defaultRefresh, Island.refreshFloor)
        screenIndex = try c.decodeIfPresent(Int.self, forKey: .screenIndex) ?? 0
        topGap = try c.decodeIfPresent(Double.self, forKey: .topGap) ?? 0
    }
}

struct IslandStore {
    static let shared = IslandStore()

    private var url: URL? { SharedStore.container?.appendingPathComponent("island.json") }

    func load() -> Island? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Island.self, from: data)
    }

    func save(_ island: Island?) {
        guard let url else { return }
        guard let island else { try? FileManager.default.removeItem(at: url); return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(island).write(to: url, options: .atomic)
    }

    func clearIfUses(_ documentID: UUID) {
        guard let island = load() else { return }
        if island.documentID == documentID {
            save(nil)
        } else if island.expandedDocumentID == documentID {
            var copy = island
            copy.expandedDocumentID = nil
            save(copy)
        }
    }
}
